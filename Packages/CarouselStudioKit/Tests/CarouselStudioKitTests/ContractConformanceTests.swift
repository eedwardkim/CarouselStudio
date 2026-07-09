import CoreGraphics
import CoreModels
import Foundation
import MatchingEngine
import MusicMatching
import PhotoSources
import QuestEngine
import TemplateEngine
import Testing

// Compile-time proof that every contract can be conformed to under Swift 6
// strict concurrency, in the shapes real implementations will take: actors
// for stateful engines and stores, structs for pure logic. Bodies are
// deliberately inert — these are signature checks, not implementations.

private actor StubPhotoSource: PhotoSource {
    let kind: PhotoSourceKind = .photoKit
    func requestAccess() async -> PhotoAccessStatus { .full }
    nonisolated func assets(matching query: AssetQuery) -> AsyncThrowingStream<PhotoAsset, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func image(for id: PhotoAssetID, variant: ImageVariant) async throws -> CGImage {
        throw PhotoSourceError.assetNotFound(id)
    }
}

private struct StubObserver: PhotoLibraryObserving {
    func changes() -> AsyncStream<PhotoLibraryChange> {
        AsyncStream { $0.finish() }
    }
}

private struct StubImporter: GooglePhotosImporting {
    func importFromPicker() async throws -> GooglePhotosImportResult {
        GooglePhotosImportResult()
    }
}

private struct StubEmbedder: EmbeddingProviding {
    let modelVersion = "stub-v0"
    func embedding(for image: CGImage) async throws -> Embedding {
        throw EmbeddingError.modelUnavailable(reason: "stub")
    }
    func embedding(for text: String) async throws -> Embedding {
        Embedding(vector: [1, 0], modelVersion: modelVersion)
    }
}

private actor StubEmbeddingStore: EmbeddingStore {
    func embedding(for id: PhotoAssetID, modelVersion: String) async throws -> Embedding? { nil }
    func store(_ embedding: Embedding, for id: PhotoAssetID) async throws {}
    func removeEmbeddings(for ids: [PhotoAssetID]) async throws {}
    func compact(keepingModelVersion modelVersion: String) async throws {}
}

private struct StubSlotMatcher: SlotMatching {
    func candidates(
        in corpus: [AssetEmbedding],
        for slot: Slot,
        criteriaEmbedding: Embedding,
        limit: Int
    ) async throws -> [SlotCandidate] { [] }
}

private struct StubReasoner: CandidateReasoning {
    let isAvailable = false
    func verdict(for asset: PhotoAsset, image: CGImage, slot: Slot) async throws -> ReasoningVerdict {
        throw ReasoningError.unavailable
    }
}

private actor StubTemplateMatcher: TemplateMatching {
    func match(_ template: Template, options: MatchOptions) async throws -> TemplateMatch {
        // Honors the shape guarantee: a key for every slot, empty = no candidates.
        TemplateMatch(
            templateID: template.id,
            candidatesBySlot: Dictionary(uniqueKeysWithValues: template.slots.map { ($0.id, []) })
        )
    }
    func update(
        _ existing: TemplateMatch,
        applying change: PhotoLibraryChange,
        for template: Template,
        options: MatchOptions
    ) async throws -> TemplateMatch { existing }
}

private actor StubFeedback: FeedbackRecording {
    func record(_ feedback: MatchFeedback) async throws {}
    func feedbackHistory(for templateID: Template.ID) async throws -> [MatchFeedback] { [] }
}

private struct StubCorpus: SongCorpus {
    let corpusVersion = "stub-corpus-v0"
    func allSongs() async throws -> [Song] { [] }
}

private struct StubRecommender: SongRecommending {
    func suggestions(
        for template: Template,
        match: TemplateMatch?,
        caption: String?,
        limit: Int
    ) async throws -> [SongSuggestion] { [] }
}

private actor StubTemplateStore: TemplateStore {
    func allTemplates() async throws -> [Template] { [] }
    func template(withID id: Template.ID) async throws -> Template? { nil }
    func save(_ template: Template) async throws {}
    func deleteTemplate(withID id: Template.ID) async throws {}
    nonisolated func changes() -> AsyncStream<TemplateChange> {
        AsyncStream { $0.finish() }
    }
}

private struct StubValidator: TemplateValidating {
    func validate(_ template: Template) -> [TemplateValidationIssue] { [] }
}

private struct StubStarters: StarterTemplateProviding {
    func starterTemplates() -> [Template] { [] }
}

private struct StubPolicy: CoveragePolicy {
    func coverage(for slot: Slot, candidates: [SlotCandidate]) -> SlotCoverage {
        SlotCoverage(slotID: slot.id, level: .none, candidateCount: 0)
    }
}

private actor StubReportStore: QuestReportStore {
    func latestReport(for templateID: Template.ID) async throws -> QuestReport? { nil }
    func history(for templateID: Template.ID, limit: Int) async throws -> [QuestReport] { [] }
    func save(_ report: QuestReport) async throws {}
    func deleteReports(for templateID: Template.ID) async throws {}
}

private actor StubCoordinator: QuestCoordinating {
    func activate() async {}
    func deactivate() async {}
    func refresh(templateID: Template.ID?) async throws {}
    nonisolated func reports() -> AsyncStream<QuestReport> {
        AsyncStream { $0.finish() }
    }
}

@Suite struct ContractConformanceTests {
    @Test func everyContractIsConformable() {
        // Existential assignment forces each conformance to actually be used.
        let _: any PhotoSource = StubPhotoSource()
        let _: any PhotoLibraryObserving = StubObserver()
        let _: any GooglePhotosImporting = StubImporter()
        let _: any EmbeddingProviding = StubEmbedder()
        let _: any EmbeddingStore = StubEmbeddingStore()
        let _: any SlotMatching = StubSlotMatcher()
        let _: any CandidateReasoning = StubReasoner()
        let _: any TemplateMatching = StubTemplateMatcher()
        let _: any FeedbackRecording = StubFeedback()
        let _: any SongCorpus = StubCorpus()
        let _: any SongRecommending = StubRecommender()
        let _: any TemplateStore = StubTemplateStore()
        let _: any TemplateValidating = StubValidator()
        let _: any StarterTemplateProviding = StubStarters()
        let _: any CoveragePolicy = StubPolicy()
        let _: any QuestReportStore = StubReportStore()
        let _: any QuestCoordinating = StubCoordinator()
    }

    @Test func matchKeysEverySlotEvenWhenEmpty() async throws {
        let template = Template(
            name: "travel post",
            format: .carousel,
            slots: [
                Slot(position: 0, criteria: "a posed photo with a scenic background"),
                Slot(position: 1, criteria: "an aesthetic detail shot", judgment: .subjective),
            ]
        )
        let match = try await StubTemplateMatcher().match(template, options: .default)
        #expect(Set(match.candidatesBySlot.keys) == Set(template.slots.map(\.id)))
        #expect(match.candidatesBySlot.values.allSatisfy { $0.isEmpty })
    }

    @Test func slotMatcherYieldsNothingForEmptyCorpus() async throws {
        let slot = Slot(position: 0, criteria: "anything")
        let criteria = Embedding(vector: [1, 0], modelVersion: "stub-v0")
        let ranked = try await StubSlotMatcher()
            .candidates(in: [], for: slot, criteriaEmbedding: criteria, limit: 5)
        #expect(ranked.isEmpty)
    }

    @Test func unavailableReasonerThrowsTypedError() async {
        let asset = PhotoAsset(
            id: PhotoAssetID(source: .photoKit, rawValue: "A"),
            pixelWidth: 1,
            pixelHeight: 1
        )
        let slot = Slot(position: 0, criteria: "funny", judgment: .subjective)
        let image = makeTinyImage()
        await #expect(throws: ReasoningError.unavailable) {
            _ = try await StubReasoner().verdict(for: asset, image: image, slot: slot)
        }
    }
}

private func makeTinyImage() -> CGImage {
    let context = CGContext(
        data: nil,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    return context.makeImage()!
}
