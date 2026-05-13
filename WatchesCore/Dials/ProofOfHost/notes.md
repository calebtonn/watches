# Proof of Host — Design Notes

Internal developer dial. Visibility is `.hidden` — never appears in the user-facing picker.

## Purpose

Validate the `DialRenderer` protocol surface end-to-end before any real dial lands. Specifically:

- Layer lifecycle (`attach` → `tick` → `detach`) without crash or leak
- Time-source injection works (renderer never calls `Date()` directly)
- Dirty-region return semantics (`tick` returns only the second-hand frame)
- Reduce-motion contract (sub-second smoothing dropped to whole-second ticks)
- Multi-display + Retina (per-display instance; canvas-relative geometry)

## What it renders

- White circle outline at 80% of `min(canvas.width, canvas.height)`
- Red second hand from center to circle edge, ticking with system time

## What it does NOT render

- Hour or minute hands (excessive for the proof point)
- Tick marks, numerals, branding
- Anything that would tempt this dial into being kept past Story 1.6

## Reduce-motion behavior

Drops sub-second smoothing on the second hand. The hand jumps once per second instead of sweeping smoothly. Other ambient animation: none (there isn't any).

## Layer hierarchy

```
rootLayer
├── proofOfHost.circle      (CAShapeLayer, white stroke, no fill)
└── proofOfHost.secondHand  (CAShapeLayer, red stroke, rotates each tick)
```

## Future state

May be removed after Stories 1.5 (Royale) and 1.6 (Asymmetric Moonphase) prove the protocol against the two hardest stress dials. If removed:

1. Delete `Watches/Dials/ProofOfHost/`
2. Remove `ProofOfHostRenderer.self` from `DialRegistry.all`
3. Update host's default-dial fallback to point at a registered dial
