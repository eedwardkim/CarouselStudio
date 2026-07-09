import CoreGraphics
import CoreModels
import Foundation
import Photos
import os
#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// `PhotoSource` backed by the local PhotoKit library (`PHPhotoLibrary`).
///
/// Stateless by design: PhotoKit's shared objects (`PHPhotoLibrary`,
/// `PHImageManager`) are internally thread-safe, so this struct holds no
/// storage of its own and is trivially `Sendable`. Consumers never see
/// `PHAsset` — only `CoreModels.PhotoAsset` and `CGImage` cross the boundary.
public struct PhotoKitSource: PhotoSource {
    public let kind: PhotoSourceKind = .photoKit

    /// Longest display-variant edge, in pixels. Big enough for full-screen
    /// browsing on any current iPhone without decoding originals.
    private static let displayTargetSize = CGSize(width: 1280, height: 1280)

    public init() {}

    // MARK: - Access

    public func requestAccess() async -> PhotoAccessStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard current == .notDetermined else { return Self.accessStatus(from: current) }
        let granted = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return Self.accessStatus(from: granted)
    }

    private static func accessStatus(from status: PHAuthorizationStatus) -> PhotoAccessStatus {
        switch status {
        case .authorized: .full
        case .limited: .limited
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    /// Whether enumeration/decoding may proceed under the current status.
    private var hasReadAccess: Bool {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited: true
        default: false
        }
    }

    // MARK: - Enumeration

    public func assets(matching query: AssetQuery) -> AsyncThrowingStream<PhotoAsset, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                guard hasReadAccess else {
                    continuation.finish(throwing: PhotoSourceError.accessDenied)
                    return
                }

                let options = PHFetchOptions()
                var predicates: [NSPredicate] = []
                if let after = query.capturedAfter {
                    predicates.append(NSPredicate(format: "creationDate > %@", after as NSDate))
                }
                if let before = query.capturedBefore {
                    predicates.append(NSPredicate(format: "creationDate < %@", before as NSDate))
                }
                if !predicates.isEmpty {
                    options.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
                }
                // Newest capture first. PhotoKit's SQLite sorts NULL creation
                // dates as smallest, so with a descending sort the undated
                // assets land after every dated one, in stable store order —
                // exactly the contract's requirement.
                options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                if let limit = query.limit {
                    options.fetchLimit = limit
                }

                // PHFetchResult faults objects in in batches, so enumerating
                // here never materializes a 50k-photo library at once.
                let result = PHAsset.fetchAssets(with: .image, options: options)
                result.enumerateObjects { asset, _, stop in
                    if Task.isCancelled {
                        stop.pointee = true
                        return
                    }
                    continuation.yield(
                        PhotoAsset(
                            id: PhotoAssetID(source: .photoKit, rawValue: asset.localIdentifier),
                            capturedAt: asset.creationDate,
                            pixelWidth: asset.pixelWidth,
                            pixelHeight: asset.pixelHeight,
                            isFavorite: asset.isFavorite
                        ))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Pixel decode

    public func image(for id: PhotoAssetID, variant: ImageVariant) async throws -> CGImage {
        precondition(id.source == kind, "asset \(id.rawValue) does not belong to PhotoKit")
        guard hasReadAccess else { throw PhotoSourceError.accessDenied }

        guard
            let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id.rawValue], options: nil)
                .firstObject
        else {
            throw PhotoSourceError.assetNotFound(id)
        }

        let targetSize: CGSize
        let contentMode: PHImageContentMode
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.version = .current
        switch variant {
        case .scoringThumbnail:
            // Square crop at MobileCLIP's native input edge; the embedding
            // provider re-validates size, so `.exact` keeps work out of Core ML.
            targetSize = CGSize(width: 256, height: 256)
            contentMode = .aspectFill
            options.resizeMode = .exact
        case .display:
            targetSize = Self.displayTargetSize
            contentMode = .aspectFit
            options.resizeMode = .fast
        case .original:
            targetSize = PHImageManagerMaximumSize
            contentMode = .default
            options.resizeMode = .none
        }

        // Tracks the in-flight PhotoKit request so task cancellation can stop
        // it promptly, and guards the continuation against double resume.
        let state = OSAllocatedUnfairLock(initialState: RequestState())

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let requestID = PHImageManager.default().requestImage(
                    for: asset,
                    targetSize: targetSize,
                    contentMode: contentMode,
                    options: options
                ) { image, info in
                    // `.highQualityFormat` promises a single callback, but a
                    // degraded preview slipping through must not double-resume.
                    if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                    let shouldResume = state.withLock { state in
                        if state.resumed { return false }
                        state.resumed = true
                        return true
                    }
                    guard shouldResume else { return }

                    if (info?[PHImageCancelledKey] as? Bool) == true {
                        continuation.resume(throwing: CancellationError())
                    } else if let cgImage = image?.asCGImage {
                        continuation.resume(returning: cgImage)
                    } else if (info?[PHImageResultIsInCloudKey] as? Bool) == true
                        || info?[PHImageErrorKey] is NSError
                    {
                        // No pixels plus an error/in-cloud marker: data is
                        // unreachable right now (iCloud offload, network).
                        continuation.resume(throwing: PhotoSourceError.resourceUnavailable(id))
                    } else {
                        continuation.resume(throwing: PhotoSourceError.decodingFailed(id))
                    }
                }
                let cancelledEarly = state.withLock { state in
                    state.requestID = requestID
                    return state.cancelled
                }
                if cancelledEarly {
                    PHImageManager.default().cancelImageRequest(requestID)
                }
            }
        } onCancel: {
            let requestID = state.withLock { state in
                state.cancelled = true
                return state.requestID
            }
            if let requestID {
                PHImageManager.default().cancelImageRequest(requestID)
            }
        }
    }
}

/// Mutable bookkeeping for one `requestImage` call, guarded by an unfair lock.
private struct RequestState: Sendable {
    var requestID: PHImageRequestID?
    var resumed = false
    var cancelled = false
}

#if canImport(UIKit)
    extension UIImage {
        /// The upright bitmap for this image. PhotoKit delivers orientation
        /// pre-applied for resized renditions, so `cgImage` is already upright.
        fileprivate var asCGImage: CGImage? { cgImage }
    }
#elseif canImport(AppKit)
    extension NSImage {
        fileprivate var asCGImage: CGImage? {
            cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
    }
#endif
