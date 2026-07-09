import CoreModels
import Foundation

/// Persistence and change notification for templates. The production
/// implementation is SwiftData-backed; tests use an in-memory store.
///
/// Lookups return `nil` and deletes are no-ops for unknown IDs — thrown
/// errors are always genuine storage faults (`PersistenceError`).
public protocol TemplateStore: Sendable {
    /// Every stored template, most recently updated first.
    /// - Throws: `PersistenceError`.
    func allTemplates() async throws -> [Template]

    /// The template, or `nil` when the ID is unknown.
    /// - Throws: `PersistenceError`.
    func template(withID id: Template.ID) async throws -> Template?

    /// Insert-or-update, keyed on `template.id`. Implementations set
    /// `updatedAt` on the way through and emit `.saved` after the write
    /// commits. Saving does not validate — run `TemplateValidating` first.
    /// - Throws: `PersistenceError`.
    func save(_ template: Template) async throws

    /// Removes the template if present, emitting `.deleted` only when
    /// something was actually removed. Idempotent. Cascading cleanup (quest
    /// reports, feedback) is the Quest Engine's reaction to the change
    /// event, not this store's job.
    /// - Throws: `PersistenceError`.
    func deleteTemplate(withID id: Template.ID) async throws

    /// One element per committed mutation, in commit order. No replay —
    /// subscribe before mutating. Never finishes on its own. Designed for a
    /// single consumer (the Quest Engine); the composition root fans out if
    /// a second listener ever appears.
    func changes() -> AsyncStream<TemplateChange>
}

public enum TemplateChange: Hashable, Sendable {
    case saved(Template.ID)
    case deleted(Template.ID)
}

/// Bundled starter templates (e.g. "travel post") offered on first launch
/// and in the template gallery.
public protocol StarterTemplateProviding: Sendable {
    /// Pure data, deterministic, non-throwing — starters are compiled in or
    /// ship as build-time-vetted resources. Template IDs are stable across
    /// calls and releases, so callers can detect which starters the user has
    /// already added to their store.
    func starterTemplates() -> [Template]
}
