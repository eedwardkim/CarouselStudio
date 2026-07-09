import CoreML
import Foundation
import MatchingEngine
import Persistence
import PhotoSources
import SwiftData
import QuestEngine
import TemplateEngine
import os

/// Composition root: owns the concrete implementations behind the
/// CarouselStudioKit protocols and hands them to views via the environment.
/// Construction is lazy — the Core ML towers load on the first match, not at
/// launch.
@MainActor
@Observable
final class AppServices {
    let photoSource = PhotoKitSource()
    let starterTemplates = BuiltInStarterTemplates()
    let templateStore: SwiftDataTemplateStore

    static let logger = Logger(
        subsystem: "com.edwardkim.CarouselStudio", category: "matching")

    init() {
        let container = try! PersistenceSchema.makeContainer(inMemory: false)
        self.templateStore = SwiftDataTemplateStore(container: container)
    }

    /// Seeds the bundled starter templates on first launch.
    func seedStartersIfNeeded() async {
        do {
            let existing = try await templateStore.allTemplates()
            if existing.isEmpty {
                let starters = starterTemplates.starterTemplates()
                for template in starters {
                    try await templateStore.save(template)
                }
                AppServices.logger.info("Seeded \(starters.count) starter templates")
            }
        } catch {
            AppServices.logger.error("Failed to seed starter templates: \(error.localizedDescription)")
        }
    }

    @ObservationIgnored private var cachedEmbedder: MobileCLIPEmbeddingProvider?
    @ObservationIgnored private var cachedStore: FileEmbeddingStore?
    @ObservationIgnored private(set) var questCoordinator: DefaultQuestCoordinator?

    /// Loads (once) the bundled MobileCLIP-S0 towers.
    func embedder() async throws -> MobileCLIPEmbeddingProvider {
        if let cachedEmbedder { return cachedEmbedder }
        guard
            let imageURL = Bundle.main.url(
                forResource: "mobileclip_s0_image", withExtension: "mlmodelc"),
            let textURL = Bundle.main.url(
                forResource: "mobileclip_s0_text", withExtension: "mlmodelc")
        else {
            throw EmbeddingError.modelUnavailable(
                reason: "MobileCLIP-S0 towers are missing from the app bundle")
        }
        let configuration = MLModelConfiguration()
        #if targetEnvironment(simulator)
            // No ANE in the simulator, and its GPU path is unreliable for
            // some conv layers — CPU is correct and fast enough there.
            configuration.computeUnits = .cpuOnly
        #endif
        let embedder = try await MobileCLIPEmbeddingProvider(
            imageModelURL: imageURL,
            textModelURL: textURL,
            configuration: configuration
        )
        cachedEmbedder = embedder
        return embedder
    }

    private func embeddingStore() throws -> FileEmbeddingStore {
        if let cachedStore { return cachedStore }
        let store = FileEmbeddingStore(fileURL: try FileEmbeddingStore.defaultFileURL())
        cachedStore = store
        return store
    }

    /// A matcher wired to the shared source/embedder/cache, reporting
    /// per-asset progress through `progress` (already hopped to the main
    /// actor).
    func templateMatcher(
        progress: @escaping @MainActor (MatchProgress) -> Void
    ) async throws -> DefaultTemplateMatcher {
        DefaultTemplateMatcher(
            photoSource: photoSource,
            embedder: try await embedder(),
            embeddingStore: try embeddingStore(),
            slotMatcher: CosineSlotMatcher(),
            progress: { update in
                Task { @MainActor in progress(update) }
            }
        )
    }

    /// Creates and activates the long-running quest coordinator once photo access
    /// has been granted. Safe to call multiple times — the coordinator is only
    /// constructed on the first invocation.
    func activateQuestEngine() async {
        guard questCoordinator == nil else {
            await questCoordinator?.activate()
            return
        }

        let matcher = try? await templateMatcher(progress: { _ in })
        guard let matcher else { return }

        let coordinator = DefaultQuestCoordinator(
            observer: PhotoKitLibraryObserver(),
            templateStore: templateStore,
            matcher: matcher,
            policy: DefaultCoveragePolicy(),
            reportStore: InMemoryQuestReportStore()
        )
        self.questCoordinator = coordinator
        await coordinator.activate()
        AppServices.logger.notice("Quest engine activated")
    }

    /// Deactivates the quest coordinator when the app moves to the background.
    func deactivateQuestEngine() async {
        await questCoordinator?.deactivate()
    }
}
