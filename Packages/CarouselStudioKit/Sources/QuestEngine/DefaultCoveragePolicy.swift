import CoreModels

/// Default quality-bar coverage classification.
///
/// Counts candidates whose `combinedScore` clears `qualityFloor`, and buckets
/// that count into `none`, `scarce`, or `ample`. The best score is always the
/// maximum `combinedScore` seen, even if every candidate falls below the bar,
/// so the UI can surface "almost good enough" evidence.
public struct DefaultCoveragePolicy: CoveragePolicy {
    public var qualityFloor: Double
    public var scarceMax: Int
    public var ampleMin: Int

    public init(qualityFloor: Double = 0.35, scarceMax: Int = 2, ampleMin: Int = 3) {
        self.qualityFloor = qualityFloor
        self.scarceMax = scarceMax
        self.ampleMin = ampleMin
    }

    public func coverage(for slot: Slot, candidates: [SlotCandidate]) -> SlotCoverage {
        let goodCandidates = candidates.filter { $0.combinedScore >= qualityFloor }
        let candidateCount = goodCandidates.count

        let bestScore: Double? = candidates.isEmpty ? nil : candidates.map(\.combinedScore).max()

        let level: CoverageLevel
        if candidateCount == 0 {
            level = .none
        } else if candidateCount <= scarceMax {
            level = .scarce
        } else if candidateCount >= ampleMin {
            level = .ample
        } else {
            // Gap between scarceMax and ampleMin - 1: treat as scarce by default.
            level = .scarce
        }

        return SlotCoverage(
            slotID: slot.id,
            level: level,
            candidateCount: candidateCount,
            bestScore: bestScore
        )
    }
}
