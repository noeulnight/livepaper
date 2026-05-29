# AGENTS.md - LivePaper

## Project Intent
LivePaper is a local-first macOS live wallpaper app. The first goal is a small, reliable MVP for local video wallpapers on one or more displays. Prefer native macOS APIs, simple process boundaries, and behavior that remains debuggable when the app is running for long sessions.

This project should not start as a cloud wallpaper platform, account system, marketplace, or full Wallpaper Engine clone. Build the local runtime first.

## Core Principles
- Keep the app local-first: no analytics, tracking, account requirement, or remote service unless explicitly added later.
- Prefer Swift and native Apple frameworks for app code.
- Keep architecture boundaries stable so the runtime can move from in-app windows to process helpers and later XPC without rewriting UI code.
- Prefer small, reversible changes. Avoid new dependencies unless there is a strong reason.
- Optimize for predictable behavior on sleep/wake, display hotplug, Spaces, fullscreen apps, and battery power.
- Do not use private APIs for the default runtime path.

## Initial Architecture
Use these conceptual modules even if they start as simple files:

```text
LivePaper.app
  App/UI layer
  WallpaperCoordinator
  WallpaperRuntime protocol
  ProcessHelperRuntime or InAppRuntime

Wallpaper runtime
  ScreenSession per display
  WallpaperWindow
  VideoPlaybackController
  PowerStateMonitor
  DisplayMonitor
```

The UI must talk to `WallpaperCoordinator`, not directly to `NSWindow`, `Process`, XPC, or helper executables.

## Runtime Boundary
Define runtime behavior behind a protocol before adding substantial implementation:

```swift
protocol WallpaperRuntime {
    func start(config: WallpaperConfig) async throws
    func stop(displayID: DisplayID) async
    func stopAll() async
    func update(config: WallpaperConfig) async throws
    func pause(displayID: DisplayID) async
    func resume(displayID: DisplayID) async
}
```

The first implementation may be `InAppRuntime` or `ProcessHelperRuntime`. A future `XPCRuntime` should be able to reuse the same coordinator and config model.

## Configuration Model
Keep runtime configuration structured and serializable:

```swift
struct WallpaperConfig: Codable, Sendable {
    let displayUUID: String
    let videoURL: URL
    let scaleMode: ScaleMode
    let volume: Double
    let muted: Bool
    let pauseOnBattery: Bool
    let pauseOnFullscreen: Bool
}
```

Do not scatter raw argv arrays or UserDefaults keys through UI code. Centralize mapping at the runtime boundary.

## MVP Scope
Implement first:
- Menu bar macOS app.
- Local `.mp4` and `.mov` video selection.
- `NSScreen`/display UUID based screen sessions.
- Borderless desktop-level `NSWindow` with `AVPlayerLayer` playback.
- Looping playback with `AVQueuePlayer` and `AVPlayerLooper`.
- Leave the user's macOS desktop wallpaper untouched; app stop, pause, sleep, fullscreen pause, and restart gaps should reveal the existing macOS wallpaper.
- Pause or reduce work on battery, lock, sleep, or display removal. Fullscreen auto-detection is deferred until it can be implemented without invasive process/window inspection.
- Persist selected wallpaper per display.

Defer:
- Cloud library.
- User uploads.
- Accounts, license checks, payments.
- Lock Screen or Screen Saver integration.
- XPC service.
- LaunchAgent/LoginItem agent separate from the main app.
- HTML/JS wallpaper compatibility.

## Runtime Strategy
Start simple. A good path is:

```text
1. In-app ScreenSession per display.
2. Process helper per display if isolation is needed.
3. XPC runtime only when status queries and live control justify it.
4. LoginItem or LaunchAgent only after runtime behavior is stable.
```

A process helper is an app-bundled executable managed by the main app. It is not a system daemon. It must run in the user session so it can create windows.

## macOS API Choices
Use:
- `AppKit` for `NSWindow`, `NSScreen`, menu bar app behavior, and `NSWorkspace`.
- `AVFoundation` for video playback.
- `AVPlayerLayer` for hardware-accelerated rendering.
- `CoreGraphics` only for display/window-level details when needed.
- `UserDefaults` for small settings.
- `NSOpenPanel` for user-selected file access. Keep the returned URL's security scope active only while the runtime is reading the file.
- Do not add custom "grant folder access" flows.
- `LivePaper.entitlements` for sandbox file-access policy, including Downloads read access.

Avoid by default:
- Private APIs.
- Root/system `LaunchDaemon` designs.
- Hand-rolled video decoding.
- Database persistence before it is needed.

## Performance Rules
- Prefer `AVPlayerLayer`; do not decode frames manually for normal video playback.
- Cap work when not visible or not useful: pause on lock/sleep, battery, fullscreen, or covered display when implemented.
- Use `preferredMaximumResolution` and `preferredPeakBitRate` for reduced-performance modes.
- Do not call `NSWorkspace.setDesktopImageURL` in the default runtime path.
- Keep one `ScreenSession` per active display.
- Clean up players, loopers, observers, notifications, and windows explicitly.

## Multi-Display Rules
- Identify displays by stable UUID, not only current index.
- Reconcile display sessions after hotplug or screen parameter changes.
- A display disappearing should stop only that display session.
- A display reappearing should restore its saved wallpaper if configured.
- Keep same-video multi-display support possible, but do not optimize prematurely for shared decoders.

## UI Rules
- Keep the first screen as the usable app, not a marketing page.
- Prefer a quiet utility UI: compact controls, clear display selection, predictable settings.
- Use native controls and symbols where possible.
- Avoid adding onboarding, cloud browsing, or decorative UI before the core runtime works.

## Testing and Verification
Before claiming runtime work complete:
- Build the app in Xcode or via `xcodebuild`.
- Test at least one local video on the main display.
- If display code changed, test multi-display behavior when available or isolate with unit-level display identity logic.
- Verify stop/cleanup removes windows and players.
- Verify the app survives sleep/wake or document the untested risk.

For pure model/coordinator code, add unit tests once a test target exists.

## Git and Change Hygiene
- Do not commit unless the user explicitly asks.
- Keep commits Conventional Commits when requested.
- Do not add dependencies without explicit approval.
- Prefer small files with clear ownership over large mixed UI/runtime files.
- Do not copy GPL code from reference projects unless the license implications are intentional and documented.

## Reference Notes
`thusvill/LiveWallpaperMacOS` is useful as a reference for daemon-per-display architecture and power-state handling. Do not blindly copy its Objective-C++ implementation. Use it to inform behavior, not as a source of pasted code.
