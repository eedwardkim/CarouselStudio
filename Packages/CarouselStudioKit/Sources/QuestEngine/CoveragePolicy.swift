import CoreModels

/// Buckets candidate evidence into none/scarce/ample. Kept behind a protocol
/// so quality thresholds can be tuned — and later personalized from feedback —
/// without touching the engine.
public protocol CoveragePolicy: Sendable {
    /// Classifies one slot's candidate supply.
    ///
    /// Pure and deterministic. The policy owns the quality bar: which
    /// candidates count as "good" (e.g. `combinedScore` above a threshold)
    /// and where the none/scarce/ample boundaries sit. Subjective slots may
    /// get a different bar than objective ones.
    ///
    /// - Parameters:
    ///   - slot: The slot being classified.
    ///   - candidates: That slot's ranked candidates from the latest match;
    ///     empty when the slot matched nothing.
    /// - Returns: `SlotCoverage` for `slot.id`, with `candidateCount` = the
    ///   number of candidates clearing the bar (≤ `candidates.count`) and
    ///   `bestScore` = the top `combinedScore` seen, if any candidate exists.
    func coverage(for slot: Slot, candidates: [SlotCandidate]) -> SlotCoverage
}
