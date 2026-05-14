# Coke GMT — Design Notes

Coke GMT is the project's homage of the **Tudor Black Bay GMT (Coke
variant)**. Story 2.1 ships it. Architecturally: this dial is the **fourth
falsification test** for the `DialRenderer` protocol — the **parameter-
passing** stress test. The four hands derive from TWO different time
sources (local time + UTC) without any change to the protocol contract.

Inspired by the Tudor Black Bay GMT (Coke variant).

## Visibility

`.default` — Coke GMT is a main user-facing dial and appears in the prefs
picker normally.

## Source of truth

`design-spec.md` is the canonical source of truth for every visual decision
on this dial. It was produced up-front by the designer-agent pattern that
landed in Story 1.6's retro: rather than iterate from photo-to-code, the
designer agent reads the reference photo once and produces a comprehensive
spec that the implementer applies in one pass.

**Any future visual change to this dial should update `design-spec.md`
first, then implement against the diff.** Don't eyeball changes from the
reference photo — that path didn't converge on the Lange.

## Design decisions

### D1: Parameter-passing model

The four hands consume **two calendars** that both read from the same
injected `TimeSource`'s `Date`:

- `localCalendar = Calendar.autoupdatingCurrent` — for hour, minute,
  second hands.
- `CokeGMTMath.utcCalendar` — a pinned Gregorian calendar with
  `TimeZone(identifier: "UTC")`. Used by `gmtAngle(from:)` for the
  24-hour GMT hand.

**No protocol amendment.** `tick(reduceMotion:)` still takes only a
`Bool`. The renderer holds both calendars as properties. The math
functions are pure, taking the calendar as a parameter. This extends
AC8 outcome (a) from Story 1.6 to four confirmed stress dimensions
(digital paradigm, paradigm-mixing, non-concentric layout, multi-source
parameter passing).

### D2: GMT hand reads UTC (v1)

The GMT hand always points to UTC time on the 24h bezel. A future
follow-up could expose a `secondaryTimezone` preference via
`ScreenSaverDefaults` (Story 3.1's `DialPreferences` makes this
trivial); for v1 we hardcode UTC because:

- It's the convention for "GMT" watches.
- It's testable deterministically.
- The bezel can be mentally rotated by the user to read any other
  timezone offset from UTC.

If a future story adds a user-configurable secondary timezone, the
math function `CokeGMTMath.gmtAngle(from:)` would take an optional
TimeZone parameter; the rest of the renderer stays unchanged.

### D3: Trademark surface — omit entirely

**Decision.** No "TUDOR", no "GENEVE", no "GMT MASTER CHRONOMETER",
no "Swiss Made" on the rendered dial. Brand credit appears only in
`credit.txt` and `DialIdentity.homageCredit`.

**Why.** Matches the legal posture from Story 1.5 (Royale) and Story
1.6 (Asymmetric Moonphase). Brand name appears in credits, never on
the dial.

### D4: Cream tones unified, gold tones distinct

The dial has TWO color families for "applied" elements:

- **Cream lume family:** snowflake hands (hour + minute), hour markers
  (dots + bars + triangle), triangle pip on the bezel. All share
  `lumeCream` and `lumeCreamOutline`. Logic: these elements all
  represent applied luminous material.
- **Gold family:** seconds hand (`secondHandCream`), GMT hand
  (`gmtHandGold`), center hub, date frame. They form a hierarchy of
  warm yellow-gold tones, with the GMT hand the brightest. Logic:
  these represent polished metal (not lume).

Per designer-spec D3 judgment call. If the implementer wants the
snowflake hands in steel/silver instead (more typical "polished steel
snowflake"), swap `lumeCream` for a steel color in the hour/minute
hand fill only. The current cream-on-cream pairing matches Tudor's
modern Black Bay GMT photography.

### D5: Bicolor bezel split at 6/18 (3 and 9 o'clock visual)

**Decision.** Black covers the upper semicircle (24h positions 18 → 24
→ 6, i.e. 9 o'clock visual → 12 o'clock → 3 o'clock). Red covers the
lower semicircle. The split is at the 6 and 18 positions on the 24h
scale.

**Why.** This is the standard Coke colorway. The split allows GMT-hand
readability across both day/night halves (black for night hours 18–6
UTC, red for day hours 6–18 UTC).

### D6: 24h numerals upright, not radial

**Decision.** Each 24h numeral is rendered upright in the wearer's
frame (so "2" reads upright in the upper-right, "6" reads upright at 3
o'clock — NOT rotated 90°). Numerals at even hours only (2, 4, 6, 8,
10, 12, 14, 16, 18, 20, 22); odd hours marked with rectangular ticks;
24/00 is the triangle pip.

**Why.** Matches the Tudor reference. Radially-rotated numerals (each
glyph tilted to point outward) would be illegible. The upright
convention is standard on GMT bezels.

### D7: Procedural textures (dial grain + brushed steel)

**Decision.** Two procedural CGImage textures generated once at attach:

- `dialGrainImage` — 512×512, 4000 random 1×1 grayscale dots,
  applied at opacity 0.04 over the matte black dial.
- `brushedSteelImage` — 256×256, 2000 random 6×1 horizontally-
  elongated rectangles, applied at opacity 0.08 over the chamfer ring.

**Why.** Carries forward Pass E2's lesson from Asymmetric Moonphase
that photorealistic metal/matte surfaces NEED procedural texture to
break the flat-RGB look. The Lange used a single silver stipple at
0.07; Coke GMT uses lower-opacity grain (0.04) on the black dial
because dark surfaces show texture more readily.

### D8: Reduce-motion contract

- **Integer-second dedup** in `tick(reduceMotion:)`. Skip the whole
  tick if `floor(now.timeIntervalSince1970) == lastTickIntegerSecond`.
- **Seconds hand:** freezes at its current position. Hour, minute,
  GMT hands tick to position (no animation).
- **Date digit:** updates on day rollover only.
- **No ambient animations.** Unlike Asymmetric Moonphase, Coke GMT has
  no moonphase advance — the dial is fully static between ticks.

## Protocol-amendment assessment (AC8 from prior stories)

**Outcome (a): protocol survived parameter-passing stress. No amendment.**

The four-hand-from-two-time-sources work happens entirely inside the
renderer. `tick(reduceMotion: Bool)` still takes only the bool. The
host doesn't know there are two calendars in play. The dial author's
contract is unchanged from prior dials.

**This extends the AC8 finding to four stress dimensions:** digital
paradigm + paradigm-mixing + non-concentric layout + multi-source
parameter passing. Remaining Epic 2 dials (Octagon, Moonchrono,
Diver) are execution rather than architecture.

## Helper carry-over from Asymmetric Moonphase

**Used as-is:**
- `textPath(string:font:)` — for bezel numerals + date digit (with
  HelveticaNeue rather than serif).
- Drop-shadow + `shadowPath` pattern for raised gold/lume elements.
- `CATransaction.setDisableActions(true)` wrapping around per-tick
  layer writes.
- Procedural texture pattern (CGContext + arc4random dots) from the
  Lange faceplate stipple.

**Not used:**
- `serifFont(size:bold:)` — Tudor is sans-serif. Coke GMT defines its
  own `bezelFont(size:)` and `sansBoldFont(size:)` for HelveticaNeue.

**New helpers added (per design-spec Element 16):**
- `snowflakeHandPath(width:length:isMinute:)` — 16-vertex constructor
  for the Tudor snowflake silhouette.
- `gmtHandPath(width:length:)` — shaft + triangle arrowhead.
- `secondsNeedlePath(width:forwardLength:tailLength:)` — needle with
  short tail.
- `bezelHalfPath(center:outerR:innerR:startAngle:endAngle:clockwise:)`
  — annular half-ring constructor (likely useful for future bezel
  dials; could be hoisted into a shared helper file in Story 2.2+).
- `makeStippleImage(size:dotCount:dotSize:)` — generalized
  procedural-texture generator. Replaces the Lange's
  `makeFaceStippleImage()` with a parameterized version that handles
  both the dial grain (1×1 dots) and brushed steel (6×1 dots).

## Open follow-ups (deferred to Story 2.1.1 or later)

- **Chevron-notched GMT arrowhead.** Spec Element 11 offers a chevron
  refinement (notched back on the arrow). v1 ships with the plain
  triangle; chevron is a polish item.
- **User-configurable secondary timezone.** Per D2 above. The math
  function and `DialPreferences` would both need a small addition.
- **Bracelet/lugs/crown.** Spec explicitly omits per the
  "screensaver renders only the dial face" framing.
- **`applyLumeSpecular` helper.** Specced but NOT yet implemented in
  the renderer (the cream surfaces currently rely on drop-shadow +
  outline for dimensionality, no specular gradient). If Caleb wants
  the photoreal cream-on-matte-black to pop more, this is the first
  thing to add. Carries the design-spec's `lumeSpecularHi/Mid/Lo`
  palette entries.
- **Gold specular on GMT/seconds/hub/date-frame.** Likewise — the
  gold specular gradient is in the palette but not wired in v1. Add
  via the existing pattern from Asymmetric Moonphase if the gold
  reads too flat after smoke-testing.

## Test footprint

- `CokeGMTMathTests.swift` — 17 new tests covering:
  - `hourAngle` at noon + 3:00 + 3:30 (creep).
  - `minuteAngle` at 30 + 30:30 (creep).
  - `secondAngle` at 0 + 30.
  - `gmtAngle` at 0/6/12/18 UTC + 6:30 UTC + locality-independence.
  - `gmtMinusLocalHourAngle` at UTC, NY (UTC-5), Tokyo (UTC+9) —
    headline expression of Story 2.1's parameter-passing stress.
  - `dayOfMonth` extraction + timezone-respecting day rollover.
- Suite size: 69 → 86 (+17). Duration ~0.08s. Well under ADR-001's
  1-second budget.

UI elements (renderer drawing, picker integration) are NOT unit-tested
per the ADR-001 boundary.
