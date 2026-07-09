import CoreModels
import Foundation
import QuestEngine
import Testing

@Suite struct CoveragePolicyTests {
    private let slot = Slot(position: 0, criteria: "a posed photo with a scenic background")

    private func candidate(
        id: String,
        score: Double,
        slotID: Slot.ID? = nil
    ) -> SlotCandidate {
        SlotCandidate(
            assetID: PhotoAssetID(source: .photoKit, rawValue: id),
            slotID: slotID ?? slot.id,
            clipScore: score,
            combinedScore: score
        )
    }

    @Test func emptyCandidatesReturnsNoneWithNilBestScore() {
        let policy = DefaultCoveragePolicy()
        let coverage = policy.coverage(for: slot, candidates: [])

        #expect(coverage.slotID == slot.id)
        #expect(coverage.level == .none)
        #expect(coverage.candidateCount == 0)
        #expect(coverage.bestScore == nil)
    }

    @Test func oneCandidateBelowFloorIsNoneButBestScoreIsRecorded() {
        let policy = DefaultCoveragePolicy(qualityFloor: 0.35)
        let coverage = policy.coverage(for: slot, candidates: [candidate(id: "A", score: 0.2)])

        #expect(coverage.level == .none)
        #expect(coverage.candidateCount == 0)
        #expect(coverage.bestScore == 0.2)
    }

    @Test func oneCandidateAtExactlyFloorIsScarce() {
        let policy = DefaultCoveragePolicy(qualityFloor: 0.35)
        let coverage = policy.coverage(for: slot, candidates: [candidate(id: "A", score: 0.35)])

        #expect(coverage.level == .scarce)
        #expect(coverage.candidateCount == 1)
        #expect(coverage.bestScore == 0.35)
    }

    @Test func scarceMaxCandidatesAboveFloorIsScarce() {
        let policy = DefaultCoveragePolicy(qualityFloor: 0.35, scarceMax: 2, ampleMin: 3)
        let candidates = [
            candidate(id: "A", score: 0.9),
            candidate(id: "B", score: 0.8),
        ]
        let coverage = policy.coverage(for: slot, candidates: candidates)

        #expect(coverage.level == .scarce)
        #expect(coverage.candidateCount == 2)
        #expect(coverage.bestScore == 0.9)
    }

    @Test func ampleMinCandidatesAboveFloorIsAmple() {
        let policy = DefaultCoveragePolicy(qualityFloor: 0.35, scarceMax: 2, ampleMin: 3)
        let candidates = [
            candidate(id: "A", score: 0.9),
            candidate(id: "B", score: 0.8),
            candidate(id: "C", score: 0.7),
        ]
        let coverage = policy.coverage(for: slot, candidates: candidates)

        #expect(coverage.level == .ample)
        #expect(coverage.candidateCount == 3)
        #expect(coverage.bestScore == 0.9)
    }

    @Test func manyCandidatesAboveFloorIsAmple() {
        let policy = DefaultCoveragePolicy(qualityFloor: 0.35)
        let candidates = (0..<10).map { candidate(id: "\($0)", score: 0.4 + Double($0) * 0.01) }
        let coverage = policy.coverage(for: slot, candidates: candidates)

        #expect(coverage.level == .ample)
        #expect(coverage.candidateCount == 10)
        #expect(coverage.bestScore == 0.49)
    }

    @Test func mixedCandidatesCountsOnlyGoodAndBestScoreIncludesAll() {
        let policy = DefaultCoveragePolicy(qualityFloor: 0.35)
        let candidates = [
            candidate(id: "A", score: 0.2),
            candidate(id: "B", score: 0.4),
            candidate(id: "C", score: 0.1),
            candidate(id: "D", score: 0.36),
        ]
        let coverage = policy.coverage(for: slot, candidates: candidates)

        #expect(coverage.level == .scarce)
        #expect(coverage.candidateCount == 2)
        #expect(coverage.bestScore == 0.4)
    }

    @Test func customThresholdsReclassifyCoverage() {
        let policy = DefaultCoveragePolicy(qualityFloor: 0.5, scarceMax: 1, ampleMin: 2)
        let candidates = [
            candidate(id: "A", score: 0.6),
            candidate(id: "B", score: 0.4),
            candidate(id: "C", score: 0.7),
        ]
        let coverage = policy.coverage(for: slot, candidates: candidates)

        // 0.4 is below the custom 0.5 floor; 0.6 and 0.7 clear it.
        #expect(coverage.level == .ample)
        #expect(coverage.candidateCount == 2)
        #expect(coverage.bestScore == 0.7)
    }

    @Test func gapBetweenScarceAndAmpleFallsToScarce() {
        // scarceMax: 1, ampleMin: 3 means 2 good candidates sit in the gap.
        let policy = DefaultCoveragePolicy(qualityFloor: 0.35, scarceMax: 1, ampleMin: 3)
        let candidates = [
            candidate(id: "A", score: 0.9),
            candidate(id: "B", score: 0.8),
        ]
        let coverage = policy.coverage(for: slot, candidates: candidates)

        #expect(coverage.level == .scarce)
        #expect(coverage.candidateCount == 2)
    }
}
