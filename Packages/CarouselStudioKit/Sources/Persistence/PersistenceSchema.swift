import Foundation
import SwiftData

/// The single SwiftData schema for the app. All models live in one container
/// so relationships (Template ↔ Slot ↔ Candidate ↔ Quest) resolve; store
/// implementations share it and map models to CoreModels value types at
/// their boundaries.
public enum PersistenceSchema {
    public static let models: [any PersistentModel.Type] = [
        Template.self,
        Slot.self,
        Candidate.self,
        SlotMatchScore.self,
        FeedbackEvent.self,
        Quest.self,
        QuestSlotState.self,
        SongCorpusEntry.self,
    ]

    /// The app's on-disk container; tests pass `inMemory: true`.
    public static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: Schema(models), configurations: [configuration])
    }
}
