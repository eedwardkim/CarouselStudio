import Foundation

/// Stage-1 result: how well one photo matches one slot's criteria.
public struct SlotScore: Codable, Hashable, Sendable {
    public var assetID: PhotoAssetID
    public var slotID: Slot.ID
    /// Image↔text similarity from MobileCLIP, calibrated to 0…1. Raw cosine
    /// similarities are not comparable across different prompts, so scorers
    /// must normalize per slot (see ARCHITECTURE.md, "Score calibration").
    public var value: Double

    public init(assetID: PhotoAssetID, slotID: Slot.ID, value: Double) {
        self.assetID = assetID
        self.slotID = slotID
        self.value = value
    }
}

/// Stage-2 result (Phase 4): Foundation Models' judgment of a shortlisted
/// candidate for a subjective slot.
public struct ReasoningVerdict: Codable, Hashable, Sendable {
    /// 0…1 fit for the slot's criteria.
    public var fitScore: Double
    /// Short model-provided justification, surfaced in the UI ("why this photo?").
    public var rationale: String

    public init(fitScore: Double, rationale: String) {
        self.fitScore = fitScore
        self.rationale = rationale
    }
}

/// A photo shortlisted for a slot, with all evidence accumulated so far.
public struct SlotCandidate: Codable, Hashable, Sendable {
    public var assetID: PhotoAssetID
    public var slotID: Slot.ID
    public var clipScore: Double
    /// Present only after the stage-2 reasoning pass has run for this candidate.
    public var verdict: ReasoningVerdict?
    /// Final ranking key: equals `clipScore` after stage 1, blended with
    /// `verdict.fitScore` after stage 2.
    public var combinedScore: Double

    public init(
        assetID: PhotoAssetID,
        slotID: Slot.ID,
        clipScore: Double,
        verdict: ReasoningVerdict? = nil,
        combinedScore: Double
    ) {
        self.assetID = assetID
        self.slotID = slotID
        self.clipScore = clipScore
        self.verdict = verdict
        self.combinedScore = combinedScore
    }
}

/// Result of matching one template against the available photo corpus.
public struct TemplateMatch: Codable, Hashable, Sendable {
    public var templateID: Template.ID
    public var matchedAt: Date
    /// Candidates per slot, best first. An empty array means the slot has no
    /// viable candidates at all.
    public var candidatesBySlot: [Slot.ID: [SlotCandidate]]

    public init(
        templateID: Template.ID,
        matchedAt: Date = Date(),
        candidatesBySlot: [Slot.ID: [SlotCandidate]] = [:]
    ) {
        self.templateID = templateID
        self.matchedAt = matchedAt
        self.candidatesBySlot = candidatesBySlot
    }
}

/// What the user did with a suggested candidate (Phase 4 personalization signal).
public enum FeedbackSignal: String, Codable, CaseIterable, Sendable {
    /// Kept the suggestion in the final post.
    case accepted
    /// Swapped it for a different photo.
    case replaced
    /// Dismissed it outright.
    case rejected
}

public struct MatchFeedback: Codable, Hashable, Sendable {
    public var templateID: Template.ID
    public var slotID: Slot.ID
    public var assetID: PhotoAssetID
    public var signal: FeedbackSignal
    public var recordedAt: Date

    public init(
        templateID: Template.ID,
        slotID: Slot.ID,
        assetID: PhotoAssetID,
        signal: FeedbackSignal,
        recordedAt: Date = Date()
    ) {
        self.templateID = templateID
        self.slotID = slotID
        self.assetID = assetID
        self.signal = signal
        self.recordedAt = recordedAt
    }
}
