import CoreModels
import Foundation
import Photos

/// `PhotoLibraryObserving` implementation backed by PhotoKit's change observer.
///
/// Changes are coalesced and debounced for 0.5 seconds so that bursts such as
/// iCloud syncs or bulk imports do not overwhelm downstream rescans. The stream
/// has a single consumer: calling `changes()` again finishes the previous
/// continuation.
public final class PhotoKitLibraryObserver: NSObject, PhotoLibraryObserving, PHPhotoLibraryChangeObserver, @unchecked Sendable {
    private let lock = NSLock()
    private var fetchResult: PHFetchResult<PHAsset>
    private var continuation: AsyncStream<PhotoLibraryChange>.Continuation?
    private var continuationToken: UUID?
    private var pendingChanges: [PhotoLibraryChange] = []
    private var pendingWorkItem: DispatchWorkItem?

    public override init() {
        self.fetchResult = PHAsset.fetchAssets(with: .image, options: nil)
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)

        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.finish()
    }

    public func changes() -> AsyncStream<PhotoLibraryChange> {
        AsyncStream { [weak self] continuation in
            guard let self else { return }

            let token = UUID()
            self.lock.lock()
            self.continuation?.finish()
            self.continuation = continuation
            self.continuationToken = token
            self.lock.unlock()

            continuation.onTermination = { [weak self] _ in
                self?.lock.lock()
                if self?.continuationToken == token {
                    self?.continuation = nil
                    self?.continuationToken = nil
                }
                self?.lock.unlock()
            }
        }
    }

    @objc public func photoLibraryDidChange(_ changeInstance: PHChange) {
        lock.lock()
        defer { lock.unlock() }

        guard let changeDetails = changeInstance.changeDetails(for: fetchResult) else {
            return
        }

        let inserted = changeDetails.insertedObjects.map {
            PhotoAssetID(source: .photoKit, rawValue: $0.localIdentifier)
        }
        let deleted = changeDetails.removedObjects.map {
            PhotoAssetID(source: .photoKit, rawValue: $0.localIdentifier)
        }
        let modified = changeDetails.changedObjects
            .map { PhotoAssetID(source: .photoKit, rawValue: $0.localIdentifier) }
            .filter { !deleted.contains($0) && !inserted.contains($0) }

        let change = PhotoLibraryChange(
            inserted: inserted,
            deleted: deleted,
            modified: modified
        )
        guard !change.isEmpty else {
            fetchResult = changeDetails.fetchResultAfterChanges
            return
        }

        pendingChanges.append(change)
        fetchResult = changeDetails.fetchResultAfterChanges

        pendingWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.flushPendingChanges()
        }
        pendingWorkItem = workItem
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    private func flushPendingChanges() {
        lock.lock()
        let changes = pendingChanges
        let merged = Self.merge(changes)
        let cont = continuation
        pendingChanges = []
        pendingWorkItem = nil
        lock.unlock()

        guard !merged.isEmpty else { return }
        cont?.yield(merged)
    }
}

// MARK: - Coalescing merge

extension PhotoKitLibraryObserver {
    /// Merges a sequence of batched changes into a single net change.
    ///
    /// Precedence rules across bursts:
    /// - Deleted takes precedence over inserted and modified.
    /// - Inserted takes precedence over modified.
    ///
    /// The resulting arrays are therefore disjoint: an ID appears in at most one
    /// of them.
    static func merge(_ changes: [PhotoLibraryChange]) -> PhotoLibraryChange {
        var inserted = Set<PhotoAssetID>()
        var deleted = Set<PhotoAssetID>()
        var modified = Set<PhotoAssetID>()

        for change in changes {
            inserted.formUnion(Set(change.inserted))
            deleted.formUnion(Set(change.deleted))
            modified.formUnion(Set(change.modified))
        }

        // Apply precedence: deleted > inserted > modified.
        inserted.subtract(deleted)
        modified.subtract(deleted)
        modified.subtract(inserted)

        return PhotoLibraryChange(
            inserted: Array(inserted),
            deleted: Array(deleted),
            modified: Array(modified)
        )
    }
}

private extension PhotoLibraryChange {
    var isEmpty: Bool {
        inserted.isEmpty && deleted.isEmpty && modified.isEmpty
    }
}
