import CoreModels

public enum SongCorpusError: Error, Equatable, Sendable {
    /// The bundled corpus file is missing — a packaging bug, not a user
    /// state.
    case corpusUnavailable(reason: String)
    /// The corpus file exists but doesn't parse or validate.
    case corpusCorrupted(reason: String)
}

/// Read-only access to the curated corpus: a hand-tagged JSON file bundled
/// with the app (theme/mood tags only, no audio), refreshed via app updates.
public protocol SongCorpus: Sendable {
    /// Bumped when the bundled corpus changes; recommenders may cache per
    /// version. Constant within one app launch.
    var corpusVersion: String { get }

    /// Every corpus entry, in an unspecified but stable (per `corpusVersion`)
    /// order.
    /// - Throws: `SongCorpusError`.
    func allSongs() async throws -> [Song]
}

/// Tag-overlap recommender. Deliberately no audio analysis and no live
/// third-party API — Spotify closed audio-features access in 2024 and
/// MusicKit exposes none. A suggestion names a track and a placement; the
/// user adds the actual audio in Instagram's/TikTok's native picker at
/// export.
public protocol SongRecommending: Sendable {
    /// Ranked suggestions for a template.
    ///
    /// - Parameters:
    ///   - template: Its `moodTags` are the primary matching signal.
    ///   - match: Pass the current match when one exists so tags can be
    ///     weighted by which slots actually have strong candidates (a
    ///     "funny" template whose funny slot is empty shouldn't pull a
    ///     comedy track). `nil` = rank on template tags alone.
    ///   - caption: The user's draft post caption, when one exists — an
    ///     additional mood signal. v1's tag-overlap scorer may ignore it;
    ///     the parameter exists so caption-aware ranking lands later without
    ///     a signature change.
    ///   - limit: Maximum suggestions returned. Must be ≥ 1.
    /// - Returns: At most `limit` suggestions, ordered by `confidence`
    ///   descending. Empty when nothing overlaps — never an error. Each
    ///   suggestion's `matchedTags` explains the pick.
    /// - Throws: `SongCorpusError` from the underlying corpus;
    ///   `CancellationError` if the task is cancelled.
    func suggestions(
        for template: Template,
        match: TemplateMatch?,
        caption: String?,
        limit: Int
    ) async throws -> [SongSuggestion]
}
