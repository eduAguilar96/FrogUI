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

Sounds and haptics are semantic cue ids. Generic controls can inherit
`theme.sounds`; a component overrides a cue only when its action has more
specific meaning. The Host calls the injected provider and never imports audio
assets or platform code.
