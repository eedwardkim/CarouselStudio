import CoreModels

/// The long-running coordinator behind the quest system: observes
/// photo-library and template changes, keeps per-template matches fresh via
/// incremental updates, and publishes coverage reports. Constructed with a
/// `PhotoLibraryObserving`, `TemplateStore`, `TemplateMatching`,
/// `CoveragePolicy`, and `QuestReportStore`.
///
/// Resilience: rescans triggered by observation absorb their own errors — a
/// failed pass leaves the previous report standing and retries on the next
/// trigger. Only the user-initiated `refresh` surfaces failure to its caller.
public protocol QuestCoordinating: Sendable {
    /// Starts observing library and template changes. Returns once
    /// observation is wired; any initial catch-up scan proceeds in the
    /// background. Idempotent — activating an active coordinator is a no-op.
    /// Called on app launch once photo access is granted.
    ///
    /// Note: PHPhotoLibraryChangeObserver only fires while the app has a
    /// process, so this covers foreground + brief background; deep catch-up
    /// scans ride BGProcessingTask (see ARCHITECTURE.md).
    func activate() async

    /// Stops observing and cancels in-flight rescans. Idempotent. `reports()`
    /// streams stay open — subscribers simply see no new elements until the
    /// next `activate()`.
    func deactivate() async

    /// Forced rescan (pull-to-refresh): a full `match`, not an incremental
    /// update. Returns after reports for the affected templates are saved
    /// and published.
    ///
    /// - Parameter templateID: One template, or `nil` for all of them.
    ///   Unknown IDs are a no-op.
    /// - Throws: `PhotoSourceError.accessDenied` when the library isn't
    ///   readable, plus anything `TemplateMatching.match` throws;
    ///   `CancellationError` if the task is cancelled. When refreshing all
    ///   templates, reports already produced before a failure are still
    ///   published.
    func refresh(templateID: Template.ID?) async throws

    /// Replays the latest known report per template on subscription, then
    /// streams live updates as rescans complete. Usable before `activate()`
    /// (replay only). Never finishes on its own. Designed for a single
    /// consumer; the composition root fans out if a second listener ever
    /// appears.
    func reports() -> AsyncStream<QuestReport>
}
