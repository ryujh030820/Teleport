# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Teleport is a macOS menu bar app switcher triggered by `Option+Tab`. It shows running apps in a grid with quick-key shortcuts for direct jumping. Runs as an accessory app (no dock icon, menu bar only).

- **Language:** Swift 6 (strict concurrency)
- **UI:** SwiftUI views hosted in AppKit via NSHostingView
- **Platform:** macOS 14.0+ (Sonoma)
- **Build system:** Swift Package Manager

## Build & Run Commands

```bash
# Run in debug mode
swift run Teleport

# Build release and package as .app bundle
./Scripts/build_app.sh
open dist/Teleport.app

# Build only (debug)
swift build

# Build only (release)
swift build -c release --product Teleport
```

There are no tests configured in this project.

## Architecture

All source lives in `Sources/Teleport/`. The app uses @MainActor isolation throughout for thread safety.

**Data flow:** HotKeyManager → AppDelegate → RunningAppStore.makeSnapshot() → SwitcherWindowController → SwitcherViewModel → SwiftUI views

Key files:

- **main.swift** — Entry point. Sets up NSApplication with `.accessory` activation policy.
- **AppDelegate.swift** — Orchestrates all components. Contains `StatusBarController` for the menu bar icon. Connects hot key events to the switcher presentation.
- **HotKeyManager.swift** — Registers global `Option+Tab` hotkey using Carbon HIToolbox APIs. Uses C callback bridge with `Unmanaged` pointers.
- **RunningAppStore.swift** — Tracks running apps in MRU order via `NSWorkspace.didActivateApplicationNotification`. Produces immutable `SwitcherSnapshot` for the UI.
- **SwitcherModels.swift** — Contains all data models and SwiftUI views in one file:
    - `SwitchableApp` — wraps NSRunningApplication with UI metadata
    - `QuickKeyAllocator` — assigns mnemonic keys from app names, then fallback pool
    - `SwitcherLayout` — calculates responsive grid dimensions from app count and screen size
    - `SwitcherViewModel` — @ObservableObject driving the SwiftUI grid
    - `SwitcherOverlayView` / `SwitcherAppCard` — SwiftUI views with glass morphism styling
- **SwitcherWindowController.swift** — Manages a borderless floating NSPanel. Handles all keyboard/mouse input via local NSEvent monitoring. Activates selected app on Option key release.

## Key Patterns

- **Snapshot architecture:** RunningAppStore produces immutable snapshots decoupled from live state, ensuring consistent UI during a single switcher session.
- **Carbon-SwiftUI bridge:** Global hotkeys use Carbon HIToolbox (no Swift-native alternative), while the overlay UI is pure SwiftUI hosted in an NSPanel via NSHostingView.
- **Input handling:** The switcher intercepts Tab, arrow keys, letter/number quick keys, mouse hover, Return, Escape, and modifier release — all via `NSEvent.addLocalMonitorForEvents` in SwitcherWindowController.
- **Quick key allocation:** Letters are assigned preferentially from each app's name before falling back to remaining available keys (A-Z, 0-9).

## Commit Convention

- Format: `type: description` (lowercase, imperative mood)
- Types: `feat`, `fix`, `ui`, `refactor`, `docs`, `chore`, `perf`, `test`
- Commit per logical unit of work — when a task is completed, commit immediately before moving on
- Keep the subject line concise (under 72 characters); use the body for details when needed

## Bundle Configuration

- **Bundle ID:** `com.junghwanryu.teleport-switcher`
- **Info.plist:** Located in `AppResources/Info.plist`. LSUIElement=true (no dock icon).
- **build_app.sh** creates the .app bundle structure in `dist/`, copies the binary and Info.plist, and ad-hoc codesigns.
