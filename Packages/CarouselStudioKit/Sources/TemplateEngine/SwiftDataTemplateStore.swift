import CoreModels
import Foundation
import Persistence
import SwiftData

// Disambiguate: bare Template/Slot names below refer to CoreModels value
// types unless explicitly qualified with Persistence.
import struct CoreModels.Template
import struct CoreModels.Slot
import enum CoreModels.SlotJudgment

/// A TemplateStore implementation backed by a SwiftData ModelContainer.
///
/// All mutations happen on an internal ModelContext that lives on this actor,
/// keeping SwiftData access single-threaded and Sendable-safe. Change events
/// are broadcast over an AsyncStream backed by a single continuation
/// (one consumer per the protocol contract).
public actor SwiftDataTemplateStore: TemplateStore {

    private let context: ModelContext

    // nonisolated(unsafe) lets changes() -- which the protocol requires to
    // be synchronous (non-async) and therefore implicitly nonisolated on an
    // actor -- write the continuation. The single-consumer contract and the
    // fact that only changes() ever writes this value make the unsafety
    // benign in practice.
    nonisolated(unsafe) private var continuation: AsyncStream<TemplateChange>.Continuation?

    /// Creates a store using the supplied container. All SwiftData work happens
    /// on a freshly allocated ModelContext owned by this actor.
    public init(container: ModelContainer) {
        self.context = ModelContext(container)
    }

    // MARK: - TemplateStore

    /// Every stored template, most recently updated first.
    public func allTemplates() async throws -> [Template] {
        var descriptor = FetchDescriptor<Persistence.Template>()
        descriptor.sortBy = [SortDescriptor(\.updatedAt, order: .reverse)]
        let persisted = try context.fetch(descriptor)
        return persisted.map(coreModel(from:))
    }

    /// Returns the template with the given UUID, or nil if not found.
    public func template(withID id: Template.ID) async throws -> Template? {
        guard let persisted = try fetchPersisted(id: id) else { return nil }
        return coreModel(from: persisted)
    }

    /// Insert-or-update keyed on template.id. Sets updatedAt = Date.now
    /// on the persisted model and emits .saved after the write commits.
    public func save(_ template: Template) async throws {
        if let existing = try fetchPersisted(id: template.id) {
            // Update in-place.
            existing.name = template.name
            existing.formatRawValue = template.format.rawValue
            existing.moodTags = template.moodTags.map(\.rawValue).sorted()
            existing.updatedAt = Date.now
            // Replace slots: delete old ones, insert new ones.
            for slot in existing.slots {
                context.delete(slot)
            }
            existing.slots = []
            for coreSlot in template.slots {
                let persistedSlot = persistenceSlot(from: coreSlot, template: existing)
                context.insert(persistedSlot)
            }
        } else {
            // New record.
            let persistedTemplate = Persistence.Template(
                uuid: template.id,
                name: template.name,
                format: template.format,
                moodTags: template.moodTags.map(\.rawValue).sorted(),
                createdAt: template.createdAt,
                updatedAt: Date.now
            )
            context.insert(persistedTemplate)
            for coreSlot in template.slots {
                let persistedSlot = persistenceSlot(from: coreSlot, template: persistedTemplate)
                context.insert(persistedSlot)
            }
        }
        try context.save()
        continuation?.yield(.saved(template.id))
    }

    /// Removes the template if present, emitting .deleted only when something
    /// was actually removed. Idempotent -- never throws for an unknown ID.
    public func deleteTemplate(withID id: Template.ID) async throws {
        guard let existing = try fetchPersisted(id: id) else { return }
        context.delete(existing)
        try context.save()
        continuation?.yield(.deleted(id))
    }

    /// A non-replaying stream of committed mutations. Designed for a single
    /// consumer; replaces any previously stored continuation.
    nonisolated public func changes() -> AsyncStream<TemplateChange> {
        AsyncStream<TemplateChange> { [self] continuation in
            self.continuation = continuation
        }
    }

    // MARK: - Private helpers

    /// Fetches the persisted model whose uuid matches id, or nil.
    private func fetchPersisted(id: UUID) throws -> Persistence.Template? {
        let idValue = id
        var descriptor = FetchDescriptor<Persistence.Template>(
            predicate: #Predicate { $0.uuid == idValue }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Maps a Persistence.Template to a CoreModels.Template.
    private func coreModel(from persisted: Persistence.Template) -> Template {
        let slots = persisted.orderedSlots.map { slot -> Slot in
            Slot(
                id: slot.uuid,
                position: slot.position,
                criteria: slot.criteria,
                judgment: SlotJudgment(rawValue: slot.judgmentRawValue) ?? .objective
            )
        }
        return Template(
            id: persisted.uuid,
            name: persisted.name,
            format: PostFormat(rawValue: persisted.formatRawValue) ?? .carousel,
            slots: slots,
            moodTags: Set(persisted.moodTags.map { MoodTag(rawValue: $0) }),
            createdAt: persisted.createdAt,
            updatedAt: persisted.updatedAt
        )
    }

    /// Maps a CoreModels.Slot to a new Persistence.Slot linked to template.
    private func persistenceSlot(
        from slot: Slot,
        template: Persistence.Template
    ) -> Persistence.Slot {
        Persistence.Slot(
            uuid: slot.id,
            position: slot.position,
            criteria: slot.criteria,
            judgment: slot.judgment,
            template: template
        )
    }
}
