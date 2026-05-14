# Asymmetric Moonphase — Design Spec

Implementation-grade design specification for the Lange 1 Moonphase homage dial.
Every value below is intended to become code in a single implementation pass.

**Coordinate convention:** Core Animation y-up. Positions expressed as
`(caseCenter.x + dialRadius * X, caseCenter.y + dialRadius * Y)`. Signs:
`+x` is right, `+y` is up. All lengths use `dialRadius` as the unit (NOT
`caseRadius`).

**Light source (global):** single soft area-light at the **upper-left,
approximately 45°** above the dial plane. Every drop shadow points
**lower-right** (positive shadowOffset.width, negative shadowOffset.height).
Every specular highlight sits at the **upper-left** of its element.
Every recessed edge darkens at the **upper rim** (light blocked by the lip)
and lightens at the **lower rim** (light bouncing off the well floor).

**Faceplate finish:** the main dial is **matte** with extremely fine
stippling. The three recessed sub-dials (main time, sub-seconds) are
**polished silver** — they get radial gloss. The sub-dial faces are NOT
flat — there is a barely-perceptible recess depth (~0.6% of dial radius
in virtual space, sold by gradient shading + perimeter shadow ring, not a
real Z-translation).

**Layout intent:** the four readouts are positioned so the dial looks
distinctly Lange-1 asymmetric, not a generic 3-counter chronograph:

- Main time (large) — center-LEFT, ~50% of dial radius
- Big date (two boxes) — TOP-RIGHT, abutting the main time at its
  upper-right corner
- Sub-seconds (small) — BOTTOM-RIGHT
- Power reserve (arc) — RIGHT edge, vertical span

---

## Element 1 — Case and bezel

The bezel is a **flat polished gold ring**, not a stepped/faceted ring.
The Lange 1 case is unusually slim and the bezel reads as a single
warm-gold band with a smooth vertical gradient.

- **Outer radius:** `caseRadius = min(canvas.width, canvas.height) * 0.425`
  (i.e. case diameter = 85% of the smaller canvas dimension; unchanged from
  current).
- **Inner edge (dial boundary):** `dialRadius = caseRadius * 0.93`
  (bezel thickness ≈ 7% of caseRadius — slimmer than current 12%; the Lange
  1 reference has a notably thin bezel).
- **Bezel fill — `CAGradientLayer` (linear, masked to ring):**
  - Direction: `startPoint = (0.30, 1.00)`, `endPoint = (0.70, 0.00)` —
    nearly vertical with a slight tilt that matches the upper-left light.
  - Colors + locations:
    - `0.00` → `NSColor(srgbRed: 0.98, green: 0.88, blue: 0.62, alpha: 1.0)`
      — bright top highlight (rename `caseGoldHighlight`).
    - `0.30` → `NSColor(srgbRed: 0.92, green: 0.76, blue: 0.45, alpha: 1.0)`
      — warm gold midtone.
    - `0.62` → `NSColor(srgbRed: 0.78, green: 0.60, blue: 0.32, alpha: 1.0)`
      — `caseGold` proper.
    - `1.00` → `NSColor(srgbRed: 0.42, green: 0.30, blue: 0.16, alpha: 1.0)`
      — deep bottom shadow (rename `caseGoldShadow`).
- **Outer rim highlight (silhouette pop):** a `CAShapeLayer` stroking the
  outer circle (radius = `caseRadius`).
  - `lineWidth = max(0.5, caseRadius * 0.004)`
  - `strokeColor = NSColor(srgbRed: 1.00, green: 0.94, blue: 0.78, alpha: 1.0)`
- **Inner lip (where bezel meets dial face):** a `CAShapeLayer` stroking
  the inner circle (radius = `dialRadius`).
  - `lineWidth = max(0.5, caseRadius * 0.007)`
  - `strokeColor = NSColor(srgbRed: 0.30, green: 0.20, blue: 0.10, alpha: 0.7)`
    — engraved-channel feel; partial transparency so it doesn't read as
    a stark line.
- **Z-order:** background → vignette → bezel fill → outer rim highlight →
  inner lip stroke → dial face.

---

## Element 2 — Dial faceplate

The Lange 1 dial is **matte silver/argenté with a very fine stippled
texture** (almost a fine pebble). It is NOT sunburst guilloché. No
specular highlights belong on the faceplate.

- **Shape:** filled circle, radius = `dialRadius`, centered at
  `caseCenter`.
- **Base color:** `NSColor(srgbRed: 0.945, green: 0.935, blue: 0.905,
  alpha: 1.0)` — slightly warmer silver than current. Replace
  `dialFace`.
- **Vignette overlay:** a `CAGradientLayer` of type `.radial` masked to
  the dial circle, applied as a subtle inner darkening at the perimeter.
  - `startPoint = (0.45, 0.55)`, `endPoint = (1.05, 1.05)` (centered
    slightly upper-left to bias toward the light).
  - Colors:
    - `0.00` → `NSColor(white: 1.0, alpha: 0.06)` — barely brighter at
      the light source.
    - `0.70` → `NSColor(white: 1.0, alpha: 0.0)` — neutral.
    - `1.00` → `NSColor(srgbRed: 0.55, green: 0.50, blue: 0.40, alpha:
      0.18)` — warm shadow at the bezel transition.
- **Stippling texture (optional but recommended):** a `CALayer` at the
  faceplate position with `backgroundColor = .clear` and a single
  noise-pattern `CGImage` as its `contents`, `opacity = 0.06`. Generate
  the pattern once at attach time by filling a 256×256 buffer with
  small low-contrast dots (use `CIRandomGenerator` or a manual stipple).
  If the implementation skips this, the dial still reads as matte
  because there's no specular highlight on it.
- **Z-order:** dial face → vignette overlay → (stippling) → all
  sub-dial layers above.

---

## Element 3 — Main time sub-dial (recessed silver)

The main time dial occupies the left half of the watch. It is **recessed
into the plate** — confirmed. It has a **polished silver** finish (so it
DOES get a soft radial highlight, but a gentle one — this is not a
sunburst-bright sub-dial, it's a flat polished plate that's barely
brighter than the main faceplate).

- **Center:** `(caseCenter.x + dialRadius * -0.18, caseCenter.y +
  dialRadius * 0.00)` — shift the sub-dial LEFT and keep it on the
  horizontal midline. Current value of `-0.13, -0.05` looks slightly
  high-left; adjust to centered-left.
- **Radius:** `mainTimeRadius = dialRadius * 0.55` — grow slightly from
  current 0.50. The reference's main time dial is **more than half** the
  case width.
- **Face fill:** `NSColor(srgbRed: 0.965, green: 0.955, blue: 0.925,
  alpha: 1.0)` — a hair lighter than the main dial.
- **Recess shading (inner edge):**
  Two ring strokes built as `CAShapeLayer`s stroking the face circle —
  these together sell the recess depth without a gold rim:
  - **Upper-rim shadow (the dark crescent at the top of the well):**
    a CAShapeLayer with `path = ellipseIn(faceRect)`, `lineWidth =
    max(0.6, mainTimeRadius * 0.020)`, `strokeColor = NSColor(srgbRed:
    0.55, green: 0.50, blue: 0.40, alpha: 0.65)`. Use `shadowOffset =
    (0, -mainTimeRadius * 0.010)`, `shadowRadius = mainTimeRadius *
    0.010`, `shadowOpacity = 0.6`, `shadowColor = .black`. The shadow
    blooms downward, simulating the lip blocking the light.
  - **Lower-rim highlight (bounce light):** a second CAShapeLayer
    stroking the same circle, `lineWidth = max(0.4, mainTimeRadius *
    0.012)`, `strokeColor = NSColor(white: 1.0, alpha: 0.45)`,
    `shadowOpacity = 0`. Mask this layer with a half-disc covering only
    the lower 40% of the face so the highlight reads as a faint moon
    along the bottom of the well — NOT a full ring.
- **Recess gradient (depth fill):** Keep the existing
  `mainTimeRecessShade` `CAGradientLayer` but soften:
  - `startPoint = (0.5, 1.0)`, `endPoint = (0.5, 0.0)`
  - Colors / locations:
    - `0.0` → `NSColor(white: 0.0, alpha: 0.13)` (top of well = darker)
    - `0.55` → `NSColor(white: 0.0, alpha: 0.0)`
    - `1.0` → `NSColor(white: 1.0, alpha: 0.06)` (faint bottom bounce)
- **Polished sheen (`mainTimeGlossLayer`):**
  - Type `.radial`.
  - `startPoint = (0.32, 0.78)`, `endPoint = (0.95, 0.20)` — centered
    upper-left.
  - Colors / locations:
    - `0.0` → `NSColor(white: 1.0, alpha: 0.18)` — reduced from current
      0.45 (the reference's polished silver is subtle, not chrome).
    - `0.45` → `NSColor(white: 1.0, alpha: 0.06)`
    - `1.0` → `NSColor(white: 1.0, alpha: 0.0)`
- **Z-order within main time:** face fill → recess gradient → gloss
  highlight → upper-rim shadow → lower-rim highlight → ticks → markers
  → numerals → hands → hub.

---

## Element 4 — Hour markers (raised gold lozenges)

**Count:** 8 lozenges at the non-cardinal hours (1, 2, 4, 5, 7, 8, 10,
11). Confirmed by user. The four cardinals (12, 3, 6, 9) use Roman
numerals instead — see Element 5.

The lozenge in the reference is a **slender vertical diamond**, longer
than it is wide, with a slight bias toward elongation (height ≈ 2.8 ×
width). It is polished gold with crisp facet edges.

- **Radial center position:** `markerCenterR = mainTimeRadius * 0.86`
  (current 0.92 places them at the perimeter where they fight the
  numerals; pull them inward).
- **Lozenge silhouette** — in marker-local coords where the marker is
  axis-aligned along the radial direction, with the radial axis = local
  +y:
  - `markerLong = mainTimeRadius * 0.085` (full radial length)
  - `markerWide = mainTimeRadius * 0.030` (perpendicular width)
  - Four vertices, traversed clockwise starting at outer tip:
    - `(0, +markerLong/2)`        — outer point
    - `(+markerWide/2, 0)`        — right shoulder
    - `(0, -markerLong/2)`        — inner point
    - `(-markerWide/2, 0)`        — left shoulder
  - Closed subpath. Rotate by `theta = π/2 - (i/12) * 2π` so the long
    axis points radially outward from the sub-dial center.
- **Fill:** `NSColor(srgbRed: 0.86, green: 0.68, blue: 0.36, alpha:
  1.0)` — `handGold` (matches hand color so all "applied gold"
  components share the same alloy).
- **Edge stroke (3D facet cue):**
  - `strokeColor = NSColor(srgbRed: 0.42, green: 0.28, blue: 0.12,
    alpha: 1.0)`
  - `lineWidth = max(0.3, mainTimeRadius * 0.0035)`
- **Drop shadow (raised feel):**
  - `shadowColor = .black`
  - `shadowOffset = (0.6, -0.6)` — lower-right (light from upper-left)
  - `shadowOpacity = 0.45`
  - `shadowRadius = 1.2`
  - `shadowPath = markersPath` (already in current code).
- **Highlight stroke (optional, +20% realism):** a second
  `CAShapeLayer` with the same path stroked at `lineWidth = 0.4`,
  `strokeColor = NSColor(white: 1.0, alpha: 0.55)`, with a translation
  of `(-0.3, 0.3)` (upper-left) applied to the layer transform. This
  fakes a top edge highlight on each marker.
- **Z-order:** ABOVE recess shading / gloss / rim strokes. BELOW the
  hands and the moonphase aperture.

---

## Element 5 — Roman numerals (XII, III, VI, IX) — raised gold

The four cardinals are **raised gold serif Romans** — confirmed by user.
The reference detail shot shows them as small, elegant, somewhat narrow
serifs with serif feet that catch light.

- **Font:** `NSFont(name: "BodoniSvtyTwoITCTT-Book", size: ...)` — Bodoni
  72 Book gives the slim Lange-1 serif feel. Fall back chain (already in
  code) for `Didot` and Times New Roman. **Use the Book/Regular weight,
  not Bold** — the reference numerals are slim, not blocky.
- **Size:** `mainTimeRadius * 0.13` (slightly smaller than current 0.16
  — the reference numerals are notably smaller than the lozenge length).
- **Radial position:** `romanRadius = mainTimeRadius * 0.86` — same
  radius as the lozenges so they sit on the same circle. Important:
  the Lange 1 places markers and Romans on a single circle.
- **Angles** (Core Animation y-up; counterclockwise from +x):
  - XII → `π/2`
  - III → `0`
  - VI  → `-π/2`
  - IX  → `π`
- **Glyph anchoring:** translate each glyph path so the glyph's
  `boundingBox.midX, .midY` lands at the radial position (current
  code does this; keep it).
- **Fill:** `handGold` — `NSColor(srgbRed: 0.86, green: 0.68, blue:
  0.36, alpha: 1.0)`.
- **Edge stroke:** `lineWidth = 0.35`, `strokeColor = NSColor(srgbRed:
  0.42, green: 0.28, blue: 0.12, alpha: 1.0)`.
- **Drop shadow:**
  - `shadowOffset = (0.6, -0.8)`
  - `shadowOpacity = 0.45`
  - `shadowRadius = 1.2`
  - `shadowPath = romansPath`

---

## Element 6 — Minute track

The Lange 1 has a **minute track of 60 thin hairline ticks**, all the
same length. There is no 5-second major-tick variation — the lozenges
and Romans serve as the hour majors.

- **Tick count:** 60. **Skip the 4 cardinal positions (0, 15, 30, 45) —
  they're occupied by Roman numerals. Skip the 8 lozenge positions —
  they're occupied by markers.** So actually emit ticks at all
  `i ∈ [0, 60)` where `i % 5 != 0` (current code does this — keep it).
  Then also emit small EXTRA hairline ticks at the 5/10/20/25/35/40/50/55
  positions (between lozenges and Romans? — NO, those are where the
  lozenges are at 12-hour ticks). Wait: `i % 5 != 0` already gives 48
  ticks at every minute except hour positions. That's correct.
- **Tick geometry:**
  - `outer = mainTimeRadius * 0.985` (very close to the perimeter)
  - `inner = mainTimeRadius * 0.955`
  - `lineWidth = max(0.4, mainTimeRadius * 0.012)` — reduce from current
    0.020 (the reference hairlines are very thin).
  - `lineCap = .butt` (NOT round — the reference ticks are crisp printed
    hairlines).
  - `strokeColor = NSColor(srgbRed: 0.12, green: 0.10, blue: 0.08,
    alpha: 0.92)` — near-black, slightly translucent.
- **Treatment:** these are **printed** ticks (no drop shadow).

---

## Element 7 — Hour + minute hands

Confirmed solid gold (no hollow lozenge). The Lange 1 hand silhouette is
a **lance** with these features:
- A small **counterweight tail** behind the pivot (about 20% of forward
  length).
- A **slim straight shaft** rising from the pivot.
- A **broad symmetric lozenge** that fills the middle ~40% of the
  forward length, peaking at ~65% of forward length.
- A **needle tip** beyond the lozenge.
- **No pivot eye** on either hand (confirmed via the detail reference —
  the pivot is just the gold dot of the hub; there's no visible hole).
  → Implementation: pass `withHole: false` for both hour and minute
  hands.

The hand path is constructed in hand-local coordinates where the layer's
`bounds.size = (width, length * (1 + tailFraction))`, `anchorPoint =
(0.5, tailFraction / (1 + tailFraction))`. Pivot at the anchorPoint.

**Proportions (fractions of input `width` and `length`):**

| Property              | Value             |
|-----------------------|-------------------|
| `tailFraction`        | 0.20              |
| `shaftWidth`          | `width * 0.18`    |
| `tailWidth` (peak)    | `width * 0.55`    |
| `diamondPeakWidth`    | `width * 1.0`     |
| `tailPeakY`           | `tailL * 0.55`    |
| `diamondStartY`       | `tailL + length * 0.42` |
| `diamondPeakY`        | `tailL + length * 0.66` |
| `tipNarrowY`          | `tailL + length * 0.92` |
| `tipY`                | `tailL + length`  |

**Vertex sequence (centerline at `cx = width / 2`):**

1. `(cx, 0)` — counterweight tail point.
2. `(cx + tailW/2, tailPeakY)` — tail-right shoulder.
3. `(cx + shaftW/2, tailL)` — pivot shoulder right.
4. `(cx + shaftW/2, diamondStartY)` — shaft top right (lozenge base).
5. `(cx + diamondW/2, diamondPeakY)` — lozenge right peak.
6. `(cx + shaftW/3, tipNarrowY)` — pre-tip right.
7. `(cx, tipY)` — tip.
8. `(cx - shaftW/3, tipNarrowY)` — pre-tip left.
9. `(cx - diamondW/2, diamondPeakY)` — lozenge left peak.
10. `(cx - shaftW/2, diamondStartY)` — shaft top left.
11. `(cx - shaftW/2, tailL)` — pivot shoulder left.
12. `(cx - tailW/2, tailPeakY)` — tail-left shoulder.
13. Close back to (1).

**Hour hand size:**
- `length = mainTimeRadius * 0.50`
- `width = mainTimeRadius * 0.12`

**Minute hand size:**
- `length = mainTimeRadius * 0.78`
- `width = mainTimeRadius * 0.08`

**Fill:** `handGold = NSColor(srgbRed: 0.86, green: 0.68, blue: 0.36,
alpha: 1.0)`.

**Edge stroke (subtle facet definition):**
- `strokeColor = NSColor(srgbRed: 0.42, green: 0.28, blue: 0.12, alpha:
  1.0)`
- `lineWidth = max(0.3, mainTimeRadius * 0.0035)`

**Drop shadow:**
- `shadowColor = .black`
- `shadowOpacity = 0.40`
- `shadowOffset = (1.2, -1.8)` — clearly lower-right; hands sit on top
  of the dial and should cast a longer shadow than the markers.
- `shadowRadius = 2.5`
- `shadowPath = handPath` (avoids the alpha-channel shadow path).

**Highlight overlay (optional but strongly recommended):**
add a second `CAShapeLayer` overlaying the hand with the same path, but
filled with a vertical gradient via `CAGradientLayer` masked to that
shape:
- `colors = [NSColor(white: 1.0, alpha: 0.30), NSColor(white: 1.0,
  alpha: 0.0)]`
- `startPoint = (0.30, 1.0)`, `endPoint = (0.7, 0.0)`
This fakes the upper-half polished gleam.

**Z-order:** hour below minute. Both above moonphase aperture frame.
Both below the center hub.

---

## Element 8 — Center hub

A small gold dot at the pivot. Single solid filled circle, no detail.

- **Position:** `mainTimeCenter` (the pivot point).
- **Radius:** `mainTimeRadius * 0.040` (reduced from current 0.05 — the
  reference hub is small).
- **Fill:** `handGold`.
- **Edge stroke:** `lineWidth = 0.4`, `strokeColor = NSColor(srgbRed:
  0.42, green: 0.28, blue: 0.12, alpha: 1.0)`.
- **Drop shadow:** `shadowOffset = (0.5, -0.6)`, `shadowOpacity = 0.45`,
  `shadowRadius = 1.0`.
- **Z-order:** above both hands.

---

## Element 9 — Moonphase aperture

The aperture is a **wide horizontal oval** with **two subtle scallops**
nibbling up from the bottom. The shape is asymmetric: the top is one
broad arch; the bottom is broken into three flat segments separated by
two upward-curving cuts.

The aperture sits **above the hands' pivot, biased toward the upper half
of the main time sub-dial**.

- **Center position (baseline-center of the aperture):**
  `(mainTimeCenter.x, mainTimeCenter.y + mainTimeRadius * 0.36)` —
  slightly higher than current (0.34 → 0.36) so the aperture clears the
  hands.
- **Half-width:** `apertureHalfWidth = mainTimeRadius * 0.36`.
- **Half-height (i.e. the full height of the upper arch above the
  baseline):** `apertureHalfHeight = apertureHalfWidth * 0.58` — slightly
  taller than current 0.55, matching the reference's noticeable arch.

The aperture path is constructed in canvas coordinates. Define
`leftX = cx - hw`, `rightX = cx + hw`, `baseY = aperture baseline y`,
`topY = baseY + hh`.

**Upper arch (two cubic Beziers, magic constant κ = 0.5522847498307933):**

1. Move to `(leftX, baseY)`.
2. Curve to `(cx, topY)` with controls:
   - `c1 = (leftX, baseY + hh * κ)`
   - `c2 = (cx - hw * κ, topY)`
3. Curve to `(rightX, baseY)` with controls:
   - `c1 = (cx + hw * κ, topY)`
   - `c2 = (rightX, baseY + hh * κ)`

**Bottom (right-to-left, with two scallop cuts):**

Define scallop geometry:
- `hillHalfWidth = hw * 0.30` (each scallop's footprint = `2 *
  hillHalfWidth` along the baseline)
- `hillGap = hw * 0.12` (distance from center to nearest scallop edge)
- `hillHeight = hh * 0.22` (peak rise into the aperture, slightly higher
  than current 0.18)
- `controlYOffset = hillHeight * 2.0` (control-point lift for the
  quadratic Bezier; the peak ends up at half the control rise)

Then:

4. Line to `(rightHillRight, baseY)` where
   `rightHillRight = cx + hillGap + 2 * hillHalfWidth`.
5. Quadratic curve to `(rightHillLeft = cx + hillGap, baseY)` with
   control `((rightHillLeft + rightHillRight)/2, baseY + controlYOffset)`.
6. Line to `(leftHillRight = cx - hillGap, baseY)`.
7. Quadratic curve to `(leftHillLeft = cx - hillGap - 2 * hillHalfWidth,
   baseY)` with control `((leftHillLeft + leftHillRight)/2, baseY +
   controlYOffset)`.
8. Line back to `(leftX, baseY)`.
9. Close subpath.

**Gold rim around the aperture:**
- A `CAShapeLayer` stroking the aperture path.
- `strokeColor = handGold`
- `fillColor = nil`
- `lineWidth = max(0.6, apertureHalfWidth * 0.055)`
- Drop shadow: `shadowOffset = (0.6, -0.6)`, `shadowOpacity = 0.5`,
  `shadowRadius = 1.0`, `shadowColor = .black`, `shadowPath = the
  aperturePath` (cheap, since this is fill=nil it's a hollow shape — but
  CALayer.shadow honors stroke).

**Sky fill (inside the aperture):**
- A `CAShapeLayer` filled with the aperture path.
- `fillColor = moonSky = NSColor(srgbRed: 0.09, green: 0.14, blue: 0.30,
  alpha: 1.0)` — a deep midnight blue, very slightly less purple than
  current.

**Z-order:** sky → stars → (moving moon disc + face inside masked
container) → gold rim frame on top.

---

## Element 10 — Moon disc + face

The moon disc is **gold, solid, with a smiling face** (man-in-the-moon)
of two eyes and a curved mouth, all in a darker bronze.

- **Disc radius:** `discR = apertureHalfHeight * 0.72` — large enough
  that the disc nearly touches the top of the upper arch but leaves
  visible navy on left/right at the "full moon" position.
- **At "full moon" (fraction = 0.5), the disc center is at:**
  `(apertureRect.midX, apertureRect.minY + apertureHalfHeight * 0.58)`
  in canvas coordinates. (In the existing implementation this is
  computed in container-local coordinates — unchanged.)
- **Translation range (sliding past the aperture):**
  - At `fraction = 0`: `dx = +(apertureHalfWidth + discR)` (moon
    offscreen-right).
  - At `fraction = 1`: `dx = -(apertureHalfWidth + discR)` (moon
    offscreen-left).
  - Linear interpolation: `dx = (apertureHalfWidth + discR) * (1 - 2 *
    fraction)`. (Already in code.)
- **Moon disc fill:** `NSColor(srgbRed: 0.95, green: 0.82, blue: 0.50,
  alpha: 1.0)` — `moonGold`.
- **Moon disc edge stroke:** none (the face details supply enough
  definition; an edge stroke would clash with the gold-on-gold of the
  rim frame).
- **Drop shadow on the disc:** none. It would clip strangely against
  the aperture mask; the disc reads as flat-printed.

**Man-in-the-moon face (in disc-local coords, disc center = origin,
radius = discR):**

- **Left eye:** filled circle, center = `(-discR * 0.30, +discR * 0.18)`,
  radius = `discR * 0.07`.
- **Right eye:** filled circle, center = `(+discR * 0.30, +discR *
  0.18)`, radius = `discR * 0.07`.
- **Smile (open arc):** `addArc(center: (0, +discR * 0.30), radius:
  discR * 0.38, startAngle: -π * 0.85, endAngle: -π * 0.15,
  clockwise: false)`. This produces a downward-opening crescent below
  the eyes — a classic smile. **Stroke**, not fill.
  - `strokeColor = NSColor(srgbRed: 0.55, green: 0.36, blue: 0.16,
    alpha: 1.0)` — bronze, definitely darker than `moonGold`.
  - `lineWidth = max(0.6, discR * 0.07)`
  - `lineCap = .round`
- **Eye fill color:** same bronze as smile stroke.

---

## Element 11 — Stars in moonphase sky

Small four-pointed stars dotting the navy aperture, visible at the
edges when the moon is at full or near-full phase.

- **Count:** 8 stars (current count is fine).
- **Star shape:** 4-pointed star with `outerRadius / innerRadius = 2.5`
  (current uses 2.5 — `outer = hw * 0.05`, `inner = outer * 0.40`).
  Keep `outer = apertureHalfWidth * 0.05`.
- **Color:** `starGold = NSColor(srgbRed: 1.00, green: 0.92, blue: 0.62,
  alpha: 1.0)` — brighter than the moon disc so they pop against navy.
- **Positions** (normalized: `fx ∈ [-1, +1]` across half-width;
  `fy ∈ [0, 1]` across full aperture height):

  | fx     | fy   |
  |--------|------|
  | -0.85  | 0.40 |
  | -0.62  | 0.75 |
  | -0.45  | 0.20 |
  | -0.92  | 0.18 |
  |  0.45  | 0.22 |
  |  0.62  | 0.78 |
  |  0.85  | 0.40 |
  |  0.92  | 0.20 |

  Convert to canvas coords: `sx = apertureRect.midX + fx *
  apertureHalfWidth`, `sy = apertureRect.minY + fy *
  apertureHalfHeight`.
- **No drop shadow** on stars (they're printed/painted onto the sky).
- **Z-order:** above sky, below the moving moon disc.

---

## Element 12 — Navy sky color (already covered)

`NSColor(srgbRed: 0.09, green: 0.14, blue: 0.30, alpha: 1.0)`. Replace
existing `moonSky`. The current `(0.10, 0.16, 0.32)` is slightly too
desaturated; this value is closer to the reference's deep midnight.

---

## Element 13 — Big date window (two boxes)

Confirmed: **TWO separate gold-framed white boxes** for the Lange 1
variant. (The Grand Lange 1 in the secondary reference uses one frame;
we target the regular Lange 1.)

- **Box center (midpoint between the two boxes):**
  `(caseCenter.x + dialRadius * 0.30, caseCenter.y + dialRadius * 0.42)`
  — adjust slightly right and slightly lower than current to clear the
  main time sub-dial's upper-right edge.
- **Box height:** `boxH = dialRadius * 0.17`.
- **Box width (each):** `boxW = boxH * 0.78`.
- **Gap between boxes:** `gap = boxH * 0.04`.
- **Corner radius (interior white boxes):** `boxH * 0.06` — barely
  rounded; the reference is rectilinear.
- **Gold frame inset (frame extends beyond the box):**
  `frameInset = boxH * 0.045`. Frame corner radius = `boxH * 0.06 +
  frameInset`.
- **Frame fill:** `handGold`. Frame edge stroke: `strokeColor =
  NSColor(srgbRed: 0.42, green: 0.28, blue: 0.12, alpha: 1.0)`,
  `lineWidth = max(0.4, boxH * 0.010)`.
- **Frame drop shadow** (makes the frame look applied/raised — the
  reference frame is a physical gold rim):
  - `shadowOffset = (0.8, -1.2)`
  - `shadowOpacity = 0.50`
  - `shadowRadius = 1.6`
  - `shadowColor = .black`
- **Inner white box fill:** `dateBackground = NSColor(srgbRed: 1.00,
  green: 0.99, blue: 0.96, alpha: 1.0)` — keep.
- **Inner white box subtle inner shadow:** add a 1-px dark stroke
  at the inner box edge (`strokeColor = NSColor(white: 0.0, alpha:
  0.15)`, `lineWidth = 0.5`) to ground the frame.
- **Separator between boxes:** keep current thin vertical line, but
  move it INTO each box (the reference has each digit own its box; the
  "separator" is really just the gap between two gold frames). Set
  separator alpha to 0 — remove it entirely. The gap + the two gold
  frame edges already provide the visual separation.
- **Digit font:** prefer `NSFont(name: "Didot-Bold", size:
  boxH * 0.82)`. Fall-back chain (in priority order):
  1. `Didot-Bold`
  2. `BodoniSvtyTwoITCTT-Bold`
  3. `Bodoni 72 Bold`
  4. `TimesNewRomanPS-BoldMT`
  5. System serif bold.
- **Digit color:** `dateNumeral = NSColor(srgbRed: 0.05, green: 0.04,
  blue: 0.03, alpha: 1.0)` — near-black.
- **Digit drop shadow** (digits sit physically on the white plate
  beneath the gold frame):
  - `shadowOffset = (0.5, -0.8)`
  - `shadowOpacity = 0.30`
  - `shadowRadius = 0.8`
- **Z-order:** gold frame → white box → digits.

---

## Element 14 — Sub-seconds dial

Recessed silver, same treatment recipe as the main time dial, just
smaller.

- **Center:** `(caseCenter.x + dialRadius * 0.32, caseCenter.y +
  dialRadius * -0.40)` — slight tweak right + slight tweak up vs
  current (0.30, -0.45), so the dial doesn't crowd the bottom edge.
- **Radius:** `subSecondsRadius = dialRadius * 0.22` (grown from
  current 0.20 — the reference sub-seconds is more prominent).
- **Face fill:** `subDialFace` — same color as main time.
- **Recess shading:** copy the main time treatment (upper-rim shadow +
  lower-rim highlight strokes, recess gradient, polished gloss radial)
  with scaled radii.
- **Perimeter boundary:** a single thin shadow stroke at the face
  perimeter. `lineWidth = max(0.4, subSecondsRadius * 0.020)`,
  `strokeColor = NSColor(srgbRed: 0.55, green: 0.50, blue: 0.40, alpha:
  0.7)`.
- **Tick marks (60 minute ticks):**
  - `outer = subSecondsRadius * 0.95`
  - Major (every 5th, i.e. 0, 5, …, 55): `inner = subSecondsRadius *
    0.80`, `lineWidth = max(0.5, subSecondsRadius * 0.030)`.
  - Minor (other 48): `inner = subSecondsRadius * 0.88`, `lineWidth =
    max(0.3, subSecondsRadius * 0.018)`.
  - **Two separate `CAShapeLayer`s** — one for majors, one for minors —
    so the line widths can differ. (Current code merges them, losing
    the major/minor distinction.)
  - `strokeColor = subDialNumeral`.
- **Arabic numerals at 60 / 10 / 20 / 30 / 40 / 50:**
  - Font: `serifFont(size: subSecondsRadius * 0.22, bold: false)`.
  - Radius: `subSecondsRadius * 0.68` (slightly inset from current 0.70
    so the numerals don't crowd the major ticks).
  - Position: at angles `π/2 - (i/6) * 2π` for `i = 0..5` (i=0 → "60"
    at top, then proceed clockwise).
  - Color: `subDialNumeral = NSColor(srgbRed: 0.20, green: 0.16, blue:
    0.10, alpha: 1.0)`. **No** drop shadow — these are printed.
- **Z-order:** face → recess → gloss → rim shadow → minor ticks → major
  ticks → numerals → seconds hand → hub.

---

## Element 15 — Sub-seconds hand

A **slim gold needle, no counterweight tail.** Confirmed — the reference
detail shot shows the seconds hand as a straight slim taper without a
visible tail behind the hub.

- **Length:** `subSecondsRadius * 0.85`.
- **Width:** `subSecondsRadius * 0.06` (slimmer than current 0.07 — the
  reference is a very thin needle).
- **Hand-local path (anchorPoint = (0.5, 0.0), pivot at (cx, 0)):**

  - `cx = width / 2`
  - `baseHalf = width * 0.45`
  - Path:
    1. Move to `(cx - baseHalf, 0)`.
    2. Line to `(cx + baseHalf, 0)`.
    3. Line to `(cx + baseHalf * 0.40, length * 0.88)`.
    4. Line to `(cx, length)`.
    5. Line to `(cx - baseHalf * 0.40, length * 0.88)`.
    6. Close.

- **Fill:** `handGold`.
- **Edge stroke:** `lineWidth = 0.3`, `strokeColor = NSColor(srgbRed:
  0.42, green: 0.28, blue: 0.12, alpha: 1.0)`.
- **Drop shadow:** `shadowOffset = (0.6, -0.8)`, `shadowOpacity = 0.35`,
  `shadowRadius = 1.0`.
- **Hub:** small gold disc, radius = `subSecondsRadius * 0.06`. Same
  treatment as the main time hub (drop shadow, slight stroke).

---

## Element 16 — Power reserve indicator

The Lange 1's power reserve is a **tall vertical arc** on the right
edge, opening toward the dial center. Red triangular markers point
**inward** at each end (toward the AUF and AB labels), and the indicator
hand sweeps between them.

- **Arc pivot center:** `(caseCenter.x + dialRadius * 0.62, caseCenter.y
  + dialRadius * -0.05)` — adjust slightly right vs current 0.55 to push
  the arc closer to the case edge.
- **Arc radius:** `powerReserveRadius = dialRadius * 0.32`.
- **Arc angular span:** `arcSpan = π / 2.4 ≈ 75°` — slightly tighter
  than current 82°, matching the reference's narrower visual span.
  - `aufAngle = +arcSpan / 2` (upper-right of pivot)
  - `abAngle  = -arcSpan / 2` (lower-right of pivot)
- **Tick count:** `8` segments (9 ticks). Major ticks at i=0, 4, 8
  (i.e. AUF, midpoint, AB). Minor ticks at i=1, 2, 3, 5, 6, 7.
- **Major ticks:**
  - `outer = powerReserveRadius * 1.00`
  - `inner = powerReserveRadius * 0.82`
  - `lineWidth = max(0.5, powerReserveRadius * 0.030)`
  - `strokeColor = subDialNumeral`
- **Minor ticks:**
  - `outer = powerReserveRadius * 1.00`
  - `inner = powerReserveRadius * 0.92`
  - `lineWidth = max(0.3, powerReserveRadius * 0.014)`
  - `strokeColor = NSColor(srgbRed: 0.40, green: 0.34, blue: 0.22,
    alpha: 0.7)` — lighter than the major.
  - Use **two separate `CAShapeLayer`s** so widths/colors can differ.
- **Red triangles at AUF and AB:**
  - These point **outward** from the pivot — away from the dial center
    — sitting just past the outer tick.
  - Size: `triR = powerReserveRadius * 0.085` (current 0.10 is slightly
    too large).
  - Color: `powerReserveRed = NSColor(srgbRed: 0.80, green: 0.16, blue:
    0.14, alpha: 1.0)` — slightly more saturated red.
  - Geometry: tip at `(pivot + (radius + triR * 0.9) * unit(angle))`,
    base corners at `(pivot + radius * unit(angle)) ± (triR/2 *
    perp(angle))`.
- **AUF / AB labels:**
  - Font: `serifFont(size: powerReserveRadius * 0.18, bold: false)` —
    slightly smaller than current 0.22 to match reference proportions.
  - Position: `labelInner = powerReserveRadius * 0.60`, located along
    the same angle as the tick they label (so AUF is at angle
    `+arcSpan/2`, AB at `-arcSpan/2`, both translated INSIDE the arc
    toward the pivot).
  - Color: `subDialNumeral`.
  - **No** drop shadow (printed).
- **Indicator hand:**
  - This is a **slim lance with a small tail** (it's a hand, not a
    needle — confirmed in the reference detail shot — but its lozenge
    is much shorter than the time hands).
  - Length: `powerReserveRadius * 0.82` (slightly longer than current
    0.74; the hand in the reference reaches close to the outer ticks).
  - Width: `powerReserveRadius * 0.14` (slimmer than current 0.18).
  - Use the same `goldHandPath(taper: true, withHole: false)`
    constructor as the time hands.
  - Fill `handGold`, edge stroke as for the time hands.
  - Drop shadow: `shadowOffset = (0.8, -1.0)`, `shadowOpacity = 0.40`,
    `shadowRadius = 1.5`.
- **Hand rotation logic:** target angle (in standard CCW-from-+x) =
  `abAngle + fraction * (aufAngle - abAngle)`. The hand's intrinsic
  forward direction is +y (angle π/2). Rotation applied =
  `targetAngle - π/2` (counterclockwise positive). Current
  implementation is correct.
- **No power reserve hub disc** — the reference has the hand pivoting
  off the right edge with no visible center cap (the pivot lives behind
  the bezel). Implementation: omit any hub circle here.
- **Z-order:** minor ticks → major ticks → red triangles → labels →
  indicator hand.

---

## Element 17 — Lighting model summary

- **Light source:** soft area light at the upper-left, ~45° elevation.
- **Shadow direction:** lower-right. All drop shadow offsets follow
  `(+w, -h)` with `w, h > 0`.
- **Shadow magnitudes by element role** (rough guidance):

  | Role                              | offset       | opacity | radius |
  |-----------------------------------|--------------|---------|--------|
  | Hour markers, Romans, hub         | `(0.6, -0.6)`| 0.45    | 1.2    |
  | Hands (sit higher off the plate)  | `(1.2, -1.8)`| 0.40    | 2.5    |
  | Date frame (sits higher)          | `(0.8, -1.2)`| 0.50    | 1.6    |
  | Date digits (recessed in box)     | `(0.5, -0.8)`| 0.30    | 0.8    |
  | Power reserve hand                | `(0.8, -1.0)`| 0.40    | 1.5    |
  | Gold aperture rim                 | `(0.6, -0.6)`| 0.50    | 1.0    |

- **Highlight position (where each polished sub-dial gloss peaks):**
  normalized `(0.32, 0.78)` in the sub-dial's local space (upper-left).
- **Recess upper-rim shadow direction:** the dark crescent lives at
  `(0.5, 1.0)` in local space (top center) and fades downward — the
  light blocked by the lip is blocked at the top of the well.
- **Recess lower-rim bounce-light:** lives at `(0.5, 0.0)` (bottom
  center), faint warm reflection.
- **Matte faceplate:** receives zero specular highlight. Only the
  vignette gradient is applied.

---

## Implementation order

When wiring this up, build top-down z-order so each element appears as
expected:

1. Canvas background.
2. Vignette overlay.
3. Bezel ring (gradient + outer rim highlight + inner lip).
4. Dial face (matte silver + vignette).
5. Main time sub-dial face + recess + gloss + rim strokes.
6. Main time minute ticks.
7. Main time hour lozenges (with shadows).
8. Main time Roman numerals (with shadows).
9. Moonphase: sky (clipped) → stars (clipped) → moving disc + face
   (clipped to stationary aperture mask) → gold rim frame.
10. Hands: hour → minute (both above the moonphase rim).
11. Center hub (top of stack at sub-dial level).
12. Sub-seconds: face → recess → gloss → rim → minor ticks → major
    ticks → numerals → hand → hub.
13. Big date: gold frames → white boxes → digits.
14. Power reserve: minor ticks → major ticks → red triangles → labels →
    indicator hand.

---

## Palette update summary

The following palette entries should change from their current values:

| Constant                    | New value                                    |
|-----------------------------|----------------------------------------------|
| `caseGold`                  | `(0.78, 0.60, 0.32, 1.0)`                    |
| `caseGoldHighlight`         | `(0.98, 0.88, 0.62, 1.0)`                    |
| `caseGoldShadow`            | `(0.42, 0.28, 0.12, 1.0)`                    |
| `caseRim`                   | `(1.00, 0.94, 0.78, 1.0)`                    |
| `dialFace`                  | `(0.945, 0.935, 0.905, 1.0)`                 |
| `subDialFace`               | `(0.965, 0.955, 0.925, 1.0)`                 |
| `subDialShadow`             | `(0.55, 0.50, 0.40, 0.7)`                    |
| `handGold`                  | `(0.86, 0.68, 0.36, 1.0)`                    |
| `numeralBlack`              | `(0.12, 0.10, 0.08, 0.92)`                   |
| `moonSky`                   | `(0.09, 0.14, 0.30, 1.0)`                    |
| `moonGold`                  | `(0.95, 0.82, 0.50, 1.0)`                    |
| `moonFaceBronze` (new)      | `(0.55, 0.36, 0.16, 1.0)`                    |
| `starGold`                  | `(1.00, 0.92, 0.62, 1.0)` (unchanged)        |
| `dateBackground`            | `(1.00, 0.99, 0.96, 1.0)` (unchanged)        |
| `dateNumeral`               | `(0.05, 0.04, 0.03, 1.0)` (unchanged)        |
| `powerReserveRed`           | `(0.80, 0.16, 0.14, 1.0)`                    |
| `powerReserveTrack`         | `(0.40, 0.34, 0.22, 0.7)` (minor-tick color) |
