# FrogUI authoring style

This living guide keeps framework code and consumer components readable. When
review establishes a clearer convention, update this file in the same change.

## Names reveal render ownership

Use PascalCase for every named component or helper that returns a FrogUI
description:

```lua
local StatusBadge = Frog.component("StatusBadge", function(props)
    return Frog.Box { Frog.Text(props.label) }
end)

local function EmptyMessage(text)
    return Frog.Text { role = "caption", text }
end
```

Use lower camel case for data helpers and behavior. Use `UPPER_SNAKE_CASE` for
immutable module constants. Files and folders use `snake_case`.

Anonymous actor render functions and `Frog.each` callbacks do not need an
invented PascalCase name: their surrounding semantic owner already names them.

## Every file and owner explains its purpose

Every Lua file starts with a short comment answering why it exists. Every
component, actor, and named render helper gets one brief comment describing its
visible responsibility or ownership boundary.

Explain visual invariants and non-obvious geometry. Do not narrate syntax:

```lua
-- Keeps the notification above modal content without joining input routing.
local function NotificationLayer(items)
```

## Files read in one predictable order

Prefer this order:

1. file-purpose comment;
2. imports;
3. constants;
4. lower-camel data helpers;
5. PascalCase render helpers;
6. prop validation;
7. public component or actor;
8. attached actions, events, views, or addresses;
9. one `return`.

Create a real `Frog.component` when a visible concept is reused, deserves
independent props or inspection identity, or owns behavior. Keep a private
PascalCase helper when the fragment is small and meaningful only inside its
owner. Promote a helper when it becomes a second component-sized concept.

Do not create barrel `init.lua` files, adapters, projection files, or separate
style/geometry files merely to hide an owner. Component-local paint and box
model values stay beside the visible component.

## Trees scan visually

- Put structural props before children.
- Keep child layout and paint order visible in the table.
- Key every reordered or generated child by stable semantic identity.
- Use `condition and Child { ... }` for simple optional children; use a clear
  `if` for legitimately falsy values or non-trivial branching.
- Lua forwards every value from a final function call. Assign or parenthesize
  calls such as `gsub` when exactly one child value is intended.
- Constructed descriptions and committed props are framework-owned, read-only
  values. Publish changes through actor actions, events, viewport changes, or
  explicit root props.
- Static identity and completed prose are not clickable. Interactive surfaces
  need a distinct user-facing action.

## Public API stays discoverable

The complete LuaLS contract for every primitive and Host service lives in
`frogui/init.lua`. Closed string vocabularies use literal-union aliases so
hover and completion reveal valid `align`, `justify`, `fit`, `axis`, and
`dismiss` values.

A new public prop updates its adjacent annotation, validation, focused
contract, guide, and changelog in the same change. Undocumented Host internals
and the custom painter protocol are not compatibility promises during 0.x.

## State stays semantic

Components are pure render functions. An actor owns the smallest meaningful
state and changes it through typed actions or events. The root composes actors;
it does not duplicate their state.

Keep payloads small and plain. Rendering never calls domain mutation, advances
simulation, or manufactures state by inspecting committed nodes. If a UI needs
an authoritative fact, its application layer provides it explicitly.

Use `Frog.useResource` only for an external process with a precise lifetime.
Create and clean it up in the same owner, keep hooks unconditional and in a
stable order, and publish only a semantic revision or narrow snapshot. A frame
callback advances that process; it does not call Host render directly.

## Layout and refs remain explicit

Compose ordinary layouts with Box, Row, Column, and Overlay. Read responsive
state through `Frog.useViewport()` rather than global window queries. A
component owns its portrait/wide composition visibly.

Create committed geometry handles only with `Frog.useRef()` or one
`Frog.useKeyedRefs(keys)` call. Hooks are positional, unconditional, and never
called inside loops. Attach one ref to one primitive. Refs expose detached
arranged geometry, not transient Motion transforms; never inspect `testId` or
the private Host tree at runtime.

Motion changes paint and input transforms, never layout footprint. The parent
allocates stable space for the largest intended visual state.

## Effects and feedback are declarative

Use `EffectLayer` as a non-interactive feedback plane above stable content.
Finite effects have stable semantic keys and explicit clocks. Use refs for
moving/reflowing anchors and layer-local points only for deliberately detached
feedback.

`ParticleBurst` requires an explicit seed. Presentation effects never consume
simulation randomness or calculate domain results. `PopupText`, `Projectile`,
`Flipbook`, and `ParticleBurst` report terminal completion; their owner removes
the keyed entry.

Components declare semantic sound and haptic cue ids, never asset paths or
`love.audio` calls. The Host feedback provider maps cues to platform behavior.
Generic controls inherit theme defaults; override only when the visible action
has a more precise meaning.

Use named `juice` recipes or Frog.Motion for micro-interactions. Do not add a
per-component update/draw loop. Select a clock deliberately when pause or speed
policy matters. Reduced motion is a Host concern and must preserve terminal
semantic completion.

## Images, shaders, and Canvas

Use semantic asset tokens. `Image` preserves authored RGB; `Icon` recolors an
alpha silhouette; `SpriteSheet` samples an explicit clock; `TiledImage` repeats
art; `ShaderImage` wraps one paint leaf with a theme-owned shader.

Keep shader source in `theme.shaders`, not components. A plain fallback should
preserve essential art when the GPU path is unavailable.

Use `Canvas` only for bounded vector geometry that cannot be expressed through
ordinary primitives or finite effects. Give it explicit dimensions and use
only its record-only painter. It owns no input, state, physics, clock, or
children.

## Interaction is semantic

Use Button for keyboard-visible actions. Pressable is pointer-only by design.
DragSource owns a plain payload and callback; DropTarget exposes a typed,
stable address. Domain policy remains in the consumer callback, never FrogUI's
interaction runtime.

Touch never synthesizes mouse hover. Every gesture has one owner, and terminal
commit/reject/cancel behavior is explicit. Avoid raw screen input when a
primitive already owns the interaction.

## Runtime and test discipline

One Lua VM may mount one Host at a time. Candidate render/resize/refresh
failures retain the last committed tree; runtime update, feedback, and input
faults fault the Host loudly. A faulted Host is diagnostic-only and must be
unmounted before replacement.

Tests assert public behavior. Internal seams such as `Host:tree()` may be used
only through `tests/support.lua` and do not become consumer API. Test fixtures
are generated or repository-owned; the standalone suite never borrows a
consumer's modules or assets.

Run both gates before committing:

```text
love . --headless
love . --graphical
```

Also run `git diff --check`. Visual changes still receive a manual portrait,
wide, resize, mouse, touch, and keyboard smoke pass in a real consumer.
