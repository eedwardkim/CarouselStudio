import CoreML
import Foundation
import MatchingEngine
import PhotoSources
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

    static let logger = Logger(
        subsystem: "com.edwardkim.CarouselStudio", category: "matching")

    @ObservationIgnored private var cachedEmbedder: MobileCLIPEmbeddingProvider?
    @ObservationIgnored private var cachedStore: FileEmbeddingStore?

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
}
