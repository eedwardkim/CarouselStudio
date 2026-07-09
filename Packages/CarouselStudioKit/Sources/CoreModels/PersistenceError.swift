/// Failure vocabulary shared by every persistence-backed store contract
/// (`TemplateStore`, `EmbeddingStore`, `QuestReportStore`, `FeedbackRecording`).
///
/// "Not found" is never an error in those contracts — lookups return `nil` and
/// deletes are idempotent no-ops — so a thrown `PersistenceError` always means
/// the storage layer itself misbehaved.
public enum PersistenceError: Error, Equatable, Sendable {
    /// The backing store can't be opened at all (corrupt database, disk full,
    /// protected data unavailable before first unlock). Usually not
    /// recoverable within the same launch.
    case storageUnavailable(reason: String)
    /// One read or write failed, but the store itself remains usable.
    /// Retryable.
    case operationFailed(reason: String)
}
