# MacCleaner

A native macOS app that scans your disk and helps you reclaim storage space by safely removing developer caches, build artifacts, app caches, logs, iOS backups, and Time Machine snapshots.

## Features

- **Concurrent scanning** — all categories are scanned in parallel using Swift structured concurrency
- **Preview before delete** — review every file before anything is removed; deselect items you want to keep
- **Safety ratings** — each category is labelled Safe, Review, or Careful so you always know the risk
- **Trash-first deletion** — items go to the Trash when possible; permanent delete is used only as a fallback and flagged in the UI
- **Path safety guard** — deletion is blocked for any path outside your home directory (except known safe system paths)
- **Time Machine snapshot cleanup** — lists and deletes local snapshots via `tmutil`

## What it cleans

| Group | Category | Safety |
|-------|----------|--------|
| Developer | Xcode Derived Data | Safe |
| Developer | Xcode Archives | Careful |
| Developer | CoreSimulator Devices | Careful |
| Developer | Android Gradle Cache | Safe |
| Developer | NPM Cache | Safe |
| Developer | CocoaPods Cache | Safe |
| Developer | Flutter Pub Cache | Safe |
| Developer | Project Build Files (`node_modules`, `Pods`, `.next`, `build`, `.dart_tool` inside `~/Developer`) | Review |
| General | App Caches (whitelisted safe apps only) | Review |
| General | User Logs | Safe |
| System Data | iPhone/iPad Backups | Careful |
| System Data | Crash Reports | Safe |
| System Data | Time Machine Snapshots | Review |

> **App Caches** only removes caches from a known-safe list of apps (Chrome, Firefox, Slack, Spotify, VS Code, Figma, Zoom, JetBrains IDEs, etc.) — system and unknown app caches are left untouched.

## Requirements

- macOS 13 Ventura or later
- Xcode 15+ (to build)
- No sandbox entitlements required — runs as a standard user process

## Building

### With Xcode

Open `MacCleaner.xcodeproj` and press **Cmd+R**.

### From the command line

```bash
./build.sh
```

The compiled app lands in `build/MacCleaner.app`.

## Project Structure

```
Sources/
├── MacCleanerApp.swift          # App entry point, window setup
├── ContentView.swift            # Root view: sidebar + dashboard layout
├── Models/
│   └── StorageCategory.swift   # Category types, safety ratings, paths, icons
├── Services/
│   ├── StorageManager.swift    # Scanning, size calculation, deletion logic
│   └── ShellRunner.swift       # Safe shell execution (tmutil wrapper)
└── Views/
    └── PreviewSheet.swift      # File-by-file preview and confirm sheet
```

## How it works

1. **Scan** — `StorageManager.startScan()` fans out one async task per category. Each task walks the target directory (or calls `tmutil listlocalsnapshotdates`) and totals the cleanable bytes. Safe categories are auto-checked; moderate and caution categories require manual opt-in.

2. **Preview** — Clicking **Preview & Clean** opens a sheet listing every item sorted by size. You can filter, re-sort, and deselect anything before committing.

3. **Clean** — Confirmed items are deleted concurrently by category. Each file is first moved to the Trash via `FileManager.trashItem`. If that fails (e.g. on a volume that doesn't support Trash), `removeItem` is used and the UI reports it. Time Machine snapshots are deleted with `tmutil deletelocalsnapshots`.

## Notes

- Deleting **CoreSimulator Devices** or **Xcode Archives** will remove simulator runtimes and app archives permanently (after Trash). Re-downloading simulators requires Xcode.
- Deleting **iPhone/iPad Backups** is irreversible once the Trash is emptied.
- Time Machine snapshot deletion may fail without admin privileges — the UI will surface an error message if that happens.
