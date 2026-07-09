import CoreModels
import Foundation
import Testing
@testable import PhotoSources

@Suite struct PhotoKitLibraryObserverTests {
    @Test func mergeEmpty() {
        let change = PhotoLibraryChange(inserted: [id("a")], deleted: [], modified: [])
        #expect(PhotoKitLibraryObserver.merge([]).isEmpty)
        #expect(PhotoKitLibraryObserver.merge([change]) == change)
    }

    @Test func mergeDisjoint() {
        let c1 = PhotoLibraryChange(
            inserted: [id("a")],
            deleted: [id("b")],
            modified: [id("c")]
        )
        let c2 = PhotoLibraryChange(
            inserted: [id("d")],
            deleted: [id("e")],
            modified: [id("f")]
        )
        let merged = PhotoKitLibraryObserver.merge([c1, c2])
        #expect(Set(merged.inserted) == [id("a"), id("d")])
        #expect(Set(merged.deleted) == [id("b"), id("e")])
        #expect(Set(merged.modified) == [id("c"), id("f")])
    }

    @Test func deleteWinsOverInsert() {
        let c1 = PhotoLibraryChange(inserted: [id("x")], deleted: [], modified: [])
        let c2 = PhotoLibraryChange(inserted: [], deleted: [id("x")], modified: [])
        let merged = PhotoKitLibraryObserver.merge([c1, c2])
        #expect(merged.deleted == [id("x")])
        #expect(merged.inserted.isEmpty)
        #expect(merged.modified.isEmpty)
    }

    @Test func insertWinsOverModify() {
        let c1 = PhotoLibraryChange(inserted: [], deleted: [], modified: [id("x")])
        let c2 = PhotoLibraryChange(inserted: [id("x")], deleted: [], modified: [])
        let merged = PhotoKitLibraryObserver.merge([c1, c2])
        #expect(merged.inserted == [id("x")])
        #expect(merged.deleted.isEmpty)
        #expect(merged.modified.isEmpty)
    }

    @Test func deleteWinsOverModify() {
        let c1 = PhotoLibraryChange(inserted: [], deleted: [], modified: [id("x")])
        let c2 = PhotoLibraryChange(inserted: [], deleted: [id("x")], modified: [])
        let merged = PhotoKitLibraryObserver.merge([c1, c2])
        #expect(merged.deleted == [id("x")])
        #expect(merged.inserted.isEmpty)
        #expect(merged.modified.isEmpty)
    }

    @Test func allArraysDisjoint() {
        let c1 = PhotoLibraryChange(
            inserted: [id("a"), id("b")],
            deleted: [id("c")],
            modified: [id("d")]
        )
        let c2 = PhotoLibraryChange(
            inserted: [id("c")],
            deleted: [id("b")],
            modified: [id("a")]
        )
        let merged = PhotoKitLibraryObserver.merge([c1, c2])
        let combined = Set(merged.inserted + merged.deleted + merged.modified)
        #expect(combined.count == merged.inserted.count + merged.deleted.count + merged.modified.count)
    }

    @Test func emptyChangeSkipped() {
        let empty = PhotoLibraryChange(inserted: [], deleted: [], modified: [])
        let nonEmpty = PhotoLibraryChange(inserted: [id("a")], deleted: [], modified: [])
        let merged = PhotoKitLibraryObserver.merge([empty, nonEmpty, empty])
        #expect(merged == nonEmpty)
    }
}

private func id(_ rawValue: String) -> PhotoAssetID {
    PhotoAssetID(source: .photoKit, rawValue: rawValue)
}

private extension PhotoLibraryChange {
    var isEmpty: Bool {
        inserted.isEmpty && deleted.isEmpty && modified.isEmpty
    }
}
