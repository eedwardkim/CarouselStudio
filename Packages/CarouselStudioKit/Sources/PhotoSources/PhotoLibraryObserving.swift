import CoreModels

/// Continuous change monitoring. Only the PhotoKit source implements this —
/// it wraps PHPhotoLibraryChangeObserver. Google Photos is picker-driven and
/// never observed.
///
/// Observation only works while the app has a live process; changes missed
/// while suspended are caught by scheduled rescans, not by this stream.
public protocol PhotoLibraryObserving: Sendable {
    /// One element per observed library change, coalesced and debounced so
    /// bursts (imports, iCloud syncs) don't trigger rescan storms.
    ///
    /// No replay: only changes committed after subscription are delivered.
    /// The stream never finishes on its own — it ends when the consuming task
    /// is cancelled. Designed for a single consumer (the Quest Engine); the
    /// composition root fans out if a second listener ever appears.
    func changes() -> AsyncStream<PhotoLibraryChange>
}

/// A net diff of the library. The three fields are disjoint: an asset appears
/// in at most one of them per element (an insert followed by a delete inside
/// one coalescing window nets out to nothing).
public struct PhotoLibraryChange: Hashable, Sendable {
    /// New assets — candidates for scoring.
    public var inserted: [PhotoAssetID]
    /// Gone. Scores, candidates, and cached embeddings must be dropped.
    public var deleted: [PhotoAssetID]
    /// Edited in place (crop, filter, adjustment) — cached embeddings for
    /// these assets are stale and must be recomputed.
    public var modified: [PhotoAssetID]

    public init(
        inserted: [PhotoAssetID] = [],
        deleted: [PhotoAssetID] = [],
        modified: [PhotoAssetID] = []
    ) {
        self.inserted = inserted
        self.deleted = deleted
        self.modified = modified
    }
}
