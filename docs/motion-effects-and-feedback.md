# Motion, effects, and feedback

Juice recipes are inert declarative data: tween, spring, shake, delay,
sequence, parallel, loop, sound, and haptic. Bind them by name to a primitive or
play them from a typed reaction. A stable key starts one finite lifetime;
replacement or unmount cancels stale completion.

Motion wraps one child and applies translation, rotation, scale, opacity, tint,
and pivot without changing layout. Explicit clocks allow the consumer to state
pause and playback-speed policy. Reduced motion settles visual recipes while
preserving required terminal completion.

EffectLayer is a non-interactive plane for PopupText, Projectile, Flipbook,
ParticleBurst, or bounded Canvas leaves. Effects use stable keys, explicit
clocks, committed refs or layer-local points, and terminal callbacks. A particle
burst also requires a deterministic presentation seed and has a framework-owned
count ceiling.

A quiet reconciliation shares the committed immutable particle catalog. It
copies that catalog only if candidate time or placement needs a new pose, then
ends the rollback alias when the candidate commits. Rejected candidates cannot
mutate committed particles, while an unchanged rerender avoids copying every
particle.

Use `recolor` when an effect skin's authored pixels provide shape and
brightness while runtime state supplies the visible hue:

```lua
Frog.Projectile {
    key = effect.id,
    from = source,
    to = target,
    duration = effect.travelTime,
    frames = effect.frames,
    color = effect.color,
    tint = effect.color,
    recolor = {
        color = effect.color,
        hotCore = 0.65,
        hotCoreExp = 2.5,
    },
}
```

`tint` multiplies the source RGB. `recolor` instead uses the source pixel's
brightest channel as intensity, replaces its hue with `recolor.color`, keeps
the source alpha, and can blend the brightest pixels toward white. `hotCore`
controls whitening strength; `hotCoreExp` controls how tightly whitening stays
within the brightest pixels. Projectile, Flipbook, and asset-backed
ParticleBurst share this contract. Circle particles continue to use `color`.
If the device cannot compile the recolor shader, FrogUI uses ordinary `tint`,
so always provide an intentional fallback tint.

Sounds and haptics are semantic cue ids. Generic controls can inherit
`theme.sounds`; a component overrides a cue only when its action has more
specific meaning. The Host calls the injected provider and never imports audio
assets or platform code.
