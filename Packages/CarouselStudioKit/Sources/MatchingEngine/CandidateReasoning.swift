import CoreGraphics
import CoreModels

public enum ReasoningError: Error, Equatable, Sendable {
    /// Called while `isAvailable` is false, or availability was lost
    /// mid-flight (Apple Intelligence toggled off, thermal pressure).
    case unavailable
    /// The model declined the request (safety guardrails). Not retryable for
    /// this candidate.
    case guardrailBlocked
    /// The model responded, but not in the expected structured shape.
    /// Retryable once; after that, treat like `guardrailBlocked`.
    case malformedOutput(reason: String)
}

/// Stage 2 (Phase 4): closer multimodal reasoning over CLIP-shortlisted
/// candidates for subjective slots ("funny", "aesthetic"), via Apple's
/// Foundation Models framework with image input.
public protocol CandidateReasoning: Sendable {
    /// Foundation Models needs a newer OS and Apple Intelligence enabled;
    /// with a 17.0 deployment target this is a runtime capability, not a
    /// compile-time guarantee. It can also flip mid-session (Settings toggle,
    /// device conditions), so callers check per matching pass, not once at
    /// launch. When false, subjective slots keep their stage-1 ranking — the
    /// app degrades, never breaks.
    var isAvailable: Bool { get }

    /// Judges one shortlisted candidate against one slot's criteria.
    /// Batching, prompt construction, and structured-output parsing are
    /// implementation concerns.
    ///
    /// - Parameters:
    ///   - asset: Metadata for the candidate; capture date and similar fields
    ///     may inform the prompt.
    ///   - image: An upright, display-quality rendition — reasoning quality
    ///     needs more pixels than the scoring thumbnail.
    ///   - slot: Its `criteria` is the question being asked.
    /// - Returns: A verdict with `fitScore` in 0…1 and a short, user-facing
    ///   `rationale` ("why this photo?").
    /// - Throws: `ReasoningError`; `CancellationError` if the task is
    ///   cancelled. Whatever the error, the orchestrator keeps the
    ///   candidate's stage-1 rank — a failed verdict must never evict a
    ///   candidate.
    func verdict(for asset: PhotoAsset, image: CGImage, slot: Slot) async throws -> ReasoningVerdict
}
