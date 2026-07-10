import Foundation
import Persistence
import SwiftData
import Testing

/// Structural checks on the app-layer composition root.
///
/// The package tests cannot import the app target, so where a contract lives
/// in app code (AppServices.swift) these tests inspect the source directly —
/// lint-style. The contract under test: `PersistenceSchema.makeContainer` is
/// `throws` by design (storage can be unavailable: disk full, corrupt store,
/// failed migration), and the composition root must handle that failure
/// gracefully instead of crashing at launch.
@Suite struct CompositionRootStructuralTests {

    /// `AppServices.init` currently does
    /// `try! PersistenceSchema.makeContainer(inMemory: false)`, which turns
    /// every container failure into an unrecoverable crash on the very first
    /// frame of app launch. The composition root should propagate or absorb
    /// the error (failable init, error state the UI can render, or a fallback
    /// in-memory container with a user-visible warning) — never `try!`.
    @Test func appServicesDoesNotForceTryTheModelContainer() throws {
        // Repo root, derived from this file's location:
        // <root>/Packages/CarouselStudioKit/Tests/CarouselStudioKitTests/<file>
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // CarouselStudioKitTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // CarouselStudioKit/
            .deletingLastPathComponent()  // Packages/
            .deletingLastPathComponent()  // repo root
        let appServicesURL = repoRoot.appending(path: "CarouselStudio/AppServices.swift")

        guard let source = try? String(contentsOf: appServicesURL, encoding: .utf8) else {
            // Package checked out standalone (no app target on disk):
            // nothing to verify here.
            return
        }
        #expect(
            !source.contains("try! PersistenceSchema.makeContainer"),
            "AppServices must not force-try ModelContainer creation; a storage fault at launch must degrade gracefully, not crash")
    }

    /// Pin the throwing shape of the seam itself: `makeContainer` can fail, so
    /// callers are forced to write a `try` — the composition root's `try!` is
    /// a choice, not a necessity. (Also proves the happy path works, so a
    /// graceful-handling refactor has a green baseline.)
    @Test func makeContainerFailureIsRepresentable() throws {
        let container = try PersistenceSchema.makeContainer(inMemory: true)
        _ = container
    }
}
