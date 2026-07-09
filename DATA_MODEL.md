# CarouselStudio Data Model

The SwiftData schema lives in one package target,
`Packages/CarouselStudioKit/Sources/Persistence`, as a single
`ModelContainer` schema (`PersistenceSchema.makeContainer()`). Per
ARCHITECTURE.md's boundary rule, these `@Model` classes never leave store
implementations — stores map them to `CoreModels` value types
(`CoreModels.Template`, `SlotCandidate`, `MatchFeedback`, …) at their
boundaries, and reuse CoreModels vocabulary (`PostFormat`, `SlotJudgment`,
`FeedbackSignal`, `MoodTag`, `PhotoAssetID`) instead of redefining it.

## Entities

| Model | One sentence |
| --- | --- |
| `Template` | Reusable recipe for a multi-slide post; owns ordered `Slot`s. |
| `Slot` | One position: plain-language criteria (doubles as the CLIP prompt), a `SlotCategory`, and a `SlotJudgment`. |
| `Candidate` | A photo the pipeline has seen: source-qualified asset identifier + cached MobileCLIP embedding. **No pixels.** |
| `SlotMatchScore` | Join row: how well one candidate fits one slot (stage-1 CLIP score, optional stage-2 verdict, combined score). |
| `FeedbackEvent` | Join row: one accept/replace/reject decision, kept as append-only history for personalization. |
| `Quest` | An active instance of a template the user is filling; owns per-slot states. |
| `QuestSlotState` | Fill state of one slot in one quest: `empty` / `some` / `plenty`, plus candidate count. |
| `SongCorpusEntry` | Curated song metadata: title, artist, theme + mood tags. No audio, ever. |

`SlotCategory` presets: `selfWithScenery`, `detailAesthetic`, `candidFunny`,
`selfAesthetic`, `humor`, `custom`. Each seeds a default `SlotJudgment`
(aesthetic/funny categories are `subjective`, so they get the Phase-4
stage-2 reasoning pass; `selfWithScenery`/`custom` default to `objective`).

## Relationships and delete rules

```
Template 1 ──< Slot                          cascade   (order = Slot.position)
Template 1 ──< Quest                         cascade
Quest    1 ──< QuestSlotState >── 1 Slot     cascade from Quest AND from Slot
Slot     1 ──< SlotMatchScore >── 1 Candidate cascade from Slot AND from Candidate
Slot     1 ──< FeedbackEvent  >── 1 Candidate cascade from Slot AND from Candidate
SongCorpusEntry                              standalone
```

- Join rows die with **either** parent; all to-one back-references are
  optional and nullify, so deleting a child never deletes its parent.
- Deleting a `Template` takes down its slots, quests, and — through the
  slots — their scores, feedback, and quest states.
- **`Candidate` survives template deletion.** Its embedding is expensive to
  recompute and valid for any future template. Deleting a `Candidate` (e.g.
  the photo left the library) removes its scores and feedback with it.
- Deleting a `Quest` never touches feedback: feedback keys off
  (candidate, slot) and outlives any one quest.

## Conventions

- **Identity**: stores match on `Template.uuid` / `Slot.uuid` / `Quest.uuid`
  (`@Attribute(.unique)`, round-trip as the CoreModels `ID`s),
  `Candidate.assetKey` (`"<source>:<localIdentifier>"`), and
  `SongCorpusEntry.corpusID`.
- **Enums are stored as raw strings** (`formatRawValue`, `categoryRawValue`,
  `fillStateRawValue`, …) with typed computed accessors, so `#Predicate`
  filtering stays reliable. Predicates must target the `*RawValue` fields.
- **Ordering**: SwiftData to-many relationships are unordered; order lives on
  `Slot.position` — always read `template.orderedSlots` /
  `quest.orderedSlotStates`.
- **Fill states map 1:1 to CoreModels.CoverageLevel**: `empty`↔`none`,
  `some`↔`scarce`, `plenty`↔`ample` (`SlotFillState.init(_:)` /
  `.coverageLevel`). The Quest Engine's `CoveragePolicy` output persists
  directly.
- **Growth control**: `SlotMatchScore` rows exist only for shortlisted
  candidates (top N per slot), never the full corpus × slots cross product;
  full-corpus scoring stays transient inside the Matching Engine.
- **No CloudKit**: `PHAsset.localIdentifier`s are device-local and the schema
  uses unique constraints (CloudKit supports neither). Deliberate.

## Embeddings

`Candidate.embedding` stores the MobileCLIP image vector as a raw Float32
buffer (512-d ≈ 2 KB, `.externalStorage`), with `embeddingModelVersion` for
invalidation on model upgrades — satisfying `EmbeddingStore`'s
cache-and-version contract. This diverges from ARCHITECTURE.md's note that
embeddings should live outside SwiftData in a flat binary store: keeping them
on `Candidate` means one store, one delete path, and blobs that only fault in
when read. At 2 KB/photo (~40 MB per 20k photos) that's acceptable; if
benchmarks disagree, `EmbeddingStore` is the seam — repoint it at a flat
file and drop the column.

## Privacy: raw photo data is never persisted

**Confirmed: no pixel data, thumbnails, file paths, or EXIF are ever written
to this store.** Per photo, the schema persists exactly:

1. its `PHAsset.localIdentifier` (or Google picker media-item ID) — an
   opaque reference into the user's library,
2. the derived MobileCLIP embedding (2 KB of floats),
3. derived bookkeeping: match scores, stage-2 rationale strings,
   accept/reject events, timestamps.

Pixels are re-fetched on demand through `PhotoSource.image(for:variant:)`
and exist only in memory. If a photo disappears from the library, its
identifier dangles harmlessly and the `Candidate` cascade removes every
derived trace.

## Toolchain note

The `@Model` macro ships only with Xcode's toolchain — the bare Command Line
Tools lack the `SwiftDataMacros` plugin, so `swift build` of the
`Persistence` target (like `swift test`, see the note in
`CoreModelsTests.swift`) requires Xcode installed and selected.
