import CoreModels
import Foundation
import PhotoSources

/// Progress of one matching pass, for UI display. Corpus size is known once
/// enumeration finishes, before embedding starts.
public struct MatchProgress: Hashable, Sendable {
    /// Assets embedded (or served from cache) so far.
    public var completed: Int
    /// Total assets in the pass's corpus.
    public var total: Int

    public init(completed: Int, total: Int) {
        self.completed = completed
        self.total = total
    }
}

/// Stage-1-only `TemplateMatching`: enumerate → embed (cache-aware) → rank
/// each slot with the injected `SlotMatching`. The stage-2 reasoning pass is
/// Phase 4; `MatchOptions.enableReasoningPass` is accepted and ignored, which
/// the contract defines as the correct degradation.
///
/// Per-asset failures (deleted mid-scan, iCloud-unreachable, undecodable,
/// un-embeddable) skip that asset. Systemic failures (access denied, model
/// unavailable, storage faults) throw.
public actor DefaultTemplateMatcher: TemplateMatching {
    private let photoSource: any PhotoSource
    private let embedder: any EmbeddingProviding
    private let embeddingStore: any EmbeddingStore
    private let slotMatcher: any SlotMatching
    private let onProgress: (@Sendable (MatchProgress) -> Void)?

    /// Concurrent decode+embed width. Small: thumbnail decodes are I/O-bound
    /// but Core ML predictions serialize on the compute device anyway.
    private static let embeddingWidth = 3

    /// - Parameter progress: Called from an arbitrary task as assets finish
    ///   embedding; hop to the main actor before touching UI.
    public init(
        photoSource: any PhotoSource,
        embedder: any EmbeddingProviding,
        embeddingStore: any EmbeddingStore,
        slotMatcher: any SlotMatching,
        progress: (@Sendable (MatchProgress) -> Void)? = nil
    ) {
        self.photoSource = photoSource
        self.embedder = embedder
        self.embeddingStore = embeddingStore
        self.slotMatcher = slotMatcher
        self.onProgress = progress
    }

    // MARK: - TemplateMatching

    public func match(_ template: Template, options: MatchOptions) async throws -> TemplateMatch {
        var assetIDs: [PhotoAssetID] = []
        for try await asset in photoSource.assets(matching: options.query ?? .all) {
            assetIDs.append(asset.id)
        }

        let corpus = try await embedCorpus(assetIDs)

        var candidatesBySlot: [Slot.ID: [SlotCandidate]] = [:]
        for slot in template.slots {
            // Criteria are authored as full descriptions ("a candid photo of
            // friends laughing"), so they embed as-is — no prompt wrapper.
            let criteria = try await embedder.embedding(for: slot.criteria)
            candidatesBySlot[slot.id] = try await slotMatcher.candidates(
                in: corpus,
                for: slot,
                criteriaEmbedding: criteria,
                limit: options.shortlistSize
            )
        }
        return TemplateMatch(templateID: template.id, candidatesBySlot: candidatesBySlot)
    }

    public func update(
        _ existing: TemplateMatch,
        applying change: PhotoLibraryChange,
        for template: Template,
        options: MatchOptions
    ) async throws -> TemplateMatch {
        // Phase-1 folding: purge stale cache entries, then re-run the full
        // pass. The embedding cache means only `inserted`/`modified` assets
        // actually hit Core ML, and a full re-rank is exactly "equivalent to
        // re-running match over the updated corpus". True incremental
        // re-ranking lands with the Quest Engine in Phase 2.
        try await embeddingStore.removeEmbeddings(for: change.deleted + change.modified)
        return try await match(template, options: options)
    }

    // MARK: - Corpus embedding

    private func embedCorpus(_ ids: [PhotoAssetID]) async throws -> [AssetEmbedding] {
        let total = ids.count
        onProgress?(MatchProgress(completed: 0, total: total))

        return try await withThrowingTaskGroup(of: AssetEmbedding?.self) { group in
            var corpus: [AssetEmbedding] = []
            corpus.reserveCapacity(total)
            var completed = 0
            var iterator = ids.makeIterator()

            func enqueueNext() -> Bool {
                guard let id = iterator.next() else { return false }
                group.addTask { try await self.embedIfPossible(id) }
                return true
            }

            for _ in 0..<Self.embeddingWidth where enqueueNext() {}
            while let element = try await group.next() {
                if let element {
                    corpus.append(element)
                }
                completed += 1
                onProgress?(MatchProgress(completed: completed, total: total))
                _ = enqueueNext()
            }
            return corpus
        }
    }

    /// One asset's embedding — from cache when possible, else decode + embed
    /// + cache. `nil` when this asset should be skipped.
    private func embedIfPossible(_ id: PhotoAssetID) async throws -> AssetEmbedding? {
        if let cached = try await embeddingStore.embedding(for: id, modelVersion: embedder.modelVersion) {
            return AssetEmbedding(assetID: id, embedding: cached)
        }
        do {
            let thumbnail = try await photoSource.image(for: id, variant: .scoringThumbnail)
            let embedding = try await embedder.embedding(for: thumbnail)
            try await embeddingStore.store(embedding, for: id)
            return AssetEmbedding(assetID: id, embedding: embedding)
        } catch PhotoSourceError.assetNotFound, PhotoSourceError.resourceUnavailable,
            PhotoSourceError.decodingFailed
        {
            return nil
        } catch EmbeddingError.imageEncodingFailed {
            return nil
        }
    }
}
