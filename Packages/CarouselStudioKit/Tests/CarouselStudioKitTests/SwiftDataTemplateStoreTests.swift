import CoreModels
import Foundation
import Persistence
import SwiftData
import TemplateEngine
import Testing

// Disambiguate: bare Template/Slot below refer to CoreModels value types.
import struct CoreModels.Template
import struct CoreModels.Slot
import enum CoreModels.SlotJudgment

@Suite struct SwiftDataTemplateStoreTests {

    // MARK: - Helpers

    private func makeStore() throws -> SwiftDataTemplateStore {
        let container = try PersistenceSchema.makeContainer(inMemory: true)
        return SwiftDataTemplateStore(container: container)
    }

    private func sampleTemplate(
        id: UUID = UUID(),
        name: String = "Travel Post",
        slots: [Slot] = []
    ) -> Template {
        Template(
            id: id,
            name: name,
            format: .carousel,
            slots: slots,
            moodTags: [MoodTag(rawValue: "travel")],
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    // MARK: - Tests

    /// Saving a template then calling allTemplates() returns that template.
    @Test func saveAndRetrieveAll() async throws {
        let store = try makeStore()
        let template = sampleTemplate()
        try await store.save(template)
        let all = try await store.allTemplates()
        #expect(all.count == 1)
        let fetched = try #require(all.first)
        #expect(fetched.id == template.id)
        #expect(fetched.name == template.name)
        #expect(fetched.format == template.format)
        #expect(fetched.moodTags == template.moodTags)
    }

    /// Saving the same template twice (same id, different name) results in one
    /// record with the updated name and a later updatedAt.
    @Test func saveIdempotentlyUpdatesExisting() async throws {
        let store = try makeStore()
        let id = UUID()
        let original = sampleTemplate(id: id, name: "Original Name")
        try await store.save(original)
        try await Task.sleep(for: .milliseconds(10))
        let updated = sampleTemplate(id: id, name: "Updated Name")
        try await store.save(updated)
        let all = try await store.allTemplates()
        #expect(all.count == 1)
        let fetched = try #require(all.first)
        #expect(fetched.name == "Updated Name")
        #expect(fetched.updatedAt > original.updatedAt)
    }

    /// template(withID:) returns nil for an unknown UUID.
    @Test func templateWithUnknownIDReturnsNil() async throws {
        let store = try makeStore()
        let result = try await store.template(withID: UUID())
        #expect(result == nil)
    }

    /// template(withID:) returns the correct template when it exists.
    @Test func templateWithKnownIDReturnsTemplate() async throws {
        let store = try makeStore()
        let template = sampleTemplate()
        try await store.save(template)
        let result = try await store.template(withID: template.id)
        let fetched = try #require(result)
        #expect(fetched.id == template.id)
        #expect(fetched.name == template.name)
    }

    /// deleteTemplate(withID:) removes a known template.
    @Test func deleteKnownTemplateRemovesIt() async throws {
        let store = try makeStore()
        let template = sampleTemplate()
        try await store.save(template)
        try await store.deleteTemplate(withID: template.id)
        let all = try await store.allTemplates()
        #expect(all.isEmpty)
    }

    /// deleteTemplate(withID:) on an unknown ID does NOT throw.
    @Test func deleteUnknownIDDoesNotThrow() async throws {
        let store = try makeStore()
        try await store.deleteTemplate(withID: UUID())
    }

    /// changes() stream delivers .saved when a template is saved.
    @Test func changesStreamDeliversSavedEvent() async throws {
        let store = try makeStore()
        let stream = await store.changes()
        let template = sampleTemplate()
        try await store.save(template)
        var iterator = stream.makeAsyncIterator()
        let event = await iterator.next()
        #expect(event == .saved(template.id))
    }

    /// changes() stream delivers .deleted when a template is deleted (not when an unknown ID is deleted).
    @Test func changesStreamDeliversDeletedEventOnlyForKnownID() async throws {
        let store = try makeStore()
        let stream = await store.changes()
        let template = sampleTemplate()
        // Save -- produces .saved event.
        try await store.save(template)
        // Delete unknown ID -- produces no event.
        try await store.deleteTemplate(withID: UUID())
        // Delete known ID -- produces .deleted event.
        try await store.deleteTemplate(withID: template.id)
        var iterator = stream.makeAsyncIterator()
        let firstEvent = await iterator.next()
        #expect(firstEvent == .saved(template.id))
        let secondEvent = await iterator.next()
        #expect(secondEvent == .deleted(template.id))
    }

    /// allTemplates() returns templates sorted by updatedAt descending.
    @Test func allTemplatesSortedByUpdatedAtDescending() async throws {
        let store = try makeStore()
        let first = sampleTemplate(name: "First")
        try await store.save(first)
        try await Task.sleep(for: .milliseconds(10))
        let second = sampleTemplate(name: "Second")
        try await store.save(second)
        let all = try await store.allTemplates()
        #expect(all.count == 2)
        #expect(all[0].name == "Second")
        #expect(all[1].name == "First")
    }

    /// Slots round-trip correctly through the store.
    @Test func slotsRoundTripThroughStore() async throws {
        let store = try makeStore()
        let slots = [
            Slot(id: UUID(), position: 0, criteria: "a scenic view", judgment: SlotJudgment.objective),
            Slot(id: UUID(), position: 1, criteria: "a candid laugh", judgment: SlotJudgment.subjective),
        ]
        let template = sampleTemplate(slots: slots)
        try await store.save(template)
        let fetched = try await store.template(withID: template.id)
        let f = try #require(fetched)
        #expect(f.slots.count == 2)
        #expect(f.slots[0].position == 0)
        #expect(f.slots[0].criteria == "a scenic view")
        #expect(f.slots[0].judgment == SlotJudgment.objective)
        #expect(f.slots[1].position == 1)
        #expect(f.slots[1].criteria == "a candid laugh")
        #expect(f.slots[1].judgment == SlotJudgment.subjective)
    }
}
