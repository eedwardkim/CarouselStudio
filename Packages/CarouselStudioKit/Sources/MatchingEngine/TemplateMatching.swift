import CoreModels
import PhotoSources

/// Orchestrates the full two-stage pipeline for a template. Concrete engines
/// are constructed with a `PhotoSource`, `EmbeddingProviding`,
/// `EmbeddingStore`, `SlotMatching`, and optionally `CandidateReasoning` —
/// the protocol itself stays dependency-free so the UI and Quest Engine can
/// share one engine instance.
///
/// Error policy: trouble with a *single asset* (undecodable, deleted
/// mid-scan, un-embeddable) is skipped — that asset simply produces no
/// candidates. Systemic failures (photo access denied, model unavailable,
/// storage faults) throw. "No candidates found" is never an error.
public protocol TemplateMatching: Sendable {
    /// Full pass: enumerate corpus → embed images (cache-aware) → rank every
    /// slot via `SlotMatching` → stage-2 refinement for subjective slots
    /// (when enabled and available) → ranked candidates.
    ///
    /// - Parameters:
    ///   - template: The template to match. Callers validate first
    ///     (`TemplateValidating`); a slotless template yields an empty match
    ///     rather than throwing.
    ///   - options: Shortlist size, stage-2 toggle, corpus query.
    /// - Returns: A `TemplateMatch` whose `candidatesBySlot` has a key for
    ///   *every* slot in the template — an empty array means "no candidates",
    ///   which is exactly the evidence `CoveragePolicy` needs. Each slot's
    ///   candidates are ordered by `combinedScore` descending.
    /// - Throws: `PhotoSourceError.accessDenied`,
    ///   `EmbeddingError.modelUnavailable`, `SlotMatchingError`,
    ///   `PersistenceError` (embedding cache), `CancellationError`. Stage-2
    ///   failures never propagate — a failed verdict downgrades that
    ///   candidate to its stage-1 rank.
    func match(_ template: Template, options: MatchOptions) async throws -> TemplateMatch

    /// Incremental pass: fold a library change into an existing match without
    /// re-scoring the whole corpus. The Quest Engine's hot path — only
    /// new/modified assets are embedded.
    ///
    /// Per change field: `inserted` assets are embedded and scored into every
    /// slot; `deleted` assets are removed from every candidate list;
    /// `modified` assets are re-embedded and re-scored. The result is
    /// equivalent to re-running `match` over the updated corpus, except that
    /// implementations may approximate per-slot recalibration — unchanged
    /// candidates' scores can drift slightly, but their order relative to
    /// each other is preserved.
    ///
    /// - Parameters:
    ///   - existing: The match to fold into, typically the last saved result.
    ///   - change: Net library diff (fields are disjoint).
    ///   - template: Must be the template `existing` was produced from. If
    ///     the template itself changed, run a full `match` instead.
    ///   - options: Should equal the options that produced `existing`.
    /// - Returns: An updated match with the same shape guarantees as `match`.
    /// - Throws: Same as `match`.
    func update(
        _ existing: TemplateMatch,
        applying change: PhotoLibraryChange,
        for template: Template,
        options: MatchOptions
    ) async throws -> TemplateMatch
}

public struct MatchOptions: Hashable, Sendable {
    /// Candidates kept per slot after stage 1. Must be ≥ 1.
    public var shortlistSize: Int
    /// Run Foundation Models on subjective slots (Phase 4; ignored when the
    /// reasoner reports itself unavailable).
    public var enableReasoningPass: Bool
    /// Restrict the corpus (e.g. "photos from this trip"). `nil` = everything.
    public var query: AssetQuery?

    public init(
        shortlistSize: Int = 20,
        enableReasoningPass: Bool = false,
        query: AssetQuery? = nil
    ) {
        self.shortlistSize = shortlistSize
        self.enableReasoningPass = enableReasoningPass
        self.query = query
    }

    public static let `default` = MatchOptions()
}

/// Phase 4: records accept/replace/reject signals so future matches can be
/// personalized (per-user prompt tuning, score re-weighting).
public protocol FeedbackRecording: Sendable {
    /// Appends one signal. Feedback is an append-only log — recording the
    /// same event twice stores two entries.
    /// - Throws: `PersistenceError`.
    func record(_ feedback: MatchFeedback) async throws

    /// Every signal for a template, oldest first (stable chronology for
    /// learning). Empty when none exist — never an error.
    /// - Throws: `PersistenceError`.
    func feedbackHistory(for templateID: Template.ID) async throws -> [MatchFeedback]
}
