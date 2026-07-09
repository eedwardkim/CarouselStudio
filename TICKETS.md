# CarouselStudio — Implementation Tickets

Scope: Phase 1 remainder + all of Phase 2 (Quest Engine).
Phase 3 (music) and Phase 4 (Google Photos, Foundation Models, feedback) are
out of scope here.

**Verification tags**

- `cloud-safe` — pure Swift logic; verifiable with `swift test` under the
  Xcode toolchain, no Simulator required.
- `local-only` — requires a real Xcode/Simulator build (`xcodebuild` +
  `simctl`) to confirm the acceptance criterion.

**Build command reference** (from AGENTS.md)

```
# Package build + tests
export DEVELOPER_DIR=~/Downloads/Xcode.app/Contents/Developer
cd Packages/CarouselStudioKit
swift build && swift test

# App build
export DEVELOPER_DIR=~/Downloads/Xcode.app/Contents/Developer
xcodebuild -project CarouselStudio.xcodeproj \
           -scheme CarouselStudio \
           -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
           build
```

---

## Phase 1 — Remaining tickets

### T-01 · `TemplateValidating` concrete implementation

**Title:** Implement `DefaultTemplateValidator` conforming to `TemplateValidating`

**Files touched:**
- `Packages/CarouselStudioKit/Sources/TemplateEngine/DefaultTemplateValidator.swift` *(new)*
- `Packages/CarouselStudioKit/Tests/CarouselStudioKitTests/TemplateValidationTests.swift` *(new)*

**What to build:**
Create `public struct DefaultTemplateValidator: TemplateValidating` in the
`TemplateEngine` target. `validate(_ template:)` must perform all five checks
from the `TemplateValidationIssue.Kind` enum, in this order, returning every
issue found (no short-circuit):

1. `.emptyName` — `template.name` is blank after whitespace trimming.
2. `.noSlots` — `template.slots` is empty.
3. `.emptyCriteria(slot.id)` — any slot's `criteria` is blank after trimming;
   one issue per offending slot, in position order.
4. `.criteriaTooLong(slot.id)` — any slot's `criteria`, when tokenized by a
   simple whitespace split, produces more than 77 tokens (the CLIP window);
   one issue per offending slot, in position order.  
   *Approximation is fine here — the goal is a UI warning, not exact BPE
   counting. Count space-separated words as a proxy.*
5. `.duplicatePositions` — two or more slots share the same `position` value;
   one issue total (not one per duplicate).

Write unit tests covering: all-valid (empty result), each issue type in
isolation, and a template that triggers all five issues simultaneously.

**Acceptance criterion:** `swift test --filter TemplateValidationTests` passes;
all five issue kinds are exercised.

**Verification:** `cloud-safe`

---

### T-02 · `SwiftDataTemplateStore` — SwiftData-backed `TemplateStore`

**Title:** Implement `SwiftDataTemplateStore` conforming to `TemplateStore`

**Files touched:**
- `Packages/CarouselStudioKit/Sources/TemplateEngine/SwiftDataTemplateStore.swift` *(new)*
- `Packages/CarouselStudioKit/Tests/CarouselStudioKitTests/SwiftDataTemplateStoreTests.swift` *(new)*

**What to build:**
Create `public actor SwiftDataTemplateStore: TemplateStore` in the
`TemplateEngine` target (add `import SwiftData` and `import Persistence`).
The actor wraps a `ModelContext` (or `ModelContainer` from which it creates
its own context). Map between `CoreModels.Template`/`CoreModels.Slot` and the
`Persistence.Template`/`Persistence.Slot` `@Model` classes.

Contract requirements to honour exactly:
- `allTemplates()` returns templates sorted most-recently-updated first
  (`updatedAt` descending).
- `template(withID:)` returns `nil` (not a throw) for an unknown ID.
- `save(_:)` does insert-or-update keyed on `template.id`; sets `updatedAt`
  to `Date.now`; emits `.saved(id)` on the `changes()` stream after the write
  commits.
- `deleteTemplate(withID:)` is a no-op (no throw) for unknown IDs; emits
  `.deleted(id)` only when something was actually removed.
- `changes()` returns a non-replaying `AsyncStream<TemplateChange>`.

Write unit tests (using an in-memory `ModelContainer`) covering: save-then-
fetch round-trip, update-stamp mutation on re-save, delete of known and
unknown IDs, and `changes()` stream delivery.

**Note on build:** SwiftData `@Model` macros require full Xcode (not CLT).
`swift build` / `swift test` will work if `DEVELOPER_DIR` points into
`~/Downloads/Xcode.app`. The CLT-only typecheck workaround from AGENTS.md
is **not** sufficient for this ticket because the macro must expand at
compile time; run the full `swift test` command under Xcode.

**Acceptance criterion:** `swift test --filter SwiftDataTemplateStoreTests`
passes with an in-memory container; all four protocol methods and the
`changes()` stream are covered.

**Verification:** `cloud-safe`

---

### T-03 · Wire `SwiftDataTemplateStore` into `AppServices` and `TemplateListView`

**Title:** Replace starter-only template list with live `SwiftDataTemplateStore` in the app

**Files touched:**
- `CarouselStudio/AppServices.swift`
- `CarouselStudio/TemplateListView.swift`

**What to build:**
1. In `AppServices`, add a lazy-initialized `SwiftDataTemplateStore` property
   backed by a `ModelContainer` built via `PersistenceSchema.makeContainer()`.
   On first launch (when the store is empty), seed it with
   `BuiltInStarterTemplates().starterTemplates()` by saving each starter.
2. In `TemplateListView`, replace the call to
   `services.starterTemplates.starterTemplates()` with an async load from
   `services.templateStore.allTemplates()`. Show a `ProgressView` while
   loading, and `ContentUnavailableView` on error. Keep the existing
   `NavigationLink → SlotMatchView` path unchanged.
3. The dev hook (`AUTO_OPEN_TEMPLATE=1`) must keep working: after load it
   should still push the first template automatically.

**Acceptance criterion:** Launch the app in the Simulator; the three starter
templates appear in the list loaded from SwiftData (not from the compiled-in
array). Kill and relaunch — the list still shows the same templates (persistent,
not re-seeded). The `AUTO_OPEN_TEMPLATE=1` smoke-launch still navigates to
`SlotMatchView`.

**Verification:** `local-only`

---

### T-04 · Template creation UI — add a new template

**Title:** Add a "New Template" sheet with slot editor and validation feedback

**Files touched:**
- `CarouselStudio/TemplateEditorView.swift` *(new)*
- `CarouselStudio/TemplateListView.swift`
- `CarouselStudio/AppServices.swift`

**What to build:**
Add a toolbar "+" button in `TemplateListView` that presents a sheet
(`TemplateEditorView`) for creating a new template.

`TemplateEditorView` must include:
- A `TextField` for template name.
- A list of slots, each with a `TextField` for `criteria` and a
  `Picker` for `SlotJudgment` (objective / subjective). Slots display
  their 1-based position number.
- "Add Slot" and swipe-to-delete controls; slots maintain contiguous
  zero-based `position` values as the user adds/removes them.
- A "Save" button (disabled while the template has validation errors).
- Inline validation feedback: run `DefaultTemplateValidator` on every
  edit and surface each `TemplateValidationIssue.message` beneath the
  relevant field (or at the top for template-level issues like `.noSlots`
  and `.duplicatePositions`).
- A "Cancel" button that discards changes without saving.

On "Save", call `services.templateStore.save(template)`. Dismiss the sheet on
success; show an alert on `PersistenceError`.

The new template must appear in `TemplateListView` immediately after save
(driven by the `changes()` stream or a re-fetch — your choice, but the list
must refresh without a manual pull-to-refresh).

**Acceptance criterion:** In the Simulator, tap "+", fill in a name and at
least one slot criterion, tap "Save", and the new template appears in the list.
Attempting to save with an empty name shows an inline error and keeps the Save
button disabled.

**Verification:** `local-only`

---

### T-05 · Template deletion UI — swipe to delete from template list

**Title:** Swipe-to-delete templates in `TemplateListView`

**Files touched:**
- `CarouselStudio/TemplateListView.swift`

**What to build:**
Add `.onDelete` handling to the template list. Tapping "Delete" on a row calls
`services.templateStore.deleteTemplate(withID:)`. Show a confirmation alert
before deleting (to avoid accidental loss of custom templates). Remove the row
from the list on success; show an alert on `PersistenceError`. Starter
templates are deletable — no special-casing.

**Acceptance criterion:** In the Simulator, swipe a template row, confirm
deletion, and the row disappears. Kill and relaunch — the deleted template is
gone.

**Verification:** `local-only`

---

## Phase 2 — Quest Engine tickets

### T-06 · `PhotoKitLibraryObserver` — `PhotoLibraryObserving` implementation

**Title:** Implement `PhotoKitLibraryObserver` conforming to `PhotoLibraryObserving`

**Files touched:**
- `Packages/CarouselStudioKit/Sources/PhotoSources/PhotoKitLibraryObserver.swift` *(new)*
- `Packages/CarouselStudioKit/Tests/CarouselStudioKitTests/PhotoKitLibraryObserverTests.swift` *(new)*

**What to build:**
Create `public final class PhotoKitLibraryObserver: PhotoLibraryObserving`
(mark `@unchecked Sendable`; it wraps a `PHPhotoLibraryChangeObserver`
registration). Implement `changes() -> AsyncStream<PhotoLibraryChange>`.

Requirements:
- Register a `PHPhotoLibraryChangeObserver` the first time `changes()` is
  called (or on `init`); deregister when the stream's `onTermination` fires.
- Map `PHChange` → `PhotoLibraryChange`: use `PHChange.changeDetails(for:)`
  on the `PHAsset` fetch results to populate `inserted`, `deleted`,
  `modified` with `PhotoAssetID(source: .photoKit, rawValue: asset.localIdentifier)`.
  Fields must be disjoint: an asset that appears in `inserted` must not also
  appear in `modified`.
- Coalescing/debouncing: if `photoLibraryDidChange` fires more than once
  within 0.5 s, merge the changes into one emission (union of inserted/deleted/
  modified, with delete taking precedence over insert/modify for the same ID,
  and insert taking precedence over modify).
- The stream never emits an element where all three arrays are empty.

Write unit tests with a `MockPHChangeObserver` or equivalent to verify the
coalescing logic and the disjointness guarantee without needing a real photo
library. Tests that require PhotoKit authorization can be skipped on CI
(`guard PHPhotoLibrary.authorizationStatus() == .authorized else { ... }`).

**Acceptance criterion:** `swift test --filter PhotoKitLibraryObserverTests`
passes; coalescing and disjointness covered by unit tests.

**Verification:** `cloud-safe`

---

### T-07 · `DefaultCoveragePolicy` — `CoveragePolicy` implementation

**Title:** Implement `DefaultCoveragePolicy` conforming to `CoveragePolicy`

**Files touched:**
- `Packages/CarouselStudioKit/Sources/QuestEngine/DefaultCoveragePolicy.swift` *(new)*
- `Packages/CarouselStudioKit/Tests/CarouselStudioKitTests/CoveragePolicyTests.swift` *(new)*

**What to build:**
Create `public struct DefaultCoveragePolicy: CoveragePolicy`. Implement
`coverage(for slot:candidates:) -> SlotCoverage` with these thresholds (all
tunable via `init` parameters with the defaults shown):

| Threshold | Default | Meaning |
|---|---|---|
| `qualityFloor: Double` | `0.35` | Minimum `combinedScore` for a candidate to count as "good" |
| `scarceMax: Int` | `2` | ≤ this many good candidates → `.scarce`; 0 good → `.none` |
| `ampleMin: Int` | `3` | ≥ this many good candidates → `.ample` |

The returned `SlotCoverage` must have:
- `slotID` = `slot.id`
- `level` = `.none` when `candidateCount == 0`, `.scarce` when
  `1 ≤ candidateCount ≤ scarceMax`, `.ample` when `candidateCount ≥ ampleMin`.
- `candidateCount` = count of candidates with `combinedScore ≥ qualityFloor`.
- `bestScore` = top `combinedScore` in the full `candidates` array (regardless
  of the quality floor), or `nil` when `candidates` is empty.

Subjective vs. objective `SlotJudgment` does not affect the default thresholds
in Phase 2 (reserved for personalisation).

Write unit tests covering: empty candidates → `.none` + nil bestScore; one
below-floor candidate → `.none` + non-nil bestScore; candidates spanning all
three levels; threshold boundary conditions.

**Acceptance criterion:** `swift test --filter CoveragePolicyTests` passes.

**Verification:** `cloud-safe`

---

### T-08 · `InMemoryQuestReportStore` — in-memory `QuestReportStore` for tests

**Title:** Implement `InMemoryQuestReportStore` conforming to `QuestReportStore`

**Files touched:**
- `Packages/CarouselStudioKit/Sources/QuestEngine/InMemoryQuestReportStore.swift` *(new)*
- `Packages/CarouselStudioKit/Tests/CarouselStudioKitTests/QuestReportStoreTests.swift` *(new)*

**What to build:**
Create `public actor InMemoryQuestReportStore: QuestReportStore`. This is the
store used in tests and the composition root until a SwiftData-backed version
arrives. Store reports in a `[Template.ID: [QuestReport]]` dictionary keyed on
`templateID`, maintaining newest-first order.

Contract requirements to honour exactly:
- `latestReport(for:)` returns `nil` for an unknown `templateID`.
- `history(for:limit:)` returns at most `limit` reports, newest first.
- `save(_:)` is insert-or-replace on `report.id` (idempotent re-delivery is
  safe); newest-first ordering must be maintained after each save.
- `deleteReports(for:)` removes all history for a `templateID`; idempotent.

Write unit tests covering: save-then-fetch, insert-or-replace idempotency,
newest-first ordering, limit capping, and delete idempotency.

**Acceptance criterion:** `swift test --filter QuestReportStoreTests` passes.

**Verification:** `cloud-safe`

---

### T-09 · `DefaultQuestCoordinator` — `QuestCoordinating` implementation

**Title:** Implement `DefaultQuestCoordinator` conforming to `QuestCoordinating`

**Files touched:**
- `Packages/CarouselStudioKit/Sources/QuestEngine/DefaultQuestCoordinator.swift` *(new)*
- `Packages/CarouselStudioKit/Tests/CarouselStudioKitTests/QuestCoordinatorTests.swift` *(new)*

**What to build:**
Create `public actor DefaultQuestCoordinator: QuestCoordinating`. Constructor
injection:

```swift
public init(
    observer: any PhotoLibraryObserving,
    templateStore: any TemplateStore,
    matcher: any TemplateMatching,
    policy: any CoveragePolicy,
    reportStore: any QuestReportStore
)
```

Implement the four protocol methods:

**`activate()`**
Starts two concurrent observation loops (idempotent; guard with a flag):
1. *Library loop* — `for await change in observer.changes()`: calls
   `templateStore.allTemplates()`, then for each template calls
   `matcher.update(existingMatch, applying: change, ...)`, runs
   `policy.coverage(for:candidates:)` per slot, builds a `QuestReport`
   (trigger `.libraryChange`), saves it, and yields it to the `reports()`
   stream. A per-template error is logged and skipped; does not stop the loop.
2. *Template loop* — `for await change in templateStore.changes()`:
   on `.saved(id)` re-runs a full `matcher.match(...)` for that template
   (trigger `.templateChange`); on `.deleted(id)` calls
   `reportStore.deleteReports(for: id)` and emits nothing.

**`deactivate()`**
Cancels both observation tasks. `reports()` streams stay open.

**`refresh(templateID:)`**
Runs a full `matcher.match(...)` (not incremental) for the specified template
(or all templates when `nil`). Trigger `.manual`. Saves and publishes each
report as it completes. Throws on the first systemic error encountered.

**`reports()`**
Returns an `AsyncStream<QuestReport>` that:
- Replays the latest known report per template (fetched from `reportStore`) on
  subscription.
- Then delivers live updates as they are produced by the loops above.

**Error handling:** observation loops absorb per-template errors (log at
`os.Logger` level `.error`, continue). `refresh` propagates errors to its
caller.

Write unit tests using stub implementations (reuse the stubs pattern from
`ContractConformanceTests.swift`). Cover:
- `activate()` idempotency (calling twice starts only one set of loops).
- `refresh(templateID: nil)` produces one report per template and saves them.
- `refresh(templateID: someID)` only touches that template.
- `reports()` replays latest known reports on subscription.
- Receiving a `.deleted` template change causes `deleteReports` to be called.

**Acceptance criterion:** `swift test --filter QuestCoordinatorTests` passes.

**Verification:** `cloud-safe`

---

### T-10 · Wire Quest Engine into `AppServices` and activate on launch

**Title:** Activate `DefaultQuestCoordinator` in `AppServices` after photo access is granted

**Files touched:**
- `CarouselStudio/AppServices.swift`
- `CarouselStudio/CarouselStudioApp.swift`

**What to build:**
1. In `AppServices`, add a lazy-initialized `DefaultQuestCoordinator` property
   wired to: `PhotoKitLibraryObserver`, `SwiftDataTemplateStore`,
   a `DefaultTemplateMatcher` (reuse the same factory as `templateMatcher(…)`
   but without a progress closure), `DefaultCoveragePolicy()`, and
   `InMemoryQuestReportStore`.
2. In `CarouselStudioApp` (or a `.task` on the root view), after photo access
   is confirmed (`.full` or `.limited`), call
   `await services.questCoordinator.activate()`.
3. On `scenePhase` change to `.background`, call
   `await services.questCoordinator.deactivate()`; on return to `.active`,
   call `activate()` again. Use SwiftUI's `@Environment(\.scenePhase)`.

**Acceptance criterion:** Run the app in the Simulator. After granting photo
access, the OSLog stream (`subsystem == "com.edwardkim.CarouselStudio"`)
shows at least one log line from the coordinator indicating the initial scan
ran (add a single `Logger` `.notice` log in `DefaultQuestCoordinator` when
a `QuestReport` is saved — message format: `"quest report saved:
templateID=\(id) coverage=\(coverage.map { "\($0.slotID):\($0.level)" })"`).
Background/foreground cycling does not crash.

**Verification:** `local-only`

---

### T-11 · Quest coverage UI — surface `QuestReport` in `TemplateListView`

**Title:** Show per-template slot coverage badges in `TemplateListView`

**Files touched:**
- `CarouselStudio/TemplateListView.swift`
- `CarouselStudio/AppServices.swift`

**What to build:**
In `AppServices`, expose the latest `QuestReport` per template as an
`@Observable` dictionary property
(`var latestReports: [Template.ID: QuestReport] = [:]`), updated by consuming
`services.questCoordinator.reports()` in a long-lived `Task`.

In `TemplateListView`, beneath each template row's subtitle, add a coverage
summary line if a `QuestReport` is available. Format:

- If every slot is `.ample`: `"✓ All slots covered"` in a green/secondary
  style.
- If any slot is `.none`: `"⚠ \(noneCount) slot\(noneCount == 1 ? "" : "s")
  need photos"` in an orange/warning style.
- Otherwise (mix of scarce/ample, no `.none`): `"→ \(scarceCount)
  slot\(scarceCount == 1 ? "" : "s") could use more photos"` in a secondary
  style.
- If no report yet: show nothing (don't show a "scanning…" placeholder —
  keep the list clean until data arrives).

**Acceptance criterion:** In the Simulator, after photo access is granted and
the initial scan completes, at least one template row shows a coverage line.
The text matches one of the three formats above. A `refresh(templateID: nil)`
call (trigger it via pull-to-refresh on the list — add `List { … }.refreshable
{ try? await services.questCoordinator.refresh(templateID: nil) }`) updates
the coverage lines.

**Verification:** `local-only`

---

## Dependency order and parallelism guidance

```
T-01  (no deps)          ─── cloud-safe, independent
T-02  (no deps)          ─── cloud-safe, independent
T-06  (no deps)          ─── cloud-safe, independent
T-07  (no deps)          ─── cloud-safe, independent
T-08  (no deps)          ─── cloud-safe, independent

T-03  depends on T-02    ─── local-only (Simulator)
T-04  depends on T-02, T-01
T-09  depends on T-06, T-07, T-08

T-05  depends on T-03    ─── local-only
T-10  depends on T-03, T-06, T-07, T-08, T-09
T-11  depends on T-10
```

Tickets T-01, T-02, T-06, T-07, T-08 have no interdependencies and can be
handed to parallel agents. T-03 and T-04 may be parallelised only if T-02
and T-01 are complete respectively. T-09 requires T-06, T-07, and T-08 to all
be complete. T-10 and T-11 must run sequentially at the end.
