import CoreModels
import Foundation
import SwiftData

/// A photo the matching pipeline has seen, identified only by its
/// source-qualified asset identifier. Persists the derived MobileCLIP
/// embedding and accumulates per-slot scores and feedback — never pixels.
/// Display images are always re-fetched through `PhotoSource`.
@Model
public final class Candidate {
    /// Source-qualified dedupe key, `"<source>:<localIdentifier>"`
    /// (e.g. `"photoKit:ABC-123"`). See `assetKey(for:)`.
    @Attribute(.unique) public var assetKey: String
    /// Raw value of `PhotoSourceKind`; use `assetID` in code.
    public var sourceRawValue: String
    /// `PHAsset.localIdentifier` for PhotoKit assets; the picker media-item
    /// ID for Google Photos imports. Device-local — never synced.
    public var assetLocalIdentifier: String
    /// MobileCLIP image embedding as a raw Float32 buffer (512-d for the S2
    /// model, ~2 KB), or nil until the first embed pass — or after a model
    /// upgrade invalidates it. Use `embeddingVector` in code.
    @Attribute(.externalStorage) public var embedding: Data?
    /// Which MobileCLIP release produced `embedding`; a mismatch with the
    /// current model version means "re-embed on the next pass".
    public var embeddingModelVersion: String?
    public var firstSeenAt: Date

    @Relationship(deleteRule: .cascade, inverse: \SlotMatchScore.candidate)
    public var matchScores: [SlotMatchScore]

    @Relationship(deleteRule: .cascade, inverse: \FeedbackEvent.candidate)
    public var feedbackEvents: [FeedbackEvent]

    public var assetID: PhotoAssetID {
        PhotoAssetID(
            source: PhotoSourceKind(rawValue: sourceRawValue) ?? .photoKit,
            rawValue: assetLocalIdentifier
        )
    }

    public var embeddingVector: [Float]? {
        get {
            guard let embedding, !embedding.isEmpty else { return nil }
            var vector = [Float](repeating: 0, count: embedding.count / MemoryLayout<Float>.stride)
            vector.withUnsafeMutableBytes { _ = embedding.copyBytes(to: $0) }
            return vector
        }
        set { embedding = newValue.map(Self.data(from:)) }
    }

    public static func assetKey(for id: PhotoAssetID) -> String {
        "\(id.source.rawValue):\(id.rawValue)"
    }

    private static func data(from vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    public init(
        assetID: PhotoAssetID,
        embeddingVector: [Float]? = nil,
        embeddingModelVersion: String? = nil,
        firstSeenAt: Date = Date()
    ) {
        self.assetKey = Self.assetKey(for: assetID)
        self.sourceRawValue = assetID.source.rawValue
        self.assetLocalIdentifier = assetID.rawValue
        self.embedding = embeddingVector.map(Self.data(from:))
        self.embeddingModelVersion = embeddingModelVersion
        self.firstSeenAt = firstSeenAt
        self.matchScores = []
        self.feedbackEvents = []
    }
}

/// How well one candidate fits one slot — the persisted counterpart of
/// `CoreModels.SlotCandidate`. Rows exist only for shortlisted candidates
/// (top N per slot), not the full corpus × slots cross product; full-corpus
/// scoring stays transient inside the Matching Engine.
@Model
public final class SlotMatchScore {
    /// Stage-1 MobileCLIP similarity, calibrated to 0…1 per slot.
    public var clipScore: Double
    /// Stage-2 Foundation Models fit score (Phase 4), if that pass has run.
    public var reasoningFitScore: Double?
    /// Stage-2 model-provided justification, surfaced as "why this photo?".
    public var reasoningRationale: String?
    /// Final ranking key: `clipScore` after stage 1, blended after stage 2.
    public var combinedScore: Double
    public var computedAt: Date

    public var slot: Slot?
    public var candidate: Candidate?

    public var verdict: ReasoningVerdict? {
        get {
            guard let reasoningFitScore, let reasoningRationale else { return nil }
            return ReasoningVerdict(fitScore: reasoningFitScore, rationale: reasoningRationale)
        }
        set {
            reasoningFitScore = newValue?.fitScore
            reasoningRationale = newValue?.rationale
        }
    }

    public init(
        slot: Slot? = nil,
        candidate: Candidate? = nil,
        clipScore: Double,
        verdict: ReasoningVerdict? = nil,
        combinedScore: Double? = nil,
        computedAt: Date = Date()
    ) {
        self.clipScore = clipScore
        self.reasoningFitScore = verdict?.fitScore
        self.reasoningRationale = verdict?.rationale
        self.combinedScore = combinedScore ?? clipScore
        self.computedAt = computedAt
        self.slot = slot
        self.candidate = candidate
    }
}

/// One accept/replace/reject decision the user made about a candidate for a
/// slot — the persisted counterpart of `CoreModels.MatchFeedback`, kept as
/// an append-only history for Phase-4 personalization.
@Model
public final class FeedbackEvent {
    /// Raw value of `FeedbackSignal`; use `signal` in code.
    public var signalRawValue: String
    public var recordedAt: Date

    public var candidate: Candidate?
    public var slot: Slot?

    public var signal: FeedbackSignal {
        // Unknown raw values (schema drift) read as the negative signal so
        // personalization never over-trusts them.
        get { FeedbackSignal(rawValue: signalRawValue) ?? .rejected }
        set { signalRawValue = newValue.rawValue }
    }

    public init(
        candidate: Candidate? = nil,
        slot: Slot? = nil,
        signal: FeedbackSignal,
        recordedAt: Date = Date()
    ) {
        self.signalRawValue = signal.rawValue
        self.recordedAt = recordedAt
        self.candidate = candidate
        self.slot = slot
    }
}
