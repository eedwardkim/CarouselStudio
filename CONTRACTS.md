# CarouselStudio — Contracts Reference

This document pins the exact property names, types, and enum cases for every
shared model and protocol in `CarouselStudioKit`. It is the single source of
truth for sessions that cannot see each other: if a property name here differs
from a file in the repo, the file is wrong.

All Swift is Swift 6, strict concurrency. All public value types are `Sendable`
and (where meaningful) `Codable` and `Hashable`. Persistence `@Model` classes
are `final class` (SwiftData requirement); everything else is a `struct` or
`enum`. Protocols are `Sendable`.

---

## Module layout

```
CarouselStudioKit/
  Sources/
    CoreModels/       — value types, zero dependencies
    PhotoSources/     — PhotoKit abstraction (only module that imports PhotoKit)
    TemplateEngine/   — template CRUD protocols + BuiltInStarterTemplates impl
    MatchingEngine/   — two-stage pipeline protocols + Phase-1 impls
    MusicMatching/    — song corpus + recommendation protocols
    QuestEngine/      — quest coordinator protocols
    Persistence/      — SwiftData @Model classes (never leave store impls)
```

Dependency graph (→ = "depends on"):
```
TemplateEngine → CoreModels
PhotoSources   → CoreModels
MatchingEngine → CoreModels, PhotoSources
MusicMatching  → CoreModels
QuestEngine    → CoreModels, TemplateEngine, PhotoSources, MatchingEngine
Persistence    → CoreModels
```

---

## CoreModels

### `PostFormat` (enum, String raw)
```swift
case carousel   // "carousel"
case story      // "story"
```

### `MoodTag` (struct)
```swift
var rawValue: String   // RawRepresentable
```

### `Template` (struct, Identifiable)
```swift
let id: UUID                // Template.ID == UUID
var name: String
var format: PostFormat
var slots: [Slot]           // ordered by Slot.position
var moodTags: Set<MoodTag>
var createdAt: Date
var updatedAt: Date
```

### `SlotJudgment` (enum, String raw)
```swift
case objective   // "objective"  — CLIP score alone ranks candidates
case subjective  // "subjective" — stage-2 reasoning pass applies (Phase 4)
```

### `Slot` (struct, Identifiable)
```swift
let id: UUID                // Slot.ID == UUID
var position: Int           // zero-based
var criteria: String        // plain language; doubles as CLIP zero-shot prompt
var judgment: SlotJudgment
```

### `PhotoSourceKind` (enum, String raw)
```swift
case photoKit      // "photoKit"
case googlePhotos  // "googlePhotos"
```

### `PhotoAssetID` (struct, Hashable)
```swift
var source: PhotoSourceKind
var rawValue: String        // PHAsset.localIdentifier or picker media-item ID
```

### `PhotoAsset` (struct, Identifiable)
```swift
let id: PhotoAssetID        // PhotoAsset.ID == PhotoAssetID
var capturedAt: Date?
var pixelWidth: Int
var pixelHeight: Int
var isFavorite: Bool
```

### `SlotScore` (struct)
```swift
var assetID: PhotoAssetID
var slotID: Slot.ID
var value: Double           // calibrated 0…1 per slot (not raw cosine)
```

### `ReasoningVerdict` (struct)
```swift
var fitScore: Double        // 0…1
var rationale: String       // user-facing "why this photo?"
```

### `SlotCandidate` (struct)
```swift
var assetID: PhotoAssetID
var slotID: Slot.ID
var clipScore: Double       // stage-1 calibrated score (0…1)
var verdict: ReasoningVerdict?  // nil until stage-2 runs
var combinedScore: Double   // ranking key; == clipScore until stage 2 blends in
```

### `TemplateMatch` (struct, Identifiable)
```swift
var templateID: Template.ID
var matchedAt: Date
var candidatesBySlot: [Slot.ID: [SlotCandidate]]
    // key present for every slot in the template; empty array = no candidates
    // candidates ordered by combinedScore descending
```

### `FeedbackSignal` (enum, String raw)
```swift
case accepted   // "accepted"
case replaced   // "replaced"
case rejected   // "rejected"
```

### `MatchFeedback` (struct)
```swift
var templateID: Template.ID
var slotID: Slot.ID
var assetID: PhotoAssetID
var signal: FeedbackSignal
var recordedAt: Date
```

### `CoverageLevel` (enum, String raw)
```swift
case none    // "none"    — zero good candidates
case scarce  // "scarce"  — below the "plenty" threshold
case ample   // "ample"   — many good candidates
```

### `SlotCoverage` (struct)
```swift
var slotID: Slot.ID
var level: CoverageLevel
var candidateCount: Int     // candidates clearing the policy's quality bar
var bestScore: Double?      // top combinedScore seen, nil when candidateCount == 0
```

### `QuestTrigger` (enum, String raw)
```swift
case libraryChange   // "libraryChange"
case templateChange  // "templateChange"
case manual          // "manual"
case scheduled       // "scheduled"
```

### `QuestReport` (struct, Identifiable)
```swift
let id: UUID
var templateID: Template.ID
var generatedAt: Date
var trigger: QuestTrigger
var coverage: [SlotCoverage]   // one per slot, in slot position order
```

### `Song` (struct, Identifiable)
```swift
let id: String             // stable corpus identifier
var title: String
var artist: String
var tags: Set<MoodTag>
var searchHint: String?    // for IG/TikTok picker disambiguation
```

### `SongPlacement` (enum)
```swift
case wholePost
case fromSlide(Int)        // zero-based slide index
```

### `SongSuggestion` (struct)
```swift
var song: Song
var placement: SongPlacement
var confidence: Double      // 0…1, tag-overlap score
var matchedTags: Set<MoodTag>
```

### `PersistenceError` (enum, Error)
```swift
case storageUnavailable(reason: String)
case operationFailed(reason: String)
```

---

## PhotoSources

### `PhotoAccessStatus` (enum, String raw)
```swift
case notDetermined
case restricted
case denied
case limited    // user-selected subset only
case full
```

### `PhotoSourceError` (enum, Error)
```swift
case accessDenied
case assetNotFound(PhotoAssetID)
case resourceUnavailable(PhotoAssetID)
case decodingFailed(PhotoAssetID)
```

### `AssetQuery` (struct)
```swift
var capturedAfter: Date?
var capturedBefore: Date?
var limit: Int?

static let all: AssetQuery   // all three nils
```

### `ImageVariant` (enum)
```swift
case scoringThumbnail   // encoder-native small square for CLIP
case display            // screen-resolution for candidate browsing
case original           // full res for export
```

### `PhotoLibraryChange` (struct)
```swift
var inserted: [PhotoAssetID]
var deleted: [PhotoAssetID]
var modified: [PhotoAssetID]
// fields are disjoint per element
```

### `GooglePhotosImportResult` (struct)
```swift
var imported: [PhotoAsset]
var failedItemCount: Int
```

### `GooglePhotosImportError` (enum, Error)
```swift
case notAuthenticated
case pickerFailed(reason: String)
```

---

## PhotoSources — Protocols

### `PhotoSource`
```swift
var kind: PhotoSourceKind { get }
func requestAccess() async -> PhotoAccessStatus
func assets(matching query: AssetQuery) -> AsyncThrowingStream<PhotoAsset, Error>
func image(for id: PhotoAssetID, variant: ImageVariant) async throws -> CGImage
```
Throws from `image`: `PhotoSourceError.accessDenied`, `.assetNotFound`,
`.resourceUnavailable`, `.decodingFailed`, `CancellationError`.

### `PhotoLibraryObserving`
```swift
func changes() -> AsyncStream<PhotoLibraryChange>
```
No replay; never finishes on its own; single consumer.

### `GooglePhotosImporting`
```swift
func importFromPicker() async throws -> GooglePhotosImportResult
```
Throws: `GooglePhotosImportError`, `CancellationError`.

---

## TemplateEngine — Protocols

### `TemplateStore`
```swift
func allTemplates() async throws -> [Template]
func template(withID id: Template.ID) async throws -> Template?
func save(_ template: Template) async throws
func deleteTemplate(withID id: Template.ID) async throws
func changes() -> AsyncStream<TemplateChange>
```
Throws: `PersistenceError`. Lookups return `nil` for unknown IDs; deletes are
idempotent. `save` sets `updatedAt` and emits `.saved`; a real delete emits
`.deleted`.

### `TemplateChange` (enum, Hashable)
```swift
case saved(Template.ID)
case deleted(Template.ID)
```

### `TemplateValidating`
```swift
func validate(_ template: Template) -> [TemplateValidationIssue]
```

### `TemplateValidationIssue` (struct)
```swift
var kind: Kind
var message: String   // human-readable, ready for display

enum Kind {
    case emptyName
    case noSlots
    case emptyCriteria(Slot.ID)
    case criteriaTooLong(Slot.ID)
    case duplicatePositions
}
```
All issues found in one pass; ordered template-level first, then slots in
position order.

### `StarterTemplateProviding`
```swift
func starterTemplates() -> [Template]   // pure, deterministic, non-throwing
```

---

## MatchingEngine

### `Embedding` (struct)
```swift
var vector: [Float]         // L2-normalized; dimension fixed per modelVersion
var modelVersion: String    // embeddings with different versions never mix
```

### `EmbeddingError` (enum, Error)
```swift
case modelUnavailable(reason: String)
case imageEncodingFailed(reason: String)
case textEncodingFailed(reason: String)
```

### `AssetEmbedding` (struct)
```swift
var assetID: PhotoAssetID
var embedding: Embedding
```

### `SlotMatchingError` (enum, Error)
```swift
case mismatchedEmbeddingSpace(expected: String, found: String)
case dimensionMismatch(expected: Int, found: Int)
```

### `MatchOptions` (struct)
```swift
var shortlistSize: Int          // candidates kept per slot after stage 1; ≥ 1; default 20
var enableReasoningPass: Bool   // stage-2 toggle; default false
var query: AssetQuery?          // nil = whole library

static let `default`: MatchOptions   // shortlistSize=20, enableReasoningPass=false, query=nil
```

### `ReasoningError` (enum, Error)
```swift
case unavailable
case guardrailBlocked
case malformedOutput(reason: String)
```

---

## MatchingEngine — Protocols

### `EmbeddingProviding`
```swift
var modelVersion: String { get }
func embedding(for image: CGImage) async throws -> Embedding
func embedding(for text: String) async throws -> Embedding
```
Throws: `EmbeddingError`, `CancellationError`.

### `EmbeddingStore`
```swift
func embedding(for id: PhotoAssetID, modelVersion: String) async throws -> Embedding?
func store(_ embedding: Embedding, for id: PhotoAssetID) async throws
func removeEmbeddings(for ids: [PhotoAssetID]) async throws
func compact(keepingModelVersion modelVersion: String) async throws
```
Cache miss = `nil` return, never an error. Throws: `PersistenceError`.

### `SlotMatching`
```swift
func candidates(
    in corpus: [AssetEmbedding],
    for slot: Slot,
    criteriaEmbedding: Embedding,
    limit: Int
) async throws -> [SlotCandidate]
```
Returns ≤ `limit` candidates ordered by `combinedScore` descending, ties
broken by `assetID`. All returned candidates have `clipScore == combinedScore`
and `verdict == nil` (stage 1 only). Throws: `SlotMatchingError`,
`CancellationError`.

### `TemplateMatching`
```swift
func match(_ template: Template, options: MatchOptions) async throws -> TemplateMatch
func update(
    _ existing: TemplateMatch,
    applying change: PhotoLibraryChange,
    for template: Template,
    options: MatchOptions
) async throws -> TemplateMatch
```
`match` guarantees a key for every slot in `candidatesBySlot` (empty array =
no candidates). Throws: `PhotoSourceError.accessDenied`,
`EmbeddingError.modelUnavailable`, `SlotMatchingError`, `PersistenceError`,
`CancellationError`. Per-asset failures are skipped, not thrown.

### `CandidateReasoning`
```swift
var isAvailable: Bool { get }
func verdict(for asset: PhotoAsset, image: CGImage, slot: Slot) async throws -> ReasoningVerdict
```
Throws: `ReasoningError`, `CancellationError`. A failed verdict keeps the
candidate's stage-1 rank.

### `FeedbackRecording`
```swift
func record(_ feedback: MatchFeedback) async throws
func feedbackHistory(for templateID: Template.ID) async throws -> [MatchFeedback]
```
Append-only log; recording the same event twice stores two entries.
Throws: `PersistenceError`.

---

## MusicMatching

### `SongCorpusError` (enum, Error)
```swift
case corpusUnavailable(reason: String)
case corpusCorrupted(reason: String)
```

### `SongCorpus`
```swift
var corpusVersion: String { get }
func allSongs() async throws -> [Song]
```
Throws: `SongCorpusError`.

### `SongRecommending`
```swift
func suggestions(
    for template: Template,
    match: TemplateMatch?,
    caption: String?,
    limit: Int
) async throws -> [SongSuggestion]
```
Returns ≤ `limit` suggestions ordered by `confidence` descending. Empty result
is never an error. Throws: `SongCorpusError`, `CancellationError`.

---

## QuestEngine — Protocols

### `CoveragePolicy`
```swift
func coverage(for slot: Slot, candidates: [SlotCandidate]) -> SlotCoverage
```
Pure and deterministic. `candidateCount` = candidates clearing the quality bar.

### `QuestReportStore`
```swift
func latestReport(for templateID: Template.ID) async throws -> QuestReport?
func history(for templateID: Template.ID, limit: Int) async throws -> [QuestReport]
func save(_ report: QuestReport) async throws
func deleteReports(for templateID: Template.ID) async throws
```
`latestReport` returns `nil` for never-scanned templates. `save` is
insert-or-replace on `report.id`. Throws: `PersistenceError`.

### `QuestCoordinating`
```swift
func activate() async
func deactivate() async
func refresh(templateID: Template.ID?) async throws
func reports() -> AsyncStream<QuestReport>
```
`activate`/`deactivate` are idempotent. `refresh(nil)` rescans all templates.
`reports()` replays the latest known report per template on subscription, then
streams live updates. Throws from `refresh`: `PhotoSourceError.accessDenied`,
`TemplateMatching` errors, `CancellationError`.

---

## Persistence (`@Model` classes)

These classes live in the `Persistence` target and **never cross store
boundaries** — stores map them to CoreModels value types at their edges.

### `SlotCategory` (enum, String raw — lives in Persistence, not CoreModels)
```swift
case selfWithScenery    // "selfWithScenery"  — defaultJudgment: .objective
case detailAesthetic    // "detailAesthetic"  — defaultJudgment: .subjective
case candidFunny        // "candidFunny"      — defaultJudgment: .subjective
case selfAesthetic      // "selfAesthetic"    — defaultJudgment: .subjective
case humor              // "humor"            — defaultJudgment: .subjective
case custom             // "custom"           — defaultJudgment: .objective

var defaultJudgment: SlotJudgment   // computed
```

### `Template` (@Model)
Stored columns:
```swift
@Attribute(.unique) var uuid: UUID
var name: String
var formatRawValue: String          // PostFormat.rawValue
var moodTags: [String]              // [MoodTag.rawValue], sorted
var createdAt: Date
var updatedAt: Date
```
Relationships:
```swift
@Relationship(deleteRule: .cascade, inverse: \Slot.template)
var slots: [Slot]

@Relationship(deleteRule: .cascade, inverse: \Quest.template)
var quests: [Quest]
```
Computed:
```swift
var format: PostFormat              // read/write via formatRawValue
var moodTagSet: Set<MoodTag>        // read/write via moodTags
var orderedSlots: [Slot]            // sorted by position
```

### `Slot` (@Model)
Stored columns:
```swift
@Attribute(.unique) var uuid: UUID
var position: Int
var criteria: String
var categoryRawValue: String        // SlotCategory.rawValue
var judgmentRawValue: String        // SlotJudgment.rawValue
```
Relationships:
```swift
var template: Template?

@Relationship(deleteRule: .cascade, inverse: \SlotMatchScore.slot)
var matchScores: [SlotMatchScore]

@Relationship(deleteRule: .cascade, inverse: \FeedbackEvent.slot)
var feedbackEvents: [FeedbackEvent]

@Relationship(deleteRule: .cascade, inverse: \QuestSlotState.slot)
var questSlotStates: [QuestSlotState]
```
Computed:
```swift
var category: SlotCategory          // read/write via categoryRawValue
var judgment: SlotJudgment          // read/write via judgmentRawValue
```

### `Candidate` (@Model)
Stored columns:
```swift
@Attribute(.unique) var assetKey: String  // "<source>:<localIdentifier>"
var sourceRawValue: String                // PhotoSourceKind.rawValue
var assetLocalIdentifier: String          // PHAsset.localIdentifier or picker ID
@Attribute(.externalStorage) var embedding: Data?  // Float32 buffer, 512-d ≈ 2 KB
var embeddingModelVersion: String?
var firstSeenAt: Date
```
Relationships:
```swift
@Relationship(deleteRule: .cascade, inverse: \SlotMatchScore.candidate)
var matchScores: [SlotMatchScore]

@Relationship(deleteRule: .cascade, inverse: \FeedbackEvent.candidate)
var feedbackEvents: [FeedbackEvent]
```
Computed:
```swift
var assetID: PhotoAssetID           // derived from sourceRawValue + assetLocalIdentifier
var embeddingVector: [Float]?       // read/write via embedding Data

static func assetKey(for id: PhotoAssetID) -> String   // "\(id.source.rawValue):\(id.rawValue)"
```

### `SlotMatchScore` (@Model)
Stored columns:
```swift
var clipScore: Double
var reasoningFitScore: Double?      // nil until stage-2 runs
var reasoningRationale: String?     // nil until stage-2 runs
var combinedScore: Double
var computedAt: Date
```
Relationships:
```swift
var slot: Slot?
var candidate: Candidate?
```
Computed:
```swift
var verdict: ReasoningVerdict?      // composed from reasoningFitScore + reasoningRationale
```
Only shortlisted rows (top N per slot) are stored; full-corpus scoring is
transient inside the Matching Engine.

### `FeedbackEvent` (@Model)
Stored columns:
```swift
var signalRawValue: String          // FeedbackSignal.rawValue
var recordedAt: Date
```
Relationships:
```swift
var candidate: Candidate?
var slot: Slot?
```
Computed:
```swift
var signal: FeedbackSignal          // read/write via signalRawValue
                                    // unknown raw value → .rejected (conservative)
```
Append-only; keys off (candidate, slot) and outlives any individual quest.

### `QuestStatus` (enum, String raw — lives in Persistence)
```swift
case active      // "active"
case completed   // "completed"
case abandoned   // "abandoned"
```

### `SlotFillState` (enum, String raw — lives in Persistence)
```swift
case empty    // "empty"   ↔ CoverageLevel.none
case some     // "some"    ↔ CoverageLevel.scarce
case plenty   // "plenty"  ↔ CoverageLevel.ample

init(_ level: CoverageLevel)   // maps CoverageLevel → SlotFillState
var coverageLevel: CoverageLevel
```

### `Quest` (@Model)
Stored columns:
```swift
@Attribute(.unique) var uuid: UUID
var statusRawValue: String          // QuestStatus.rawValue
var startedAt: Date
var completedAt: Date?
```
Relationships:
```swift
var template: Template?

@Relationship(deleteRule: .cascade, inverse: \QuestSlotState.quest)
var slotStates: [QuestSlotState]
```
Computed:
```swift
var status: QuestStatus             // read/write via statusRawValue
var orderedSlotStates: [QuestSlotState]   // sorted by slot.position
```

### `QuestSlotState` (@Model)
Stored columns:
```swift
var fillStateRawValue: String       // SlotFillState.rawValue; unknown → .empty
var matchingCandidateCount: Int
var updatedAt: Date
```
Relationships:
```swift
var quest: Quest?
var slot: Slot?
```
Computed:
```swift
var fillState: SlotFillState        // read/write via fillStateRawValue
```

### `SongCorpusEntry` (@Model)
Stored columns:
```swift
@Attribute(.unique) var corpusID: String
var title: String
var artist: String
var themeTags: [String]             // [MoodTag.rawValue], sorted
var moodTags: [String]              // [MoodTag.rawValue], sorted
```
Computed:
```swift
var themeTagSet: Set<MoodTag>       // read/write via themeTags
var moodTagSet: Set<MoodTag>        // read/write via moodTags
```
Note: `Song` (CoreModels) uses a single `tags: Set<MoodTag>` field.
`SongCorpusEntry` splits these into `themeTags` + `moodTags` for richer
corpus filtering; when mapping to `Song`, callers merge both sets into
`Song.tags`.

### `PersistenceSchema`
```swift
static let models: [any PersistentModel.Type]
    // [Template, Slot, Candidate, SlotMatchScore, FeedbackEvent,
    //  Quest, QuestSlotState, SongCorpusEntry]

static func makeContainer(inMemory: Bool = false) throws -> ModelContainer
```

---

## Delete rules (summary)

| Parent deleted | Cascades to |
|---|---|
| `Template` | `Slot`, `Quest` |
| `Slot` | `SlotMatchScore`, `FeedbackEvent`, `QuestSlotState` |
| `Candidate` | `SlotMatchScore`, `FeedbackEvent` |
| `Quest` | `QuestSlotState` |

`Candidate` **survives** `Template` deletion — the embedding is expensive to
recompute and valid for any future template. All to-one back-references (the
optional `var` side of each relationship) nullify on delete and never cascade
back to the parent.

---

## Naming conventions

- **Unique identity key**: `@Attribute(.unique)` on `uuid: UUID` for `Template`,
  `Slot`, `Quest`; on `assetKey: String` for `Candidate`; on `corpusID: String`
  for `SongCorpusEntry`. These round-trip to `CoreModels` IDs.
- **Enum storage**: every enum stored by SwiftData uses a `*RawValue: String`
  column + a typed computed accessor. `#Predicate` targets the raw-value field,
  never the computed one.
- **Tag storage**: tag sets stored as sorted `[String]` arrays (SwiftData
  cannot store `Set`); access through the typed `*Set` computed property.
- **Ordering**: SwiftData to-many relationships are unordered; use `orderedSlots`
  / `orderedSlotStates`; order is carried by `Slot.position`.
- **No pixels, ever**: the schema persists `PHAsset.localIdentifier` (opaque
  reference) and the derived MobileCLIP embedding (2 KB floats). No pixel data,
  thumbnails, file paths, or EXIF are written.
- **No CloudKit**: `PHAsset.localIdentifier` is device-local; the schema uses
  `@Attribute(.unique)` (CloudKit doesn't support it). Deliberate.
