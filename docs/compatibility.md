# Compatibility policy

FrogUI `0.1` targets LÖVE 11.5 and Lua 5.1/LuaJIT. The tagged repository and
source archive are the supported distribution forms; LuaRocks is deferred.

During 0.x, patch releases avoid intentional breaks to documented calls. Minor
releases may change public API and include migration notes in `CHANGELOG.md`.
Undocumented Host methods, mutable node internals, underscore-prefixed probes,
and the custom painter protocol may change at any release.

Every release aligns `frogui/version.lua`, `Frog.VERSION`, the changelog, and
the `v<version>` tag. It passes headless and graphical suites, boots examples at
portrait and wide sizes, verifies a nested vendor installation, and inspects
the archive for consumer code or assets.

Automated CI covers Linux desktop LÖVE behavior. Beta tags record the platform
matrix they have actually exercised: `0.1.0-beta.1` has local macOS evidence,
while Windows, Android, and iOS consumer smoke passes remain unverified. A 1.0
release requires those platform passes, two sustained real consumers, stable
documented error semantics, and a fresh public/private API review.
