import CoreModels

/// Report persistence, enabling deltas across time in the UI ("3 new
/// candidates for slot 2 since last week"). Reports are immutable facts:
/// saving appends history, nothing is edited in place.
public protocol QuestReportStore: Sendable {
    /// The most recent report, or `nil` when the template has never been
    /// scanned.
    /// - Throws: `PersistenceError`.
    func latestReport(for templateID: Template.ID) async throws -> QuestReport?

    /// Up to `limit` reports, newest first. `limit` must be ≥ 1.
    /// - Throws: `PersistenceError`.
    func history(for templateID: Template.ID, limit: Int) async throws -> [QuestReport]

    /// Appends one report. Saving a report whose `id` is already stored is
    /// insert-or-replace, so at-least-once delivery from the engine is safe.
    /// - Throws: `PersistenceError`.
    func save(_ report: QuestReport) async throws

    /// Drops all history for a template. Called when a template is deleted.
    /// Idempotent.
    /// - Throws: `PersistenceError`.
    func deleteReports(for templateID: Template.ID) async throws
}
