import Foundation
import Persistence
import SwiftData
import Testing

// Scoped imports keep `Template`/`Slot` unambiguous: bare names below always
// mean the Persistence @Model classes, not the CoreModels value types.
import enum CoreModels.CoverageLevel
import enum CoreModels.FeedbackSignal
import struct CoreModels.MoodTag
import struct CoreModels.PhotoAssetID
import enum CoreModels.PhotoSourceKind
import struct CoreModels.ReasoningVerdict

@Suite struct PersistenceTests {
    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let container = try PersistenceSchema.makeContainer(inMemory: true)
        return (container, ModelContext(container))
    }

    @Test func slotsComeBackInPositionOrder() throws {
        let (container, context) = try makeContext()
        _ = container
        let template = Template(name: "travel post", format: .story, moodTags: ["travel"])
        context.insert(template)
        for position in [2, 0, 1] {
            let slot = Slot(position: position, criteria: "criteria \(position)")
            context.insert(slot)
            slot.template = template
        }
        try context.save()

        let fetched = try #require(try context.fetch(FetchDescriptor<Template>()).first)
        #expect(fetched.format == .story)
        #expect(fetched.moodTagSet == [MoodTag(rawValue: "travel")])
        #expect(fetched.orderedSlots.map(\.position) == [0, 1, 2])
    }

    @Test func categoriesSeedJudgmentsUnlessOverridden() {
        #expect(SlotCategory.selfWithScenery.defaultJudgment == .objective)
        #expect(SlotCategory.custom.defaultJudgment == .objective)
        #expect(SlotCategory.detailAesthetic.defaultJudgment == .subjective)
        #expect(SlotCategory.candidFunny.defaultJudgment == .subjective)
        #expect(SlotCategory.selfAesthetic.defaultJudgment == .subjective)
        #expect(SlotCategory.humor.defaultJudgment == .subjective)

        let defaulted = Slot(position: 0, criteria: "a funny screenshot", category: .humor)
        #expect(defaulted.judgment == .subjective)
        let overridden = Slot(position: 0, criteria: "a funny screenshot", category: .humor, judgment: .objective)
        #expect(overridden.judgment == .objective)
    }

    @Test func embeddingRoundTripsThroughRawData() throws {
        let (container, context) = try makeContext()
        _ = container
        let assetID = PhotoAssetID(source: .photoKit, rawValue: "ABC-123/L0/001")
        let vector = (0..<512).map { Float($0) / 512 }
        let candidate = Candidate(
            assetID: assetID,
            embeddingVector: vector,
            embeddingModelVersion: "mobileclip-s2-v1"
        )
        context.insert(candidate)
        try context.save()

        let fetched = try #require(try context.fetch(FetchDescriptor<Candidate>()).first)
        #expect(fetched.assetKey == "photoKit:ABC-123/L0/001")
        #expect(fetched.assetID == assetID)
        #expect(fetched.embeddingVector == vector)
        #expect(fetched.embedding?.count == 512 * MemoryLayout<Float>.stride)
    }

    @Test func scoresAndFeedbackLinkSlotsToCandidates() throws {
        let (container, context) = try makeContext()
        _ = container
        let template = Template(name: "food tour")
        let slot = Slot(position: 0, criteria: "an aesthetic detail shot", category: .detailAesthetic)
        let candidate = Candidate(assetID: PhotoAssetID(source: .photoKit, rawValue: "XYZ"))
        context.insert(template)
        context.insert(slot)
        context.insert(candidate)
        slot.template = template

        let score = SlotMatchScore(clipScore: 0.42)
        context.insert(score)
        score.slot = slot
        score.candidate = candidate
        let feedback = FeedbackEvent(signal: .accepted)
        context.insert(feedback)
        feedback.slot = slot
        feedback.candidate = candidate
        try context.save()

        #expect(slot.matchScores.count == 1)
        #expect(candidate.matchScores.first?.slot?.uuid == slot.uuid)
        #expect(score.combinedScore == 0.42)
        #expect(score.verdict == nil)
        #expect(slot.feedbackEvents.count == 1)
        #expect(candidate.feedbackEvents.first?.signal == .accepted)

        score.verdict = ReasoningVerdict(fitScore: 0.9, rationale: "sharp, well lit")
        try context.save()
        #expect(score.verdict?.fitScore == 0.9)
    }

    @Test func questSlotStatesFollowSlotOrderAndDefaultToEmpty() throws {
        let (container, context) = try makeContext()
        _ = container
        let template = Template(name: "travel post")
        context.insert(template)
        let slots = [0, 1].map { Slot(position: $0, criteria: "criteria \($0)") }
        let quest = Quest()
        context.insert(quest)
        quest.template = template
        for slot in slots.reversed() {
            context.insert(slot)
            slot.template = template
            let state = QuestSlotState()
            context.insert(state)
            state.quest = quest
            state.slot = slot
        }
        try context.save()

        #expect(quest.status == .active)
        #expect(quest.orderedSlotStates.compactMap(\.slot?.position) == [0, 1])
        #expect(quest.slotStates.allSatisfy { $0.fillState == .empty })
    }

    @Test func fillStatesMirrorCoverageLevels() {
        #expect(SlotFillState(CoverageLevel.none) == .empty)
        #expect(SlotFillState(CoverageLevel.scarce) == .some)
        #expect(SlotFillState(CoverageLevel.ample) == .plenty)
        #expect(SlotFillState.allCases.map(\.coverageLevel) == CoverageLevel.allCases)
    }

    @Test func deletingTemplateCascadesEverywhereButSparesCandidates() throws {
        let (container, context) = try makeContext()
        _ = container
        let template = Template(name: "travel post")
        let slot = Slot(position: 0, criteria: "a posed photo with scenery", category: .selfWithScenery)
        let candidate = Candidate(
            assetID: PhotoAssetID(source: .photoKit, rawValue: "KEEP-ME"),
            embeddingVector: [0.25, -0.5, 0.75]
        )
        context.insert(template)
        context.insert(slot)
        context.insert(candidate)
        slot.template = template
        let score = SlotMatchScore(clipScore: 0.8)
        context.insert(score)
        score.slot = slot
        score.candidate = candidate
        let feedback = FeedbackEvent(signal: .rejected)
        context.insert(feedback)
        feedback.slot = slot
        feedback.candidate = candidate
        let quest = Quest()
        context.insert(quest)
        quest.template = template
        let state = QuestSlotState(fillState: .plenty, matchingCandidateCount: 4)
        context.insert(state)
        state.quest = quest
        state.slot = slot
        try context.save()

        context.delete(template)
        try context.save()

        let slotCount = try context.fetchCount(FetchDescriptor<Slot>())
        let questCount = try context.fetchCount(FetchDescriptor<Quest>())
        let stateCount = try context.fetchCount(FetchDescriptor<QuestSlotState>())
        let scoreCount = try context.fetchCount(FetchDescriptor<SlotMatchScore>())
        let feedbackCount = try context.fetchCount(FetchDescriptor<FeedbackEvent>())
        #expect(slotCount == 0)
        #expect(questCount == 0)
        #expect(stateCount == 0)
        #expect(scoreCount == 0)
        #expect(feedbackCount == 0)

        let survivors = try context.fetch(FetchDescriptor<Candidate>())
        #expect(survivors.count == 1)
        #expect(survivors.first?.embeddingVector == [0.25, -0.5, 0.75])
        #expect(survivors.first?.matchScores.isEmpty == true)
    }

    @Test func deletingCandidateRemovesItsScoresAndFeedbackOnly() throws {
        let (container, context) = try makeContext()
        _ = container
        let slot = Slot(position: 0, criteria: "any photo")
        let candidate = Candidate(assetID: PhotoAssetID(source: .googlePhotos, rawValue: "IMPORTED-1"))
        context.insert(slot)
        context.insert(candidate)
        let score = SlotMatchScore(clipScore: 0.6)
        context.insert(score)
        score.slot = slot
        score.candidate = candidate
        try context.save()

        context.delete(candidate)
        try context.save()

        let scoreCount = try context.fetchCount(FetchDescriptor<SlotMatchScore>())
        let slotCount = try context.fetchCount(FetchDescriptor<Slot>())
        #expect(scoreCount == 0)
        #expect(slotCount == 1)
    }

    @Test func songCorpusEntriesKeepTagMetadataOnly() throws {
        let (container, context) = try makeContext()
        _ = container
        let entry = SongCorpusEntry(
            corpusID: "corpus-001",
            title: "Golden Hour",
            artist: "JVKE",
            themeTags: ["travel", "summer"],
            moodTags: ["upbeat", "dreamy"]
        )
        context.insert(entry)
        try context.save()

        let fetched = try #require(try context.fetch(FetchDescriptor<SongCorpusEntry>()).first)
        #expect(fetched.corpusID == "corpus-001")
        #expect(fetched.themeTagSet.contains(MoodTag(rawValue: "travel")))
        #expect(fetched.moodTagSet.contains(MoodTag(rawValue: "upbeat")))
    }
}
