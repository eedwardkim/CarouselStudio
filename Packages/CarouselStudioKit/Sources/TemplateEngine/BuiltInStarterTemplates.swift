import CoreModels
import Foundation

/// The compiled-in starter catalog. IDs and dates are constants so callers
/// can detect which starters already exist in the user's store, and repeated
/// calls are bit-for-bit identical (the contract's determinism requirement).
public struct BuiltInStarterTemplates: StarterTemplateProviding {
    public init() {}

    public func starterTemplates() -> [Template] {
        [Self.travelRecap, Self.natureMoodboard, Self.goldenHourStory]
    }

    /// One fixed authoring date for the whole catalog (2024-06-01T00:00:00Z).
    private static let catalogDate = Date(timeIntervalSince1970: 1_717_200_000)

    private static func slot(
        _ id: String, _ position: Int, _ criteria: String,
        _ judgment: SlotJudgment = .objective
    ) -> Slot {
        Slot(id: UUID(uuidString: id)!, position: position, criteria: criteria, judgment: judgment)
    }

    static let travelRecap = Template(
        id: UUID(uuidString: "9A1DFA53-5AE2-4E92-8F86-0D6A7F00A001")!,
        name: "Travel Recap",
        format: .carousel,
        slots: [
            slot(
                "9A1DFA53-5AE2-4E92-8F86-0D6A7F00A101", 0,
                "a scenic landscape photo with mountains, water, or a beautiful view"),
            slot(
                "9A1DFA53-5AE2-4E92-8F86-0D6A7F00A102", 1,
                "a photo of a person posing outdoors on a trip"),
            slot(
                "9A1DFA53-5AE2-4E92-8F86-0D6A7F00A103", 2,
                "a close-up photo of food or a drink"),
            slot(
                "9A1DFA53-5AE2-4E92-8F86-0D6A7F00A104", 3,
                "a candid funny photo of friends laughing or making faces", .subjective),
        ],
        moodTags: [MoodTag(rawValue: "travel"), MoodTag(rawValue: "adventure")],
        createdAt: catalogDate,
        updatedAt: catalogDate
    )

    static let natureMoodboard = Template(
        id: UUID(uuidString: "9A1DFA53-5AE2-4E92-8F86-0D6A7F00B001")!,
        name: "Nature Moodboard",
        format: .carousel,
        slots: [
            slot(
                "9A1DFA53-5AE2-4E92-8F86-0D6A7F00B101", 0,
                "a photo of colorful flowers in bloom"),
            slot(
                "9A1DFA53-5AE2-4E92-8F86-0D6A7F00B102", 1,
                "a photo of a waterfall or a stream in a forest"),
            slot(
                "9A1DFA53-5AE2-4E92-8F86-0D6A7F00B103", 2,
                "a close-up detail photo of leaves, plants, or natural textures"),
        ],
        moodTags: [MoodTag(rawValue: "calm"), MoodTag(rawValue: "nature")],
        createdAt: catalogDate,
        updatedAt: catalogDate
    )

    static let goldenHourStory = Template(
        id: UUID(uuidString: "9A1DFA53-5AE2-4E92-8F86-0D6A7F00C001")!,
        name: "Golden Hour Story",
        format: .story,
        slots: [
            slot(
                "9A1DFA53-5AE2-4E92-8F86-0D6A7F00C101", 0,
                "a photo of a sunset or golden hour sky"),
            slot(
                "9A1DFA53-5AE2-4E92-8F86-0D6A7F00C102", 1,
                "an aesthetic moody photo with warm light and soft shadows", .subjective),
        ],
        moodTags: [MoodTag(rawValue: "dreamy"), MoodTag(rawValue: "warm")],
        createdAt: catalogDate,
        updatedAt: catalogDate
    )
}
