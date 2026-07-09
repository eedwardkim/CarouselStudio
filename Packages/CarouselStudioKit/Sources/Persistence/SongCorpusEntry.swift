import CoreModels
import Foundation
import SwiftData

/// One song in the curated corpus — metadata only, no audio file, no audio
/// features. Seeded from the bundled hand-tagged JSON at first launch (and
/// re-seeded when `corpusVersion` bumps); the user attaches actual audio in
/// Instagram's/TikTok's own picker at export time.
@Model
public final class SongCorpusEntry {
    /// Stable corpus identifier; survives corpus updates.
    @Attribute(.unique) public var corpusID: String
    public var title: String
    public var artist: String
    /// Raw `MoodTag` values describing subject matter ("travel", "food").
    public var themeTags: [String]
    /// Raw `MoodTag` values describing feel ("upbeat", "nostalgic").
    public var moodTags: [String]

    public var themeTagSet: Set<MoodTag> {
        get { Set(themeTags.map(MoodTag.init(rawValue:))) }
        set { themeTags = newValue.map(\.rawValue).sorted() }
    }

    public var moodTagSet: Set<MoodTag> {
        get { Set(moodTags.map(MoodTag.init(rawValue:))) }
        set { moodTags = newValue.map(\.rawValue).sorted() }
    }

    public init(
        corpusID: String,
        title: String,
        artist: String,
        themeTags: [String] = [],
        moodTags: [String] = []
    ) {
        self.corpusID = corpusID
        self.title = title
        self.artist = artist
        self.themeTags = themeTags
        self.moodTags = moodTags
    }
}
