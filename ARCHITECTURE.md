# CarouselStudio Architecture

CarouselStudio helps content creators assemble multi-slide social posts (carousels
and Stories) by matching their photo library against reusable **templates** —
ordered slots with plain-language criteria — then suggesting a song and running a
background **quest** system that reports which slots have zero/some/many good
candidates.

This document defines the four subsystems, their boundaries, the data flow between
them, and the Swift protocol contracts each exposes. Contracts live in
`Packages/CarouselStudioKit`; nothing is implemented yet.

## Fixed constraints (decided, not open)

- **Photos**: iOS PhotoKit is the primary, continuously monitored source
  (`PHPhotoLibraryChangeObserver` drives quest rescans). Google Photos is
  secondary and picker-driven only — Google removed the Library API's broad-read
  scopes in 2025, so no silent scanning of a user's Google library.
- **Classification** is two-stage: (1) MobileCLIP (Apple's on-device CLIP, via
  Core ML) zero-shot-scores every photo against each slot's plain-language
  criteria; (2) for subjective slots only (funny, aesthetic), shortlisted
  candidates get a second pass through Apple's Foundation Models framework with
  image input.
- **Music**: no live third-party audio-features API (Spotify closed access in
  2024; MusicKit exposes none). A small curated, hand-tagged corpus (theme/mood
  tags only) ships with the app. The user adds actual audio via Instagram's/
  TikTok's native picker at export.
- **Targets**: iOS 17 minimum, Swift 6 language mode, SwiftUI.

## Module map

One app target plus a local Swift package, `CarouselStudioKit`, with one target
per module. The app links the single umbrella product and composes everything at
the root.

```
CarouselStudio (app target)
  SwiftUI shell · composition root · draft assembly · export handoff
        │ links
        ▼
CarouselStudioKit (local package)
  ┌────────────────┬───────────────┬───────────────┬──────────────┐
  │ TemplateEngine │ MatchingEngine│ MusicMatching │ QuestEngine  │   subsystems
  └───────┬────────┴──────┬─┬──────┴──────┬────────┴──┬─┬─┬─┬─────┘
          │               │ │             │           │ │ │ │
          │               │ └─────────────┼───────────┼─┘ │ │      QuestEngine → MatchingEngine
          ▼               ▼               ▼           ▼   ▼ │      QuestEngine → TemplateEngine
  ┌───────────────────────────────────────────────────┐    │
  │ CoreModels — shared value types, zero dependencies │◄───┘
  └───────────────────────────────────────────────────┘
          ▲
  ┌───────┴────────┐
  │ PhotoSources   │  infrastructure: used by MatchingEngine + QuestEngine
  └────────────────┘
```

Dependency rules:

| Target | Depends on | Why |
| --- | --- | --- |
| `CoreModels` | — | Shared vocabulary. Value types only; no protocols, no frameworks beyond Foundation. |
| `TemplateEngine` | CoreModels | Templates are pure data + persistence. |
| `PhotoSources` | CoreModels | Photo access abstraction. The only module that will ever import PhotoKit. |
| `MatchingEngine` | CoreModels, PhotoSources | Needs assets and pixels; never touches PhotoKit types directly. |
| `MusicMatching` | CoreModels | Tags in, suggestions out. |
| `QuestEngine` | CoreModels, TemplateEngine, PhotoSources, MatchingEngine | The orchestrator; the only module allowed to depend on other subsystems. |

Two structural rules keep the boundaries honest:

1. **`CoreModels` is the only shared language.** Subsystems communicate through
   its value types (`Template`, `PhotoAsset`, `TemplateMatch`, `QuestReport`, …),
   never through each other's internals.
2. **Framework types stop at module edges.** `PHAsset` never leaves
   `PhotoSources`; Core ML types never leave `MatchingEngine`'s concrete scorer;
   SwiftData models never leave the store implementations. Contracts trade only
   in CoreModels types plus `CGImage`.

## Subsystem 1: Template Engine

**Responsibilities**: define, persist, validate, and version templates; ship
starter templates (e.g. "travel post"); notify listeners when templates change.

**Explicitly not responsible for**: photo access, scoring, or deciding when
matching runs. A template is inert data; other subsystems act on it.

**Contracts** (in `Packages/CarouselStudioKit/Sources/TemplateEngine/`):

| Protocol | Role |
| --- | --- |
| `TemplateStore` | CRUD + `changes()` stream of `TemplateChange`. Production: SwiftData-backed. |
| `TemplateValidating` | Structural checks (empty criteria, duplicate positions, criteria exceeding CLIP's 77-token window). |
| `StarterTemplateProviding` | Bundled starter templates for first launch. |

Design note: `Slot.criteria` doubles as the stage-1 zero-shot prompt, so the
Template Engine is also where prompt hygiene lives — validation warns when
criteria are too long or empty, and each slot carries a `SlotJudgment`
(`objective`/`subjective`) that tells the Matching Engine whether a stage-2
reasoning pass applies.

## Subsystem 2: Matching Engine

**Responsibilities**: turn (template, photo corpus) into ranked per-slot
candidates via the two-stage pipeline; own the embedding cache that makes
rescans cheap; support incremental updates for the Quest Engine.

**Explicitly not responsible for**: enumerating or observing the photo library
(PhotoSources does that), deciding when to run (UI and Quest Engine call it), or
persisting match results long-term (callers own their results).

**Pipeline** for `match(template, options)`:

```
corpus (PhotoSource.assets)
  → image embeddings          EmbeddingProviding + EmbeddingStore (cache hit = skip)
  → per-slot text embedding   EmbeddingProviding (criteria as prompt)
  → score + calibrate + rank  SlotMatching, once per slot
  → shortlist (top N/slot)    SlotMatching, MatchOptions.shortlistSize
  → stage 2 for subjective    CandidateReasoning (Phase 4, availability-gated)
  → TemplateMatch             ranked SlotCandidates per slot
```

**Contracts** (in `Packages/CarouselStudioKit/Sources/MatchingEngine/`):

| Protocol | Role |
| --- | --- |
| `TemplateMatching` | Orchestrator: full `match(_:options:)` and incremental `update(_:applying:for:options:)`. |
| `EmbeddingProviding` | MobileCLIP's two towers (image → vector, text → vector). Exposing towers, not scores, is what makes caching work: editing criteria re-embeds one string, not the library. |
| `EmbeddingStore` | Persistent image-embedding cache keyed by asset + model version. |
| `SlotMatching` | Stage-1 ranking seam: (pre-embedded corpus, slot, criteria embedding) → calibrated, ranked shortlist. Pure embedding-space math — unit-testable with synthetic vectors, no Core ML. |
| `CandidateReasoning` | Stage 2 (Phase 4): Foundation Models verdict per shortlisted candidate. Runtime `isAvailable` gate. |
| `FeedbackRecording` | Phase 4: accept/replace/reject signals for personalization. |

**Score calibration**: raw CLIP cosine similarities cluster in a narrow band and
are not comparable across prompts, so `SlotScore.value` is defined as *calibrated
to 0…1 per slot* (e.g. z-score or min-max over the corpus for that prompt). The
contract fixes the semantics; the calibration method is an implementation detail
to tune in Phase 1. It lives behind `SlotMatching`, so tuning it never touches
the orchestrator — and scores are only comparable within one `candidates(in:…)`
call, never across calls.

**Foundation Models gating**: the framework needs a newer OS and Apple
Intelligence enabled; with a 17.0 deployment target this is strictly a runtime
capability (`isAvailable`). When unavailable, subjective slots keep their stage-1
ranking — the app degrades, never breaks.

## Subsystem 3: Music Matching

**Responsibilities**: recommend tracks (and a placement hint) for a template from
the curated corpus, by mood/theme tag overlap; explain each pick via
`matchedTags`.

**Explicitly not responsible for**: audio playback, audio analysis, calling any
music API, or attaching audio at export — the user does that in Instagram's/
TikTok's own picker; we hand them the track name (plus `searchHint`).

**Contracts** (in `Packages/CarouselStudioKit/Sources/MusicMatching/`):

| Protocol | Role |
| --- | --- |
| `SongCorpus` | Read-only access to the bundled hand-tagged JSON corpus (`corpusVersion` for cache-busting). |
| `SongRecommending` | Ranked `SongSuggestion`s for a template; optionally takes the current `TemplateMatch` (so tags are weighted by which slots actually have strong candidates) and a draft `caption` for future text-derived mood signals. |

The corpus and templates share the `MoodTag` type from CoreModels — matching is
tag-set overlap, deliberately simple, upgradeable later without touching callers.

## Subsystem 4: Quest Engine

**Responsibilities**: keep per-template coverage fresh — observe library and
template changes, drive *incremental* matching, classify each slot's candidate
supply as none/scarce/ample, persist reports, and stream them to the UI (which
renders them as quests: "slot 2 has no candidates — go shoot a detail shot").

**Explicitly not responsible for**: scoring photos (delegates to
`TemplateMatching.update`), owning templates, or rendering notifications (app
layer decides how reports surface).

**Runtime loop**:

```
PhotoLibraryObserving.changes() ─┐  (coalesced/debounced)
TemplateStore.changes() ─────────┤
manual refresh() ────────────────┴─► for each affected template:
                                       TemplateMatching.update(existing, change)
                                       CoveragePolicy.coverage(per slot)
                                       QuestReportStore.save(report)
                                       reports() stream ─► UI / notifications
```

**Contracts** (in `Packages/CarouselStudioKit/Sources/QuestEngine/`):

| Protocol | Role |
| --- | --- |
| `QuestCoordinating` | `activate()`/`deactivate()`, forced `refresh()`, and the `reports()` stream (replays latest per template, then live updates). |
| `CoveragePolicy` | Maps candidate evidence → `SlotCoverage` (none/scarce/ample). Behind a protocol so thresholds are tunable and, later, personalized. |
| `QuestReportStore` | Report history, enabling deltas ("3 new candidates since last week"). |

**Background-execution reality check**: `PHPhotoLibraryChangeObserver` only fires
while the app has a live process. So the quest loop runs eagerly in the
foreground, and catch-up scans ride `BGProcessingTask` (opportunistic, system-
scheduled, typically overnight on power). "Continuously monitored" means
*foreground-live + background-opportunistic*; the embedding cache makes catch-up
scans cheap enough for that budget.

## Infrastructure: PhotoSources

Not one of the four subsystems, but the shared abstraction two of them stand on.
It exists so Matching and Quest never see PhotoKit or Google types, and so the
Google Photos path (Phase 4) plugs in without touching either engine.

| Protocol | Role |
| --- | --- |
| `PhotoSource` | Access request, streamed asset enumeration (`AssetQuery`), on-demand pixel decode (`ImageVariant`: scoring thumbnail / display / original). Implementations: `PhotoKitSource` (Phase 1), `GooglePhotosSource` (Phase 4, serves imported local copies). |
| `PhotoLibraryObserving` | Coalesced `PhotoLibraryChange` stream (inserted/deleted/modified). PhotoKit only. |
| `GooglePhotosImporting` | Phase 4: present Google's picker, download local copies, return them as `googlePhotos`-sourced assets. One-shot per session, by design and by Google policy. |

`PhotoAssetID` is source-qualified (`source` + `rawValue`), so scores,
embeddings, and feedback key uniformly across both sources.

## End-to-end data flows

**A. User assembles a post (Phase 1)**

1. UI loads templates from `TemplateStore`.
2. User picks one; UI calls `TemplateMatching.match(template, options: .default)`.
3. Engine streams corpus from `PhotoKitSource`, embeds cache-misses, scores,
   shortlists → `TemplateMatch`.
4. UI shows ranked candidates per slot; user accepts/swaps (recorded via
   `FeedbackRecording` in Phase 4).
5. App layer assembles the draft (ordered full-res images via
   `PhotoSource.image(for:variant:.original)`) and, in Phase 3, shows
   `SongRecommending.suggestions(...)` alongside. Export = save images in order +
   show the song to add in IG/TikTok's picker.

**B. Quest loop (Phase 2)**

1. `QuestCoordinating.activate()` on launch (post photo-permission).
2. Library change arrives → coalesced → `TemplateMatching.update(existing,
   applying: change, ...)` per template — only new/changed assets are embedded.
3. `CoveragePolicy` buckets each slot; report saved; `reports()` stream updates
   the quest UI ("2 slots still need photos").

**C. Google import (Phase 4)**

1. User taps import → `GooglePhotosImporting.importFromPicker()`.
2. Local copies join the corpus under `PhotoSourceKind.googlePhotos`.
3. UI triggers `QuestCoordinating.refresh(templateID: nil)` — imported photos are
   scored on the next pass. No observation, no re-sync; re-importing is always an
   explicit user action.

## Cross-cutting decisions

**Concurrency (Swift 6, strict)**: every contract is `Sendable`; engines will be
actors; events flow through `AsyncStream` (single-consumer is sufficient — the
composition root fans out if needed). The app target uses `MainActor` default
isolation (Xcode 26 setting; harmless under Xcode 16); package modules keep
nonisolated defaults since they're concurrency-heavy.

**Failure vocabulary**: every contract throws typed errors —
`PhotoSourceError`, `GooglePhotosImportError`, `EmbeddingError`,
`SlotMatchingError`, `ReasoningError`, `SongCorpusError` — plus a shared
`PersistenceError` (CoreModels) for all stores. "Not found" is a `nil` return,
deletes are idempotent no-ops, and cancellation is Swift's `CancellationError`,
so a thrown error always means something actually failed. Per-asset trouble
during matching (undecodable photo, deleted mid-scan) is skipped, never thrown;
only systemic failures (access denied, model unavailable, storage faults)
propagate.

**Persistence**: SwiftData (iOS 17+) behind the store protocols for templates,
quest reports, and feedback. Embeddings do *not* go in SwiftData — a few hundred
KB per thousand photos of dense float vectors wants a flat binary/SQLite layout;
`EmbeddingStore` hides the choice.

**Model assets**: MobileCLIP ships as a Core ML package. Working assumption:
start with **MobileCLIP-S2** (512-d embeddings, good speed/accuracy balance on
A16+), quantized; benchmark S0 vs S2 on-device in Phase 1 before locking. Deliver
in-bundle first; move to Background Assets if app size becomes a problem.
`modelVersion` strings flow through `Embedding`/`EmbeddingStore` so an upgrade
invalidates cleanly.

**Composition root**: the app target wires concrete implementations to protocols
(constructor injection, no DI framework). It also owns everything deliberately
*not* made a subsystem yet: draft assembly, export handoff, notifications,
onboarding.

## Phase map

| Phase | Ships | Modules touched |
| --- | --- | --- |
| 1 | Template CRUD + full matching on iOS Photos (MobileCLIP only) | TemplateEngine, PhotoSources (PhotoKit), MatchingEngine (stage 1), app UI |
| 2 | Quest system | QuestEngine, PhotoSources (observer), MatchingEngine (incremental `update`) |
| 3 | Song suggestions | MusicMatching, corpus JSON, export UI |
| 4 | Google Photos import · Foundation Models stage 2 · personalization | PhotoSources (picker), MatchingEngine (`CandidateReasoning`, `FeedbackRecording`) |

Every Phase-4 seam (`SlotJudgment`, `CandidateReasoning.isAvailable`,
`verdict`/`combinedScore` on `SlotCandidate`, `PhotoSourceKind.googlePhotos`,
`FeedbackRecording`, the `caption` parameter on `SongRecommending`) already
exists in the contracts, so later phases add implementations, not migrations.

## Assumptions made (flag anything wrong)

1. **Bundle ID** `com.edwardkim.CarouselStudio`; project lives at
   `~/CarouselStudio`; iPhone + iPad device families.
2. **One local package, six targets** rather than separate packages per module —
   boundaries enforced by target dependencies, cheap to split later.
3. **SwiftData** for structured persistence (vs Core Data/GRDB), given iOS 17
   floor; embeddings in a binary store.
4. **MobileCLIP-S2** as the starting model variant, pending on-device benchmarks.
5. **Quest cadence** = foreground-live + `BGProcessingTask` catch-up; no
   continuous background daemon (iOS doesn't offer one).
6. **Draft assembly & export live in the app layer**, not a fifth subsystem —
   they're UI-heavy and thin on logic until multi-platform export grows.
7. **Song corpus is bundled JSON** updated via app releases (no server), matching
   the "small curated corpus" constraint.
8. **`AsyncStream` single-consumer semantics** are acceptable for v1 event
   plumbing; the composition root multiplexes if two listeners ever need one
   stream.
9. **Package also builds for macOS** solely so `swift build`/`swift test` run
   without a simulator; contracts stay framework-free (Foundation + CoreGraphics)
   to keep that true.
