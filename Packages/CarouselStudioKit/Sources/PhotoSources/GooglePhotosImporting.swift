import CoreModels

/// Outcome of one Google Photos picker session.
public struct GooglePhotosImportResult: Hashable, Sendable {
    /// Downloaded and stored locally — already servable by the
    /// `.googlePhotos` `PhotoSource`, keyed by picker media-item ID.
    public var imported: [PhotoAsset]
    /// Items the user picked whose download failed (network drop, item
    /// revoked mid-session). Counted so the UI can say "3 photos didn't make
    /// it" and offer a retry, instead of silently under-importing.
    public var failedItemCount: Int

    public init(imported: [PhotoAsset] = [], failedItemCount: Int = 0) {
        self.imported = imported
        self.failedItemCount = failedItemCount
    }
}

public enum GooglePhotosImportError: Error, Equatable, Sendable {
    /// No Google account is connected, or sign-in/consent failed.
    case notAuthenticated
    /// The picker session couldn't be created or returned a broken payload.
    case pickerFailed(reason: String)
}

/// Phase 4. One-shot, user-driven import via the Google Photos Picker API.
/// Google removed the Library API's broad read scopes in 2025, so there is no
/// silent scanning: the user picks photos in Google's UI, we download local
/// copies, and the copies join the corpus as `PhotoSourceKind.googlePhotos`
/// assets served by a local `PhotoSource`.
public protocol GooglePhotosImporting: Sendable {
    /// Presents Google's picker and suspends until the session ends.
    ///
    /// Dismissing the picker without choosing anything is a normal return
    /// with an empty result — not an error. Individual download failures
    /// don't fail the import: successes are returned, failures are counted.
    /// No Google session or token outlives the call.
    ///
    /// - Returns: Locally stored assets plus a count of failed downloads.
    /// - Throws: `GooglePhotosImportError`; `CancellationError` if the
    ///   surrounding task is cancelled mid-download.
    func importFromPicker() async throws -> GooglePhotosImportResult
}
