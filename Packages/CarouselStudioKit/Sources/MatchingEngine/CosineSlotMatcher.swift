import CoreModels
import Foundation

/// Stage-1 `SlotMatching`: dot-product scoring (vectors are unit-norm, so
/// that *is* cosine similarity) followed by per-call min–max calibration to
/// the 0…1 `SlotScore` scale.
///
/// Min–max was chosen over z-scores for Phase 1 because it needs no
/// distributional assumptions and always uses the full 0…1 range, which reads
/// naturally in the UI ("best photo in your library for this slot" = 1.0).
/// Scores are therefore only comparable within one call — exactly the
/// contract's guarantee, no stronger.
public struct CosineSlotMatcher: SlotMatching {
    public init() {}

    public func candidates(
        in corpus: [AssetEmbedding],
        for slot: Slot,
        criteriaEmbedding: Embedding,
        limit: Int
    ) async throws -> [SlotCandidate] {
        precondition(limit >= 1, "limit must be ≥ 1")
        guard !corpus.isEmpty else { return [] }

        let expectedVersion = criteriaEmbedding.modelVersion
        let expectedDimension = criteriaEmbedding.vector.count

        var scored: [(id: PhotoAssetID, similarity: Double)] = []
        scored.reserveCapacity(corpus.count)
        for element in corpus {
            try Task.checkCancellation()
            guard element.embedding.modelVersion == expectedVersion else {
                throw SlotMatchingError.mismatchedEmbeddingSpace(
                    expected: expectedVersion, found: element.embedding.modelVersion)
            }
            guard element.embedding.vector.count == expectedDimension else {
                throw SlotMatchingError.dimensionMismatch(
                    expected: expectedDimension, found: element.embedding.vector.count)
            }
            let similarity = zip(element.embedding.vector, criteriaEmbedding.vector)
                .reduce(Float(0)) { $0 + $1.0 * $1.1 }
            scored.append((element.assetID, Double(similarity)))
        }

        // Per-slot calibration over this corpus. A degenerate spread (single
        // asset, or identical scores) maps everything to a neutral 0.5 —
        // "present but unranked" — rather than a fake perfect score.
        let low = scored.lazy.map(\.similarity).min() ?? 0
        let high = scored.lazy.map(\.similarity).max() ?? 0
        let spread = high - low
        func calibrated(_ value: Double) -> Double {
            spread > .ulpOfOne ? (value - low) / spread : 0.5
        }

        return
            scored
            .sorted { lhs, rhs in
                if lhs.similarity != rhs.similarity { return lhs.similarity > rhs.similarity }
                return (lhs.id.source.rawValue, lhs.id.rawValue)
                    < (rhs.id.source.rawValue, rhs.id.rawValue)
            }
            .prefix(limit)
            .map { entry in
                let score = calibrated(entry.similarity)
                return SlotCandidate(
                    assetID: entry.id,
                    slotID: slot.id,
                    clipScore: score,
                    combinedScore: score
                )
            }
    }
}
