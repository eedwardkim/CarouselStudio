# Agent notes

- Design docs: `ARCHITECTURE.md` (subsystems, boundaries, contracts) and
  `DATA_MODEL.md` (SwiftData schema, delete rules, privacy guarantees). Read
  both before touching `Packages/CarouselStudioKit`.
- Build/test: `cd Packages/CarouselStudioKit && swift build && swift test`.
  **Both require full Xcode** (`xcode-select -p` must point into Xcode.app):
  the bare Command Line Tools ship neither Swift Testing nor the SwiftData
  `@Model` macro plugin (`SwiftDataMacros`), so the `Persistence` target and
  the test target fail to compile under CLT.
- Xcode lives at `~/Downloads/Xcode.app` (26.6). Without sudo, prefix
  commands with `export DEVELOPER_DIR=~/Downloads/Xcode.app/Contents/Developer`
  instead of `xcode-select -s`. Update the path if it moves to /Applications.
- CLT-only fallback used for verification: copy sources to a temp dir, strip
  `@Model` / `@Attribute(...)` / `@Relationship(...)` lines, then
  `swiftc -swift-version 6 -typecheck` against a prebuilt `CoreModels`
  module. Validates everything except macro expansion and runtime behavior.
- Conventions: Swift 6 language mode, everything `Sendable` where possible,
  `///` doc comments on public API, value types in `CoreModels`, SwiftData
  models never leave store implementations, enums persisted as raw strings.

## Phase 1 (implemented)

- Concrete implementations: `PhotoKitSource` (PhotoSources),
  `MobileCLIPEmbeddingProvider` + `CLIPTokenizer` + `CosineSlotMatcher` +
  `FileEmbeddingStore` + `DefaultTemplateMatcher` (MatchingEngine),
  `BuiltInStarterTemplates` (TemplateEngine). App UI: `TemplateListView` →
  `SlotMatchView` (segmented slot picker + paged swipe of ranked candidates).
- Model assets: MobileCLIP-**S0** (user decision; ARCHITECTURE.md's S2 note is
  superseded until benchmarked). Two `.mlpackage`s in `CarouselStudio/MLModels/`
  (Xcode compiles them into the bundle; loaded by URL, codegen classes unused).
  Tokenizer vocab/merges ship as `MatchingEngine` package resources.
- App build:
  `xcodebuild -project CarouselStudio.xcodeproj -scheme CarouselStudio
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`.
- Simulator smoke run: `simctl install booted <app>` then
  `SIMCTL_CHILD_AUTO_OPEN_TEMPLATE=1 simctl launch booted
  com.edwardkim.CarouselStudio` auto-opens the first template. Match evidence:
  `log stream --predicate 'subsystem == "com.edwardkim.CarouselStudio"'`.
- `simctl privacy … grant photos` does **not** stick on the iOS 26.5 runtime
  (photolibraryd ignores the TCC row); accept the photo dialog in the
  Simulator window once instead — it persists afterwards.
- Model-level smoke test without a simulator:
  `swift run MatchingSmokeCLI [image.mlpackage] [text.mlpackage]` (defaults to
  `/tmp/mobileclip/…`; verifies towers, tokenizer, ranking, cache).
