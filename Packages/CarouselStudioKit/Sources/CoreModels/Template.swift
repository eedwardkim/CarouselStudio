import Foundation

/// The social formats a template can target.
public enum PostFormat: String, Codable, CaseIterable, Sendable {
    /// Multi-image feed post (e.g. an Instagram carousel).
    case carousel
    /// Sequence of full-screen frames (e.g. Instagram/TikTok Stories).
    case story
}

/// A lightweight theme/mood tag shared by templates and the song corpus.
/// Music matching happens on tag overlap, so both sides speak this type.
public struct MoodTag: RawRepresentable, Codable, Hashable, Sendable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// An ordered, reusable recipe for a multi-slide post: each slot describes, in
/// plain language, what kind of photo belongs at that position.
public struct Template: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var format: PostFormat
    /// Ordered by `Slot.position`.
    public var slots: [Slot]
    /// Drives music matching; also usable for browsing/filtering templates.
    public var moodTags: Set<MoodTag>
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        format: PostFormat,
        slots: [Slot] = [],
        moodTags: Set<MoodTag> = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.format = format
        self.slots = slots
        self.moodTags = moodTags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// One position in a template.
public struct Slot: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    /// Zero-based position within the template.
    public var position: Int
    /// Plain-language criteria, e.g. "a candid or funny photo, often a mirror
    /// selfie or with friends". Doubles as the zero-shot text prompt for
    /// stage-1 CLIP scoring, so phrasing directly affects match quality.
    public var criteria: String
    /// Whether stage-1 similarity is trusted as-is, or the slot needs the
    /// stage-2 reasoning pass because its criteria are subjective.
    public var judgment: SlotJudgment

    public init(
        id: UUID = UUID(),
        position: Int,
        criteria: String,
        judgment: SlotJudgment = .objective
    ) {
        self.id = id
        self.position = position
        self.criteria = criteria
        self.judgment = judgment
    }
}

/// How candidates for a slot are ultimately ranked.
public enum SlotJudgment: String, Codable, CaseIterable, Sendable {
    /// Concrete, visual criteria ("posed photo with scenic background").
    /// MobileCLIP similarity alone ranks candidates.
    case objective
    /// Subjective criteria ("funny", "aesthetic"). CLIP produces a shortlist;
    /// Foundation Models re-ranks it with multimodal reasoning (Phase 4).
    case subjective
}
