import Foundation

/// One entry in the curated, hand-tagged song corpus. Tags only — no audio
/// data and no third-party audio-features API (Spotify closed that access in
/// 2024; MusicKit exposes none). The user adds the actual audio through
/// Instagram's/TikTok's native picker at export time.
public struct Song: Identifiable, Codable, Hashable, Sendable {
    /// Stable corpus identifier; survives corpus updates.
    public let id: String
    public var title: String
    public var artist: String
    public var tags: Set<MoodTag>
    /// Optional search string that finds the track in Instagram's/TikTok's
    /// picker when title+artist alone is ambiguous (remixes, sped-up versions).
    public var searchHint: String?

    public init(
        id: String,
        title: String,
        artist: String,
        tags: Set<MoodTag> = [],
        searchHint: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.tags = tags
        self.searchHint = searchHint
    }
}

/// Where the track should sit in the post. A hint for the user, not an edit
/// the app performs.
public enum SongPlacement: Codable, Hashable, Sendable {
    /// Play across the whole carousel/story.
    case wholePost
    /// Suggest timing the track's highlight to a specific zero-based slide.
    case fromSlide(Int)
}

public struct SongSuggestion: Codable, Hashable, Sendable {
    public var song: Song
    public var placement: SongPlacement
    /// 0…1, from tag-overlap scoring.
    public var confidence: Double
    /// The overlapping tags, so the UI can explain the pick.
    public var matchedTags: Set<MoodTag>

    public init(
        song: Song,
        placement: SongPlacement = .wholePost,
        confidence: Double,
        matchedTags: Set<MoodTag> = []
    ) {
        self.song = song
        self.placement = placement
        self.confidence = confidence
        self.matchedTags = matchedTags
    }
}
