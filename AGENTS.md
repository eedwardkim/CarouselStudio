# Agent notes

- Design docs: `ARCHITECTURE.md` (subsystems, boundaries, contracts) and
  `DATA_MODEL.md` (SwiftData schema, delete rules, privacy guarantees). Read
  both before touching `Packages/CarouselStudioKit`.
- Build/test: `cd Packages/CarouselStudioKit && swift build && swift test`.
  **Both require full Xcode** (`xcode-select -p` must point into Xcode.app):
  the bare Command Line Tools ship neither Swift Testing nor the SwiftData
  `@Model` macro plugin (`SwiftDataMacros`), so the `Persistence` target and
  the test target fail to compile under CLT.
- CLT-only fallback used for verification: copy sources to a temp dir, strip
  `@Model` / `@Attribute(...)` / `@Relationship(...)` lines, then
  `swiftc -swift-version 6 -typecheck` against a prebuilt `CoreModels`
  module. Validates everything except macro expansion and runtime behavior.
- Conventions: Swift 6 language mode, everything `Sendable` where possible,
  `///` doc comments on public API, value types in `CoreModels`, SwiftData
  models never leave store implementations, enums persisted as raw strings.
