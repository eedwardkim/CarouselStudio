import CoreGraphics
import CoreModels

/// A unit-normalized vector from MobileCLIP's image or text tower.
///
/// Invariants: `vector` is L2-normalized, and its dimension is fixed per
/// `modelVersion` (512 for MobileCLIP-S2). Vectors are only comparable when
/// their `modelVersion`s match; similarity is their dot product.
public struct Embedding: Codable, Hashable, Sendable {
    public var vector: [Float]
    /// Model that produced it; embeddings from different versions never mix.
    public var modelVersion: String

    public init(vector: [Float], modelVersion: String) {
        self.vector = vector
        self.modelVersion = modelVersion
    }
}

/// Failure vocabulary for embedding inference.
public enum EmbeddingError: Error, Equatable, Sendable {
    /// The Core ML model can't be loaded or compiled on this device/OS.
    /// Fatal for the whole matching pass, not for one input.
    case modelUnavailable(reason: String)
    /// This image couldn't be encoded (unsupported pixel format, zero-sized
    /// bitmap). Skip the asset; other inputs are unaffected.
    case imageEncodingFailed(reason: String)
    /// This string couldn't be encoded. Rare — tokenization accepts anything;
    /// this signals inference failure, not bad input.
    case textEncodingFailed(reason: String)
}

/// Stage-1 primitive: the two CLIP towers. The production implementation
/// wraps MobileCLIP via Core ML. Similarity is computed by `SlotMatching`,
/// not here — exposing the towers (rather than a scoring call) is what makes
/// embedding caching possible: editing a slot's criteria re-embeds one
/// string, not the whole library.
///
/// Both towers are deterministic (same input + `modelVersion` → same vector)
/// and safe to call concurrently; batching is an implementation concern.
public protocol EmbeddingProviding: Sendable {
    /// Identifies the model and weights. Stamped into every produced
    /// `Embedding` and used by `EmbeddingStore` as part of the cache key.
    /// Constant for the lifetime of the instance.
    var modelVersion: String { get }

    /// Embeds one image through the image tower.
    ///
    /// - Parameter image: Any decodable `CGImage`, upright. Implementations
    ///   resize/crop to the encoder's native input; callers should pass the
    ///   `scoringThumbnail` variant rather than full-resolution pixels.
    /// - Returns: A unit-normalized vector stamped with `modelVersion`.
    /// - Throws: `EmbeddingError.modelUnavailable` or `.imageEncodingFailed`;
    ///   `CancellationError` if the task is cancelled.
    func embedding(for image: CGImage) async throws -> Embedding

    /// Embeds one string through the text tower. Callers pass slot criteria,
    /// optionally wrapped in a prompt template ("a photo of …").
    ///
    /// Text beyond CLIP's 77-token window is truncated silently, matching
    /// standard CLIP behavior — `TemplateValidating` warns upstream; this call
    /// never rejects long input. Empty strings embed without error (garbage
    /// in, garbage out).
    ///
    /// - Returns: A unit-normalized vector stamped with `modelVersion`.
    /// - Throws: `EmbeddingError.modelUnavailable` or `.textEncodingFailed`;
    ///   `CancellationError` if the task is cancelled.
    func embedding(for text: String) async throws -> Embedding
}
