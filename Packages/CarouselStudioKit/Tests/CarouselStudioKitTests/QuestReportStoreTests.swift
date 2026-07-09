import CoreModels
import Foundation
import QuestEngine
import Testing

// MARK: - Helpers

private func makeReport(
    templateID: UUID = UUID(),
    generatedAt: Date = Date()
) -> QuestReport {
    QuestReport(
        id: UUID(),
        templateID: templateID,
        generatedAt: generatedAt,
        trigger: .manual,
        coverage: []
    )
}

// MARK: - Tests

@Suite struct QuestReportStoreTests {

    // MARK: latestReport

    @Test func latestReportReturnsNilForUnknownTemplateID() async throws {
        let store = InMemoryQuestReportStore()
        let result = try await store.latestReport(for: UUID())
        #expect(result == nil)
    }

    @Test func latestReportReturnsSavedReport() async throws {
        let store = InMemoryQuestReportStore()
        let templateID = UUID()
        let report = makeReport(templateID: templateID)
        try await store.save(report)
        let result = try await store.latestReport(for: templateID)
        #expect(result == report)
    }

    @Test func latestReportReturnsNewerOfTwoReports() async throws {
        let store = InMemoryQuestReportStore()
        let templateID = UUID()
        let now = Date()
        let older = makeReport(templateID: templateID, generatedAt: now.addingTimeInterval(-60))
        let newer = makeReport(templateID: templateID, generatedAt: now)
        // Save older first, then newer — order of insertion must not matter.
        try await store.save(older)
        try await store.save(newer)
        let result = try await store.latestReport(for: templateID)
        #expect(result == newer)
    }

    // MARK: history

    @Test func historyReturnsReportsNewestFirst() async throws {
        let store = InMemoryQuestReportStore()
        let templateID = UUID()
        let now = Date()
        let r1 = makeReport(templateID: templateID, generatedAt: now.addingTimeInterval(-120))
        let r2 = makeReport(templateID: templateID, generatedAt: now.addingTimeInterval(-60))
        let r3 = makeReport(templateID: templateID, generatedAt: now)
        // Save in an arbitrary order.
        try await store.save(r1)
        try await store.save(r3)
        try await store.save(r2)
        let result = try await store.history(for: templateID, limit: 10)
        #expect(result == [r3, r2, r1])
    }

    @Test func historyCapsAtLimit() async throws {
        let store = InMemoryQuestReportStore()
        let templateID = UUID()
        let now = Date()
        for i in 0 ..< 5 {
            let report = makeReport(
                templateID: templateID,
                generatedAt: now.addingTimeInterval(Double(i) * 10)
            )
            try await store.save(report)
        }
        let result = try await store.history(for: templateID, limit: 3)
        #expect(result.count == 3)
    }

    @Test func historyReturnsEmptyForUnknownTemplateID() async throws {
        let store = InMemoryQuestReportStore()
        let result = try await store.history(for: UUID(), limit: 5)
        #expect(result.isEmpty)
    }

    // MARK: save (insert-or-replace)

    @Test func saveSameIDReplacesExistingEntry() async throws {
        let store = InMemoryQuestReportStore()
        let templateID = UUID()
        let now = Date()
        let original = makeReport(templateID: templateID, generatedAt: now)
        try await store.save(original)

        // Replace with a report carrying the same id but a different generatedAt.
        let replacement = QuestReport(
            id: original.id,
            templateID: templateID,
            generatedAt: now.addingTimeInterval(30),
            trigger: .scheduled,
            coverage: []
        )
        try await store.save(replacement)

        let history = try await store.history(for: templateID, limit: 100)
        #expect(history.count == 1)
        #expect(history.first == replacement)
    }

    // MARK: deleteReports

    @Test func deleteReportsRemovesAllHistoryForTemplate() async throws {
        let store = InMemoryQuestReportStore()
        let templateID = UUID()
        try await store.save(makeReport(templateID: templateID))
        try await store.save(makeReport(templateID: templateID))
        try await store.deleteReports(for: templateID)
        let history = try await store.history(for: templateID, limit: 10)
        #expect(history.isEmpty)
    }

    @Test func deleteReportsOnUnknownTemplateIDDoesNotThrow() async throws {
        let store = InMemoryQuestReportStore()
        // Must not throw — idempotent.
        try await store.deleteReports(for: UUID())
    }

    // MARK: isolation between templateIDs

    @Test func differentTemplateIDsAreStoredIndependently() async throws {
        let store = InMemoryQuestReportStore()
        let idA = UUID()
        let idB = UUID()
        let reportA = makeReport(templateID: idA)
        let reportB = makeReport(templateID: idB)
        try await store.save(reportA)
        try await store.save(reportB)

        let historyA = try await store.history(for: idA, limit: 10)
        let historyB = try await store.history(for: idB, limit: 10)
        #expect(historyA == [reportA])
        #expect(historyB == [reportB])

        try await store.deleteReports(for: idA)
        let historyAAfterDelete = try await store.history(for: idA, limit: 10)
        let historyBAfterDelete = try await store.history(for: idB, limit: 10)
        #expect(historyAAfterDelete.isEmpty)
        #expect(historyBAfterDelete == [reportB])
    }
}
