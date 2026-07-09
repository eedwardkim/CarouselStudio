# CarouselStudio

Native iOS app (SwiftUI, iOS 17+, Swift 6) that helps content creators assemble
multi-slide social posts — carousels and Stories — by matching their photo library
against reusable slot-based templates. It also suggests a matching song from a
curated corpus and runs a background "quest" system that reports which template
slots have zero/some/many good candidate photos.

## Requirements

- Xcode 16 or later (Xcode 26 recommended)
- iOS 17.0+ deployment target, Swift 6 language mode

## Getting started

```sh
open CarouselStudio.xcodeproj
```

Run the `CarouselStudio` scheme. All domain logic lives in the local Swift package:

```sh
cd Packages/CarouselStudioKit
swift build && swift test
```

## Layout

| Path | What it is |
| --- | --- |
| `CarouselStudio/` | App target: SwiftUI shell, composition root |
| `Packages/CarouselStudioKit/` | Local package with one target per module |
| `ARCHITECTURE.md` | Subsystems, boundaries, data flow, protocol contracts |

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full design.
