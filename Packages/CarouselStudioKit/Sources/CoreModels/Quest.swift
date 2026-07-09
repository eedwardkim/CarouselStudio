import Foundation

/// Bucketing of "how many good candidates exist for this slot".
public enum CoverageLevel: String, Codable, CaseIterable, Sendable {
    /// Zero good candidates — the quest: go shoot one.
    case none
    /// A few candidates, below the "plenty" threshold.
    case scarce
    /// Many good candidates.
    case ample
}

/// Per-slot coverage evidence inside a quest report.
public struct SlotCoverage: Codable, Hashable, Sendable {
    public var slotID: Slot.ID
    public var level: CoverageLevel
    /// Candidates clearing the policy's quality bar.
    public var candidateCount: Int
    /// Best combined score seen, if any candidate exists.
    public var bestScore: Double?

    public init(
        slotID: Slot.ID,
        level: CoverageLevel,
        candidateCount: Int,
        bestScore: Double? = nil
    ) {
        self.slotID = slotID
        self.level = level
        self.candidateCount = candidateCount
        self.bestScore = bestScore
    }
}

/// What prompted a rescan.
public enum QuestTrigger: String, Codable, CaseIterable, Sendable {
    case libraryChange
    case templateChange
    case manual
    case scheduled
}

/// One rescan's summary for one template. The UI turns these into quests
/// ("Slot 2 has no candidates — go shoot a detail shot of a local place").
public struct QuestReport: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var templateID: Template.ID
    public var generatedAt: Date
    public var trigger: QuestTrigger
    /// One entry per slot in the template, in slot order.
    public var coverage: [SlotCoverage]

    public init(
        id: UUID = UUID(),
        templateID: Template.ID,
        generatedAt: Date = Date(),
        trigger: QuestTrigger,
        coverage: [SlotCoverage]
    ) {
        self.id = id
        self.templateID = templateID
        self.generatedAt = generatedAt
        self.trigger = trigger
        self.coverage = coverage
    }
}
