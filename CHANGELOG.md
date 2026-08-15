# Changelog

All notable changes to FrogUI are documented here. The format follows Keep a
Changelog, and versions follow Semantic Versioning while the public API remains
in beta.

## [Unreleased]

### Added

- Brightness-preserving `recolor` recipes for Projectile, Flipbook, and
  asset-backed ParticleBurst effects, with an authored multiplicative-tint
  fallback when the device cannot compile the built-in shader.
- Optional scale amplitude, exponential damping, and coherent-channel sampling
  for `Frog.shake`, allowing exact finite spring-like feedback without
  application frame callbacks.

### Changed

- RadialDial now tolerates incidental angular touch jitter before promoting a
  left/right tap into a drag preview.
- Quiet ParticleBurst reconciliation now shares unchanged particle catalogs
  transactionally instead of deep-copying them.
- Resolved-tree finalization no longer creates empty fallback collections for
  nodes without actors or event listeners.
- Host teardown now releases Host-owned decoded asset and font caches.

## [0.1.0-beta.1] - 2026-08-13

### Added

- Readable nested primitives and stateless components.
- Actor-owned state with typed actions, addressed sends, broadcast events, and
  deterministic breadth-first delivery.
- One atomic Host with responsive virtual viewports, input forwarding,
  semantic services, lifecycle-bound resources, refs, and diagnostics.
- Declarative Motion, juice, Canvas, shaders, semantic feedback, and finite
  popup, projectile, flipbook, and deterministic particle effects.
- Independent headless and graphical contracts, examples, LuaLS annotations,
  and the first standalone compatibility policy.

### Changed

- Extracted the public namespace to `require("frogui")` with no legacy alias.
- Made virtual design dimensions explicit Host input instead of a game-owned
  default.

### Known gaps

- Windows, Android, and iOS consumer smoke passes have not yet been completed;
  `0.1.0-beta.1` records macOS and automated-contract evidence only.

[Unreleased]: https://github.com/eduAguilar96/FrogUI/compare/v0.1.0-beta.1...HEAD
[0.1.0-beta.1]: https://github.com/eduAguilar96/FrogUI/releases/tag/v0.1.0-beta.1
