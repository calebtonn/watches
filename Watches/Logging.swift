import os

/// Project-wide `os.Logger` factories, scoped by subsystem and category per P6.
///
/// Subsystem is `com.calebtonn.watches`. Categories partition concerns:
///   - `host`     — `WatchesScreenSaverView` lifecycle, display link, power state
///   - `renderer` — per-dial render activity (debug-level only; stripped in Release)
///   - `prefs`    — preferences pane (Story 3.1+)
///   - `exit`     — Sonoma `legacyScreenSaver` exit-bug watchdog (Story 1.3)
///
/// Usage: `Logging.host.info("...")`, `Logging.renderer.debug("...")`, etc.
/// Filter in Console.app by `subsystem:com.calebtonn.watches`.
///
/// `print(...)` is forbidden in shipping code (P6). Use these loggers instead.
enum Logging {
    static let subsystem = "com.calebtonn.watches"

    static let host     = Logger(subsystem: subsystem, category: "host")
    static let renderer = Logger(subsystem: subsystem, category: "renderer")
    static let prefs    = Logger(subsystem: subsystem, category: "prefs")
    static let exit     = Logger(subsystem: subsystem, category: "exit")
}
