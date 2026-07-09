import CoreModels
import Foundation
import SwiftData

public enum QuestStatus: String, Codable, CaseIterable, Sendable {
    /// Being tracked: rescans keep the slot states fresh.
    case active
    /// The user assembled and exported the post.
    case completed
    /// Dismissed without exporting.
    case abandoned
}

/// How full a quest slot is. The persisted counterpart of
/// `CoreModels.CoverageLevel` (none/scarce/ample), in quest vocabulary.
public enum SlotFillState: String, Codable, CaseIterable, Sendable {
    /// Zero good candidates — the quest: go shoot one.
    case empty
    /// A few candidates, below the "plenty" threshold.
    case some
    /// Enough strong candidates to fill the slot comfortably.
    case plenty

    public init(_ level: CoverageLevel) {
        switch level {
        case .none: self = .empty
        case .scarce: self = .some
        case .ample: self = .plenty
        }
    }

    public var coverageLevel: CoverageLevel {
        switch self {
        case .empty: .none
        case .some: .scarce
        case .plenty: .ample
        }
    }
}

/// An active instance of a template the user is working toward: "fill every
/// slot of 'travel post' with a good photo". Carries one `QuestSlotState`
/// per slot; the Quest Engine's rescans keep those fresh.
@Model
public final class Quest {
    @Attribute(.unique) public var uuid: UUID
    /// Raw value of `QuestStatus`; use `status` in code.
    public var statusRawValue: String
    public var startedAt: Date
    public var completedAt: Date?

    public var template: Template?

    @Relationship(deleteRule: .cascade, inverse: \QuestSlotState.quest)
    public var slotStates: [QuestSlotState]

    public var status: QuestStatus {
        get { QuestStatus(rawValue: statusRawValue) ?? .active }
        set { statusRawValue = newValue.rawValue }
    }

    /// Slot states in the template's slot order.
    public var orderedSlotStates: [QuestSlotState] {
        slotStates.sorted { ($0.slot?.position ?? .max) < ($1.slot?.position ?? .max) }
    }

    public init(
        uuid: UUID = UUID(),
        template: Template? = nil,
        status: QuestStatus = .active,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        slotStates: [QuestSlotState] = []
    ) {
        self.uuid = uuid
        self.statusRawValue = status.rawValue
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.template = template
        self.slotStates = slotStates
    }
}

/// The fill state of one slot within one quest, refreshed on every rescan.
@Model
public final class QuestSlotState {
    /// Raw value of `SlotFillState`; use `fillState` in code.
    public var fillStateRawValue: String
    /// Candidates currently clearing the coverage policy's quality bar;
    /// powers copy like "3 new candidates since last week".
    public var matchingCandidateCount: Int
    public var updatedAt: Date

    public var quest: Quest?
    public var slot: Slot?

    public var fillState: SlotFillState {
        // Unknown raw values read as .empty — the conservative bucket that
        // prompts attention rather than silently claiming coverage.
        get { SlotFillState(rawValue: fillStateRawValue) ?? .empty }
        set { fillStateRawValue = newValue.rawValue }
    }

    public init(
        quest: Quest? = nil,
        slot: Slot? = nil,
        fillState: SlotFillState = .empty,
        matchingCandidateCount: Int = 0,
        updatedAt: Date = Date()
    ) {
        self.fillStateRawValue = fillState.rawValue
        self.matchingCandidateCount = matchingCandidateCount
        self.updatedAt = updatedAt
        self.quest = quest
        self.slot = slot
    }
}
