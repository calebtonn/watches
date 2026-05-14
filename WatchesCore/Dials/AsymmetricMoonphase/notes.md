# Asymmetric Moonphase — Design Notes

Asymmetric Moonphase is the project's homage of the A. Lange & Söhne Lange 1
Moonphase. Story 1.6 ships it. Architecturally: this dial is the **second
falsification test** for the `DialRenderer` protocol — the non-concentric
layout stress test. (Royale was the digital-paradigm stress test in Story 1.5.)

Inspired by the A. Lange & Söhne Lange 1 Moonphase.

## Visibility

`.default` — Asymmetric is one of the project's main user-facing dials and
appears in the prefs picker normally. Unlike Royale (`.hidden` easter egg),
this dial is the first thing a new user sees if they activate the screensaver.

## Design decisions

### D1: Round case + gold bezel + silver dial

**Decision.** Round watch case with a warm-gold bezel (vertical-tilt gradient
from highlight at upper-left → shadow at lower-right, matching Royale's
single-light-source convention), silver-champagne dial face, gold hands.

**Why.** Matches the reference photo's gold-case Lange 1 Moonphase variant.
Warm/luxurious feel. Distinct from Royale's silver chamfered-rectangle case.

**Rejected alternatives.** Platinum case + heat-blued hands (the platinum
Lange 1 variant exists), white-gold + dark dial. Caleb chose gold per
AskUserQuestion answer 2026-05-13.

### D2: Continuous angular moonphase

**Decision.** Moon disc translates laterally across the navy aperture based
on a continuous lunar phase fraction `[0, 1)`. Math anchored to a documented
new moon at 2000-01-06 18:14:00 UTC; synodic month = 29.530588868 days.

**Why.** Real watches show smooth phase transitions; a 28-frame discrete
sequence would visibly step once per day. Continuous math is also more
compact (no per-frame asset bundling).

**Rejected alternative.** 28-frame discrete sequence with pre-rendered moon
shapes. Simpler math but visibly stepped. Caleb chose continuous per
AskUserQuestion answer 2026-05-13.

### D3: Trademark surface — omit entirely

**Decision.** No `A. Lange & Söhne`, no `Glashütte I/SA`, no `Made in
Germany`, no `Gangreserve 72 Stunden` on the rendered dial. Brand credit
appears only in `credit.txt` and `DialIdentity.homageCredit`.

**Why.** Matches the legal posture established for Royale (Story 1.5 AC2).
Brand name appears in credits, never on the dial.

**Rejected alternative.** Include the German functional label
"GANGRESERVE 72 STUNDEN" as decorative text. Borderline — it's product-
feature text, not strictly brand, but reads as brand-adjacent. Caleb chose
the strict omit per AskUserQuestion answer 2026-05-13.

### D4: Power reserve tied to laptop battery

**Decision.** The power reserve indicator (`AUF` at upper-right, `AB` at
lower-right) reflects the laptop's current battery percentage. On desktop
Macs (no battery in the IOKit power-sources array), the indicator points
at `AUF` (full power). On any IOKit error, the indicator defaults to full.

**Why.** Per Caleb's "Other" answer to AskUserQuestion 2026-05-13. Maps
the watch's mechanical power-reserve indicator to a real-world Mac metric.
Practical and a small delight.

**Rejected alternatives.**
- Static always-full (simplest, but loses the "watch-keeps-track-of-power"
  storytelling).
- Decay simulation over 72 hours of screensaver runtime (complex; doesn't
  reset across `.saver` activations; meaningless on desktops).
- Tied to system uptime (quirky; would always point to AUF on freshly-booted
  Macs, AB after weeks of uptime — doesn't quite map to the watch metaphor).

### D5: Non-concentric anchor strategy

**Decision.** All five readouts (main time + moonphase + big date +
sub-seconds + power reserve) are placed at fixed canvas-relative anchors
expressed as fractions of the dial radius:

- Main time sub-dial center: `(caseCenter.x - 0.20·dialRadius, caseCenter.y)`
- Moonphase aperture: inside main time, `+0.40·mainTimeRadius` above its center
- Big date: `(+0.30·dialRadius, +0.42·dialRadius)` from case center
- Sub-seconds: `(+0.30·dialRadius, -0.40·dialRadius)` from case center
- Power reserve: `(+0.68·dialRadius, 0)` from case center

The anchors live in a `LayoutAnchors` struct that's recomputed on each
`canvasDidChange`. No reliance on the case center for sub-readout positioning.

**Why.** Lange 1's defining visual is asymmetry. Every readout occupies a
distinct region of the dial; nothing is concentric with the case. The
`DialRenderer` protocol's `canvas: CGSize` parameter is enough — sub-dials
position themselves relative to whatever fractional offsets the dial author
picks.

### D6: Roman numerals + Arabic sub-seconds

**Decision.** Main time sub-dial uses Roman numerals at 12/3/6/9 (XII, III,
VI, IX), with simple tick marks at the other 8 hour positions and 60 small
ticks for minutes. Sub-seconds dial uses Arabic numerals at 10/20/30/40/50/60
positions.

**Why.** Matches the reference photo. Roman numerals are part of the Lange 1
aesthetic. Arabic on the sub-seconds preserves at-a-glance readability for
the smaller dial where Roman would be hard to read.

**Rejected alternative.** Arabic numerals everywhere (more readable but
loses the formal aesthetic).

### D7: Reduce-motion contract

- Integer-second dedup: `tick(reduceMotion: true)` returns early when the
  integer second hasn't advanced.
- Hour + minute hands tick to position (no animation between minute boundaries;
  `CATransaction.setDisableActions(true)` is wrapped around all transform
  writes).
- Sub-seconds hand: FREEZES in reduce-motion (same pattern as Royale's
  outer-ring seconds tick).
- Moonphase: freezes at whatever lunar phase was current when reduce-motion
  engaged.
- Power reserve indicator: continues to follow battery state regardless
  (battery changes are not "ambient animation" — they're real-world events
  the user might want to see).

### D8: Battery query as a non-P4 side channel

**Decision.** The renderer is allowed to call `IOPSCopyPowerSourcesInfo()`
(via `AsymmetricMoonphaseMath.powerReserveFraction()`) directly. This does
NOT violate P4 (TimeSource injection) because battery state is not "time" —
it's a separate side channel.

**Why.** P4 exists to make time-driven content testable via `FixedTimeSource`.
Battery state has no equivalent testability concern — it's a one-shot read
of system state, with defensive fallback to `1.0` on any error per P10. The
function lives in the math file (not the renderer) so the responsibility is
clear; the renderer just asks "what value to show", not "how to query IOKit".

## Protocol-amendment assessment (AC8)

**Outcome (a): protocol survived the non-concentric layout stress test.
No amendment needed.**

The `DialRenderer` contract held cleanly across paradigm-mixing-WITHIN-a-dial
(Story 1.5.2) AND non-concentric-layout-OF-multiple-readouts (Story 1.6).
Per-method:

- **`attach(rootLayer:canvas:timeSource:)`** — fit cleanly. The `canvas:
  CGSize` parameter is geometric; sub-readouts position themselves relative
  to fractional offsets within that canvas. No protocol-level knowledge of
  "where the dial center is" is required.
- **`tick(reduceMotion: Bool) -> [CGRect]`** — fit cleanly. All five readouts
  update from the same tick. The dirty-rect return value scales naturally:
  Asymmetric returns 7 rects (vs Royale's 5), no contract change needed.
- **`canvasDidChange(to:)`** — fit cleanly. `layoutLayers` recomputes the
  `LayoutAnchors` struct + repaints; same shape as Royale.
- **`detach()`** — fit cleanly. Removing `caseBackgroundLayer.removeFromSuperlayer()`
  cascades.

**This extends the AC8 finding from Story 1.5 + 1.5.2 to three confirmed
stress cases:** digital paradigm + paradigm-mixing-within-a-dial +
non-concentric-layout-across-readouts. Epic 2's remaining four dials
(Coke GMT, Octagon, Moonchrono, Diver) are execution rather than architecture.

## Open follow-ups

- Hand styling — current pentagonal-tapered hands are recognizable but not
  as elegant as the real Lange's "lance" hands. Future polish.
- Big date boxes — could have more pronounced frames matching the real watch.
- Moonphase aperture shape — currently an ellipse; the real watch uses a
  slightly arched shape with a downward curve at the bottom.
- Sub-seconds dial ring — could have a thin gold border matching the main time dial.
