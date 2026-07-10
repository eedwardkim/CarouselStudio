# Verification gaps

Failing tests added 2026-07-11 to expose known bugs. **These tests are meant to
fail** until the production code is fixed — do not "fix" them by weakening the
assertions. Each section names the test, the defect, and the expected fix
direction. Run everything with:

```
export DEVELOPER_DIR=~/Downloads/Xcode.app/Contents/Developer
cd Packages/CarouselStudioKit && swift test
```

Current state: 83 tests, 3 failing (by design), listed below.

---

## 1. Re-saving a template destroys its slots' match scores and feedback

**Failing test**: `SwiftDataTemplateStoreTests.resaveKeepsSlotMatchScoresAndFeedbackEvents`
(`Tests/CarouselStudioKitTests/SwiftDataTemplateStoreTests.swift`)

**Defect**: `SwiftDataTemplateStore.save` updates an existing template by
deleting every persisted `Slot` row and inserting fresh ones
(`Sources/TemplateEngine/SwiftDataTemplateStore.swift`, the
"Replace slots" block). `Persistence.Slot` carries cascade delete rules to
`SlotMatchScore`, `FeedbackEvent`, and `QuestSlotState` (CONTRACTS.md, delete
rules table), so **any** save of an existing template — including a rename or
a completely unchanged re-save — silently wipes every match score, feedback
event, and quest slot state accumulated for that template. The freshly
inserted slots reuse the same UUIDs but are new row identities; nothing
re-links the dependents. Observed failure: after one re-save, the
`SlotMatchScore` table count drops from 1 to 0.

**Impact**: Phase-4 personalization data (`FeedbackEvent`) and persisted
shortlists (`SlotMatchScore`) cannot survive template editing. Editing a
template name costs the user their entire feedback history for it.

**Fix direction**: diff slots by `uuid` inside `save` — update matching slots
in place (position/criteria/judgment), insert genuinely new ones, delete only
slots actually removed from the template.

## 2. Quest reports do not survive a process restart

**Failing test**: `QuestReportStoreTests.reportsSurviveProcessRestart`
(`Tests/CarouselStudioKitTests/QuestReportStoreTests.swift`)

**Defect**: the only `QuestReportStore` implementation is
`InMemoryQuestReportStore`, and the composition root wires it into the quest
coordinator (`CarouselStudio/AppServices.swift`, `activateQuestEngine`). All
report history evaporates on relaunch, even though the schema already defines
`Quest`/`QuestSlotState` `@Model` classes for exactly this data and
ARCHITECTURE.md commits to SwiftData persistence for quest reports.

**Contract documented by the test**: a relaunch composes a brand-new store
instance; a persisted implementation must replay everything saved before the
process died (`latestReport` and `history` both). The test constructs a second
store instance to simulate the restart — it fails for the in-memory actor by
construction and stays red until a persisted store exists *and is the type the
test composes*. When `SwiftDataQuestReportStore` (or equivalent) lands, point
the test's two instances at one shared container.

**Impact**: quest deltas ("3 new candidates since last week") are impossible;
every launch starts from a blank history, so `BGProcessingTask` catch-up scans
cannot compare against prior coverage.

## 3. App crashes at launch if the ModelContainer fails to open

**Failing test**: `CompositionRootStructuralTests.appServicesDoesNotForceTryTheModelContainer`
(`Tests/CarouselStudioKitTests/CompositionRootStructuralTests.swift`)

**Defect**: `AppServices.init` does
`try! PersistenceSchema.makeContainer(inMemory: false)`
(`CarouselStudio/AppServices.swift`). `makeContainer` is `throws` by design —
disk-full, corrupt store, and failed-migration are all reachable states — and
the force-try turns each of them into an unconditional crash on the first
frame of every subsequent launch (a crash loop, since the store stays corrupt).

**Test mechanics**: the package tests cannot import the app target, so this is
a lint-style structural test that reads `CarouselStudio/AppServices.swift`
relative to the test file's `#filePath` and asserts the container creation is
not force-tried. It passes vacuously if the package is checked out without the
app target. A companion test pins the happy path of `makeContainer(inMemory:)`
so a graceful-handling refactor starts from a green baseline.

**Fix direction**: make the composition root absorb the failure — e.g. an
error state the SwiftUI shell renders ("storage unavailable"), or a fallback
in-memory container plus a user-visible warning. Never `try!`.

## 4. Incremental update — covered, no bug found (regression lock added)

**Passing test**: `DefaultTemplateMatcherTests.updateEmbedsOnlyTheChange`
(`Tests/CarouselStudioKitTests/MatchingImplementationTests.swift`)

`DefaultTemplateMatcher.update(...)` was suspected of re-embedding the entire
corpus. The new test grows the library from 3 to 4 assets, applies a
`PhotoLibraryChange` (1 inserted + 1 modified), and counts image-tower calls:
exactly 2 additional embeds occur; the 2 unchanged assets are served from the
`EmbeddingStore` cache. The Phase-1 "purge stale cache entries, then full
re-match" folding therefore already satisfies the incremental contract
("only new/changed assets are embedded", ARCHITECTURE.md quest loop). The test
stays as a regression lock: it will fail if the cache key scheme, the purge
set, or the cache-first path in `embedIfPossible` ever regresses.

**Residual gap (untested)**: the embedding budget depends on every caller
sharing one persistent `EmbeddingStore`. That wiring lives in
`AppServices.embeddingStore()` and is not reachable from package tests.
