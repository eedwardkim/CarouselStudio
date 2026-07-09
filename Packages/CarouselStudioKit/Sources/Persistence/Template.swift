import CoreModels
import Foundation
import SwiftData

/// The archetype of photo a slot asks for. Categories seed sensible defaults
/// (criteria phrasing, stage-2 judgment) and group slots for analytics and
/// feedback learning; `custom` covers everything the presets don't.
public enum SlotCategory: String, Codable, CaseIterable, Sendable {
    /// "self + scenery": a posed photo of the creator with a scenic backdrop.
    case selfWithScenery
    /// An aesthetic detail shot (food, textures, signage, interiors).
    case detailAesthetic
    /// A candid or funny in-the-moment shot.
    case candidFunny
    /// A deliberate, aesthetic photo of the creator.
    case selfAesthetic
    /// Pure humor: memes, screenshots, absurd finds.
    case humor
    /// User-defined criteria with no preset assumptions.
    case custom

    /// Whether MobileCLIP similarity is trusted as-is (objective) or the
    /// stage-2 reasoning pass applies (subjective). Mirrors `SlotJudgment`
    /// semantics from CoreModels.
    public var defaultJudgment: SlotJudgment {
        switch self {
        case .selfWithScenery, .custom: .objective
        case .detailAesthetic, .candidFunny, .selfAesthetic, .humor: .subjective
        }
    }
}

/// Persisted counterpart of `CoreModels.Template`: an ordered, reusable recipe
/// for a multi-slide post. Slot order lives on `Slot.position`; use
/// `orderedSlots` — SwiftData to-many relationships are unordered.
@Model
public final class Template {
    /// Stable identity, round-trips as `CoreModels.Template.ID`.
    @Attribute(.unique) public var uuid: UUID
    public var name: String
    /// Raw value of `PostFormat`. Enums are persisted as strings so
    /// `#Predicate` filtering stays reliable; use `format` in code.
    public var formatRawValue: String
    /// Raw values of `MoodTag`; drives music matching.
    public var moodTags: [String]
    public var createdAt: Date
    public var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Slot.template)
    public var slots: [Slot]

    @Relationship(deleteRule: .cascade, inverse: \Quest.template)
    public var quests: [Quest]

    public var format: PostFormat {
        get { PostFormat(rawValue: formatRawValue) ?? .carousel }
        set { formatRawValue = newValue.rawValue }
    }

    public var moodTagSet: Set<MoodTag> {
        get { Set(moodTags.map(MoodTag.init(rawValue:))) }
        set { moodTags = newValue.map(\.rawValue).sorted() }
    }

    /// Slots in presentation order.
    public var orderedSlots: [Slot] {
        slots.sorted { $0.position < $1.position }
    }

    public init(
        uuid: UUID = UUID(),
        name: String,
        format: PostFormat = .carousel,
        moodTags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        slots: [Slot] = [],
        quests: [Quest] = []
    ) {
        self.uuid = uuid
        self.name = name
        self.formatRawValue = format.rawValue
        self.moodTags = moodTags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.slots = slots
        self.quests = quests
    }
}

/// Persisted counterpart of `CoreModels.Slot`: one position in a template.
/// `criteria` doubles as the stage-1 zero-shot CLIP prompt.
@Model
public final class Slot {
    /// Stable identity, round-trips as `CoreModels.Slot.ID`.
    @Attribute(.unique) public var uuid: UUID
    /// Zero-based position within the owning template.
    public var position: Int
    /// Plain-language criteria, e.g. "an aesthetic detail shot of a local place".
    public var criteria: String
    /// Raw value of `SlotCategory`; use `category` in code.
    public var categoryRawValue: String
    /// Raw value of `SlotJudgment`; use `judgment` in code.
    public var judgmentRawValue: String

    public var template: Template?

    @Relationship(deleteRule: .cascade, inverse: \SlotMatchScore.slot)
    public var matchScores: [SlotMatchScore]

    @Relationship(deleteRule: .cascade, inverse: \FeedbackEvent.slot)
    public var feedbackEvents: [FeedbackEvent]

    @Relationship(deleteRule: .cascade, inverse: \QuestSlotState.slot)
    public var questSlotStates: [QuestSlotState]

    public var category: SlotCategory {
        get { SlotCategory(rawValue: categoryRawValue) ?? .custom }
        set { categoryRawValue = newValue.rawValue }
    }

    public var judgment: SlotJudgment {
        get { SlotJudgment(rawValue: judgmentRawValue) ?? .objective }
        set { judgmentRawValue = newValue.rawValue }
    }

    public init(
        uuid: UUID = UUID(),
        position: Int,
        criteria: String,
        category: SlotCategory = .custom,
        judgment: SlotJudgment? = nil,
        template: Template? = nil
    ) {
        self.uuid = uuid
        self.position = position
        self.criteria = criteria
        self.categoryRawValue = category.rawValue
        self.judgmentRawValue = (judgment ?? category.defaultJudgment).rawValue
        self.template = template
        self.matchScores = []
        self.feedbackEvents = []
        self.questSlotStates = []
    }
}
