# Royale — Design Notes

Royale is the project's first real homage and the `DialRenderer` protocol's hardest stress case: a digital LCD watch. Story 1.5 ships it.

Inspired by the Casio AE-1200WH.

## Visibility

`.hidden` — Royale is the easter egg. The reveal gesture lives in Story 3.2; until then, Royale only appears via the temporary hardcoded default in `WatchesScreenSaverView.installRenderer()` (Story 1.5 sets that hardcode to `"royale"`; Story 1.6 swaps to `"asymmetricMoonphase"`; Story 3.1 removes the hardcode entirely).

## Design decisions

### D1: Glyph topology — hybrid 7-segment digits + 5×7 pixel-block letters

**Decision.** Digits (0–9) render as classic 7-segment glyphs; letters (subset of A–Z) render as 5-wide × 7-tall pixel-block bitmap glyphs.

**Why.** The AE-1200WH uses different LCD topologies for different display regions — large 7-segment digits for the primary time, and a coarser pixel-block style for short alphabetic fields like the day-of-week label. A unified topology (e.g., 14-segment for everything) would have rendered letters that look "off" relative to the reference, and would have made digits more visually complex than the reference shows.

**Rejected alternatives.**
- *Unified 14-segment for both digits and letters.* Less authentic to the AE-1200WH (which uses hybrid topology); letters render acceptably but digits would look unfamiliar (extra diagonals). Simpler in code, but the gain is small relative to the visual mismatch.
- *Bitmap glyph atlas for everything.* Highest fidelity but ships binary assets and loses the algorithmic-segment property useful for animation experiments later.
- *`CATextLayer` for letters.* Fast to implement but the wrong aesthetic — the LCD pixel-block look depends on visible pixel structure, which `CATextLayer` antialiases away.

### D2: Time format — `HH:MM:SS`

**Decision.** Show hours, minutes, and seconds. Reduce-motion dedup at the integer-second level (`tick` early-returns when the displayed integer second hasn't advanced).

**Why.** Caleb's preference per Story 1.5 design Q3. The seconds field exists on the real AE-1200WH (smaller, top-right of the primary time) but `HH:MM:SS` inline is the screensaver simplification.

### D3: Colon blink — 1 Hz, frozen ON in reduce-motion

**Decision.** The colons between HH/MM and MM/SS toggle on/off at 1 Hz (toggle on each integer-second tick). In `reduceMotion: true`, colons stay ON.

**Why.** The real AE-1200WH blinks its colon at 1 Hz. Reduce-motion contract is "no ambient animation," and the blink is ambient, not state-bearing.

### D4: Secondary readouts — both day-of-week AND date

**Decision.** Render both a 3-letter day-of-week label (top-left of the time block) and a numeric `MM-DD` date (below the time block).

**Why.** Caleb's preference per Story 1.5 design Q4 — matches the AE-1200WH layout, which shows both simultaneously.

### D5: Calendar locale — `.autoupdatingCurrent`

**Decision.** Use `Calendar.autoupdatingCurrent` for time decomposition and day-of-week label lookup. Day-of-week strings come from `Calendar.shortStandaloneWeekdaySymbols` (locale-aware): US Macs see `MON`, German Macs see `MO`, etc.

**Why.** Caleb's preference per Story 1.5 design Q5. The LCD aesthetic is global; the locale-respecting label honors the user's machine.

**Rejected alternative.** Fixed `.gregorian` with always-English day labels (more "authentic Casio" — the real watch ships only with English regardless of where it's sold). Lost on the call: pedantic Casio authenticity vs. respect for the user's machine. Caleb chose the latter.

### D6: Date format — `MM-DD` pinned

**Decision.** Date renders as `MM-DD` regardless of locale.

**Why.** Locale-dependent date-format ordering (DD-MM in EU, MM-DD in US, YYYY-MM-DD in JP) is *out of scope* for Story 1.5. The Casio AE-1200WH itself supports both formats via a preference; we're not building per-dial preferences in v1 (out of scope per PRD).

**Deferred.** Locale-dependent date-format ordering. Tracked in `deferred-work.md`.

### D7: World-time map — placeholder this story, bitmap in Story 1.5.1

**Decision.** Story 1.5 ships a placeholder for the world-map region (outline rectangle or low-fidelity shape). The real dot-matrix continent bitmap lands in Story 1.5.1 (created post-1.5, before Epic 2).

**Why.** Story 1.5's purpose is the protocol stress test, not pixel-perfect AE-1200WH. A real map asset adds bundle-resource management (framework-bundle path lookup) that's orthogonal to the protocol question and worth its own story.

**Deferred.** World-map bitmap asset (Story 1.5.1). Day/night terminator math (TBD).

### D8: Functional analog mini-clock inside the subdial cutout (Story 1.5.2)

**Decision.** The subdial cutout is no longer purely decorative. Behind the cutout (on the LCD layer, visible through the faceplate's circular hole) sits a small functional analog clock with:

- An hour hand and a minute hand (`CAShapeLayer` filled rectangles, rotated per tick via `setAffineTransform`)
- A single short tick mark on the subdial's **outer ring** that JUMPS once per second (60 discrete angular positions; not a smooth-sweeping third hand)
- Four short radial accent lines at the 12 / 3 / 6 / 9 positions, splitting the subdial face into visible quadrants

The faceplate-printed decoration (ring + 60 tick marks + 12 numerals + 4 corner rivets) from Story 1.5 stays exactly as-is. The mini-clock is **additive LCD content**, not a replacement.

**Why.** Story 1.5's subdial was a static prop. Adding a functional analog readout (a) gives Royale a richer time presentation — the dial now displays time three ways simultaneously (big digital `HH:MM`, small digital `SS`, and analog hands), (b) exercises the `DialRenderer` protocol in a new way (paradigm mixing within a single dial — analog subcomponent inside a digital dial), and (c) confirms architecturally that the existing `attach`/`tick`/`canvasDidChange`/`detach` shape handles paradigm mixing without amendment.

**Seconds: tick on the outer ring, NOT a sweeping hand.** Per Caleb's direction during Story 1.5 polish. Architectural rationale: the seconds-tick approach has simpler reduce-motion semantics (just freeze the layer; nothing else changes), and matches the AE-1200WH's dot-matrix LCD aesthetic of discrete-position indicators over smooth motion.

**Reduce-motion contract for the analog subcomponent.**
- Hour + minute hands: tick to exact positions, no animation between ticks (same as production behavior — transforms are written inside `setDisableActions(true)`)
- Seconds tick: **freezes** when reduce-motion is on. The renderer skips the `setAffineTransform` write on the seconds-tick layer entirely when `reduceMotion == true`, leaving it at whatever angle it last had.

**Rejected alternatives.**
- *Smooth-sweeping seconds hand.* Adds animation cost and reads as "watch movement" rather than "LCD watch." The AE-1200WH itself doesn't have one; the user's preference was explicit.
- *No analog hands at all (keep subdial fully decorative).* Wastes the visual real estate of the subdial cutout; the cutout currently only shows a small hub dot which is uninteresting compared to a functional clock.
- *Replace the faceplate-printed numerology with LCD-side numerology that rotates with the hands.* Would require redrawing the silkscreen on every tick; the static printed numerals work fine since the analog hands move beneath them.

## Reduce-motion contract (P7)

- Integer-second dedup: `tick(reduceMotion: true)` returns `[]` if `floor(now.timeIntervalSince1970)` hasn't advanced since last tick. No layer write.
- Colon blink frozen ON.
- Analog hour + minute hands tick to position without animation (transforms wrapped in `setDisableActions(true)`).
- Analog seconds tick freezes — `tick()` skips the seconds-tick transform write when reduce-motion is on.
- No ambient effects: no segment shimmer, no map terminator drift, no fade transitions.
- Layer writes that DO happen (e.g., minute advance, hour-hand creep) are wrapped in `CATransaction.setDisableActions(true)` regardless — implicit animations are inappropriate for an LCD aesthetic.

## Protocol-amendment assessment

**Outcome (a): protocol survived the stress test. No amendment needed.**

The `DialRenderer` contract held cleanly for the digital paradigm. Per-method assessment:

- **`attach(rootLayer:canvas:timeSource:)`** — fit cleanly. The "exclusive sublayer space" guarantee on `rootLayer` let Royale install ~50 segment + pixel layers across 16 glyph slots without coordinating with the host. The `canvas: CGSize` parameter was the right shape — Royale's geometry math takes `CGSize` and produces frames in canvas-relative coordinates exactly like an analog dial would.
- **`tick(reduceMotion: Bool) -> [CGRect]`** — fit cleanly. The single `Bool` reduce-motion flag was sufficient: Royale needed exactly two decisions from it (integer-second dedup early-return + colon-freeze), both readable from one bool. Returning `[CGRect]` dirty rects gave Royale a useful (if currently host-ignored, per ADR-002) signal that the time block and secondary block changed but the static map region didn't.
- **`canvasDidChange(to:)`** — fit cleanly. Recomputes layer frames against the new canvas size; same pattern as ProofOfHost.
- **`detach()`** — fit cleanly. Removed every sublayer Royale added; nil'd `rootLayer` and `timeSource`. No host-side leak risk.
- **`init()` (required, public)** — fit cleanly. Royale's state is all `attach`-time, so the zero-arg init carries no surprise.
- **`identity` / `visibility` (static)** — fit cleanly. `.hidden` visibility was honored by `DialRegistry.visible(includingHidden:)` without further plumbing.

**`TimeSource` was sufficient.** Royale only needs `now: Date`; no need for `CACurrentMediaTime`-style monotonic time. The protocol's P4 prohibition on direct `Date()` and `Calendar.current` was easy to satisfy — `Calendar.autoupdatingCurrent` is allowed and lives outside `TimeSource` because it carries locale, not time.

**One observation (not a problem).** The protocol gives no hook for "lazy allocation across multiple `attach` calls." Royale builds all segment paths and pixel layers up front in `installLayers`. That's the right shape for a long-lived dial, but the protocol couldn't express "do this once across multiple attach/detach cycles" if a future dial wanted that. Noted; no action.

**Conclusion.** The dirty-rect-returning, canvas-relative, time-injected shape Story 1.2 baked into `DialRenderer` survives the digital paradigm. The four remaining conventional analog dials (Coke GMT, Octagon, Moonchrono, Diver) are execution rather than architecture.

### Story 1.5.2 paradigm-mixing extension

Story 1.5.2 added an analog mini-clock inside Royale's subdial cutout — paradigm mixing within a single dial (analog subcomponent in a digital dial). **The protocol survived this second stress without amendment too.** The analog hands and seconds tick are just more `CAShapeLayer` sublayers of `lcdLayer` whose `setAffineTransform` is updated in the existing `tick(reduceMotion:)` call. No new lifecycle hook needed; no new state passed through the protocol. `TimeSource` still provides the only time input; reduce-motion is still expressed via the same `Bool`. AC8 outcome (a) holds.

This extends the original architectural claim: not only do separate dials with different paradigms satisfy the protocol, but a **single dial mixing paradigms internally** does too.

## Open follow-ups (post Story 1.5)

- Story 1.5.1: real world-map bitmap asset
- Day/night terminator over the world map (math + layer)
- Locale-respecting date format (DD-MM where appropriate)
- AE-1200WH-authentic segment shapes (rounded corners; the current paths are rectilinear)
- Backlight / illumination effect on hover or gesture
