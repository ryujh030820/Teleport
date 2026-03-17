# Repository Guidelines

## Project Structure & Module Organization
`Teleport` is a small Swift Package Manager app targeting macOS 14+. Core source files live in `Sources/Teleport/`, with `main.swift` as the entry point and feature logic split across focused files such as `AppDelegate.swift`, `HotKeyManager.swift`, `RunningAppStore.swift`, and `SwitcherWindowController.swift`. App bundle metadata lives in `AppResources/Info.plist`. Release packaging is handled by `Scripts/build_app.sh`. Generated output belongs in `.build/` and `dist/`; do not hand-edit those directories.

## Build, Test, and Development Commands
Use SwiftPM for local development:

```bash
swift build                    # Debug build
swift run Teleport             # Launch the menu bar app locally
swift build -c release --product Teleport
./Scripts/build_app.sh         # Create dist/Teleport.app
open dist/Teleport.app         # Launch the packaged app
```

Run commands from the repository root.

## Coding Style & Naming Conventions
Follow the existing Swift style in `Sources/Teleport/`: 4-space indentation, one top-level type per concern, and clear `UpperCamelCase` type names with `lowerCamelCase` members. Keep files small and purpose-driven; new AppKit or SwiftUI behavior should usually extend an existing feature file rather than introduce generic utility layers. Prefer `@MainActor` isolation for UI-facing code, matching the current architecture. There is no repo-local formatter config, so keep changes consistent with nearby code and Xcode’s default Swift formatting.

## Testing Guidelines
There is currently no `Tests/` target and no automated test suite configured. For now, validate changes with `swift build`, then run `swift run Teleport` and manually verify the affected switcher behavior, hotkeys, and app activation flow. When adding tests later, create a `Tests/TeleportTests/` target and use Swift Testing or XCTest with file names like `HotKeyManagerTests.swift`.

## Commit & Pull Request Guidelines
Use the `type: description` format for commit messages (lowercase, imperative mood). Common types: `feat`, `fix`, `ui`, `refactor`, `docs`, `chore`, `perf`, `test`. Keep subject lines under 72 characters; add a body for details when needed. Commit per logical unit of work — when a task is completed, commit immediately before moving on. Pull requests should include a brief summary, manual verification steps, and screenshots or screen recordings for UI changes to the switcher overlay or menu bar behavior. Link related issues when applicable and call out any macOS permission or signing changes explicitly.
