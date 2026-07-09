import CoreGraphics
import CoreModels
import Foundation

/// Read access the user has granted for a source.
public enum PhotoAccessStatus: String, Codable, CaseIterable, Sendable {
    case notDetermined
    case restricted
    case denied
    /// iOS limited-library mode: enumeration works, but covers only the photos
    /// the user selected in the limited-library picker.
    case limited
    case full
}

/// Failure vocabulary shared by all photo sources. User/task cancellation is
/// never one of these — cancelled calls throw `CancellationError` as usual.
public enum PhotoSourceError: Error, Equatable, Sendable {
    /// Access is denied, restricted, or was never requested. Callers must get
    /// a usable status from `requestAccess()` before enumerating or decoding.
    case accessDenied
    /// The asset no longer exists — typically deleted between enumeration and
    /// this call. Routine during rescans; callers drop the ID and continue.
    case assetNotFound(PhotoAssetID)
    /// Pixels can't be produced right now (e.g. the original is
    /// iCloud-offloaded and the network is unreachable). Retryable later.
    case resourceUnavailable(PhotoAssetID)
    /// The stored data exists but can't be decoded into an image. Permanent
    /// for this asset; callers should skip it.
    case decodingFailed(PhotoAssetID)
}

/// A place photos come from. `PhotoKitSource` (Phase 1) wraps PHPhotoLibrary;
/// `GooglePhotosSource` (Phase 4) serves previously imported picker items from
/// local storage. Consumers never see PHAsset or Google types.
///
/// Implementations are safe to call from any task concurrently.
public protocol PhotoSource: Sendable {
    /// Which source this is. Constant for the lifetime of the instance, and
    /// equal to `id.source` of every asset this instance produces.
    var kind: PhotoSourceKind { get }

    /// Requests read access, presenting the system prompt when the status is
    /// `.notDetermined`; otherwise returns the current status without UI.
    /// Idempotent. Never throws — every failure is expressed as a status.
    func requestAccess() async -> PhotoAccessStatus

    /// Metadata enumeration, newest capture first (assets without a capture
    /// date sort after those with one, in a stable order).
    ///
    /// Elements are produced lazily, so a 50k-photo library is never
    /// materialized in memory at once. Under `.limited` access, only the
    /// user-selected subset appears — that is not an error.
    ///
    /// - Parameter query: Date-range and count constraints; `.all` for the
    ///   whole visible library.
    /// - Returns: A stream that finishes after the last matching asset.
    ///   Cancelling the consuming task stops enumeration promptly.
    /// - Throws: `PhotoSourceError.accessDenied` (as the stream's failure)
    ///   when access is denied, restricted, or not yet determined.
    func assets(matching query: AssetQuery) -> AsyncThrowingStream<PhotoAsset, Error>

    /// Decodes pixels for one asset, on demand.
    ///
    /// The returned image is upright — EXIF orientation already applied — so
    /// it can go straight into the CLIP encoder or the UI. Implementations
    /// should cache `scoringThumbnail` renditions aggressively: one is
    /// requested per asset during a full scan.
    ///
    /// - Parameters:
    ///   - id: Must belong to this source (`id.source == kind`).
    ///   - variant: Which rendition to decode; see `ImageVariant`.
    /// - Returns: The decoded, upright image.
    /// - Throws: `PhotoSourceError.accessDenied`; `.assetNotFound` when the
    ///   asset was deleted since enumeration; `.resourceUnavailable` when the
    ///   data is remote and unreachable (common for `.original` of
    ///   iCloud-offloaded photos — thumbnails are usually local);
    ///   `.decodingFailed` for corrupt data. `CancellationError` if the task
    ///   is cancelled.
    func image(for id: PhotoAssetID, variant: ImageVariant) async throws -> CGImage
}

public struct AssetQuery: Codable, Hashable, Sendable {
    public var capturedAfter: Date?
    public var capturedBefore: Date?
    /// Cap on results, newest first. `nil` means unbounded.
    public var limit: Int?

    public init(capturedAfter: Date? = nil, capturedBefore: Date? = nil, limit: Int? = nil) {
        self.capturedAfter = capturedAfter
        self.capturedBefore = capturedBefore
        self.limit = limit
    }

    public static let all = AssetQuery()
}

/// The rendition to decode.
public enum ImageVariant: Hashable, Sendable {
    /// Small square render fed to MobileCLIP (encoder-native resolution).
    case scoringThumbnail
    /// Screen-resolution image for browsing candidates.
    case display
    /// Full resolution for export.
    case original
}
