# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

MacBridge is a macOS menu-bar app (Swift 5.9+ / SwiftUI, macOS 13+) that helps Windows-keyboard users on Mac by remapping the few keys whose muscle memory hurts most (`Ctrl+C/V/X/Z`, etc. → `Cmd+…`). Scope is intentionally narrow — it is *not* a Karabiner replacement; see `README.md` and `docs/PRD.md` for the product framing.

## Commands

```bash
# Run all tests (uses SwiftPM)
swift test

# Run a single test class or method
swift test --filter MacBridgeTests.RemapEngineTests
swift test --filter MacBridgeTests.RemapEngineTests/testCtrlCRemapsToCmdC

# Debug build (no signing/install, fastest iteration)
swift build

# Release build → universal `.app` bundle, codesign, install to /Applications, kill any running instance
./build.sh                 # release (default)
./build.sh debug           # debug variant
MACBRIDGE_SIGN_IDENTITY="My Identity" ./build.sh   # override the default ad-hoc "MacBridge Dev" identity
```

`build.sh` is the canonical packaging path — `swift build` alone does not produce a runnable `.app`. After install, launch with `open -a MacBridge`.

## Architecture

### Two parallel remap pipelines, on purpose

`docs/tech-design.md` documents the deliberate split between two mechanisms; both can be active at once for different keys:

1. **`hidutil` kernel-level mapping** — handled by `Core/HIDUtil/` and orchestrated by `Core/Profile/ProfileManager`. Used for **modifier-key swaps** (e.g. `Cmd`↔`Option` for Windows-layout external keyboards). Per-device, keyed by `VendorID`+`ProductID`. Mapping survives until reboot, so MacBridge re-applies on launch and on hot-plug, and clears mappings on `NSApplication.willTerminateNotification` (see `ProfileManager.cleanupAll`).

2. **`CGEventTap` user-space rewriting** — handled by `Core/EventTap/EventTapController` + `Core/Remap/RemapEngine`. Used for **non-modifier semantic remaps** (e.g. `Ctrl+C` → `Cmd+C`). Runs the rule pipeline against every keyDown/keyUp.

Do not "unify" these — `hidutil` is zero-latency and works under remote-control software that injects `CGEvent`s, but it cannot do app-aware or context-sensitive rewrites; `CGEventTap` can, at the cost of needing TCC permissions and being bypassable by some virtualisation paths.

### Event tap pipeline (`Core/EventTap/`)

`EventTapController` owns a single `CGEventTap` and runs an ordered `[KeyRemapRule]` against every event. Key invariants worth preserving:

- **Tap-location fallback**: prefers `.cghidEventTap` (sees system shortcuts like `Cmd+Tab`) and falls back to `.cgSessionEventTap` (the layer that always works for ad-hoc-signed user apps). Synthetic events must be re-posted at the same layer the tap was created on — that is why `RemapEngine.postEvent` is injected by `EventTapController` rather than hard-coded.
- **Synthetic-event marker**: outgoing rewrites tag `eventSourceUserData` with `KeyRemapSyntheticEvent.userData` ("MBRIDGE"). The tap callback short-circuits on this so re-entered synthetic events are not remapped a second time.
- **`isBypassed` flag**: the press-to-capture UI in `Settings/KeyCapture` toggles this so its `NSEvent` monitor sees raw keystrokes instead of rewritten ones. Don't rely on this for production gating — for that, use `AppSettings.remapEngineEnabled` (the master kill switch).
- **keyUp pairing**: `RemapEngine` records which rule fired for each `keyDown` in `remappedKeyDowns` and rewrites the matching `keyUp` by id, even if the user already released the modifier. Removing this map will cause stuck-modifier bugs in fast typing.

### Rule data model (`Core/Remap/Models.swift`)

The data shape is `SchemeLibrary` → many `Scheme`s → `RuleBook` (per scheme) → many `RemapRule`s. A `RemapRule` is `KeyTrigger` (keyCode + required + forbidden modifiers) → `KeyOutput` (optional new keyCode + set/clear modifier diffs). The engine matches on `requiredModifiers ⊆ pressed` and `forbiddenModifiers ∩ pressed = ∅`, and **modifiers not listed in either set pass through unchanged** — that's why a single `Ctrl+T` rule also handles `Ctrl+Shift+T` (the seed rules add explicit Shift variants only because the UI surfaces them as distinct toggles).

`RuleBook.unsetKeyCode = 0xFFFF` is the placeholder for newly-added rules in the editor — it never matches a real event so partially-edited rules are inert.

### Persistence layout

Three independent stores, on purpose — do not consolidate:

- **`SchemeStore` + `FileSchemePersistence`** — the rule library. JSON at `~/Library/Application Support/MacBridge/library.json`, written atomically via tmp+rename. Has migration logic for the legacy `UserDefaults` `remap.rulebook` key (one-time, on first launch after upgrade); when changing `RuleBook`/`SchemeLibrary` Codable shape, bump `RuleBook.currentVersion` / `SchemeLibrary.currentLibraryVersion` and add a migration branch in `SchemeStore.initialLibrary`.
- **`ProfileStore`** — per-keyboard `swapModifiers` flags (UserDefaults).
- **`AppSettings`** — global feature flags such as `remapEngineEnabled` (UserDefaults). Defaults to `true` because remote-control flows (UU/Moonlight) inject `CGEvent`s that bypass `hidutil`; turning this off would silently break those users.

### Permissions (`Services/PermissionService/AccessibilityPermission`)

The tap needs **three** TCC permissions: Accessibility (`AXIsProcessTrusted`), Input Monitoring (`CGPreflightListenEventAccess`), and Event Posting (`CGPreflightPostEventAccess`). `EventTapController.start()` does a *silent* check on each — never call `request*` from there, because re-signed ad-hoc builds can show "not trusted" even after the user granted permission, and prompting on every launch would spam dialogs. The user-facing prompt flow lives in `MacBridgeAppDelegate.applicationDidFinishLaunching` and the menu's "Re-check permissions" button. Preserve that separation.

### App composition (`App/MacBridgeApp.swift`)

`MacBridgeApp.init` constructs `AppSettings`, `KeyboardDetector`, `SchemeStore` (with `FileSchemePersistence`), `EventTapController`, `ProfileManager`, and `LaunchAtLoginService` and hands them to the views as `@StateObject`. There is no DI container — wiring is explicit at the top. `EventTapController` defers its first `reconcile()` to the next main-runloop tick because `CGEvent.tapCreate` returns nil if called before `NSApp` finishes launching.

`LSUIElement=true` in `Info.plist` — this is a menu-bar-only app, no Dock icon, no main window beyond the on-demand Settings window (id `macbridge.settings`).
