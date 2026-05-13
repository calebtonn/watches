# Watches

A macOS screensaver delivering six watch-face dials — five analog homages and one digital easter egg.

> **Status:** pre-release (v0.1.0, alpha). The host, dial-renderer protocol, and the Sonoma exit-bug workaround are in place. A developer "proof-of-host" dial ships in the current build; the user-visible dials land progressively in upcoming releases. No DMG yet — build from source.

---

## The dial set

| Dial | Inspiration | Status |
|---|---|---|
| Asymmetric Moonphase | A. Lange & Söhne Lange 1 Moonphase | planned |
| Diver | Rolex Submariner (tritium era, with aged "pumpkin" lume) | planned |
| Moonchrono | Omega Speedmaster Moonwatch Professional | planned |
| Coke GMT | Tudor Black Bay 58 GMT | planned |
| Octagon | Audemars Piguet Royal Oak | planned |
| Royale (digital easter egg) | Casio AE-1200WH | planned |

Each dial is a homage — not an affiliation. Brand names appear only as credit lines per the homage subject. See *Legal posture* below.

---

## Requirements

- macOS 14 (Sonoma) or newer
- Xcode 16+ (for building from source)
- Command Line Tools alone are not sufficient — full Xcode.app is required

---

## Install (from source)

```sh
git clone https://github.com/calebtonn/watches.git
cd watches
brew install xcodegen        # one-time, if not already installed
make install-dev
```

`make install-dev` builds the `.saver`, ad-hoc codesigns it, and copies it to `~/Library/Screen Savers/`. Open **System Settings → Screen Saver** and pick "Watches".

To uninstall:

```sh
rm -rf ~/Library/Screen\ Savers/Watches.saver
```

---

## Development

| Command | What it does |
|---|---|
| `make project` | Regenerate `Watches.xcodeproj` from `project.yml` (xcodegen) |
| `make build` | Build the `.saver` bundle, Release configuration, ad-hoc signed |
| `make install-dev` | Build + install into `~/Library/Screen Savers/` |
| `make test` | Run the XCTest suite (pure render math only — see test boundary below) |
| `make clean` | Remove `build/` and the generated `Watches.xcodeproj` |

### Project structure

- `WatchesCore/` — framework: `DialRenderer` protocol, registry, time source, render-math helpers, per-dial implementations
- `Watches/` — `.saver` bundle: host shim only (`WatchesScreenSaverView`)
- `WatchesTests/` — XCTest suite against `WatchesCore`
- `project.yml` — canonical Xcode project spec (the `.xcodeproj` is generated)

### Test boundary

XCTest covers pure render math (angles, tick positions, date math). It does **not** cover view hierarchies, `CALayer` state, animation correctness, or visual fidelity — those are judged by eye against reference photos. The full suite is intentionally tiny and runs in under one second.

---

## Distribution + Gatekeeper

The `.saver` is ad-hoc signed (no Apple Developer ID, no notarization). First-time install via a downloaded artifact will require:

1. Right-click the `.saver` → **Open** (not double-click)
2. Confirm the "developer cannot be verified" prompt

If macOS quarantine is sticky on a newer release:

```sh
xattr -d com.apple.quarantine ~/Library/Screen\ Savers/Watches.saver
```

A signed DMG will be published with the v1.0 release.

---

## Legal posture

This project is a fan homage. It is not affiliated with, endorsed by, or sponsored by any watch brand. Each dial is credited to its real-world inspiration in its per-dial design notes and in the eventual preferences pane. Where a homage would require reproducing a brand mark or model name on the dial face itself, the homage is rendered without that mark. If a rights holder objects to a specific dial, that dial gets renamed or removed; the project is not worth a legal fight.

The "Royale" name follows established watch-community usage for the Casio AE-1200WH and points back to the homaged object, not the Bond franchise.

---

## Credits

- Build scaffolding patterns informed by [davenicoll/swiss-railway-clock-screensaver](https://github.com/davenicoll/swiss-railway-clock-screensaver) (MIT) — re-implemented for this project
- Each dial credits its inspiration in `WatchesCore/Dials/<Dial>/credit.txt`

---

## License

MIT — see [LICENSE](LICENSE).
