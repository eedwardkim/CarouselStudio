// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CarouselStudioKit",
    // macOS is listed only so `swift build` / `swift test` work from the command
    // line without an iOS simulator; the app itself is iOS-only. Contracts are
    // framework-free (Foundation + CoreGraphics), so they compile on both.
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        // Single umbrella product; the app links it once and imports whichever
        // modules it needs (`import TemplateEngine`, `import QuestEngine`, …).
        .library(
            name: "CarouselStudioKit",
            targets: [
                "CoreModels",
                "Persistence",
                "TemplateEngine",
                "PhotoSources",
                "MatchingEngine",
                "MusicMatching",
                "QuestEngine",
            ]
        ),
    ],
    targets: [
        // Shared vocabulary: value types only, no protocols, no dependencies.
        .target(name: "CoreModels"),

        // Infrastructure: the single SwiftData schema behind the store
        // implementations. Models never leave the stores (see DATA_MODEL.md).
        .target(name: "Persistence", dependencies: ["CoreModels"]),

        // Subsystem: template CRUD, validation, starter catalog.
        .target(name: "TemplateEngine", dependencies: ["CoreModels"]),

        // Infrastructure: photo access abstraction (PhotoKit now, Google Photos
        // picker imports in Phase 4) and library change observation.
        .target(name: "PhotoSources", dependencies: ["CoreModels"]),

        // Subsystem: two-stage photo↔slot matching (MobileCLIP, then
        // Foundation Models for subjective slots in Phase 4).
        .target(name: "MatchingEngine", dependencies: ["CoreModels", "PhotoSources"]),

        // Subsystem: tag-overlap song recommendation from the curated corpus.
        .target(name: "MusicMatching", dependencies: ["CoreModels"]),

        // Subsystem: library observation → incremental rescans → coverage reports.
        .target(
            name: "QuestEngine",
            dependencies: ["CoreModels", "TemplateEngine", "PhotoSources", "MatchingEngine"]
        ),

        .testTarget(
            name: "CarouselStudioKitTests",
            dependencies: [
                "CoreModels",
                "Persistence",
                "TemplateEngine",
                "PhotoSources",
                "MatchingEngine",
                "MusicMatching",
                "QuestEngine",
            ]
        ),
    ]
)
