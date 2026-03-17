<p align="center">
  <img src="https://github.com/user-attachments/assets/e8d405ed-b3db-4799-aab1-17c41fcc01c1" width="128" height="128" alt="Teleport icon">
</p>

<h1 align="center">Teleport</h1>

<p align="center">
  <br><strong>A blazing-fast app switcher for macOS</strong><br>
  Jump to any running app instantly with <code>Command+Tab</code> and quick keys.
</p>

<p align="center">
  <a href="#installation">Installation</a>&nbsp;&nbsp;&bull;&nbsp;&nbsp;<a href="#usage">Usage</a>&nbsp;&nbsp;&bull;&nbsp;&nbsp;<a href="#building-from-source">Build</a>&nbsp;&nbsp;&bull;&nbsp;&nbsp;<a href="#how-it-works">How It Works</a>
</p>

---

## Why Teleport?

The built-in `Cmd+Tab` switcher is a single-row strip — fine for 3 apps, painful for 15. Teleport replaces that workflow with a responsive grid overlay and **direct-jump quick keys**, so you never have to Tab through a long list again.

| Feature                 | Cmd+Tab    | Teleport                                   |
| ----------------------- | ---------- | ------------------------------------------ |
| Layout                  | Single row | Adaptive grid                              |
| Direct jump to app      | No         | Yes — press the shown letter/number        |
| Multiple profiles       | No         | Yes — create profiles with custom app sets |
| Show/hide specific apps | No         | Yes — include or exclude apps per profile  |

## Installation

### Download

Grab the latest `.app` bundle from [**Releases**](../../releases).

### Build from Source

Requires **Xcode 16+** and **macOS 14 Sonoma** or later.

```bash
git clone https://github.com/junghwanryu/Teleport.git
cd Teleport
./Scripts/build_app.sh
open dist/Teleport.app
```

### First Launch

No special privacy permission is required for the default global hotkey. If macOS restores the app without the shortcut responding after an older build, remove the old `Teleport` entry from Login Items or relaunch the app bundle from `dist/Teleport.app`.

## Usage

Press **`Command+Tab`** to open the switcher. While holding Option:

| Key                              | Action                           |
| -------------------------------- | -------------------------------- |
| `Tab` / `Shift+Tab`              | Move forward / backward          |
| Arrow keys                       | Navigate the grid                |
| Shown letter or number           | Jump directly to that app        |
| Mouse hover                      | Move selection                   |
| `Return`                         | Activate selected app            |
| `Escape`                         | Dismiss without switching        |
| Release `Option`                 | Activate selected app            |
| `` ` `` (backtick)               | Open profile picker              |
| Profile hotkey (e.g. `F1`–`F12`) | Switch to that profile instantly |

Quick keys are derived from each app's name first (e.g., **S** for Safari, **F** for Finder), then assigned from a fallback pool — so they stay intuitive and stable.

## How It Works

Teleport runs as a lightweight menu bar utility (`LSUIElement`) with no Dock icon. Under the hood:

- **Global hotkey** registered via Carbon HIToolbox APIs — the only reliable way on macOS.
- **SwiftUI overlay** rendered in a borderless `NSPanel`, hosted through `NSHostingView`.
- **Snapshot architecture** — the app list is captured as an immutable snapshot when the switcher opens, so the UI stays consistent even if apps launch or quit mid-switch.
- **Input-language agnostic** — quick keys map to physical key positions, not characters, so they work regardless of your current keyboard layout.

Built with Swift 6 (strict concurrency) and SwiftUI, targeting macOS 14+.

## Tech Stack

|              |                                  |
| ------------ | -------------------------------- |
| Language     | Swift 6                          |
| UI           | SwiftUI + AppKit (NSHostingView) |
| Build System | Swift Package Manager            |
| Platform     | macOS 14.0+                      |
| Hotkey       | Carbon HIToolbox                 |

## Project Structure

```
Sources/Teleport/
├── main.swift                    # Entry point
├── AppDelegate.swift             # Orchestration & menu bar
├── HotKeyManager.swift           # Global Command+Tab registration
├── RunningAppStore.swift         # MRU app tracking & snapshots
├── SwitcherModels.swift          # Models, layout, SwiftUI views
└── SwitcherWindowController.swift # NSPanel & input handling
```

## Contributing

Contributions are welcome! Feel free to open an issue or submit a pull request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is available under the [MIT License](LICENSE).

---

<p align="center">
  Made with care for macOS power users.
</p>
