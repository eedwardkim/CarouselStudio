import CoreModels
import Foundation

/// An in-memory implementation of ``QuestReportStore`` intended for testing
/// and previews. Thread-safe via Swift actor isolation.
public actor InMemoryQuestReportStore: QuestReportStore {
    /// Keyed by `templateID`; each array is kept in newest-first order.
    private var store: [UUID: [QuestReport]] = [:]

    public init() {}

    // MARK: - QuestReportStore

    public func latestReport(for templateID: Template.ID) async throws -> QuestReport? {
        store[templateID]?.first
    }

    public func history(for templateID: Template.ID, limit: Int) async throws -> [QuestReport] {
        guard let reports = store[templateID] else { return [] }
        return Array(reports.prefix(limit))
    }

    public func save(_ report: QuestReport) async throws {
        var reports = store[report.templateID] ?? []
        // Remove any existing entry with the same id (insert-or-replace).
        reports.removeAll { $0.id == report.id }
        reports.append(report)
        // Maintain newest-first ordering by generatedAt descending.
        reports.sort { $0.generatedAt > $1.generatedAt }
        store[report.templateID] = reports
    }

    public func deleteReports(for templateID: Template.ID) async throws {
        store.removeValue(forKey: templateID)
    }
}
