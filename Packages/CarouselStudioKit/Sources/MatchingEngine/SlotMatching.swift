import CoreModels

/// A corpus element ready for scoring: one asset's identity plus its cached
/// or freshly computed image embedding.
public struct AssetEmbedding: Hashable, Sendable {
    public var assetID: PhotoAssetID
    public var embedding: Embedding

    public init(assetID: PhotoAssetID, embedding: Embedding) {
        self.assetID = assetID
        self.embedding = embedding
    }
}

public enum SlotMatchingError: Error, Equatable, Sendable {
    /// Criteria and corpus embeddings come from different model versions —
    /// their vector spaces are incompatible. Re-embed; never mix.
    case mismatchedEmbeddingSpace(expected: String, found: String)
    /// A vector's length doesn't match the space's dimension: corrupted cache
    /// data. Purge the offending entries via `EmbeddingStore`.
    case dimensionMismatch(expected: Int, found: Int)
}

/// Stage-1 ranking for a single slot: cosine scoring, per-slot calibration,
/// and the shortlist cutoff. Pure embedding-space math — no photo access, no
/// Core ML — so it's unit-testable with synthetic vectors, and score
/// calibration (the tuning hot spot of Phase 1) can be iterated in isolation.
/// `TemplateMatching` implementations run this once per slot.
public protocol SlotMatching: Sendable {
    /// Scores every corpus element against one slot's criteria and returns
    /// the ranked shortlist.
    ///
    /// Scoring is the dot product of unit vectors, then calibrated to the
    /// 0…1 `SlotScore` scale *over this corpus* (see ARCHITECTURE.md, "Score
    /// calibration"). Because calibration is per-call, scores from separate
    /// calls are not comparable — callers rank within a call, never across
    /// calls.
    ///
    /// - Parameters:
    ///   - corpus: Pre-embedded assets to consider. Empty is fine and yields
    ///     an empty result. Every embedding must share `criteriaEmbedding`'s
    ///     model version.
    ///   - slot: Supplies the `slotID` stamped on produced candidates. Its
    ///     `judgment` is not consulted — running stage 2 is the
    ///     orchestrator's decision.
    ///   - criteriaEmbedding: Text-tower embedding of `slot.criteria` (with
    ///     whatever prompt template the orchestrator applies).
    ///   - limit: Maximum candidates returned. Must be ≥ 1.
    /// - Returns: At most `limit` candidates, ordered by `combinedScore`
    ///   descending, ties broken stably by `assetID`. Every candidate has
    ///   `clipScore == combinedScore` and `verdict == nil` (stage 1 only).
    ///   Deterministic for identical inputs.
    /// - Throws: `SlotMatchingError`; `CancellationError` if the task is
    ///   cancelled.
    func candidates(
        in corpus: [AssetEmbedding],
        for slot: Slot,
        criteriaEmbedding: Embedding,
        limit: Int
    ) async throws -> [SlotCandidate]
}
