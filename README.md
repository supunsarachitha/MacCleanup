# Mac Cleanup Assistant

A small, native macOS app that finds clutter, shows exactly what it would remove and how much space that frees, and only deletes after you confirm.

SwiftUI · MVVM · macOS 14 (Sonoma) or newer · no third-party dependencies · no network access

## Build and run

Requirements: macOS 14+ and Xcode 16 or newer.

**In Xcode**

1. Open `MacCleanup.xcodeproj`.
2. Select the **MacCleanup** scheme and **My Mac**.
3. Press **⌘R**.

**From the terminal**

```sh
xcodebuild -project MacCleanup.xcodeproj -scheme MacCleanup -configuration Release build
xcodebuild -project MacCleanup.xcodeproj -scheme MacCleanup -destination 'platform=macOS' test
```

The app is built ad hoc signed (`CODE_SIGN_IDENTITY = -`), which is enough to run it on the Mac that built it. To distribute it, set your own team and signing identity in the target's **Signing & Capabilities** tab and notarize it.

**Build a drag-to-Applications installer**

```sh
./scripts/build-installer.sh
```

This builds the Release app and writes `build/installer/Mac-Cleanup-Assistant.dmg`. The current ad-hoc signature is for local use; public distribution requires signing with your Developer ID and notarizing the app.

## The workflow

```
Scan → Review → Select → Confirm → Delete → Results
```

1. **Scan System** reads the cleanup locations and measures them. It has no code path that changes anything.
2. The **summary** shows each category with its size and file count, and the total you'd recover.
3. **Review Details** expands every category: location, size, file count and a short preview (never thousands of rows).
4. Every category has a checkbox. Items that are your own files (Downloads, Xcode Archives) start unchecked.
5. **Clean Selected** opens a confirmation dialog showing the size, category count and file count. Nothing is removed until **Delete** is pressed.
6. Cleanup runs with live progress and a Stop button, then the **results** screen reports space recovered, files removed and time taken.

## What it looks at

| Category | Location | How it's cleaned |
|---|---|---|
| User Cache | `~/Library/Caches` (minus the browser and Homebrew folders below) | Deleted |
| Logs | `~/Library/Logs` | Deleted |
| Temporary Files | `/private/tmp`, `/private/var/tmp` — your own items untouched for 3+ days | Deleted |
| Safari Cache | `~/Library/Caches/com.apple.Safari` | Deleted |
| Chrome Cache | `~/Library/Caches/Google/Chrome` | Deleted |
| Firefox Cache | `~/Library/Caches/Firefox/Profiles` | Deleted |
| Trash | `~/.Trash` | Deleted |
| Xcode Derived Data | `~/Library/Developer/Xcode/DerivedData` | Deleted |
| Xcode Archives | `~/Library/Developer/Xcode/Archives` | **Moved to Trash** |
| Homebrew Downloads | `~/Library/Caches/Homebrew/downloads` and `/Cask` | Deleted |
| Docker | Stopped containers, dangling images, unused build cache | `docker … prune` |
| Downloads > N days | `~/Downloads` (N is 30 by default; change it in Settings) | **Moved to Trash** |

Only the *direct children* of those folders are removed; the folders themselves stay.

Sizes are allocated disk space, which is what you actually get back. Docker figures are estimates reported by the Docker CLI.

## Safety

- **Scan is read-only.** `ScanManager` only lists folders and reads file attributes.
- **Two-step removal.** `CleanupManager` is only started from the dialog's Delete button.
- **`SafetyPolicy` is checked twice**, at scan time and again immediately before each item is removed. It refuses anything that isn't a direct child of the category's folder, anything inside Desktop, Documents, Pictures, Movies, Music, iCloud Drive, Mail, Messages, Keychains or Application Support, any Photos/Music/TV/Final Cut library, and system locations.
- **Symlinks are never followed**, so a link inside a cache can't lead the cleanup into your documents.
- **Stale items are skipped.** Downloads and temp files are re-checked right before removal; anything modified since the scan is left alone.
- **Your own files go to the Trash**, so a mistake can be undone.
- **Docker volumes are never pruned.**
- Failures are reported per item and never abort the whole run.

### Permissions and sandboxing

A disk cleaner has to read and delete files across the user's Library, so the App Sandbox is intentionally **off** (a sandboxed app can only touch its own container). Release builds enable the Hardened Runtime. The app requests no permissions up front.

Two macOS-protected locations (the Trash and Safari's cache) can only be read with **Full Disk Access**. That's optional: without it those rows show "Needs Full Disk Access" and everything else works. The first scan of Downloads triggers macOS's standard "Downloads folder" prompt.

## Project structure

```
MacCleanup/
├── App/MacCleanupApp.swift          Entry point, window, Cleanup menu, Settings scene
├── Models/
│   ├── FileCategory.swift           What a category is (data, not behaviour)
│   ├── ItemFilter.swift             Which children of a folder qualify
│   ├── ScanResult.swift             ScannedItem, SampleEntry, CategoryScanResult
│   └── CleanupResult.swift          CleanupProgress, CleanupFailure, CleanupResult
├── Services/
│   ├── CategoryCatalog.swift        The list of categories (add new ones here)
│   ├── ScanManager.swift            Read-only concurrent scan
│   ├── CleanupManager.swift         Confirmed removal with progress
│   ├── StorageAnalyzer.swift        Disk-usage measurement
│   ├── SafetyPolicy.swift           What may never be removed
│   └── DockerService.swift          Docker CLI estimate and prune
├── ViewModels/CleanupViewModel.swift  Workflow state machine (MVVM)
├── Views/                           SwiftUI screens and components
└── Support/                         Byte/duration formatting, CommandRunner
MacCleanupTests/CleanupEngineTests.swift
```

### Adding a category

1. Add a case to `FileCategory.ID`.
2. Add one `FileCategory(...)` entry to `CategoryCatalog.categories(configuration:)` with its folder(s), a filter, and a disposal (`deletePermanently` or `moveToTrash`).

The scan, cleanup, safety checks, summary and review screens pick it up with no further changes. `CleanupEngineTests` asserts that no catalog entry points at a protected location.

## Known limitations

- Homebrew uses `~/Library/Caches/Homebrew`; a custom `HOMEBREW_CACHE` isn't detected.
- Only the current user's Trash is emptied, not per-volume trashes.
- Docker Desktop may not shrink its disk image immediately after a prune.
- The app has no custom icon yet (`Assets.xcassets/AppIcon.appiconset` is ready for one).
