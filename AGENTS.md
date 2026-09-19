# AGENTS.md

## Project

VPS SSH Tunnel — native macOS app (SwiftUI, SwiftPM executable target, no external dependencies) that manages an SSH SOCKS5 tunnel to a VPS via GUI buttons. macOS 13+.

## Build & run

- `swift build` — debug build (fast compile check).
- `./make-app.sh` — release build + assembles `dist/VPS SSH Tunnel.app` (binary, Info.plist, icon).
- `swift scripts/generate-icon.swift Resources && iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns` — regenerate the app icon (dark rounded square with teal rings, drawn programmatically; no image assets).
- No test suite. Verify changes by building and, for UI/behavior changes, launching the app and exercising the buttons (`open "dist/VPS SSH Tunnel.app"`); the log file (see below) and a screenshot of the window are the primary verification artifacts.

## Structure

- `Package.swift` — single executable target `VpsSshTunnel`.
- `Sources/VpsSshTunnel/VpsSshTunnelApp.swift` — `@main`, WindowGroup, AppDelegate (quits app when last window closes).
- `Sources/VpsSshTunnel/ContentView.swift` — UI: server/port fields, buttons, auto-restart toggle, log view. Observes both `AppState` and `LogStore`.
- `Sources/VpsSshTunnel/AppState.swift` — all action logic (Start/Check/Stop/Telegram/Chrome), auto-restart monitor, settings wiring, shutdown hook.
- `Sources/VpsSshTunnel/TunnelManager.swift` — `Process` wrappers for ssh/curl/pkill/open, app running/quit helpers.
- `Sources/VpsSshTunnel/SettingsStore.swift` — JSON config at `~/.config/vps-ssh-tunnel/.vps-ssh-tunnel`, auto-created with defaults.
- `Sources/VpsSshTunnel/LogStore.swift` — in-memory log + mirrored log file `~/.config/vps-ssh-tunnel/vps-ssh-tunnel.log` (truncated on launch).

## Conventions & gotchas

- UI and log language: Russian. Commit messages: English.
- No code comments unless requested. No new dependencies — Foundation/AppKit/SwiftUI only.
- Log format: `[HH:mm:ss] message`, one line per event, no empty lines. The 10s monitor is silent while the tunnel is healthy — it logs only failures/restarts.
- `ContentView` must observe `LogStore` directly (`@ObservedObject` via custom init). A nested `ObservableObject` inside `AppState` does NOT invalidate the view by itself — this once caused async log lines to never render.
- Never access a `@StateObject`'s wrapped value in the App struct's `init` — it creates a duplicate instance. Shutdown handling uses `NSApplication.willTerminateNotification` inside `AppState` for this reason.
- `Settings` mutations save via didSet with a `lastSaved` guard — SwiftUI writeback can trigger didSet with unchanged values; don't remove the guard.
- All button actions are guarded by `actionBusy` (reentrancy) — keep the guard and reset it on every async completion path.
- The monitor restart chain re-checks `monitorTimer != nil` after async steps and rolls back a restarted tunnel if the user pressed Stop mid-restart. Preserve this when editing.
- `pkill -f "ssh -D <port>"` matches any process whose command line contains the pattern — including the agent's own shell commands. In scripts/tests use a bracket trick: `pkill -f "ssh -D 108[0]"`.
- ssh is invoked with `-o ConnectTimeout=5` so unreachable hosts fail fast; curl check uses `--max-time 10` and expects HTTP 302 from api.telegram.org.
- Config must never hardcode the user's real server; default is `root@1.1.1.1`.
