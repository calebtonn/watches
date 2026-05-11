---
title: "Product Brief: Watches"
status: "complete"
created: "2026-05-11"
updated: "2026-05-11"
inputs:
  - screensaver-project.html
  - faces/ (six reference images)
---

# Product Brief: Watches

## Executive Summary

**Watches** is a macOS screensaver that renders six high-fidelity homages to iconic mechanical watches — five analog faces plus a hidden digital easter egg — as a quiet, accurate, ambient clock on idle Macs. It is distributed only via GitHub, MIT-licensed, with no App Store path.

The project has two stacked purposes. The **primary** purpose is **practice**: a deliberate, contained on-ramp to fluency with the BMAD-METHOD agentic workflow before applying it to a higher-stakes trading system. The secondary purpose is **product**: ship a real, polished `.saver` bundle that a horology-curious macOS user would actually keep installed. The two purposes are not equal — when they pull against each other, *practice wins*. That choice shapes the rest of this brief: the cut order, the success criteria, even the dial lineup are biased toward what produces the strongest BMAD rehearsal, not what produces the fastest ship.

The honest envelope is **3–4 weeks of evenings**, not the 2 the original spec assumed. The dial set is more complex (six specific watches, including a non-concentric layout, a GMT, a chronograph, and a non-analog easter egg), Swift is being learned on the job, and the project is optimizing for learning rather than throughput. Faster is not the goal.

The point of this project is not the screensaver. The point is rehearsing the muscles — protocol shaping under heterogeneous implementers, pre-decided scope-cut discipline, agent rhythm, legal hygiene under aesthetic temptation — that the next project will demand at much higher stakes.

## What We're Building

A macOS `.saver` bundle implemented in native Swift / SwiftUI, containing six independent dial renderers behind a common `DialRenderer` protocol. The screensaver reads the macOS system clock (already NTP-synced by the OS), uses a monotonic time source so the render does not drift within an idle session across sleep/wake, renders the user's selected dial full-screen across all displays, and exposes a small Preferences pane to pick the active dial. Distribution is a single download from a GitHub Release; see *Signing & Install* below.

## Changes from the Original Spec

`screensaver-project.html` is preserved as a historical artifact. This brief supersedes it. Material changes:

- **Project name:** `swisswatches` → `Watches` (the Lange homage is German, not Swiss; the old name no longer fit).
- **Dial set:** the spec's five genre-named dials (Bahnhof, Geneva Octagon, Lunaris, Calatrava, Submersible) are **fully replaced** by six specific-watch homages (Asymmetric Moonphase, Diver, Moonchrono, Coke GMT, Octagon, Royale). The new set is more identifiable, more complex per dial, and now explicitly includes the easter egg.
- **Tech stack:** WebKit-hosted SVG → native Swift / SwiftUI. The plugin-swap escape hatch is no longer needed; the screensaver-sandbox × WKWebView × multi-display risk class is eliminated. Swift learning curve moves from v2 to v1.
- **Distribution:** no notarization, no Apple Developer ID expense. See *Signing & Install*.

## The Dial Set

Six homages, each named publicly with a neutral descriptor — never the brand name, never the model name.

| # | Internal name | Inspiration | Character |
|---|---|---|---|
| 1 | Asymmetric Moonphase | A. Lange & Söhne Lange 1 Moonphase | Off-center main dial, big date, moonphase, power-reserve indicator |
| 2 | Diver | Rolex Submariner ref. 16610, tritium era (~1989–1998) | Matte black dial, **aluminum** bezel insert, **aged tritium markers and hands rendered in a warm pumpkin-cream tone** (not modern white lume), mercedes hands, date with cyclops. The patina is part of the homage — a clean white-lume version would miss the point. |
| 3 | Moonchrono | Omega Speedmaster Moonwatch Professional | Three sub-dials, tachymeter bezel, baton indices |
| 4 | Coke GMT | Tudor Black Bay GMT | Snowflake hands, 24-hour GMT hand, red/black bicolor bezel |
| 5 | Octagon | Audemars Piguet Royal Oak | Blue tapisserie texture, octagonal bezel, integrated bracelet hint |
| 6 (easter egg) | Royale | Casio AE-1200WH | Digital LCD aesthetic, world-time map, multi-readout segments |

Five are analog; the sixth is digital. The Royale is reached through a hidden gesture rather than the visible dial selector.

## Who This Serves

**Primary user: me.** This is a planning artifact for a project I will build and use. Every design decision is downstream of "what will I learn from this, and will I leave the screensaver running on my own Mac."

**Secondary user: horology-curious macOS users** who find the repo, like the screenshots, and don't mind a one-time right-click → Open to install an un-notarized `.saver`. They are not the target — but the project's polish should not embarrass either of us.

## Success Criteria

v1 is done when **all** of the following are true.

**Product:**

1. An **ad-hoc-signed** (no Apple Developer ID) `.saver` is attached to a v1.0 GitHub Release. Users will right-click → Open on first install; the README will say so.
2. **Per-dial acceptance.** For each of the six dials: hands or readouts are at the correct positions for the current time; the layout matches the reference image in `faces/` on side-by-side eyeball at 1× zoom (legibility, proportion, color family — not pixel-perfect); the dial renders correctly at 1080p, at Retina 2×, and across two displays of different physical sizes. The per-dial `notes.md` records anything the renderer deliberately diverges from.
3. Time does not drift within an idle session across sleep/wake. The render reads the system clock once per draw and uses a monotonic source for animation continuity; no NTP layer of our own.
4. **README is a deliverable, not a footnote.** Required: a hero animated GIF or screenshot per dial, install instructions with a Gatekeeper screenshot (and the `xattr` workaround if needed), inspiration credited inline per dial, a clear non-affiliation disclaimer, and a "design notes" link to each `Dials/<name>/notes.md`.
5. I have personally run the screensaver as my actual macOS screensaver for **seven consecutive days** without changing the active dial more than twice. *(The "without uninstalling" framing was vanity; the dial-stability framing tests whether any individual dial is annoying enough to abandon, which is the real signal.)*

There are no analytics, no telemetry, no download targets, and no community-engagement goals.

**BMAD practice (this is the primary purpose and will be the harder bar to clear):**

6. **Ran the full agent loop intentionally.** A real PRD from John (PM), a real Architecture doc from Winston (Architect), per-story creation by the SM agent, implementation by Amelia (Dev), and at least one substantive QA pass that surfaces something real — not a rubber stamp. None of these stages got skipped because "the spec already covered it" or "it's a personal project."
7. **At least one explicit spike story** (e.g., a `ScreenSaverView` + multi-display Swift rendering spike, or the aged-tritium color-science spike) executed *before* its dependent story, with a written outcome.
8. **One-paragraph retro filed per story** under `_bmad-output/retros/`. What worked, what didn't, what shapes the next story. The retros are the artifact, not the vibe.
9. **At least 3 ADRs** (architecture decision records) for non-obvious decisions. Candidates: DialRenderer protocol shape, the analog-vs-digital handling, the cut-order trigger, the no-tests posture. Filed under `_bmad-output/adrs/`.
10. **Story slicing is vertical, not horizontal.** No "all layouts first, all rendering second" epic. Each story ships a working slice end-to-end.
11. **Planning docs are updated when reality breaks an assumption.** If the cut order fires, the brief and PRD get updated within the same evening. If the envelope slips, the brief gets updated. Rotten planning docs are the silent BMAD anti-pattern.
12. **End-of-project retrospective** — one document, written deliberately, that names the patterns that will transfer to the trading project. This is the actual deliverable of the BMAD primary purpose.

## Scope (the fence)

**In v1:**
- Six dials as listed, rendered in native Swift / SwiftUI inside a `ScreenSaverView`.
- A `DialRenderer` protocol that each dial implements; the screensaver host is dial-agnostic.
- Preferences pane: dial picker with thumbnail previews. No per-dial settings.
- System-clock-driven render path with a monotonic time source for animation continuity; clean exit on screensaver dismiss.
- Multi-monitor + Retina correctness.
- GitHub Release with ad-hoc-signed `.saver`, README, screenshots, MIT license.

**Out of v1, deferred to v1.1 or later:**
- Notarization and the Apple Developer ID expense.
- Live (functional) sub-dials on the Moonchrono — they are visually drawn in v1 but do not run.
- Per-dial preferences (e.g., GMT timezone offset for Coke, bezel rotation speed for Diver).
- Animated complications beyond what each dial requires to read correctly (Asymmetric's moonphase shows the right phase but does not animate the transition).
- Any second easter egg.
- Any non-macOS target.

**The cut order, if slipping — learning-optimized.** Because practice is the primary purpose, the cut order protects the dials that *stress the protocol* and cuts the conventional ones first. Cutting an abstraction-stressing dial would salvage the screensaver at the cost of the lesson, which inverts the project's purpose.

1. **First to cut:** **Diver.** The most conventional analog dial — black face, ring of indices, three hands, date window, a bezel that doesn't need to move in screensaver mode. Nothing it needs the protocol to do hasn't already been done for the other analog dials. Cutting it is aesthetic loss without protocol loss. *(The aged-tritium color work is interesting but does not stretch the abstraction.)*
2. **Second to cut:** **Octagon.** Mostly a texture-rendering exercise (tapisserie pattern, octagonal bezel). The protocol gains little from it that Asymmetric Moonphase doesn't already demand.
3. **Third to cut:** **Moonchrono.** The three sub-dials are decorative-only in v1 anyway; the tachymeter ring is rendering work but not protocol-stretching.

**Protected from cuts** (these earn the abstraction and are the reason the project is worth doing):
- **Asymmetric Moonphase** — forces the protocol to drop any concentric-circle assumption.
- **Coke GMT** — introduces a 4th hand (24-hour) and bicolor bezel rendering; tests parameter passing through the protocol.
- **Royale** — the digital paradigm is the protocol's stress test; if the abstraction survives the Royale, it survives anything.

The cut order is decided now, not in the moment, so future-me does not argue with present-me. No calendar trip-wire — the cut fires by judgment, not by deadline. The brief is the fence.

## Technical Approach

Native Swift / SwiftUI, `ScreenSaverView` subclass hosting whichever `DialRenderer` is currently selected. Each dial is a folder under `Dials/<name>/` containing its renderer, its preview asset, its homage credit text, and a `notes.md` capturing the design decisions made and rejected — the `notes.md` is part of the deliverable, not optional. The `DialRenderer` protocol exposes (sketch, not yet final): dimensions, dirty-region declaration, a `draw(at time: Date)` method, and a preferences schema (empty in v1).

**The protocol is not the same thing as a trading `Strategy` class.** A real `Strategy` has live inputs, state across ticks, side effects, risk constraints, and adversarial conditions; a `DialRenderer` is a near-pure function of `Date` to pixels. The transferable rehearsal is not the artifact, it is the *exercise of designing it*: deciding what belongs in the protocol vs. the caller, how to keep the contract stable when implementers are heterogeneous (the Royale digital case will stress this hardest), what a preferences schema looks like as data not code, and how to declare cost-of-rendering up front. That muscle transfers.

The decision to go native Swift in v1 (rather than the spec's original WebKit-hosted SVG path) eliminates an entire class of risk: screensaver-sandbox × WKWebView × multi-display GPU-power interactions that have historically bitten community projects in this niche. The cost is a Swift learning curve carried in v1 instead of v2 — this is the single largest schedule variable in the project.

## Testing Posture

**No automated tests in v1.** Visual correctness is verified by eyeball against the reference images in `faces/` and by the personal-use criterion in *Success Criteria*. This is a decision, not an omission — the cost of building a snapshot-test harness for `ScreenSaverView` rendering against reference patinas exceeds the value at this scope. If a regression hurts later, the lesson is: when do automated tests start to pay for themselves. That lesson is itself BMAD-transferable.

## Legal Posture

Homages of **design vocabulary** only. Allowed: case silhouettes, bezel motifs, dial textures, hand styles, color palettes, indices arrangements, complications layouts. Forbidden: trademarked names, logos, signed dials, model names, distinctive trademarked elements (the Rolex crown, the AP "AP" monogram, the Patek cross, the Lange wordmark, the Casio wordmark, "Submariner," "Speedmaster," "Royal Oak," "Black Bay," "Lange 1," "F-91W," "AE-1200WH").

The README will credit each inspiration explicitly and include a non-affiliation disclaimer. The project name is **Watches**, not a brand-adjacent pun. The public dial names are descriptive, not brand-adjacent. The single exception is "Royale" for the easter egg — defensible because it is the established watch-community nickname for the Casio AE-1200WH, but flagged here so the decision is owned.

## Risks & Open Questions

- **Swift learning curve is the single largest schedule variable.** This is the first non-trivial Swift / SwiftUI project. The 3–4-week envelope is a guess; the variance is wide. A pre-emptive `ScreenSaverView` spike story is on the success-criteria checklist for exactly this reason.
- **The cut order has no trip-wire — it fires by judgment.** Deliberate: this project is optimizing for learning, not for hitting a calendar. The risk that comes with that choice is rationalization at 11pm. The mitigation is that the cut order is written, named, and ordered now — and the per-story retros are the place where slippage becomes visible.
- **The "drawn but static" Moonchrono sub-dials save less time than they look like they do.** Drawing three sub-dials at correct positions and proportions is most of the rendering cost of making them tick. Deferring the *animation* to v1.1 is honest; deferring the *layout work* is not, and the layout work has to land in v1.
- **No notarization means real install friction.** A first-time user must right-click → Open and may face a "cannot be opened because the developer cannot be verified" message that is more aggressive on recent macOS versions than on older ones. The README must spell this out with a screenshot. Quarantine-attribute behavior may exceed what right-click → Open can resolve; if so, the README will need a `xattr -d com.apple.quarantine` workaround line.
- **The Royale is a different rendering paradigm.** LCD-segment text and a small world map are nothing like analog hand sweeps. This is the strongest stress test of the `DialRenderer` abstraction — which is good pedagogically and risky for delivery.
- **Asymmetric Moonphase's off-center layout breaks the implicit "concentric circle" assumption** that every other analog dial shares. The `DialRenderer` protocol must not bake that assumption in. This is a real design constraint, not a hypothetical one.
- **The Diver's "pumpkin patina" target is a color-science problem, not a coding problem.** Aged tritium does not have a single hex value — it shifts across the dial in real watches. Getting it wrong reads as "wrong watch."
- **"Royale" is owned with eyes open.** It is the established watch-community nickname for the AE-1200WH and points back to the homaged object, not the Bond film franchise. If a cease-and-desist arrives, the easter egg gets renamed, not removed.

## Vision

This is not a forever-project. v1 ships — possibly with one or two of the *conventional* dials (Diver, Octagon, Moonchrono) deferred to v1.1 per the cut order. The protocol-stressing dials stay in v1 because they are the reason the project exists. Then the lessons are carried forward into the trading system, which is the actual destination.

**Transferable lessons being rehearsed here, explicitly named so the post-project retro has a template:**

- **Protocol shaping under heterogeneous implementers** — the Royale (digital) will fight the protocol the analog dials happily satisfy. Whichever way that conflict resolves is the lesson for the trading `Strategy` protocol.
- **Scope-cut discipline pre-decided, not in-the-moment** — the cut order in this brief is the artifact. If it fires when it should, the muscle worked. If it doesn't, that's the diagnostic.
- **Legal hygiene under aesthetic temptation** — the dial names, the README disclaimer, the Royale call — each was a chance to drift, and the record will show whether discipline held.
- **Agent rhythm at low stakes** — Analyst → PM → Architect → SM → Dev → QA in a small loop, before the trading project where the same loop has to handle live market data and real money.
- **When automated tests start to pay for themselves** — by deliberately *not* writing tests in v1, the project produces the data point.

If v1 lands and someone in the watch community notices and forks the repo, that is gravy. The goal is the muscle, not the audience.
