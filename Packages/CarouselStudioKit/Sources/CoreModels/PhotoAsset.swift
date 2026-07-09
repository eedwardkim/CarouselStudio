import Foundation

/// Where a photo came from.
public enum PhotoSourceKind: String, Codable, CaseIterable, Sendable {
    /// The user's iOS photo library via PhotoKit. Primary source; continuously
    /// monitored via PHPhotoLibraryChangeObserver.
    case photoKit
    /// Local copies from one-time, user-driven Google Photos picker imports
    /// (Phase 4). Never scanned or observed remotely.
    case googlePhotos
}

/// Stable, source-qualified identity for a photo. Everything downstream
/// (scores, embeddings, feedback) keys off this.
public struct PhotoAssetID: Codable, Hashable, Sendable {
    public var source: PhotoSourceKind
    /// `PHAsset.localIdentifier` for PhotoKit; the picker media-item ID for
    /// Google Photos imports.
    public var rawValue: String

    public init(source: PhotoSourceKind, rawValue: String) {
        self.source = source
        self.rawValue = rawValue
    }
}

/// Source-agnostic metadata snapshot. Never carries pixel data — images are
/// fetched on demand through `PhotoSource.image(for:variant:)`.
public struct PhotoAsset: Identifiable, Hashable, Sendable {
    public let id: PhotoAssetID
    public var capturedAt: Date?
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var isFavorite: Bool

    public init(
        id: PhotoAssetID,
        capturedAt: Date? = nil,
        pixelWidth: Int,
        pixelHeight: Int,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.isFavorite = isFavorite
    }
}
