---
title: "Product Brief Distillate: Watches"
type: llm-distillate
source: "product-brief-watches.md"
created: "2026-05-11"
purpose: "Token-efficient context for downstream PRD, Architecture, and Story creation"
---

# Watches — Brief Distillate

The brief is the canonical document. This distillate captures overflow detail, rejected alternatives, and downstream-agent hints that don't belong in a 1–2 page exec summary.

## Project Identity

- **Product name:** Watches (renamed from `swisswatches`; the Lange homage is German, so "swiss" no longer fits)
- **Repo directory:** still `swisswatches` (not renamed — only the product name changed)
- **License:** MIT
- **Distribution:** GitHub Releases only; no App Store, no notarization, no Apple Developer ID
- **Primary purpose:** BMAD-method practice (on-ramp to a higher-stakes trading system project)
- **Secondary purpose:** ship a real, polished macOS screensaver
- **When purposes conflict, practice wins** — this is the load-bearing decision of the brief

## Effort & Envelope

- **Honest envelope:** 3–4 weeks of evenings (revised up from the original spec's 2 weeks)
- **Largest schedule variable:** Swift learning curve — first non-trivial Swift / SwiftUI project for the author
- **No calendar trip-wire** — the cut order fires by judgment; per-story retros are where slippage becomes visible

## Dial Lineup (final, locked)

Six homages. Public names are neutral; brand names never appear in product surface or repo.

| # | Public name | Inspiration | Key character |
|---|---|---|---|
| 1 | Asymmetric Moonphase | A. Lange & Söhne Lange 1 Moonphase | Off-center main dial, big date, moonphase, power-reserve indicator |
| 2 | Diver | Rolex Submariner ref. **16610 tritium era** (~1989–1998) | Matte black dial, **aluminum** bezel (not ceramic), **pumpkin-aged tritium** markers/hands, mercedes hands, cyclops date |
| 3 | Moonchrono | Omega Speedmaster Moonwatch Professional | 3 sub-dials, tachymeter bezel, baton indices |
| 4 | Coke GMT | Tudor Black Bay GMT | Snowflake hands, 24-hour GMT hand, red/black bicolor bezel |
| 5 | Octagon | Audemars Piguet Royal Oak | Blue tapisserie, octagonal bezel, integrated-bracelet hint |
| 6 (easter egg) | **Royale** | Casio AE-1200WH | Digital LCD, world-time map, multi-readout segments — **not** analog |

**Reference-image caveat:** the file `faces/s-l1600.jpg` reads more like a 1680/5513 (dial says "660ft=200m"), but the spec target is the 16610 tritium reference. Use the image as a *patina/tone* reference, the reference name as the *spec* reference.

## Cut Order (learning-optimized, locked)

**Cut these first, in this order, if v1 slips:**
1. Diver — most conventional analog, teaches the protocol nothing the others don't already
2. Octagon — texture-rendering exercise, low protocol value
3. Moonchrono — sub-dials decorative-only in v1; tachymeter is rendering work but not protocol work

**Protected from cuts (these earn the abstraction):**
- Asymmetric Moonphase — non-concentric layout forces the protocol to abandon implicit "circle of indices" assumption
- Coke GMT — 4th hand + bicolor bezel test parameter passing
- Royale — digital paradigm is the protocol's ultimate stress test

**No calendar trip-wire** — the cut fires by author judgment, surfaced through retros.

## Tech & Architecture Hints (for Winston / Architect)

- Native **Swift / SwiftUI**, `ScreenSaverView` subclass hosting selected `DialRenderer`
- Each dial = folder under `Dials/<name>/` with: renderer, preview asset, homage credit text, **`notes.md`** (mandatory, not optional — captures design decisions made and rejected per dial)
- **`DialRenderer` protocol sketch (not yet final, Architect's job to finalize):**
  - `dimensions` (some form of size declaration)
  - dirty-region declaration
  - `draw(at time: Date)` core method
  - preferences schema (empty in v1; must exist as a contract)
- **Critical constraint:** protocol must *not* bake a concentric-circle assumption (Asymmetric breaks it); must *not* assume analog (Royale breaks it)
- **Time source:** read macOS system clock (already NTP-synced) once per draw + monotonic source for animation continuity; no NTP layer of our own
- **No automated tests in v1** — deliberate decision, not omission. Visual verification by eyeball against `faces/` images.

## Rejected Ideas (do not re-propose)

- **WebKit-hosted SVG renderer** — rejected for native Swift. The screensaver-sandbox × WKWebView × multi-display risk class is the reason; original spec recommended it but the user overrode.
- **Apple Developer ID + notarization ($99/yr)** — rejected as scope creep for v1. Users will right-click → Open instead.
- **Original 5 genre-named dials** (Bahnhof/Mondaine, Geneva Octagon, Lunaris, Calatrava, Submersible) — fully replaced. Don't reference them.
- **F-91W as the easter egg** — user picked the AE-1200WH instead. The "Casio Royale" nickname belongs to the AE-1200WH, not the F-91W.
- **Ship-optimized cut order** (cutting hardest dials first) — rejected. Cuts conventional dials first to protect the BMAD lesson.
- **Calendar trip-wire** for cut decisions — explicitly rejected; cut fires by judgment.
- **2-week envelope** — replaced with honest 3–4 weeks.
- **"Without uninstalling" success metric** — rejected as vanity; replaced with "didn't switch active dial more than twice in 7 days."
- **Per-dial preferences in v1** — deferred to v1.1 or later.
- **Live functional sub-dials on Moonchrono** — visually drawn but static in v1; live behavior is v1.1+.
- **Animated moonphase transition on Asymmetric** — phase is correct at draw time, transition not animated.
- **Modern white-lume Submariner aesthetic (126610LN)** — rejected; the homage target is the *aged-tritium 16610 patina*. A clean white-lume version misses the point.
- **App Store distribution** — out of scope, forever.

## Legal Posture (PRD must preserve)

- **Allowed:** silhouettes, bezel motifs, dial textures, hand styles, color palettes, indices arrangements, complications layouts
- **Forbidden in product surface and code:** trademarked names, logos, signed dials, model names. Explicit no-list: Rolex crown, AP monogram, Patek cross, Lange wordmark, Casio wordmark, "Submariner," "Speedmaster," "Royal Oak," "Black Bay," "Lange 1," "F-91W," "AE-1200WH"
- **README requirements:** credit each inspiration inline per dial, non-affiliation disclaimer, design-notes link per dial
- **"Royale" easter-egg name** is the single defensible exception — owned with eyes open; if a C&D arrives, the easter egg gets renamed, not removed

## User Scenarios (for PRD)

- **Primary user: Caleb himself.** Installs the screensaver on his own Mac, uses it as his actual screensaver for ≥7 consecutive days. The 7-day stability test is *the* product success signal.
- **Secondary user: horology-curious GitHub visitor.** Finds the repo, judges in ~10 seconds on screenshots + credits clarity. Downloads the `.saver`, right-clicks → Open (Gatekeeper friction), picks a dial. Not the target audience — but the polish must not embarrass either party.

## Preferences Pane (for PRD)

- Dial picker with thumbnail previews
- **No** per-dial settings in v1 (e.g., no GMT timezone offset, no bezel rotation speed)
- Royale is reached via a **hidden gesture, not a visible entry in the picker** — mechanism TBD (open question)

## Open Questions (need answers during PRD or Architecture)

- **Royale hidden-gesture mechanism** — keystroke combo? Menu modifier? Specific corner click? Brief defers; PM/Architect should resolve.
- **Aged-tritium color-science approach** — single hex? Per-marker variation? Gradient? Color-science is a real design problem on the Diver, not a coding one. Candidate for a spike story.
- **`DialRenderer` protocol surface** — brief gives a sketch (`dimensions`, dirty-region, `draw(at:)`, prefs schema); Architect must turn it into a concrete contract.
- **macOS .saver bundle viability in 2026** — web research was denied during discovery; spec assumes `.saver` is still the right artifact, but no verified 2026 data. Worth a 30-min check before Architecture lands.
- **Quarantine-attribute behavior** — may exceed what right-click → Open resolves; README may need an `xattr -d com.apple.quarantine` workaround line.

## BMAD Practice Requirements (load-bearing for the primary purpose)

The brief's success criteria #6–#12 are **the primary deliverable**, not garnish. Downstream agents must honor:

- **Full agent loop ran intentionally** — Mary (Analyst, done) → John (PM, PRD next) → Winston (Architect) → SM (story creation) → Amelia (Dev) → QA. No stage gets skipped because "the spec covered it" or "it's a personal project."
- **≥1 spike story** before its dependent story — candidates: `ScreenSaverView` + multi-display Swift rendering pipeline, aged-tritium color science
- **One-paragraph retro per story** under `_bmad-output/retros/` — required, not optional
- **≥3 ADRs** under `_bmad-output/adrs/` — candidates: protocol shape, analog-vs-digital handling, no-tests posture, cut-order rationale
- **Vertical story slicing** — every story ships an end-to-end slice. No "all layouts first, all rendering second."
- **Planning docs updated when reality breaks an assumption** — if the cut order fires, brief + PRD get updated the same evening. Rotten planning docs are the silent BMAD anti-pattern.
- **End-of-project retrospective** — one document naming patterns that will transfer to the trading project. This is the actual deliverable of the primary purpose.

## Competitive / Landscape Context (low confidence)

Web research was **denied during discovery** — both `WebSearch` and `WebFetch` were unavailable. The following is memory-based hypothesis, not verified:

- Comparable OSS macOS screensavers: Aerial, Brooklyn, Padbury Clock, Fliqlo (some closed-source)
- Aerial's README is the reference for repo polish in this niche — hero GIF, install steps, Gatekeeper guidance, troubleshooting
- Mondaine has historically enforced its SBB clock design; community pattern is generic-naming + non-affiliation disclaimer
- Casio's enforcement posture on AE-1200WH homages: not verified in current data

**Recommendation:** before launch, re-run a web-research pass with WebSearch/WebFetch enabled to verify the OSS-screensaver landscape and current trademark-enforcement posture.

## Scope Boundaries (concise)

**In v1:**
- 6 dials, Swift renderers, `DialRenderer` protocol, prefs pane (dial picker only), multi-display + Retina correctness, NTP-via-system-clock, ad-hoc-signed `.saver`, GitHub Release, README with hero per dial

**Out of v1 / deferred:**
- Notarization, Apple Dev ID, live sub-dials, per-dial prefs, animated complications beyond what's needed for correctness, second easter egg, non-macOS targets, automated tests

## What's Locked vs. What's Negotiable

**Locked (do not reopen during PRD):**
- Dial lineup of 6
- Tech: Swift / SwiftUI
- Ad-hoc signing, no Apple Dev ID
- Project name: "Watches"
- "Royale" public name for the easter egg
- Practice > product when they conflict
- Cut order
- No automated tests in v1

**Negotiable (PRD / Architecture should refine):**
- `DialRenderer` protocol surface (Architect's job)
- Royale hidden-gesture mechanism
- Per-dial acceptance bar specifics
- Story slicing — concrete story list (SM's job, but the PM should set the shape)
