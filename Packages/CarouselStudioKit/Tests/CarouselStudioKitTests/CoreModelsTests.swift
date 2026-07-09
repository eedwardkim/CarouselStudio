import CoreModels
import Foundation
import Testing

// NOTE: Swift Testing ships with Xcode's toolchain. Run via Xcode or, from the
// CLI, with Xcode selected as the active developer directory:
//   sudo xcode-select -s /Applications/Xcode.app
// The bare Command Line Tools toolchain bundles no test framework at all.

@Suite struct CoreModelsTests {
    @Test func templateRoundTripsThroughCodable() throws {
        let template = Template(
            name: "travel post",
            format: .carousel,
            slots: [
                Slot(position: 0, criteria: "a posed photo of me with a scenic background"),
                Slot(position: 1, criteria: "an aesthetic detail shot of a local place", judgment: .subjective),
                Slot(position: 2, criteria: "a candid or funny photo, often a mirror selfie or with friends", judgment: .subjective),
            ],
            moodTags: [MoodTag(rawValue: "travel"), MoodTag(rawValue: "upbeat")]
        )
        let data = try JSONEncoder().encode(template)
        let decoded = try JSONDecoder().decode(Template.self, from: data)
        #expect(decoded == template)
    }

    @Test func templateMatchRoundTripsThroughCodable() throws {
        let slotID = UUID()
        let match = TemplateMatch(
            templateID: UUID(),
            candidatesBySlot: [
                slotID: [
                    SlotCandidate(
                        assetID: PhotoAssetID(source: .photoKit, rawValue: "ABC-123"),
                        slotID: slotID,
                        clipScore: 0.82,
                        combinedScore: 0.82
                    )
                ]
            ]
        )
        let data = try JSONEncoder().encode(match)
        let decoded = try JSONDecoder().decode(TemplateMatch.self, from: data)
        #expect(decoded == match)
    }

    @Test func assetIDsAreSourceQualified() {
        let local = PhotoAssetID(source: .photoKit, rawValue: "same-raw-value")
        let imported = PhotoAssetID(source: .googlePhotos, rawValue: "same-raw-value")
        #expect(local != imported)
    }

    @Test func coverageLevelsCoverZeroSomeMany() {
        #expect(CoverageLevel.allCases == [.none, .scarce, .ample])
    }
}
