# Coke GMT — Design Spec

Implementation-grade design specification for the Tudor Black Bay GMT
(Coke variant) homage dial. Every value below is intended to become code
in a single implementation pass.

**Coordinate convention:** Core Animation y-up. Positions expressed as
`(caseCenter.x + dialRadius * X, caseCenter.y + dialRadius * Y)`. Signs:
`+x` is right, `+y` is up. All lengths use `dialRadius` as the unit (NOT
`caseRadius`).

**Light source (global):** single soft area-light at the **upper-left,
approximately 45°** above the dial plane. Every drop shadow points
**lower-right** (positive shadowOffset.width, negative shadowOffset.height).
Every specular highlight sits at the **upper-left** of its element. The
ceramic bezel sheen also peaks at upper-left but is BROADER and SOFTER
than the polished-metal sheen on the case.

**Faceplate finish:** the dial is **matte black with very fine grain** —
NOT polished, NOT sunburst. No specular highlight on the dial face. The
ceramic bezel insert is **semi-gloss** (less reflective than metal but
more than the dial — a soft sheen). The steel case is **polished +
brushed** (mirror-bright at the bezel rim and chamfer, brushed-radial on
the case top). The bracelet is OUT of scope: render the case as a single
disc, no lugs, no straps.

**Photorealism stack (carried over from Asymmetric Moonphase):** five
overlay passes stack on every applied element. Three of them carry over
cleanly:

1. **Faceplate grain** (Element 18 below) — replaces the silver stipple
   with a dark-grain noise overlay at lower alpha. The matte black dial
   needs LESS texture than the matte silver Lange — too much grain reads
   as dust.
2. **Specular highlight gradients** (Element 19) — but with THREE families
   instead of one: a **gold** family for the GMT hand and date frame
   (reuse `applyGoldSpecular`), a **cream-lume** family for the snowflake
   hands and the lume markers (new helper `applyLumeSpecular`), and a
   **steel** family for the case (new helper `applyCasePolishing`).
3. **Ceramic sheen** (Element 20) — a NEW helper specifically for the
   bezel insert: a broad soft diagonal highlight, NOT the sharp specular
   stripe used on metal. Implementation: a single radial CAGradientLayer
   centered at the upper-left of the bezel annulus, low alpha,
   masked to the bezel ring.

**Layout intent:** the Coke GMT is **concentric and symmetric** — unlike
the asymmetric Lange. The dial center, case center, and bezel center
coincide. The only off-center elements are the date window (3 o'clock)
and the four hands when rotated. Hour markers sit on a single circle.
The bezel insert is a flat annulus. This is a much simpler layout than
Asymmetric Moonphase, so the spec's emphasis shifts toward MATERIAL
QUALITY (the bicolor bezel, the cream lume, the snowflake silhouette)
rather than layout geometry.

---

## Notes on Pass 2 (2026-05-14)

Pass-1 shipped structurally complete. Caleb reviewed
`snapshots/cokeGMT.png` against `faces/tudor-m7939g1a0nru-0003.jpg` and
flagged three explicit issues plus requested a full photorealism re-pass.
The renderer is unchanged; this document is the contract for the diff.

**Three explicit fixes (must land):**

1. **Bezel orientation rotated 90° (Element 2).** Pass-1's spec used the
   wrong angle convention — `-π/2` was annotated as "3 o'clock" when
   in Core Animation y-up it's actually 6 o'clock visual. The renderer
   faithfully implemented the wrong spec, so the snapshot shows BLACK
   on the right half / RED on the left half. Caleb wants **black on
   TOP, red on BOTTOM** (which matches the Tudor reference and the 24h
   scale: "6" sits at 3 o'clock visual = angle `0`, "18" at 9 o'clock
   visual = angle `π`, so the split is the HORIZONTAL diameter). Element
   2 below is fully rewritten with the corrected geometry; the spec
   angle convention is now stated up-front.

2. **Date placeholder flash (Element 13).** The renderer initializes
   with `updateDateDigit(day: 0)` which clamps to "1" via
   `max(1, min(31, 0))`, then the first real tick overwrites it. If
   the screensaver host captures a frame before that first tick, the
   user sees "1" instead of today's date. Element 13 now specifies:
   **initialize the digit to today's day at `attach()` time** via a
   one-time `Date()` read. This is install-time visual only — not a
   P4 "time drives render" violation, because the placeholder is
   overwritten by the next real `tick()` and time-driving correctness
   is unchanged.

3. **Snowflake at the END of the hands (Elements 8, 9).** Pass-1's hour
   hand had the lozenge running 45→85% of length with a 15% tip cap
   (88→100%). The Tudor reference clearly shows a SMALL pointed cap
   past the snowflake — reading (a) from the prompt, not (b). Pass-2
   moves the lozenge outward and shortens the cap:
   - Hour hand: lozenge `0.60 → 0.90`, tip cap `0.93 → 1.00` (cap = 7%
     of length, was 12%).
   - Minute hand: lozenge `0.74 → 0.93`, tip cap `0.95 → 1.00` (cap =
     5% of length, was 10%).

**Additional findings from photorealism re-pass:**

- **Ceramic sheen is too narrow.** Element 21's radial gradient is
  positioned at `(0.25, 0.80) → (0.85, 0.20)` which produces a soft
  upper-left glow only — the snapshot shows the bezel reading slightly
  flat. The reference shows a broader curved highlight tracing the
  upper-left third of the bezel arc. Element 22 (new) adds a SECOND
  sheen layer — a stroked arc on the bezel centerline — to give the
  ceramic a clear "rounded surface" cue. Keeps Element 21 as the soft
  area-light bloom; adds a more directional arc highlight on top.
- **GMT hand too thin to read (Element 11).** The arrowhead width
  multiplier was `width * 2.4` (full width = 4.8 × shaft = 0.106 ×
  dialRadius). Reference shows a clearly readable arrowhead at this
  resolution. Pass-2 widens the shaft to `dialRadius * 0.028` and the
  arrowhead to `width * 3.0` (full arrowhead = 0.168 × dialRadius,
  ~60% larger area).
- **Seconds hand tip lume dot now MANDATORY (Element 10).** Pass-1
  marked it "optional" — the rendered seconds hand is thin enough that
  the tip is hard to track. The reference shows it clearly. Pass-2
  promotes it to required.
- **6/9 bar markers slightly too narrow (Element 6b).** Width was
  `dialRadius * 0.045`. Reference bars read chunkier — pass-2 widens
  to `dialRadius * 0.055`.
- **Specular highlights now wired (Elements 19, 20).** Pass-1 specced
  `applyLumeSpecular` and `applyGoldSpecular` but the renderer shipped
  without them. The flat appearance of the cream snowflakes and gold
  GMT hand in the snapshot is the biggest "rendered, not photographed"
  tell. Pass-2 marks specular application as **required** on hands,
  markers, date frame, GMT hand, seconds hand, and center hub.
- **Lower-right case shadow deepening (Element 1).** Reference shows
  significant shadow on the lower-right rim of the case. Pass-1's case
  gradient already has this in the color stops; recommend tightening
  `caseSteelShadow` to `(0.34, 0.35, 0.38, 1.0)` for more contrast.

**What's NOT changing in Pass 2:**

- Hour markers (dots, triangle at 12) — proportions read correct.
- Date window proportions and digit weight — read correct.
- Minute track — read correct.
- Color palette except the case-shadow tightening above.
- 24h numeral placement and font.
- Hand rotation math and `tick()` contract.
- Helpers (`textPath`, `bezelHalfPath`) and renderer structure.

---

## Element 1 — Case (stainless steel disc)

The Tudor Black Bay case is a **polished + brushed stainless steel disc**.
Bracelet, lugs, crown, and crown guard are OUT of scope (the canvas
renders only the dial face — the bracelet attachment is implied off-frame).
The case reads as a single shallow cylinder with a polished outer rim and
a brushed top face, capped by the bezel insert.

- **Outer radius:** `caseRadius = min(canvas.width, canvas.height) * 0.425`
  (case diameter = 85% of the smaller canvas dimension; same as the Lange
  homage so the screensaver feels consistent across dials).
- **Bezel boundary (inner edge of the bezel insert annulus):**
  `bezelInnerRadius = caseRadius * 0.82`. The annulus from
  `caseRadius * 0.88` to `caseRadius * 0.99` is the bezel insert (Element
  2). The annulus from `caseRadius * 0.99` to `caseRadius * 1.00` is the
  polished steel rim of the bezel. The annulus from `bezelInnerRadius`
  to `caseRadius * 0.88` is the polished steel **chamfer** between the
  bezel insert and the dial face.
- **Dial boundary:** `dialRadius = caseRadius * 0.80`. The chamfer
  (annulus from `dialRadius` to `bezelInnerRadius`, i.e. radii 0.80 to
  0.82) is the polished bevel ring connecting the brushed case top to
  the matte dial.
- **Case top fill — `CAGradientLayer` (linear, masked to the full case
  disc):**
  - Direction: `startPoint = (0.30, 1.00)`, `endPoint = (0.70, 0.00)` —
    nearly vertical, tilted toward upper-left.
  - Colors + locations:
    - `0.00` → `caseSteelHighlight = (0.96, 0.96, 0.97, 1.0)` — bright
      brushed-steel highlight near the top edge of the case.
    - `0.45` → `caseSteel = (0.78, 0.79, 0.82, 1.0)` — mid steel tone.
    - `1.00` → `caseSteelShadow = (0.34, 0.35, 0.38, 1.0)` — deep
      shadow at the bottom of the case. *(updated Pass 2 — Pass-1
      value `(0.42, 0.43, 0.46)` left the lower-right of the case
      reading flat against the reference; darkening by ~8% adds the
      curved-body shadow the reference shows.)*
  - This case-top gradient only shows in the chamfer ring (radii 0.80
    → 0.88) and the polished bezel rim (radii 0.99 → 1.00) — the
    bezel insert fully covers the annulus between them.
- **Brushed-radial texture overlay (NEW helper `caseBrushOverlay`):** the
  reference shows distinct horizontal brush lines on the steel. Implement
  as a procedural noise CGImage (256×256, generated once, see Element 18)
  but with the noise ELONGATED horizontally — sample dots as 6×1 pixel
  rectangles instead of 1×1. Apply at `opacity = 0.08` over the case top
  gradient. Mask to the chamfer ring (radii 0.80 → 0.88) ONLY — the
  bezel insert is ceramic and gets its own treatment in Element 2.
- **Polished bezel rim (outermost steel rim, radii 0.99 → 1.00):** a
  `CAShapeLayer` stroking a circle at `radius = caseRadius * 0.995`,
  `lineWidth = max(1.0, caseRadius * 0.012)`, `strokeColor =
  caseSteelHighlight`. This is the bright chrome ring that catches the
  studio light around the bezel. Add a SHORT arc highlight at the
  upper-left (see Element 1b below).
- **Polished chamfer ring (radii 0.80 → 0.82, connecting case-top to
  dial face):** a `CAShapeLayer` stroking a circle at `radius =
  caseRadius * 0.81`, `lineWidth = max(1.0, caseRadius * 0.015)`,
  `strokeColor = caseSteelHighlight`. Apply a vertical gradient (linear,
  startPoint top, endPoint bottom, colors `[caseSteelHighlight,
  caseSteel]`) by masking. This chamfer is what makes the bezel insert
  look "set into" the case rather than painted on. Add a SHORT arc
  highlight at the upper-left (Element 1b).
- **Inner edge stroke (where chamfer meets dial face):** a thin dark
  stroke at `radius = dialRadius`, `lineWidth = max(0.4, caseRadius *
  0.004)`, `strokeColor = (0.20, 0.20, 0.22, 0.70)`. This is the recess
  shadow at the bottom of the chamfer well.

### Element 1b — Case-top arc highlights (upper-left glints)

These are the bright slivers where the rounded steel edges catch the
upper-left key light. Two of them.

- **Outer bezel rim glint:**
  - `CAShapeLayer`, path = arc on circle radius `caseRadius * 0.997`
    from angle `120°` to `60°` (CCW from +x — upper-left to top-center).
  - `lineWidth = max(1.2, caseRadius * 0.014)`
  - `strokeColor = (1.00, 1.00, 1.00, 0.85)`
  - `lineCap = .round`
- **Chamfer glint:**
  - `CAShapeLayer`, path = arc on circle radius `caseRadius * 0.815`
    from angle `135°` to `75°`.
  - `lineWidth = max(0.8, caseRadius * 0.010)`
  - `strokeColor = (1.00, 1.00, 1.00, 0.65)`
  - `lineCap = .round`

**Z-order:** background → case-top gradient (chamfer + rim) → brushed
overlay → bezel insert (Element 2) → polished chamfer ring → outer bezel
rim → outer rim glint → chamfer glint → inner edge stroke → dial face.

---

## Element 2 — Bicolor ceramic bezel insert (THE signature element) *(updated Pass 2 — corrected angle convention; black goes on TOP, red on BOTTOM)*

The bezel insert is a flat ceramic annulus in two halves: **black on the
upper half (over the top of the dial, covering hours 18 → 24 → 6 on a 24h
scale)** and **red on the lower half (covering hours 6 → 12 → 18 going
under)**. The Coke colorway names the watch.

**Angle convention (canonical reference for this entire spec):** Core
Animation y-up. With angles measured CCW from the positive x axis:

- `0` = **3 o'clock visual** (positive x axis) — "6" on the 24h scale.
- `+π/2` = **12 o'clock visual** (positive y axis) — "24/00" pip.
- `π` = **9 o'clock visual** (negative x axis) — "18" on the 24h scale.
- `-π/2` = **6 o'clock visual** (negative y axis) — "12" on the 24h scale.

Pass-1's text mis-labeled `-π/2` as 3 o'clock; that was wrong and is now
corrected. The bezel split happens on the **HORIZONTAL diameter**: "6"
at angle `0` (right) and "18" at angle `π` (left). The black half is the
upper semicircle (between those split points, sweeping over the top); the
red half is the lower semicircle (sweeping under).

**Black-half arc geometry:** sweep CCW from `0` to `π` — that's from 3
o'clock visual, up through 12 o'clock visual, to 9 o'clock visual. Upper
semicircle.

**Red-half arc geometry:** sweep CW from `0` to `π` — that's from 3
o'clock visual, down through 6 o'clock visual, to 9 o'clock visual. Lower
semicircle. (Equivalently: CCW from `π` to `0` would also describe the
lower path going right-to-left; the implementation should match
`bezelHalfPath`'s argument order — see below.)

**Annulus geometry:**

- **Outer radius:** `bezelOuterR = caseRadius * 0.99` (just inside the
  polished rim).
- **Inner radius:** `bezelInnerR = caseRadius * 0.88` (just outside the
  chamfer ring).
- **Radial thickness:** ≈ 11% of caseRadius. This is wide enough to
  hold the 24h numerals comfortably.

**Each half is a `CAShapeLayer` built with a CCW-swept arc ring path.**
The existing `bezelHalfPath(center:outerR:innerR:startAngle:endAngle:clockwise:)`
helper signature is unchanged. Calls become:

```swift
// Black half — upper semicircle
let blackHalfPath = bezelHalfPath(
    center: caseCenter, outerR: bezelOuterR, innerR: bezelInnerR,
    startAngle: 0, endAngle: .pi, clockwise: false  // CCW: 3 → 12 → 9
)

// Red half — lower semicircle
let redHalfPath = bezelHalfPath(
    center: caseCenter, outerR: bezelOuterR, innerR: bezelInnerR,
    startAngle: 0, endAngle: .pi, clockwise: true   // CW: 3 → 6 → 9
)
```

The two halves share the same start/end angles; only `clockwise:` flips.
This is the corrected geometry — verify in code that swapping these
booleans is the entire bezel fix (no other angles in Element 2 need
change).

**Black-half fill — `CAGradientLayer` masked to the black-half shape:**
- Type: `.axial`
- `startPoint = (0.30, 1.00)`, `endPoint = (0.70, 0.00)` — vertical with
  upper-left bias.
- Colors / locations:
  - `0.00` → `bezelBlackHighlight = (0.30, 0.30, 0.32, 1.0)` — the
    catch-light at the top of the ceramic where light hits the upper rim.
    Ceramic doesn't go bright — even the highlight stays dark grey.
  - `0.40` → `bezelBlack = (0.08, 0.08, 0.09, 1.0)` — the base ceramic
    black, NOT pure black; ceramic has a slight blue-grey undertone.
  - `1.00` → `bezelBlackShadow = (0.02, 0.02, 0.03, 1.0)` — deepest
    shadow at the lower edge of the black half.

**Red-half fill — `CAGradientLayer` masked to the red-half shape:**
- Type: `.axial`
- `startPoint = (0.30, 1.00)`, `endPoint = (0.70, 0.00)` — same direction
  so both halves are lit consistently from the upper-left.
- Colors / locations:
  - `0.00` → `bezelRedHighlight = (0.86, 0.20, 0.18, 1.0)` — the red
    ceramic catches a slightly brighter, less saturated red where light
    hits it. The reference's red is a warm-leaning crimson, not orange,
    not blood.
  - `0.45` → `bezelRed = (0.62, 0.10, 0.10, 1.0)` — base ceramic red.
    Deeper and slightly darker than people remember — the reference is
    a *brick* red on the upper-lit portion and goes quite dark on the
    lower rim. (Photo-burn effects from saturated reds make many homages
    over-saturate this color; resist that.)
  - `1.00` → `bezelRedShadow = (0.36, 0.05, 0.05, 1.0)` — deep maroon
    shadow at the bottom of the red half.

**Top-edge highlight band on the bezel (NEW — the "ceramic sheen"):**

In the reference photo, the rounded top edge of the bezel where the
ceramic meets the polished steel rim has a clear broad highlight band on
the upper-left quadrant. This is what makes ceramic read as ceramic and
not as paint.

- A `CAShapeLayer` stroking a circle at radius `bezelOuterR -
  caseRadius * 0.005` (just inside the outer edge of the bezel
  insert).
- `lineWidth = max(1.0, caseRadius * 0.014)` — broad.
- `strokeColor = (1.00, 1.00, 1.00, 0.25)` — soft white, semi-transparent;
  ceramic sheen is BROAD and SOFT, unlike the sharp chromium of polished
  steel.
- Mask: only render on the upper-left quadrant of the bezel. Use a
  second `CAShapeLayer` mask that's a wedge from angle `60°` to `170°`
  (CCW) — the broad top-and-left sweep. Implementation: as a fan path
  (`moveTo(center)`, `addArc(...)`, `closeSubpath()`).
- `lineCap = .round` — fades softly at the ends of the sweep.

**Inner-edge dark groove on the bezel (defines the inner boundary):**

- `CAShapeLayer` stroking a circle at `bezelInnerR`, `lineWidth =
  max(0.4, caseRadius * 0.003)`, `strokeColor = (0.0, 0.0, 0.0, 0.60)`.
- This is the engraved-channel feel where the ceramic insert sits on
  top of the steel chamfer.

**Z-order within the bezel insert region:** black half → red half →
ceramic sheen highlight band → inner-edge groove → 24h numerals
(Element 3) → triangle pip (Element 4).

---

## Element 3 — 24-hour bezel numerals + tick marks

The Coke GMT bezel has cream/aged-luminous **numerals at even positions
(2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22)** and **tick marks (small
rectangles) at odd positions (1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21,
23)**. The 24/00 position carries a **triangle pip** (Element 4) instead
of a "24" numeral.

**Important reference detail:** the cream tone of the numerals matches
the cream of the hour-marker lume and the cream of the GMT hand. They
are all the same aged-luminous color, NOT yellow gold. Tudor uses a
slightly orange-tinted off-white that looks like vintage Tritium lume.

**Numeral positions and orientation:**

24h scale, with `numeralAngle(h) = π/2 - (h/24) * 2π` for the math
convention (CCW positive, 0 at top). The position "0" = top,
proceeding clockwise visually: `2` is at the upper-right, `6` at 3
o'clock, `12` at the bottom, `18` at 9 o'clock, etc.

- 24 (top, replaced by triangle pip, see Element 4)
- 2 → angle `π/2 - 2π/12 = π/2 - π/6 = π/3` (≈ 60°)
- 4 → `π/2 - π/3 = π/6` (≈ 30°)
- 6 → `0` (3 o'clock position) — note this also marks the **split point
  between the black bezel half (above) and red half (below)**
- 8 → `-π/6`
- 10 → `-π/3`
- 12 → `-π/2` (bottom, 6 o'clock visual position)
- 14 → `-2π/3`
- 16 → `-5π/6`
- 18 → `π` (9 o'clock position) — also the **split point**
- 20 → `5π/6`
- 22 → `2π/3`

**Glyph rendering:**

- **Font:** `NSFont(name: "HelveticaNeue-Bold", size: ...)` — Tudor uses
  a clean sans-serif on the bezel, not a serif. Fall back to system bold
  sans-serif. Numerals on the reference are slightly compressed
  horizontally — if compressed variant is available
  (`HelveticaNeue-CondensedBold`), prefer it; otherwise plain Bold is fine.
- **Size:** `caseRadius * 0.060`. Larger than initially feels right —
  the reference numerals fill ~50% of the radial thickness of the
  bezel insert.
- **Color:** `bezelNumeralCream = (0.93, 0.86, 0.66, 1.0)` — the warm
  off-white aged-lume tone.
- **Radial center:** `numeralR = (bezelOuterR + bezelInnerR) / 2 =
  caseRadius * 0.935` (i.e. dead center of the bezel insert annulus).
- **Glyph anchoring:** each numeral's combined bounding box `(midX,
  midY)` lands on the radial position. The glyphs themselves remain
  **upright** (NOT rotated radially) — the reference shows the numerals
  reading from the same baseline orientation as a clock face: "2" is
  upright at upper-right, "6" is upright at 3 o'clock (NOT rotated 90°),
  "12" is upright at the bottom, etc. This is the standard GMT-bezel
  convention: numerals are upright in the wearer's frame, not radial.
- **No drop shadow** on numerals — they read as printed/painted onto
  the ceramic, not raised. The slight cream-cream variation in the
  reference is achieved with a **very subtle inner stroke** at
  `strokeColor = (0.78, 0.65, 0.40, 0.4)`, `lineWidth = 0.4` — gives
  the impression of aged paint edge without lifting the glyph.

**Merged numeral layer:** combine all 11 visible numerals (2, 4, 6, 8,
10, 12, 14, 16, 18, 20, 22) into a single `CAShapeLayer` with one
combined `CGPath`. This matches the Asymmetric Moonphase Roman numeral
pattern and lets you apply a single specular pass if desired (do NOT
apply gold specular here — these are cream lume, not gold).

**Tick marks at odd hours (1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23):**

- **Shape:** small rectangle, radial-aligned. In bezel-local coords (axis
  aligned along radial direction):
  - Length (radial): `caseRadius * 0.022`
  - Width (perpendicular): `caseRadius * 0.005`
- **Radial center:** `tickR = caseRadius * 0.935` — same as numeral
  radius (the ticks sit on the same circle as the numeral centers, but
  are radially oriented).
- **Color:** `bezelNumeralCream` — same cream as the numerals.
- **No stroke, no shadow** — printed.
- **Rotation:** each tick's long axis points radially outward from the
  case center.

**Z-order within bezel:** halves → ceramic sheen → inner groove →
**tick marks → numerals → triangle pip**. Numerals on top of ticks (so
if any overlap the ticks read as background).

---

## Element 4 — Triangle pip at 24/00 (top of the bezel)

A small inverted triangle (pointing INWARD, toward the dial center) sits
at the top of the bezel, marking 24/00 on the 24h scale. The triangle is
filled with **lume cream** with a thin **gold/cream outline** that reads
as the warm border between the painted lume and the surrounding ceramic.

**Geometry (in canvas coords, isosceles inverted triangle):**

- **Tip vertex (innermost point, on dial side):** at radius
  `bezelInnerR + caseRadius * 0.008` on the angle `π/2` (top of dial).
- **Base midpoint:** at radius `bezelInnerR + caseRadius * 0.038` on the
  same angle (so the triangle is `caseRadius * 0.030` tall in the radial
  direction, with its tip pointing toward the dial center).
- **Base half-width:** `caseRadius * 0.022` (perpendicular to the radial
  axis). So the triangle has base 2 × half-width = 0.044 radians of
  arc-ish width (treated as a flat chord).
- **Triangle vertices in canvas coords** (for an axis where `+v_radial`
  points outward, `+v_perp` points clockwise — i.e. to the right when
  viewed from above):
  1. Tip: `caseCenter + (0, bezelInnerR + 0.008 * caseRadius)`
  2. Base-right: `caseCenter + (+0.022 * caseRadius, bezelInnerR + 0.038
     * caseRadius)`
  3. Base-left:  `caseCenter + (-0.022 * caseRadius, bezelInnerR + 0.038
     * caseRadius)`

**Fill:** `lumeCream = (0.95, 0.88, 0.68, 1.0)` — slightly brighter than
the bezel numeral cream because lume reflects more light than printed
cream.

**Outline stroke:** `strokeColor = (0.76, 0.62, 0.36, 0.95)` — a warm
cream-gold edging, `lineWidth = max(0.6, caseRadius * 0.0035)`. This
outline is the SIGNATURE detail of the GMT pip — it makes the pip read
as a discrete lume cap, not a painted triangle.

**Drop shadow (raised feel, the pip is physically applied to the bezel
surface):**

- `shadowColor = .black`
- `shadowOffset = (0.6, -0.6)`
- `shadowOpacity = 0.45`
- `shadowRadius = 1.0`
- `shadowPath = the triangle path`

**Z-order:** sits above all bezel numerals and ticks (top of the bezel
stack).

---

## Element 5 — Dial faceplate (matte black with fine grain)

The dial face is **matte black**, almost flat in the reference — a slight
warm-grey-black with very fine grain texture (so subtle it could be
described as the cleanest sandblasted finish you've ever seen). No
specular highlight; no sunburst.

- **Shape:** filled circle, radius = `dialRadius`, centered at
  `caseCenter`.
- **Base color:** `dialBlack = (0.045, 0.045, 0.050, 1.0)` — very dark
  with a hint of blue-grey, not pure black (pure black would look dead).
- **Vignette overlay:** a `CAGradientLayer` of type `.radial` masked to
  the dial circle.
  - `startPoint = (0.45, 0.55)`, `endPoint = (1.05, 1.05)` — centered
    slightly upper-left (toward the light source).
  - Colors:
    - `0.00` → `(1.0, 1.0, 1.0, 0.04)` — barely brighter near the light.
    - `0.70` → `(1.0, 1.0, 1.0, 0.00)` — neutral.
    - `1.00` → `(0.0, 0.0, 0.0, 0.22)` — perimeter darkening at the
      chamfer transition.
- **Grain texture overlay (Element 18 below):** procedurally generated
  noise CGImage at `opacity = 0.04`. LOWER alpha than the Lange's silver
  stipple (0.07) because matte black reads as dirty if grain shows too
  strongly. The grain's purpose here is to break up the flat-black RGB
  and prevent the dial from looking like a vector shape.
- **Z-order:** chamfer inner shadow → dial face fill → vignette overlay
  → grain overlay → all subsequent dial elements above.

---

## Element 6 — Hour markers (cream lume on matte black)

The Coke GMT marker pattern:

- **Round lume dots** at hours **1, 2, 4, 5, 7, 8, 10, 11** (the
  non-cardinal hours, with 3 omitted for the date window).
- **Rectangular lume bars** at **6 and 9** (larger, vertical/horizontal
  oriented to the radial direction).
- **Inverted triangle** at **12** (large triangle pointing inward, the
  signature 12 o'clock indicator).

The 3 o'clock position is occupied by the date window (Element 13).

**Critical reference observation:** the markers are cream LUME, not white
and not painted. They have a clear thin **gold-cream outline** (matching
the triangle pip and the GMT hand color) — this outline ring is what
distinguishes Tudor's markers from a generic black-dial design. The
outline also creates a subtle 3D lift effect when combined with the drop
shadow.

### Element 6a — Round dots (hours 1, 2, 4, 5, 7, 8, 10, 11)

- **Count:** 8 dots.
- **Radial center:** `markerR = dialRadius * 0.78` — well inside the
  bezel chamfer, with comfortable margin to the minute track.
- **Dot radius:** `dotR = dialRadius * 0.034` — chunky and easy to read.
- **Fill:** `lumeCream = (0.95, 0.88, 0.68, 1.0)`.
- **Outline stroke:** `strokeColor = (0.76, 0.62, 0.36, 0.95)`,
  `lineWidth = max(0.5, dialRadius * 0.003)`. Same warm cream-gold
  outline as the triangle pip.
- **Drop shadow:**
  - `shadowOffset = (0.5, -0.6)`, `shadowOpacity = 0.55`, `shadowRadius
    = 1.2`, `shadowColor = .black`.
  - `shadowPath = the dot path` (the merged path of all 8 dots).
- **Angles** (CCW from +x, in radians):
  - 1 → `π/2 - π/6` (≈ 60°)
  - 2 → `π/2 - π/3` (≈ 30°)
  - 4 → `-π/6` (≈ -30°)
  - 5 → `-π/3` (≈ -60°)
  - 7 → `-π/2 - π/6` (≈ -120°)
  - 8 → `-π/2 - π/3` (≈ -150°)
  - 10 → `π + π/3` (≈ 150°, or equivalently `-5π/6`)
  - 11 → `π/2 + π/3` (≈ 120°)
  - (3 omitted — date window. 6, 9, 12 omitted — bars + triangle.)

**Merged layer:** one `CAShapeLayer` with one combined path holding all
8 dots; one stroke layer above it; one drop shadow on the fill layer.

### Element 6b — Rectangular bars (hours 6 and 9)

Larger lume bars, **radially aligned** (long axis pointing radially
toward the center, so they look like elongated capsules pointing inward).

- **Radial outer end:** `barOuterR = dialRadius * 0.86`.
- **Radial inner end:** `barInnerR = dialRadius * 0.66`.
- **Bar length (radial):** `barOuterR - barInnerR = dialRadius * 0.20`.
- **Bar width (perpendicular):** `dialRadius * 0.055`. *(updated Pass 2
  — was `0.045`; reference bars read chunkier than dots and the Pass-1
  snapshot showed them too thin relative to the dot diameter.)*
- **Corner radius:** half the bar width (so the bar caps are rounded —
  the reference bars have rounded ends, not square).
- **Fill:** `lumeCream`.
- **Outline stroke:** same cream-gold as the dots, `lineWidth = max(0.5,
  dialRadius * 0.003)`.
- **Drop shadow:** same magnitude as the dots — `offset (0.5, -0.6)`,
  `opacity 0.55`, `radius 1.2`.
- **Positions:** at angles `-π/2` (6 o'clock) and `π` (9 o'clock).
- **Implementation:** build each bar in bar-local coords (rounded
  rectangle centered on origin with long axis along +y), then translate
  to the radial position and rotate so the long axis points radially
  toward the center.

### Element 6c — Inverted triangle at 12 o'clock

The 12 marker is a **large inverted triangle** pointing toward the dial
center, framed by an outline. Equivalent in role to the bezel pip but
larger, on the dial face.

- **Tip vertex (innermost, pointing toward center):** at radius
  `dialRadius * 0.62` on angle `π/2` (top).
- **Base midpoint:** at radius `dialRadius * 0.84` on angle `π/2`.
- **Base half-width:** `dialRadius * 0.055` (so triangle base = 0.11 *
  dialRadius).
- **Triangle vertices** (in canvas coords, with `+v_radial` outward and
  `+v_perp` to the right):
  1. Tip: `caseCenter + (0, dialRadius * 0.62)`
  2. Base-right: `caseCenter + (+dialRadius * 0.055, dialRadius * 0.84)`
  3. Base-left: `caseCenter + (-dialRadius * 0.055, dialRadius * 0.84)`
- **Fill:** `lumeCream`.
- **Outline stroke:** same cream-gold, `lineWidth = max(0.6, dialRadius *
  0.004)` (slightly heavier than the dots because the triangle is
  larger).
- **Drop shadow:** `offset (0.6, -0.8)`, `opacity 0.55`, `radius 1.4`.

### Element 6 — Z-order

All marker layers (dots, bars, triangle) sit in the same z-band, above
the dial face/grain and below the minute track ticks and the hands.

---

## Element 7 — Minute track (perimeter ticks)

A ring of fine ticks at every minute, with longer ticks at 5-minute
intervals. The reference shows the minute track as a delicate printed
chapter ring, MUCH thinner than the markers — almost hairline.

**Tick band radii:**

- **Outer end:** `tickOuterR = dialRadius * 0.95`. Just inside the
  chamfer inner edge.
- **Minor tick inner end** (every minute that isn't a 5-multiple):
  `dialRadius * 0.93`. Length ≈ 2% of dialRadius.
- **Major tick inner end** (every 5 minutes — 0, 5, 10, ..., 55):
  `dialRadius * 0.90`. Length ≈ 5% of dialRadius.
- **Line width (minor):** `max(0.3, dialRadius * 0.005)` — hairline.
- **Line width (major):** `max(0.5, dialRadius * 0.010)` — a hair
  thicker than minor.
- **Color:** `bezelNumeralCream = (0.93, 0.86, 0.66, 1.0)` — same cream
  as the bezel numerals and the markers. The reference's minute track is
  faintly warm-cream, NOT white.
- **Line cap:** `.butt` (crisp printed edges).
- **No drop shadow** — printed.
- **Implementation:** TWO `CAShapeLayer`s (one for minors, one for
  majors) so the line widths can differ. Each layer's path = one
  `CGMutablePath` with all the segment subpaths combined.

**Edge cases:** the major ticks at minutes 15, 30, 45 sit at the 3, 6,
9 o'clock positions — i.e. behind the date window, the 6 bar, and the
9 bar. These ticks should still be drawn at full length; the markers
sit IN FRONT of them and visually cover the overlap. The 0 (= 12)
position major tick sits just above the 12 triangle — it remains
visible above the triangle's outer base, which is fine.

**Z-order:** minute track → above grain overlay, below hour markers
(markers sit on top of ticks). Or equivalently: ticks at the same
z-level as markers, with the markers drawn after — either works.

---

## Element 8 — Hour hand (snowflake silhouette)

The Tudor snowflake hour hand is the **iconic Tudor signature**. It is a
slim shaft with a **square-ish lozenge** (a diamond rotated 45°) near
the tip, followed by a short pointed cap.

The "snowflake" looks like this when laid out flat (tip at top, pivot at
bottom):

```
            ▲          ← pointed tip cap
           ━━━━        ← short transitional taper
          ◆◆◆◆◆◆       ← square lozenge with chamfered corners
          ◆◆◆◆◆◆          (the snowflake itself — wider than the shaft)
           ━━━━
            ┃          ← slim shaft (long)
            ┃
            ┃
            ●          ← pivot
```

**Hand-local coordinate system:** `bounds.size = (width, length * (1 +
tailFraction))`. `anchorPoint = (0.5, tailFraction / (1 + tailFraction))`,
so the pivot point is at `(width/2, tailFraction * length)` in
bounds-local coords. The hand intrinsically points "up" (toward +y).

**Proportions** *(updated Pass 2 — snowflake moved outward; tip cap shortened)*:

| Property              | Value             | Pass-1 value | Note |
|-----------------------|-------------------|--------------|------|
| `tailFraction`        | 0.0 (no counterweight tail) | 0.0   | unchanged |
| `shaftWidth`          | `width * 0.18`    | `width * 0.18` | unchanged |
| `lozengeStartY`       | `length * 0.60`   | `length * 0.45` | **moved outward** — shaft is now longer, lozenge sits in the outer third of the hand |
| `lozengeMidY`         | `length * 0.75`   | `length * 0.66` | midpoint of new range |
| `lozengeEndY`         | `length * 0.90`   | `length * 0.85` | **moved outward** |
| `lozengeHalfWidth`    | `width * 0.50` (lozenge full-width = 1.0 * width) | unchanged | unchanged |
| `lozengeChamfer`      | `width * 0.10` (corner chamfer offset on the lozenge) | unchanged | unchanged |
| `tipBaseY`            | `length * 0.93`   | `length * 0.88` | **moved outward** — gap from lozengeEndY to tipBaseY stays at 0.03 (small chamfered transition) |
| `tipBaseHalfWidth`    | `width * 0.18`    | `width * 0.18` | unchanged |
| `tipY`                | `length * 1.00`   | unchanged | unchanged |

Net effect: the snowflake lozenge now occupies the outer third of the
hand (`0.60 → 0.90`), with a short pointed cap past it (`0.93 → 1.00`,
just 7% of length). The cap is approximately half its Pass-1 size. This
matches the Tudor reference: the snowflake sits visibly at the END of
the hand, with a small pointed lume tip past it. Reading (a) from the
prompt — NOT reading (b) (the snowflake is not the tip itself; it has a
small cap past it).

Note: the **hour-hand snowflake is intentionally square-ish** — width =
`length * (some_ratio)`. We achieve this by making the lozenge's
half-width almost match the lozenge's vertical span (lozenge vertical
span = `lozengeEndY - lozengeStartY = length * 0.40`; lozenge full-width
= `width * 1.0`; so as long as `width ≈ length * 0.40` the lozenge is
visually square). With our hour-hand `width = mainDialRadius * 0.085` and
`length = mainDialRadius * 0.50`, that gives lozenge span = 0.20 *
dialRadius vertical and 0.085 * dialRadius horizontal — too narrow. Let
me re-spec:

**HOUR-HAND SIZE (final):**

- `length = dialRadius * 0.48` — reaches about to the inner edge of the
  hour-marker dots.
- `width = dialRadius * 0.16` — wide enough that the lozenge is visibly
  square-ish (lozenge vertical span ≈ 0.40 × length = 0.192 * dialRadius;
  lozenge full-width = 1.0 × width = 0.16 * dialRadius; close to square,
  slightly taller).

**Vertex sequence (clockwise from pivot, centerline at `cx = width / 2`):**

The path runs around the snowflake silhouette. With the chamfer at each
lozenge corner, the lozenge has 8 corners instead of 4 (octagon-ish).

Going CCW starting at the pivot's right side:

1. `(cx + shaftWidth/2, 0)` — shaft right at pivot.
2. `(cx + shaftWidth/2, lozengeStartY)` — shaft top right (where lozenge
   begins).
3. `(cx + lozengeHalfWidth - lozengeChamfer, lozengeStartY)` — lozenge
   bottom-right corner (chamfered start).
4. `(cx + lozengeHalfWidth, lozengeStartY + lozengeChamfer)` — lozenge
   right-shoulder bottom.
5. `(cx + lozengeHalfWidth, lozengeEndY - lozengeChamfer)` — lozenge
   right-shoulder top.
6. `(cx + lozengeHalfWidth - lozengeChamfer, lozengeEndY)` — lozenge
   top-right corner (chamfered end).
7. `(cx + tipBaseHalfWidth, tipBaseY)` — tip taper right.
8. `(cx, tipY)` — tip point.
9. `(cx - tipBaseHalfWidth, tipBaseY)` — tip taper left.
10. `(cx - lozengeHalfWidth + lozengeChamfer, lozengeEndY)` — lozenge
    top-left corner.
11. `(cx - lozengeHalfWidth, lozengeEndY - lozengeChamfer)` — lozenge
    left-shoulder top.
12. `(cx - lozengeHalfWidth, lozengeStartY + lozengeChamfer)` — lozenge
    left-shoulder bottom.
13. `(cx - lozengeHalfWidth + lozengeChamfer, lozengeStartY)` — lozenge
    bottom-left corner.
14. `(cx - shaftWidth/2, lozengeStartY)` — shaft top left.
15. `(cx - shaftWidth/2, 0)` — shaft left at pivot.
16. Close back to (1).

**Fill:** `lumeCream = (0.95, 0.88, 0.68, 1.0)`. The reference's
snowflake hands are filled with the same cream lume as the markers (NOT
silver, NOT polished steel). This is intentional — Tudor's design language
unifies hand color with marker color so they read as a single "applied
lume" family.

**Edge stroke:** `strokeColor = (0.76, 0.62, 0.36, 0.95)` (cream-gold
outline, same as marker outline), `lineWidth = max(0.4, dialRadius *
0.003)`.

**Drop shadow:**
- `shadowColor = .black`
- `shadowOffset = (1.2, -1.8)` — clearly lower-right; hands cast longer
  shadows than markers because they sit higher off the dial.
- `shadowOpacity = 0.55` — strong because the snowflake lozenge is a
  large mass that casts a real shadow on the matte dial.
- `shadowRadius = 2.5`
- `shadowPath = handPath` (avoid alpha-channel shadow).

**Specular highlight (NEW helper `applyLumeSpecular`, not the gold one):**
the lume cream gets a softer, less aggressive highlight than the gold.
- Gradient: `.axial`, `startPoint = (0.0, 1.0)`, `endPoint = (1.0, 0.0)`.
- Colors / locations:
  - `0.00` → `lumeSpecularHi = (1.00, 0.96, 0.82, 0.40)` — soft cream
    highlight (less saturated than gold specular's `(1.00, 0.92, 0.72,
    0.55)`).
  - `0.40` → `(1.00, 0.92, 0.74, 0.12)` — soft mid.
  - `0.65` → `(1.0, 1.0, 1.0, 0.0)` — transparent through middle.
  - `1.00` → `lumeSpecularLo = (0.50, 0.36, 0.18, 0.25)` — warm shadow
    at lower-right edge.
- Mask: the hand's silhouette path.
- Apply as a child of the transform layer so the highlight rotates with
  the hand (matches the Asymmetric Moonphase convention for hands).

**Z-order:** above all dial markers, above the minute track. Below the
minute hand.

---

## Element 9 — Minute hand (long snowflake)

The minute hand is the same overall silhouette as the hour hand but:

- **Longer** (reaches the inner edge of the minute track).
- **Slightly slimmer** (the shaft is thinner so it doesn't read as a
  duplicate of the hour hand).
- **Smaller lozenge near the tip** (the snowflake is proportionally
  smaller relative to the hand length).

**SIZE:**

- `length = dialRadius * 0.84` — reaches to about `0.84 * dialRadius`,
  just inside the minute track's minor-tick inner radius (0.93).
  Actually that's clearly inside but the *tip* must clearly touch the
  minute track. Adjusting: `length = dialRadius * 0.88`. The tip at
  `dialRadius * 0.88` touches the major tick at the 5-minute marks.
- `width = dialRadius * 0.115` — slimmer than the hour hand (0.16).

**Proportions (same path constructor as the hour hand, with these
ratios)** *(updated Pass 2 — snowflake moved outward; tip cap shortened)*:

| Property              | Value             | Pass-1 value | Note |
|-----------------------|-------------------|--------------|------|
| `tailFraction`        | 0.0               | 0.0          | unchanged |
| `shaftWidth`          | `width * 0.14` (slimmer than hour's 0.18) | unchanged | unchanged |
| `lozengeStartY`       | `length * 0.74` (lozenge starts further out — longer shaft, shorter snowflake) | `length * 0.62` | **moved outward** |
| `lozengeMidY`         | `length * 0.83`   | `length * 0.74` | midpoint of new range |
| `lozengeEndY`         | `length * 0.93`   | `length * 0.86` | **moved outward** |
| `lozengeHalfWidth`    | `width * 0.50`    | unchanged | unchanged |
| `lozengeChamfer`      | `width * 0.10`    | unchanged | unchanged |
| `tipBaseY`            | `length * 0.95`   | `length * 0.90` | **moved outward** |
| `tipBaseHalfWidth`    | `width * 0.16`    | unchanged | unchanged |
| `tipY`                | `length * 1.00`   | unchanged | unchanged |

Net effect: the minute-hand lozenge now occupies `0.74 → 0.93` of length
with a 5%-of-length pointed cap (`0.95 → 1.00`). The cap is roughly half
its Pass-1 size. The lozenge is `length * 0.19` tall and `width * 1.0 =
dialRadius * 0.115` wide — still narrower-than-tall (the minute hand's
lozenge stays visibly slimmer and less square than the hour hand's).
Matches reading (a) from the prompt.

**Fill, stroke, shadow, specular:** identical to the hour hand — lume
cream fill, cream-gold outline, lower-right drop shadow, lume-specular
overlay. The two hands form a matched pair.

**Z-order:** above hour hand. Below second hand.

---

## Element 10 — Second hand (thin centered needle + pommel)

The seconds hand on the Coke GMT is a **thin straight needle** centered
on the pivot, with a **small round counterweight pommel** just past the
pivot on the OPPOSITE side from the tip. The reference shows the seconds
hand in the same cream-gold color family as the GMT hand (NOT silver).

**Geometry:**

- `length = dialRadius * 0.92` (slightly longer than the minute hand —
  reaches almost to the minute track outer edge).
- `width = dialRadius * 0.012` — thin.
- `tailFraction = 0.12` — short counterweight on the opposite side.
- `pommelRadius = dialRadius * 0.030` — small round disc at the end of
  the tail.

**Hand-local path** (anchorPoint at the pivot, intrinsic direction +y):

- `tailY = -tailFraction * length` (extends below the pivot).
- `cx = width / 2`.
- Path:
  1. Move to `(cx - width/2, tailY * 0.4)` (start of tail shaft).
  2. Line to `(cx + width/2, tailY * 0.4)`.
  3. Line to `(cx + width/2, length * 0.95)` (just before tip taper).
  4. Line to `(cx + width/2 * 0.3, length * 0.99)` (taper).
  5. Line to `(cx, length)` — tip.
  6. Line to `(cx - width/2 * 0.3, length * 0.99)`.
  7. Line to `(cx - width/2, length * 0.95)`.
  8. Close back to start.

**Counterweight pommel** (separate `CAShapeLayer` filled circle):
- Center: at hand-local `(cx, tailY)` (the end of the tail, below the
  pivot).
- Radius: `pommelRadius`.
- Fill: `secondHandCream` (same color as the needle).

**Tip lume dot** (separate `CAShapeLayer` filled circle) *(updated Pass 2 — promoted from optional to mandatory)*:
- Center: at hand-local `(cx, length * 0.78)` (about 78% along the
  needle).
- Radius: `dialRadius * 0.014`.
- Fill: `lumeCream`.
- Outline: same cream-gold as markers, `lineWidth = max(0.3, dialRadius *
  0.002)`.

Pass-2 promotes the tip lume dot to REQUIRED. The needle is thin enough
(`width = dialRadius * 0.012`) that it's hard to track at 2400×2400, and
the reference shows the dot clearly. Wire it.

**Fill (needle + pommel):** `secondHandCream = (0.92, 0.84, 0.62, 1.0)` —
a touch deeper cream than the snowflakes, matching the GMT hand and the
reference's "applied gold" hand family. (Tudor groups the GMT and seconds
hands as the same color, distinct from the snowflake hands.)

**Edge stroke:** `strokeColor = (0.62, 0.48, 0.24, 0.85)`, `lineWidth =
max(0.25, dialRadius * 0.002)`.

**Drop shadow:** `offset (0.8, -1.2)`, `opacity 0.45`, `radius 1.6`,
`shadowPath = needlePath + pommelPath`.

**Specular highlight:** apply the GOLD specular (`applyGoldSpecular`)
not the lume specular — the seconds hand is the gold family.

**Z-order:** above hour hand, above minute hand, above GMT hand. The
seconds hand is on top of every other hand. Below the center hub.

---

## Element 11 — GMT hand (24h scale, arrow tip)

The GMT hand is a **thin gold/cream hand with an arrow tip** that points
to the 24h bezel. It runs on a 24-hour scale (one full rotation per 24
hours, half the rate of the regular hour hand). The arrow tip reaches
the inner edge of the bezel insert.

**Geometry** *(updated Pass 2 — shaft and arrowhead enlarged for readability)*:

- `length = dialRadius * 0.94` — reaches to `bezelInnerR / dialRadius =
  caseRadius * 0.88 / (caseRadius * 0.80) = 1.10` × dialRadius. So
  length at `dialRadius * 0.94` means the tip sits just inside the
  inner edge of the bezel — which is what the reference shows: the
  arrow tip's POINT touches or barely overlaps the inner bezel rim.
- `width = dialRadius * 0.028` (shaft). *(updated Pass 2 — was `0.022`;
  Pass-1 snapshot showed the GMT hand barely readable. Widening the
  shaft by ~27% gives the hand presence without making it as dominant
  as the snowflakes.)*
- `tailFraction = 0.0` (no counterweight on the GMT hand — the
  reference shows none).

**Hand-local path** (anchorPoint at the pivot bottom = (0.5, 0.0)):

The GMT hand is a thin shaft that opens into a **chevron arrowhead** at
the tip — like a printer's caret `^`. It has NO lozenge.

Define *(updated Pass 2 — arrowhead enlarged)*:
- `cx = width / 2`
- `arrowBaseY = length * 0.82`  — where the shaft transitions into the arrowhead *(was `0.84`; pulled in slightly to give a longer arrowhead at the new width)*
- `arrowMidY = length * 0.92`   — broadest point of the arrowhead
- `arrowHalfWidth = width * 3.0` — arrowhead is wider than the shaft (full width = 6.0× shaft width = `dialRadius * 0.168`). *(updated Pass 2 — was `width * 2.4`. With the wider shaft, this keeps the arrowhead-to-shaft proportions visually similar to the reference while making the head ~60% larger in area.)*
- `tipY = length`
- `notchY = length * 0.93` — the inner notch on the back side of the arrowhead (chevron tail)
- `notchHalfWidth = width * 0.4` (the chevron is a hollow arrow shape — a notch cut into the back)

Vertex sequence:

1. `(cx + width/2, 0)` — shaft right at pivot.
2. `(cx + width/2, arrowBaseY)` — shaft top-right (entering arrowhead).
3. `(cx + arrowHalfWidth, arrowMidY)` — arrowhead right wing tip.
4. `(cx + notchHalfWidth, notchY)` — chevron right notch base.
5. `(cx, tipY)` — arrow tip (top point).
6. `(cx - notchHalfWidth, notchY)` — chevron left notch base.
7. `(cx - arrowHalfWidth, arrowMidY)` — arrowhead left wing tip.
8. `(cx - width/2, arrowBaseY)` — shaft top-left.
9. `(cx - width/2, 0)` — shaft left at pivot.
10. Close.

NOTE: A chevron arrowhead (notched back) is the more nuanced
Tudor-reference shape. If implementation simplicity is desired, omit
vertices 4–6 and use a plain triangle arrowhead (3 → 5 → 7 with the tip
at 5). Both read correctly at screensaver scale. **Recommend the plain
triangle for v1** — implement vertices 1, 2, 3, 5, 7, 8, 9 (skipping 4
and 6) for a non-notched arrow. The chevron-notch refinement is a Pass-2
polish only if the implementer wants the extra detail.

**Fill:** `gmtHandGold = (0.88, 0.72, 0.40, 1.0)` — warmer than the
seconds hand cream; this is the most clearly "gold-ish" hand on the dial.
Distinct from `lumeCream` (markers/snowflakes) and `secondHandCream`
(seconds). Tudor's reference shows the GMT hand as the brightest, most
yellow-gold of the four hands.

**Edge stroke:** `strokeColor = (0.52, 0.38, 0.16, 0.95)`, `lineWidth =
max(0.3, dialRadius * 0.0025)`.

**Drop shadow:** `offset (0.8, -1.2)`, `opacity 0.45`, `radius 1.6`,
`shadowPath = handPath`.

**Specular highlight:** apply the GOLD specular (`applyGoldSpecular`).

**Z-order:** ABOVE the snowflake hands (hour and minute), BELOW the
seconds hand. The GMT hand is the second-topmost hand.

**Reference verification:** at the reference photo timestamp (which we
don't know precisely), the GMT hand appears to point to roughly the "8"
position on the bezel — i.e. `8/24 * 2π = π/3` clockwise from 12. This
is consistent with the rendered photo being a photoshoot specimen where
all hands are deliberately positioned for the press kit (typically
10:10:35 for hour:minute:second, and the GMT often set to an
"eye-pleasing" position regardless of local time). This means our
rendered GMT hand position will look DIFFERENT from the press photo —
that's correct and expected.

---

## Element 12 — Center hub

A small disc at the pivot covering the bottoms of all four hands.

- **Position:** dial center (`caseCenter`).
- **Radius:** `dialRadius * 0.030`.
- **Fill:** `gmtHandGold` (matches the brightest gold of the GMT hand —
  the hub is the single visual anchor where all four hands meet, and it
  should match the GMT hand family per the reference).
- **Edge stroke:** `strokeColor = (0.52, 0.38, 0.16, 1.0)`, `lineWidth =
  0.4`.
- **Drop shadow:** `offset (0.5, -0.6)`, `opacity 0.50`, `radius 1.0`.
- **Specular:** apply gold specular.
- **Z-order:** above all four hands. The topmost element in the dial
  hierarchy except for the bezel and case.

---

## Element 13 — Date window (3 o'clock)

The date window is a small **white/cream rectangle with a thin gold
frame**, cut into the dial face at 3 o'clock, displaying the
day-of-month numeral.

**Position:** the window center sits at `(caseCenter.x + dialRadius *
0.70, caseCenter.y)` — close to the bezel chamfer at 3 o'clock, but with
clear margin to the chamfer (about 0.10 × dialRadius of black dial
between the window's outer edge and the chamfer's inner edge).

**Window dimensions:**

- **Box height:** `dateBoxH = dialRadius * 0.12`.
- **Box width:** `dateBoxW = dateBoxH * 1.10` — slightly wider than
  tall (the date window in the reference is closer to landscape than
  square, accommodating two digits).
- **Corner radius (interior white box):** `dateBoxH * 0.05` — barely
  rounded.

**Gold frame:**

- **Frame outer:** extends `dialRadius * 0.008` beyond the white box on
  all sides. So frame outer dimensions = `(dateBoxW + 2 * 0.008 *
  dialRadius) × (dateBoxH + 2 * 0.008 * dialRadius)`.
- **Frame corner radius:** interior corner + frame inset.
- **Frame fill:** `dateFrameGold = (0.84, 0.66, 0.34, 1.0)` —
  match the GMT hand gold for consistency with the "applied gold"
  family on this dial.
- **Frame edge stroke:** `strokeColor = (0.52, 0.38, 0.16, 0.95)`,
  `lineWidth = max(0.3, dialRadius * 0.002)`.
- **Frame drop shadow:** `offset (0.6, -0.8)`, `opacity 0.45`,
  `radius 1.2`.
- **Frame specular:** apply gold specular.

**Inner white box:**

- **Fill:** `dateBoxWhite = (0.96, 0.94, 0.88, 1.0)` — warm cream-white,
  slightly aged so it doesn't look like a fresh sticker against the
  matte black dial.
- **Inner edge stroke** (subtle inset shadow): `strokeColor = (0.0, 0.0,
  0.0, 0.20)`, `lineWidth = 0.4`. Gives the window a slight recessed
  feel.

**Date digit (1 or 2 chars):**

- **Font:** prefer `NSFont(name: "HelveticaNeue-Bold", size: dateBoxH *
  0.65)`. Fall back to system bold. The reference uses a clean
  sans-serif digit, not a serif.
- **Color:** `dateNumeralBlack = (0.04, 0.04, 0.05, 1.0)` — near-black,
  matching the dial face tone.
- **Anchoring:** digit's combined bounding box center → window center.
- **Drop shadow** (digit sits on the white plate, slight depth):
  `offset (0.3, -0.5)`, `opacity 0.25`, `radius 0.6`.

**Z-order:** above dial face/grain → frame drop shadow → frame fill →
frame specular → white box → digit.

**Initial digit at `attach()` time** *(updated Pass 2 — fix for the
"shows 1" flash Caleb reported)*:

Pass-1's `attach()` called `updateDateDigit(day: 0)` which `max(1,
min(31, day))`-clamps to **"1"**. If the screensaver host captures any
frame before the first real `tick()` runs, the user sees "1" instead of
today's date. The math is correct; the bug is the placeholder.

Pass-2 contract: at `attach()` time, before constructing any layers
that consume the digit, the renderer reads today's day-of-month via
`Calendar.current.component(.day, from: Date())` (one read, install-time
only) and seeds `lastRenderedDay` with that value, then renders the
digit from it. The subsequent `tick()` call inside `attach()` sees
`day == lastRenderedDay`, no-ops, and the first time-driven update
happens on the next real tick or day rollover.

This is **not** a P4 violation. The renderer's per-frame loop is still
purely time-driven via `tick(reduceMotion:)`. The install-time `Date()`
read happens exactly once, produces a static placeholder, and does not
influence any subsequent frame. (Treat it identically to reading
`Date()` once for "what's the current rotation of the hour hand at
install" — the rotation math is time-driven; the *initial value* is
seeded from `now`.)

**Why not "empty placeholder until first tick" (option a from the
prompt):** would leave a visible empty box during a startup window
that's not guaranteed to be zero. Worse UX than showing today's date.

**Why not "leave as Pass-1 (always shows 1 first)" (option c):** Caleb
explicitly reported the issue. If it's a one-time flash, fixing it
costs ~5 lines. Cost/benefit favors the fix.

---

## Element 14 — Hand stack proportions summary

For clarity, here are the relative lengths of the four hands as
fractions of `dialRadius`:

| Hand           | Length (× dialRadius) | Width  | Color           |
|----------------|-----------------------|--------|-----------------|
| Hour           | 0.48                  | 0.16   | `lumeCream`     |
| Minute         | 0.88                  | 0.115  | `lumeCream`     |
| Second         | 0.92                  | 0.012  | `secondHandCream` |
| GMT (24h)      | 0.94                  | 0.028  | `gmtHandGold`   |

*(updated Pass 2 — GMT hand width was 0.022; widened to 0.028 for
readability.)*

The seconds and GMT hands are the longest because they "ride on top" of
the time hands and extend to the minute track / bezel respectively. The
hour and minute hands are the visually dominant pair (the snowflake
silhouette). All four pivot at `caseCenter`.

**Rotation direction:** standard clockwise from 12. Convert from the
math angle (CCW from +x, 0 at 3 o'clock) to the layer rotation:
`layerRotation = targetMathAngle - π/2`. (Same convention as Asymmetric
Moonphase.)

**Rotation rates (math angles per second):**

- Hour hand: `-2π / (12 * 3600)` rad/sec (one full CW rotation per 12
  hours).
- Minute hand: `-2π / (60 * 60)` rad/sec (one full CW rotation per 60
  minutes).
- Second hand: `-2π / 60` rad/sec.
- GMT hand: `-2π / (24 * 3600)` rad/sec (one full CW rotation per 24
  hours — HALF the rate of the regular hour hand).

These are conceptual — the actual `tick(reduceMotion:)` reads from
`Calendar` components per the story spec.

---

## Element 15 — Lighting model summary

| Surface         | Specular family    | Highlight intensity | Helper                |
|-----------------|--------------------|---------------------|-----------------------|
| Steel case      | Polished metal     | Bright + sharp      | `applyCasePolishing`  |
| Ceramic bezel   | Soft sheen         | Broad + soft        | (inline in Element 2) |
| Matte dial      | None               | —                   | —                     |
| Lume markers    | Cream lume         | Soft + warm         | `applyLumeSpecular`   |
| Lume hands      | Cream lume         | Soft + warm         | `applyLumeSpecular`   |
| Gold seconds    | Gold               | Sharp + saturated   | `applyGoldSpecular`   |
| GMT hand        | Gold               | Sharp + saturated   | `applyGoldSpecular`   |
| Date frame      | Gold               | Sharp + saturated   | `applyGoldSpecular`   |
| Bezel pip       | Cream lume         | Soft + warm         | `applyLumeSpecular`   |

**Shadow magnitudes by element role:**

| Role                              | offset       | opacity | radius |
|-----------------------------------|--------------|---------|--------|
| Lume markers (dots, bars, triangle)| `(0.5, -0.6)`| 0.55    | 1.2    |
| Snowflake hands                   | `(1.2, -1.8)`| 0.55    | 2.5    |
| Seconds hand                      | `(0.8, -1.2)`| 0.45    | 1.6    |
| GMT hand                          | `(0.8, -1.2)`| 0.45    | 1.6    |
| Center hub                        | `(0.5, -0.6)`| 0.50    | 1.0    |
| Date frame                        | `(0.6, -0.8)`| 0.45    | 1.2    |
| Date digit                        | `(0.3, -0.5)`| 0.25    | 0.6    |
| Triangle pip                      | `(0.6, -0.6)`| 0.45    | 1.0    |

---

## Element 16 — Reuse vs new helpers

**Helpers that carry over from Asymmetric Moonphase (use as-is):**

- `applyGoldSpecular(to:useLocalPath:)` — apply to GMT hand, seconds
  hand, date frame, center hub.
- `serifFont(size:bold:)` — NOT used here (Tudor uses sans-serif). Skip.
- `textPath(string:font:)` — use as-is for bezel numerals and the date
  digit (just with `HelveticaNeue` instead of a serif).

**New helpers to add for this dial:**

1. `applyLumeSpecular(to host: CAShapeLayer, useLocalPath: Bool)` — a
   sibling of `applyGoldSpecular` with the lume color stops (Element
   8's specular spec). Apply to all four markers groups (dots merged,
   bars merged, triangle, bezel pip) and to the snowflake hands.
2. `applyCeramicSheen(to bezelHalf: CAShapeLayer, halfAngle: Range)` —
   the broad soft white-translucent radial sheen masked to the bezel
   half (Element 2). Two calls — one per half. (Or implement inline if
   it's a single 10-line block.)
3. `applyCasePolishing(to caseLayer: CALayer)` — the bright steel
   highlight gradient at the upper-left of the case top. The case is
   one layer with gradient fill, so this might just BE the case
   construction — no helper needed.
4. `brushedSteelImage()` — analog of the Asymmetric Moonphase
   stipple-image generator, but with elongated horizontal noise dots
   for brushed-steel feel. Apply only to the chamfer ring.
5. `dialGrainImage()` — analog of the stipple image but on a dark
   transparent background, applied at `opacity = 0.04` to the matte
   black dial.
6. `snowflakeHandPath(width:length:isMinute:)` — constructs the
   snowflake silhouette path with the proportions from Elements 8/9.
   `isMinute: true` uses the elongated/slimmer ratios.
7. `gmtHandPath(width:length:)` — constructs the GMT hand silhouette
   (shaft + arrow tip) per Element 11.
8. `bezelHalfPath(centerX, centerY, outerR, innerR, startAngle,
   endAngle)` — utility for building the bezel half-rings. The
   Asymmetric Moonphase code likely has something similar — reuse if
   so, otherwise add it.

The Asymmetric Moonphase renderer's general patterns (per-element
`CAShapeLayer` with separate stroke layer, drop shadow on the fill
layer, `shadowPath` set explicitly to avoid alpha-channel cost,
`CATransaction.setDisableActions(true)` around per-tick updates) all
carry over cleanly. No structural changes needed at the renderer level.

---

## Element 17 — Reduce-motion contract

Same convention as Asymmetric Moonphase (P7):

- Under `reduceMotion = true`, dedup `tick(reduceMotion:)` by integer
  second. If `floor(now.timeIntervalSince1970) == lastTickIntegerSecond`,
  return early with no dirty rects.
- **Seconds hand:** freezes at its position. Does not animate between
  ticks.
- **Hour, minute, GMT hands:** tick to position. No `CABasicAnimation`
  between positions — just set the layer's `transform` inside a
  `CATransaction.setDisableActions(true)` block.
- **Date digit:** updates on date rollover (midnight); no animation.
- **No ambient animations** on this dial (unlike Asymmetric Moonphase
  there's no moonphase to advance). The dial is fully static between
  ticks.

---

## Element 18 — Procedural textures (faceplate grain + brushed steel)

Two texture overlays on this dial — different from the Asymmetric
Moonphase's single silver stipple.

### 18a — Dial grain (matte black faceplate)

- **Buffer size:** 512×512 pixels.
- **Generation:**
  1. CGContext 512×512, 8-bit, sRGB, premultiplied alpha.
  2. Fill transparent.
  3. ~4000 random 1×1 dots (fewer than the Lange's 6000 — black dials
     handle less grain). Each dot has `alpha = 1.0` and gray value
     uniform in `[0.0, 1.0]` (so the noise is bidirectional — brightens
     AND darkens the matte black).
  4. Optional Gaussian blur radius 0.5.
  5. Extract `CGImage`, cache as `dialGrainImage`.
- **Application:** `CALayer` named `dialGrainLayer`, `contents =
  dialGrainImage`, `contentsGravity = .resize`, `opacity = 0.04`,
  masked to the dial circle.
- **Z-order:** above dial face fill + vignette, below all markers and
  hands.

### 18b — Brushed steel (chamfer + case top)

- **Buffer size:** 256×256 pixels.
- **Generation:**
  1. CGContext 256×256, 8-bit, sRGB, premultiplied alpha.
  2. Fill transparent.
  3. ~2000 random horizontally-elongated rectangles (6×1 pixel, alpha
     1.0, gray uniform `[0.0, 1.0]`). The elongation produces visible
     horizontal brush lines when viewed at normal scale.
  4. Optional 0.3 Gaussian blur (very subtle).
  5. Cache as `brushedSteelImage`.
- **Application:** `CALayer` named `caseBrushLayer`, `contents =
  brushedSteelImage`, `contentsGravity = .resize`, `opacity = 0.08`,
  masked to the chamfer ring (annulus from `dialRadius` to
  `bezelInnerR`).
- **Z-order:** above case-top gradient, below polished chamfer ring
  highlight.

---

## Element 19 — Gold specular highlight gradient (carry-over from
Asymmetric Moonphase Element 19) *(updated Pass 2 — marked REQUIRED; Pass-1 renderer shipped without it)*

**Status:** REQUIRED in Pass 2. The Pass-1 renderer did not wire
`applyGoldSpecular` to any element; this is the single biggest reason
the rendered output reads as "cleanly drawn" rather than "photographed".
All gold elements must receive this overlay in Pass 2.

Used on: GMT hand, seconds hand, center hub, date frame (both gold
elements).

**Gradient setup** (per element, via `applyGoldSpecular`):
- `.axial`, `startPoint = (0.0, 1.0)`, `endPoint = (1.0, 0.0)`.
- Colors / locations:
  - `0.00` → `goldSpecularHi = (1.00, 0.92, 0.72, 0.55)`
  - `0.30` → `goldSpecularMid = (0.96, 0.82, 0.52, 0.22)`
  - `0.55` → `(1.0, 1.0, 1.0, 0.0)` — transparent
  - `1.00` → `goldSpecularLo = (0.36, 0.22, 0.08, 0.35)`
- Mask: the element's silhouette path.
- Child of transform layer for hands (rotates with the hand). Sibling
  for non-rotating elements (date frame, center hub).

---

## Element 20 — Lume specular highlight gradient (NEW for this dial) *(updated Pass 2 — marked REQUIRED; Pass-1 renderer shipped without it)*

**Status:** REQUIRED in Pass 2. Same reasoning as Element 19 — the lume
markers and snowflake hands ship flat in Pass-1, which kills the
"applied lume" reading. Wire `applyLumeSpecular` to every element in
the lume-cream family.

Used on: snowflake hour hand, snowflake minute hand, hour-dot marker
group, hour-bar marker group, 12-triangle marker, bezel pip.

**Gradient setup** (per element, via `applyLumeSpecular`):
- `.axial`, `startPoint = (0.0, 1.0)`, `endPoint = (1.0, 0.0)`.
- Colors / locations:
  - `0.00` → `lumeSpecularHi = (1.00, 0.96, 0.82, 0.40)` — softer
    than gold's 0.55.
  - `0.40` → `lumeSpecularMid = (1.00, 0.92, 0.74, 0.12)` — softer
    mid.
  - `0.65` → `(1.0, 1.0, 1.0, 0.0)` — transparent.
  - `1.00` → `lumeSpecularLo = (0.50, 0.36, 0.18, 0.25)` — warm
    shadow at lower-right.
- Mask: the element's silhouette path.
- Child of transform layer for hands (snowflakes rotate with the hand).
  Sibling for non-rotating markers.

The lume specular family is intentionally **less saturated** than the
gold specular — lume is a matte/satin material, gold is polished metal.
The visual effect should be a subtle warm glow on the upper-left of each
lume element, not a chrome stripe.

---

## Element 21 — Ceramic bezel sheen (NEW for this dial)

The single broad soft highlight across the upper-left of the bezel
annulus, applied as a separate `CAGradientLayer` above the two bezel
halves but below the numerals.

**Implementation:**

- `CAGradientLayer`, type `.radial`.
- `startPoint = (0.25, 0.80)` — upper-left of the bounding box.
- `endPoint = (0.85, 0.20)` — lower-right.
- Colors / locations:
  - `0.00` → `(1.0, 1.0, 1.0, 0.20)` — soft white peak at upper-left.
  - `0.50` → `(1.0, 1.0, 1.0, 0.05)` — fades quickly.
  - `1.00` → `(1.0, 1.0, 1.0, 0.0)` — gone by the lower-right.
- Mask: a `CAShapeLayer` filled with the **bezel annulus** path (full
  ring from `bezelInnerR` to `bezelOuterR`) so the sheen only paints
  on the bezel surface.
- Frame: the full bezel bounding rect (`caseRadius * 2 × caseRadius *
  2` square centered on the case).

**Z-order in bezel stack:** black half → red half → **ceramic sheen
overlay** → top-edge highlight band → inner groove → ticks → numerals →
pip.

---

## Element 22 — Bezel sheen revisions (NEW Pass 2)

Pass-1 specced two sheen mechanisms for the bezel:

1. Element 2's "top-edge highlight band" — a stroked arc on the outer
   edge of the bezel from `60°` to `170°`.
2. Element 21's "ceramic sheen overlay" — a radial CAGradientLayer
   masked to the full bezel annulus.

In the rendered snapshot these read combined as a single soft glow,
which leaves the bezel feeling slightly flat against the reference's
clearly "rounded ceramic" appearance. The Tudor reference photo shows a
broad, curved, *directional* highlight tracing the upper-left third of
the bezel — the kind of highlight you get on a curved surface lit from
the upper-left.

Pass-2 adds a THIRD sheen element: a **mid-arc directional sheen**
stroked at the bezel center radius (not the outer edge), with a wider
linewidth and a tighter angular sweep, to produce the curved-surface
highlight.

**Implementation (Element 22 — mid-arc ceramic sheen):**

- `CAShapeLayer`, path = arc on circle at radius `(bezelOuterR +
  bezelInnerR) / 2 = caseRadius * 0.935` (the bezel centerline).
- Arc sweep: from angle `100°` to `170°` (CCW from +x). Note: `90°` is
  12 o'clock visual, `180°` is 9 o'clock visual — so this is a tight
  band sweeping from just left-of-top to just past 9 o'clock, hugging
  the upper-left of the bezel.
- `lineWidth = max(1.5, caseRadius * 0.040)` — wide. The sheen fills
  ~36% of the radial bezel thickness (which is `caseRadius * 0.11`).
- `strokeColor = (1.00, 1.00, 1.00, 0.18)` — soft. Lower alpha than
  Element 2's top-edge band so the two layers stack without going
  chalky.
- `lineCap = .round` — fades at the ends of the sweep.
- **No mask needed** beyond the natural lineWidth-bounded stroke (the
  arc itself doesn't extend past the bezel annulus).

**Stacking with Elements 2 and 21:**

The three sheen layers form a hierarchy:

| Layer                     | Where                  | Effect           |
|---------------------------|------------------------|------------------|
| El.21 ceramic sheen       | Full annulus, radial   | Area-light bloom |
| El.22 mid-arc sheen (NEW) | Bezel centerline arc   | Curved-surface highlight |
| El.2 top-edge band        | Outer-edge stroked arc | Rim catch-light  |

Together they give the bezel a clear "rounded ceramic lit from the
upper-left" reading instead of the flat appearance in Pass-1.

**Z-order:** above the black/red halves and the El.21 radial overlay,
below the top-edge highlight band (Element 2). The full bezel stack
becomes: black half → red half → El.21 radial sheen → **El.22 mid-arc
sheen (NEW)** → El.2 top-edge band → inner groove → ticks → numerals →
pip.

---

## Implementation order

When wiring this up, build top-down z-order so each element appears as
expected:

1. Canvas background (solid black, matches the screensaver host).
2. Vignette outside the case (optional, ambient).
3. Case top gradient (steel disc).
4. Brushed steel overlay (chamfer ring).
5. Bezel insert: black half → red half → ceramic sheen (Element 21) →
   **mid-arc sheen (Element 22, new Pass 2)** → top-edge highlight band →
   inner groove.
6. Bezel: tick marks at odd hours → numerals at even hours → triangle
   pip (with lume specular).
7. Polished chamfer ring + outer bezel rim + chamfer/rim glints.
8. Inner edge stroke (chamfer meets dial face).
9. Dial face fill → vignette → grain overlay.
10. Minute track: minor ticks → major ticks.
11. Hour markers: dots merged → bars merged → 12 triangle (all with
    lume specular).
12. Date window: frame (with gold specular) → white box → digit.
13. Hands: hour snowflake (with lume specular) → minute snowflake (with
    lume specular) → GMT hand (with gold specular) → seconds hand (with
    gold specular).
14. Center hub (with gold specular).

---

## Palette update summary

The following palette entries are defined fresh for CokeGMTPalette (no
reuse from AsymmetricMoonphasePalette — different design language):

| Constant                  | Value (sRGB tuple)                          | Notes                            |
|---------------------------|---------------------------------------------|----------------------------------|
| `caseSteel`               | `(0.78, 0.79, 0.82, 1.0)`                   | Mid steel tone                   |
| `caseSteelHighlight`      | `(0.96, 0.96, 0.97, 1.0)`                   | Polished bright edge             |
| `caseSteelShadow`         | `(0.34, 0.35, 0.38, 1.0)`                   | Deep case shadow *(Pass 2 — darkened from `(0.42, 0.43, 0.46)`)* |
| `bezelBlack`              | `(0.08, 0.08, 0.09, 1.0)`                   | Ceramic black base               |
| `bezelBlackHighlight`     | `(0.30, 0.30, 0.32, 1.0)`                   | Ceramic black top catch-light    |
| `bezelBlackShadow`        | `(0.02, 0.02, 0.03, 1.0)`                   | Ceramic black bottom shadow      |
| `bezelRed`                | `(0.62, 0.10, 0.10, 1.0)`                   | Ceramic red base — brick red     |
| `bezelRedHighlight`       | `(0.86, 0.20, 0.18, 1.0)`                   | Ceramic red top catch-light      |
| `bezelRedShadow`          | `(0.36, 0.05, 0.05, 1.0)`                   | Ceramic red bottom maroon shadow |
| `bezelNumeralCream`       | `(0.93, 0.86, 0.66, 1.0)`                   | Aged-lume cream on the bezel     |
| `dialBlack`               | `(0.045, 0.045, 0.050, 1.0)`                | Matte black dial                 |
| `lumeCream`               | `(0.95, 0.88, 0.68, 1.0)`                   | Hour markers + snowflake hands   |
| `lumeCreamOutline`        | `(0.76, 0.62, 0.36, 0.95)`                  | Marker/hand outline cream-gold   |
| `lumeSpecularHi`          | `(1.00, 0.96, 0.82, 0.40)`                  | Lume specular bright stop        |
| `lumeSpecularMid`         | `(1.00, 0.92, 0.74, 0.12)`                  | Lume specular mid stop           |
| `lumeSpecularLo`          | `(0.50, 0.36, 0.18, 0.25)`                  | Lume specular shadow stop        |
| `secondHandCream`         | `(0.92, 0.84, 0.62, 1.0)`                   | Seconds hand fill                |
| `gmtHandGold`             | `(0.88, 0.72, 0.40, 1.0)`                   | GMT hand fill — warmer gold      |
| `goldOutline`             | `(0.52, 0.38, 0.16, 0.95)`                  | GMT/seconds/hub edge stroke      |
| `goldSpecularHi`          | `(1.00, 0.92, 0.72, 0.55)`                  | Gold specular bright stop        |
| `goldSpecularMid`         | `(0.96, 0.82, 0.52, 0.22)`                  | Gold specular mid stop           |
| `goldSpecularLo`          | `(0.36, 0.22, 0.08, 0.35)`                  | Gold specular shadow stop        |
| `dateBoxWhite`            | `(0.96, 0.94, 0.88, 1.0)`                   | Warm cream-white date plate      |
| `dateNumeralBlack`        | `(0.04, 0.04, 0.05, 1.0)`                   | Date digit                       |
| `dateFrameGold`           | `(0.84, 0.66, 0.34, 1.0)`                   | Date frame fill (gold family)    |
| `ceramicSheenWhite`       | `(1.00, 1.00, 1.00, 0.20)`                  | Soft white peak on bezel sheen (Element 21) |
| `ceramicMidArcSheen`      | `(1.00, 1.00, 1.00, 0.18)`                  | Mid-arc directional sheen on bezel centerline (Element 22, new Pass 2) |
| `chamferShadow`           | `(0.20, 0.20, 0.22, 0.70)`                  | Inner edge dark stroke           |

---

## Notes on judgment calls

A few places where the reference is ambiguous and I made a confident
decision. The implementer can override any of these:

1. **Cream tone choice.** The reference photo has been color-graded by
   Tudor's photo team — the cream on the bezel numerals and on the
   markers might be slightly different in person. I've specified them
   IDENTICAL (`bezelNumeralCream` = the cream tone) and the lume hands
   in a slightly brighter cream (`lumeCream`) to give them a hierarchical
   pop. If they look too different, unify them.
2. **Red bezel saturation.** Tudor's "Coke" red varies between photo
   sets — I've gone with a *brick-red base* (`bezelRed = 0.62, 0.10,
   0.10`) that goes deep maroon in shadow. If it reads too dark on
   final render, push the base toward `(0.72, 0.12, 0.10)` and the
   highlight toward `(0.94, 0.24, 0.20)`.
3. **Snowflake hand color = lume cream, not silver.** This is a
   deliberate call — Tudor's modern Black Bay GMT family treats the
   snowflake hands as cream-lume-filled (matching the markers), unlike
   the polished-steel hands on other Tudor models. The reference
   confirms this. If the implementer prefers a more typical "polished
   steel snowflake" look, swap `lumeCream` for a steel color in the
   hour/minute hand fill only.
4. **GMT hand arrowhead — plain triangle vs chevron-notched.** I've
   recommended the plain triangle for v1 — the chevron-notch refinement
   is a Pass-2 polish.
5. **Bracelet/lugs/crown omitted.** Per the prompt — render the case as
   a disc. If the implementer wants to add lugs or a crown later,
   they're not blocked by this spec.
6. **No "MASTER CHRONOMETER" or "GMT" text on the dial.** Per the
   trademark-omit policy (D3 from Story 1.6), all brand and certification
   text is omitted from the rendered dial. Brand credit lives only in
   `credit.txt` and `DialIdentity.homageCredit`.
7. **Bezel insert sits flat (no bevel between insert and steel rim).**
   The reference shows the insert as essentially flush with the steel
   rim, with the polished chrome edge being the bezel rim's own metal,
   not a separate bevel. I've spec'd one polished rim stroke at the
   outer edge and a top-edge highlight band on the ceramic; together
   they give the impression of the insert sitting in a steel bezel
   without modeling a real bevel.
