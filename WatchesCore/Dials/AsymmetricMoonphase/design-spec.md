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

**Photorealism stack (updated Pass E2 — read this before the elements):**
Photorealism on this dial comes from FIVE overlay passes stacking on every
gold element and every recessed surface. They are tiny individually; their
sum is the difference between "flat illustration with shadows" and "studio
photo of a watch." For every gold element below — hands, markers, Romans,
hub, date frames, aperture rim, moon disc — assume these are applied as
described in Element 18 (faceplate stipple), Element 19 (gold specular
highlight gradient), and Element 20 (sub-dial guilloché).

**Layout intent (updated Pass E2 — re-measured against primary reference):**
the four readouts are positioned so the dial looks distinctly Lange-1
asymmetric, not a generic 3-counter chronograph:

- Main time (large) — center-LEFT, **~48% of dial radius** (smaller than
  prior 55%; reference shows the main dial fitting comfortably within the
  left half with clear breathing room toward the bezel and toward the date)
- Big date (two boxes) — **TOP-RIGHT, sitting HIGH on the dial** with its
  baseline well above the dial midline; abuts the main time at the upper
  right but with a clear vertical gap (the reference places the date near
  the top quarter of the dial, not at the midline)
- Sub-seconds (small) — BOTTOM-RIGHT, well clear of the dial edge
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
- **Outer rim highlight (silhouette pop) (updated Pass E2 — crisper):**
  a `CAShapeLayer` stroking the outer circle (radius = `caseRadius`).
  - `lineWidth = max(0.8, caseRadius * 0.006)` (raised from 0.004 — too
    thin in prior to register against the dark background).
  - `strokeColor = NSColor(srgbRed: 1.00, green: 0.96, blue: 0.82, alpha:
    1.0)` (a touch brighter / whiter — this is the polished metal edge
    catching the studio key light).
- **Bezel top-arc highlight (NEW Pass E2 — catches the light):** a second
  `CAShapeLayer` drawing a SHORT arc along the upper-left of the bezel,
  positioned just inside the outer rim. This is the bright glint where
  the rounded bezel edge faces the light source.
  - Path: arc on circle radius `caseRadius * 0.992`, from angle
    `120° (2π/3)` to angle `60° (π/3)` measured CCW from +x — i.e. the
    upper arc spanning the top-left to top-center of the bezel.
  - `lineWidth = max(1.0, caseRadius * 0.010)`
  - `strokeColor = NSColor(srgbRed: 1.00, green: 0.98, blue: 0.88, alpha:
    0.85)` — bright cream, slightly translucent so it blends.
  - `lineCap = .round` — the arc fades softly at each end.
  - Add `shadowOpacity = 0` (no shadow on a highlight).
  - Z-order: above bezel fill, above outer rim highlight, below inner
    lip.
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
- **Stippling texture (updated Pass E2 — now MANDATORY, see Element 18
  for the full implementation spec):** a `CALayer` at the faceplate
  position with `backgroundColor = .clear` and a procedurally-generated
  noise-pattern `CGImage` as its `contents`, `opacity = 0.07`. Generate
  the pattern once at attach time per Element 18 (512×512 buffer, ~6000
  random low-alpha dots, optional Gaussian blur 0.5). This is the
  difference between "flat painted disc" and "matte sandblasted plate" —
  do not skip.
- **Z-order:** dial face → vignette overlay → (stippling) → all
  sub-dial layers above.

---

## Element 3 — Main time sub-dial (recessed silver)

The main time dial occupies the left half of the watch. It is **recessed
into the plate** — confirmed. It has a **polished silver** finish (so it
DOES get a soft radial highlight, but a gentle one — this is not a
sunburst-bright sub-dial, it's a flat polished plate that's barely
brighter than the main faceplate).

- **Center (updated Pass E2 — re-measured against ref photo):**
  `(caseCenter.x + dialRadius * -0.20, caseCenter.y + dialRadius * -0.05)`
  — shift LEFT (slightly more than before) and a hair DOWN. In the
  reference, the main time sits left-of-center and its vertical center is
  fractionally below the case midline (the date occupies the upper-right
  quadrant; the main time biases gently toward the lower-left to balance
  it). Prior `(-0.18, 0.00)` was too high.
- **Radius (updated Pass E2 — shrunk to match ref proportions):**
  `mainTimeRadius = dialRadius * 0.48`. Prior 0.55 was too large — the
  reference clearly shows the main dial occupying roughly the left HALF
  of the visible dial radius with comfortable margin between the XII
  marker and the upper bezel lip. 0.48 gives that breathing room while
  keeping the dial dominant.
- **Face fill:** `NSColor(srgbRed: 0.965, green: 0.955, blue: 0.925,
  alpha: 1.0)` — a hair lighter than the main dial.
- **Recess shading (inner edge) (updated Pass E2 — deeper well shadow):**
  Two ring strokes built as `CAShapeLayer`s stroking the face circle —
  these together sell the recess depth without a gold rim:
  - **Upper-rim shadow (the dark crescent at the top of the well):**
    a CAShapeLayer with `path = ellipseIn(faceRect)`, `lineWidth =
    max(0.8, mainTimeRadius * 0.028)` (thicker), `strokeColor =
    NSColor(srgbRed: 0.42, green: 0.36, blue: 0.26, alpha: 0.85)`
    (darker + more opaque). Use `shadowOffset = (0, -mainTimeRadius *
    0.018)` (deeper), `shadowRadius = mainTimeRadius * 0.018` (broader
    bloom), `shadowOpacity = 0.80` (raised from 0.6), `shadowColor =
    .black`. The shadow blooms downward, simulating the lip blocking the
    light. The reference shows a clearly visible darker arc at the top
    of every sub-dial well — this needs to read as a real lip, not a
    subtle gradient.
  - **Lower-rim highlight (bounce light):** a second CAShapeLayer
    stroking the same circle, `lineWidth = max(0.4, mainTimeRadius *
    0.012)`, `strokeColor = NSColor(white: 1.0, alpha: 0.55)` (raised
    from 0.45 — the bounce reads as a faint crescent in the ref), with
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

**Highlight overlay (updated Pass E2 — now mandatory, see Element 19):**
each hand gets the standardized gold specular highlight gradient defined
in Element 19, applied as a child layer of the hand's transform layer so
the highlight rotates with the hand. The old hand-local vertical gradient
is superseded — use the Element 19 diagonal gradient (`startPoint =
(0.0, 1.0)`, `endPoint = (1.0, 0.0)`) for consistency across all gold
elements.

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

- **Left eye (updated Pass E2 — larger so it reads):** filled circle,
  center = `(-discR * 0.28, +discR * 0.20)`, radius = `discR * 0.09`
  (raised from 0.07).
- **Right eye:** filled circle, center = `(+discR * 0.28, +discR *
  0.20)`, radius = `discR * 0.09`.
- **Smile (open arc) (updated Pass E2 — thicker):** `addArc(center:
  (0, +discR * 0.28), radius: discR * 0.40, startAngle: -π * 0.85,
  endAngle: -π * 0.15, clockwise: false)`. **Stroke**, not fill.
  - `strokeColor = NSColor(srgbRed: 0.48, green: 0.28, blue: 0.10,
    alpha: 1.0)` — deeper bronze so it reads at small scale.
  - `lineWidth = max(0.8, discR * 0.09)` (thicker than prior 0.07).
  - `lineCap = .round`
- **Eye fill color:** same deeper bronze as smile stroke.

---

## Element 11 — Stars in moonphase sky

Small four-pointed stars dotting the navy aperture, visible at the
edges when the moon is at full or near-full phase.

- **Count:** 8 stars (current count is fine).
- **Star shape (updated Pass E2 — larger so they read in the navy):**
  4-pointed star with `outerRadius / innerRadius = 2.5`. Use
  `outer = apertureHalfWidth * 0.07` (raised from 0.05). The reference
  stars are small but distinctly visible four-point cross-stars — they
  must read as stars, not as dots.
- **Color (updated Pass E2 — brighter for contrast):** `starGold =
  NSColor(srgbRed: 1.00, green: 0.95, blue: 0.72, alpha: 1.0)` — a touch
  brighter than prior so they pop against the deep navy. Update palette
  to match.
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

- **Box center (updated Pass E2 — re-measured against ref photo):**
  `(caseCenter.x + dialRadius * 0.20, caseCenter.y + dialRadius * 0.55)`
  — moved INWARD (x: 0.30 → 0.20) and substantially HIGHER (y: 0.42 →
  0.55). In the reference, the big date sits in the top quarter of the
  dial with its top edge tucked close to the inner bezel lip, and its
  inner (left) edge sits roughly over the XII marker of the main time —
  i.e. clearly inboard of the case wall on the right, not pushed against
  the bezel. Prior values placed it too far right and too low (it
  collided with the main time perimeter).
- **Box height (updated Pass E2):** `boxH = dialRadius * 0.16`. Slightly
  smaller than prior 0.17 because the main time radius shrank from 0.55
  → 0.48 — the date should scale with the main dial it sits beside.
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

- **Center (updated Pass E2 — re-measured against ref photo):**
  `(caseCenter.x + dialRadius * 0.34, caseCenter.y + dialRadius * -0.38)`
  — minor tweak: a hair further right and a hair higher than prior. In
  the reference the sub-seconds sits with its right edge well clear of
  the bezel and its bottom edge above the MADE IN GERMANY text.
- **Radius (updated Pass E2 — shrunk to match ref proportions):**
  `subSecondsRadius = dialRadius * 0.18`. Prior 0.22 was oversized. In
  the reference, the sub-seconds dial is roughly 38% of the main time
  dial's radius. With `mainTimeRadius = 0.48 * dialRadius`, that yields
  `subSecondsRadius ≈ 0.18 * dialRadius`.
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
- **Indicator hand (updated Pass E2 — short slim needle, not a lance):**
  In the primary reference the power reserve hand is a **short, slim
  horizontal needle** — closer to a tapered pin than a watch hand. It is
  NOT the same silhouette as the hour/minute hands. There is no lozenge,
  no obvious counterweight, and the hand barely reaches past the inner
  edge of the major ticks.
  - Length: `powerReserveRadius * 0.78` — slightly shorter than prior
    0.82. The tip reaches the inner edge of the major ticks, not the
    outer edge.
  - Width (at base): `powerReserveRadius * 0.08` — significantly slimmer
    than prior 0.14.
  - Geometry: a simple **tapered triangle** in hand-local coords with
    `anchorPoint = (0.5, 0.15)` (pivot is at 15% along the length, giving
    a very short tail stub):
    1. Move to `(cx, length)` — tip.
    2. Line to `(cx + width/2 * 0.45, length * 0.20)` — right shoulder
       just past pivot.
    3. Line to `(cx + width/2 * 0.25, 0)` — right tail.
    4. Line to `(cx - width/2 * 0.25, 0)` — left tail.
    5. Line to `(cx - width/2 * 0.45, length * 0.20)` — left shoulder.
    6. Close.
  - This is a **custom path** for the power reserve hand. Do NOT reuse
    `goldHandPath(taper: true, withHole: false)` — that produces the
    fancy lozenge profile of the time hands. The power reserve uses its
    own simple tapered-needle constructor (name it
    `powerReserveNeedlePath`).
  - Fill `handGold`. Edge stroke `lineWidth = max(0.25, powerReserveRadius
    * 0.006)`, `strokeColor = NSColor(srgbRed: 0.42, green: 0.28, blue:
    0.12, alpha: 1.0)`.
  - **Tiny pivot dot at the base:** a small `CAShapeLayer` circle at the
    hand's pivot, `radius = powerReserveRadius * 0.025`, fill `handGold`,
    stroke `lineWidth = 0.25`, same dark-gold stroke color as above.
    The reference clearly shows a small gold pivot cap here — overriding
    the prior "no hub" rule for the power reserve.
  - Drop shadow: `shadowOffset = (0.6, -0.8)`, `shadowOpacity = 0.35`,
    `shadowRadius = 1.2`.
- **Hand rotation logic:** target angle (in standard CCW-from-+x) =
  `abAngle + fraction * (aufAngle - abAngle)`. The hand's intrinsic
  forward direction is +y (angle π/2). Rotation applied =
  `targetAngle - π/2` (counterclockwise positive). Current
  implementation is correct.
- **Power reserve hub (updated Pass E2 — added):** see the "Tiny pivot
  dot" note inside the Indicator hand spec above. Prior version said
  "no hub" — that was wrong; the reference clearly shows a small gold
  pivot cap.
- **Z-order:** minor ticks → major ticks → red triangles → labels →
  indicator hand → hub.

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

## Element 18 — Faceplate stipple texture (NEW Pass E2)

The reference photo's silver faceplate is **clearly sandblasted** — a fine
granular texture covers the entire main dial. Without this, our render
reads as a flat painted disc. This is the single biggest texture upgrade.

**Implementation strategy: procedurally-generated noise CGImage as a
low-opacity overlay layer.**

- **Buffer size:** 512×512 pixels. (Larger than 256×256 to avoid visible
  tiling on Retina screens; small enough to generate in <5ms at attach.)
- **Generation algorithm** — keep it simple and synchronous, executed
  once at attach time inside the renderer's `installLayers()`:
  1. Allocate a `CGContext` of 512×512, 8 bits per channel, sRGB,
     premultiplied alpha (`CGImageAlphaInfo.premultipliedLast`).
  2. Fill with **transparent** (alpha = 0).
  3. For each of `~6000` randomly-positioned points: draw a 1×1 pixel
     dot with `alpha = 1.0` and a gray value uniformly random in
     `[0.0, 1.0]`. Use `arc4random_uniform` — does not need to be
     cryptographically random.
  4. (Optional, +polish.) Blur the buffer slightly using
     `CIFilter.gaussianBlur(inputRadius: 0.5)` before extracting the
     CGImage. This softens the grain so it reads as fine sandblast rather
     than digital snow. If `CoreImage` is heavy, skip the blur — the raw
     dots still work.
  5. Extract the `CGImage` via `context.makeImage()`. Cache on the
     renderer (`private let faceStippleImage: CGImage`) so canvas
     resize doesn't regenerate.
- **Apply as overlay layer:**
  - New `CALayer` named `dialFaceStippleLayer`.
  - `contents = faceStippleImage`
  - `contentsGravity = .resize` (let it stretch — at 512×512 the grain
    detail survives downscaling to any normal screen).
  - `opacity = 0.07` — barely visible, just enough to break the flat
    silver.
  - `mask` = a `CAShapeLayer` filled with the dial circle so the noise
    is clipped to the faceplate (does not leak into the bezel).
  - **Important:** the stipple layer overlays the WHOLE dial face,
    INCLUDING the area covered by the sub-dials. That's fine because the
    sub-dial face layers sit ABOVE the stipple in z-order and have
    opaque fills, so the stipple shows only on the main faceplate
    region. Do not punch holes in the stipple mask.
- **Z-order:** dial face fill → faceplate vignette → faceplate stipple →
  (all sub-dial layers above).

---

## Element 19 — Gold specular highlight gradient (NEW Pass E2)

In the reference photo, every gold element — hands, lozenge markers,
Roman numerals, hub, date frames, aperture rim, moon disc — has a clearly
visible **specular highlight band** sweeping diagonally from upper-left to
lower-right. The base gold tone is the same across the dial, but each
element catches the studio key light along its upper edge. This is the
single biggest material upgrade.

**Implementation strategy: for every gold element, add a second
`CAShapeLayer` overlay with the same path, filled by a masked
`CAGradientLayer` providing the diagonal highlight band.**

We already specified a hand-only highlight in Element 7 — generalize it
to ALL gold elements.

- **Gradient layer setup (per element):**
  - Type: `.axial` (linear).
  - `startPoint = (0.0, 1.0)` — upper-left in CA y-up.
  - `endPoint = (1.0, 0.0)` — lower-right.
  - 4 color stops:
    - `0.00` → `NSColor(srgbRed: 1.00, green: 0.92, blue: 0.72, alpha:
      0.55)` — bright cream-gold highlight at the upper-left edge.
    - `0.30` → `NSColor(srgbRed: 0.96, green: 0.82, blue: 0.52, alpha:
      0.22)` — soft mid-highlight.
    - `0.55` → `NSColor(white: 1.0, alpha: 0.0)` — transparent through
      most of the element.
    - `1.00` → `NSColor(srgbRed: 0.36, green: 0.22, blue: 0.08, alpha:
      0.35)` — slight darkening at the lower-right (the shadow side of
      the element).
- **Mask:** the gradient layer's `mask` is a `CAShapeLayer` filled with
  the element's silhouette path. This clips the diagonal gradient to the
  shape of the element so the highlight only paints where the element is.
- **Frame:** the gradient layer covers the element's bounding rect.
- **Z-order per element:** base gold fill → edge stroke → specular
  highlight overlay → (drop shadow comes from the base fill layer's
  `shadowPath`).
- **Apply to:**
  1. Hour hand
  2. Minute hand
  3. Power reserve indicator hand
  4. Sub-seconds hand
  5. Each of the 8 hour lozenge markers (apply to the merged
     `mainTimeHourMarkersLayer` — the mask path can be the merged path
     of all 8 markers).
  6. Roman numerals (merged glyph path)
  7. Center hub (small enough that the gradient won't show much detail,
     but keep it for consistency)
  8. Aperture rim frame
  9. Big date gold frames (both)
  10. Sub-seconds hub
  11. Moon disc (use the *disc* circle as the mask path; the face details
      sit above this layer)
- **Don't apply to:** stars (they're separate `starGold`, not part of the
  "applied gold" family), the bezel (already has its own four-stop
  gradient).
- **Implementation helper:** add a renderer-private method
  `applyGoldSpecular(to elementLayer: CAShapeLayer, path: CGPath, bounds:
  CGRect)` that wires up the gradient + mask + adds it as a sibling
  immediately above the element. Call it once per gold element at attach
  time. Highlights do not move with the element if the element rotates
  (hands rotate; we WANT the highlight to rotate with them — the studio
  light follows the hand in skeuomorphic terms). So make the highlight
  layer a CHILD of the element's transform layer, not a sibling at the
  root. For elements that don't rotate (markers, Romans, date frames,
  aperture rim, moon disc), siblings are fine.

---

## Element 20 — Sub-dial concentric guilloché (NEW Pass E2)

The reference shows clear **concentric ring patterning** on the sub-seconds
dial face (visible as faint regular bands inside the silver). The main
time dial may also have very subtle radial bands; spec it the same way at
even lower opacity. This sells the "sub-dial is a separate inset plate
with its own machined finish" feel.

**Implementation strategy: a `CAShapeLayer` containing a path of N
concentric circles, stroked at very low alpha.**

- **Per sub-dial (main time and sub-seconds), build a guilloché layer:**
  - `CAShapeLayer` named `<subdial>GuillocheLayer`.
  - `fillColor = nil`
  - `strokeColor = NSColor(srgbRed: 0.55, green: 0.50, blue: 0.40, alpha:
    0.10)` — barely visible warm shadow tone.
  - `lineWidth = max(0.3, subDialRadius * 0.004)` — hairline.
- **Ring count + spacing:**
  - **Sub-seconds:** 7 rings, radii at `subSecondsRadius * [0.18, 0.30,
    0.42, 0.54, 0.66, 0.78, 0.90]` (roughly `0.12 * subSecondsRadius`
    apart — visibly machined banding).
  - **Main time:** 4 rings at `mainTimeRadius * [0.30, 0.50, 0.68, 0.84]`
    (sparser — main time is mostly smooth in the reference, with just a
    hint of inner banding under the hands).
- **Path construction:** for each ring radius `r`, append an
  `ellipseIn(CGRect(x: -r, y: -r, width: 2r, height: 2r))` to a single
  `CGMutablePath`. One layer, one path, multiple subpaths.
- **Z-order within each sub-dial:** face fill → recess gradient → gloss
  highlight → **guilloché rings** → upper-rim shadow → lower-rim
  highlight → ticks → numerals → hands → hub.
  (Guilloché sits ABOVE the gloss so the rings show through; BELOW the
  rim shadow so the lip is the strongest contrast in the well.)
- **Sub-seconds-specific extra ring (NEW Pass E2):** the reference clearly
  shows a slightly heavier *minute-track separator ring* at radius
  `subSecondsRadius * 0.88` — sitting between the minor tick band and
  the numeral band. Specify this as part of the sub-seconds guilloché
  layer at slightly heavier alpha 0.25 and lineWidth `max(0.4,
  subSecondsRadius * 0.008)`. Easiest: a second `CAShapeLayer`
  (`subSecondsInnerTrackRing`) so its stroke params can differ.

---

## Implementation order

When wiring this up, build top-down z-order so each element appears as
expected (updated Pass E2 — added stipple, guilloché, gold specular,
bezel top-arc highlight, power-reserve hub):

1. Canvas background.
2. Vignette overlay.
3. Bezel ring (gradient + outer rim highlight + **bezel top-arc
   highlight** + inner lip).
4. Dial face (matte silver + vignette + **faceplate stipple overlay**).
5. Main time sub-dial face + recess + gloss + **guilloché rings** + rim
   strokes.
6. Main time minute ticks.
7. Main time hour lozenges (with shadows + **gold specular**).
8. Main time Roman numerals (with shadows + **gold specular**).
9. Moonphase: sky (clipped) → stars (clipped) → moving disc + face
   (clipped to stationary aperture mask, disc with **gold specular**) →
   gold rim frame (with **gold specular**).
10. Hands: hour → minute (both above the moonphase rim, each with **gold
    specular** rotating with the hand).
11. Center hub (top of stack at sub-dial level, with **gold specular**).
12. Sub-seconds: face → recess → gloss → **guilloché rings** →
    **inner-track separator ring** → rim → minor ticks → major ticks →
    numerals → hand (with **gold specular**) → hub.
13. Big date: gold frames (with **gold specular**) → white boxes →
    digits.
14. Power reserve: minor ticks → major ticks → red triangles → labels →
    indicator needle (with **gold specular**) → **pivot hub dot**.

---

## Palette update summary

The following palette entries should change from their current values
(updated Pass E2 — added gold specular stops, deeper bronze, brighter
star, deeper subdial recess, guilloché stroke, brighter case rim):

| Constant                          | New value                                    |
|-----------------------------------|----------------------------------------------|
| `caseGold`                        | `(0.78, 0.60, 0.32, 1.0)`                    |
| `caseGoldHighlight`               | `(0.98, 0.88, 0.62, 1.0)`                    |
| `caseGoldShadow`                  | `(0.42, 0.28, 0.12, 1.0)`                    |
| `caseRim` (Pass E2 — brighter)    | `(1.00, 0.96, 0.82, 1.0)`                    |
| `caseRimTopArc` (NEW Pass E2)     | `(1.00, 0.98, 0.88, 0.85)`                   |
| `dialFace`                        | `(0.945, 0.935, 0.905, 1.0)`                 |
| `subDialFace`                     | `(0.965, 0.955, 0.925, 1.0)`                 |
| `subDialShadow` (Pass E2 — deeper)| `(0.42, 0.36, 0.26, 0.85)`                   |
| `subDialGuilloche` (NEW Pass E2)  | `(0.55, 0.50, 0.40, 0.10)`                   |
| `handGold`                        | `(0.86, 0.68, 0.36, 1.0)`                    |
| `handGoldSpecularHi` (NEW Pass E2)| `(1.00, 0.92, 0.72, 0.55)`                   |
| `handGoldSpecularMid` (NEW)       | `(0.96, 0.82, 0.52, 0.22)`                   |
| `handGoldSpecularLo` (NEW)        | `(0.36, 0.22, 0.08, 0.35)`                   |
| `numeralBlack`                    | `(0.12, 0.10, 0.08, 0.92)`                   |
| `moonSky`                         | `(0.09, 0.14, 0.30, 1.0)`                    |
| `moonGold`                        | `(0.95, 0.82, 0.50, 1.0)`                    |
| `moonFaceBronze` (Pass E2 deeper) | `(0.48, 0.28, 0.10, 1.0)`                    |
| `starGold` (Pass E2 — brighter)   | `(1.00, 0.95, 0.72, 1.0)`                    |
| `dateBackground`                  | `(1.00, 0.99, 0.96, 1.0)` (unchanged)        |
| `dateNumeral`                     | `(0.05, 0.04, 0.03, 1.0)` (unchanged)        |
| `powerReserveRed`                 | `(0.80, 0.16, 0.14, 1.0)`                    |
| `powerReserveTrack`               | `(0.40, 0.34, 0.22, 0.7)` (minor-tick color) |
