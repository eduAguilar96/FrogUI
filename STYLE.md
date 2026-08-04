# FrogUI living style guide

This is the active code-style contract for FrogUI and replacement presentation
code. Update it whenever review establishes a clearer convention; do not let a
new convention live only in a pull request, chat, or one component.

The architectural authoring contract remains
[`design/reference/frog-ui.md`](../../design/reference/frog-ui.md). The shorter
vocabulary guide is [`README.md`](README.md).

## 1. Names reveal whether code returns UI

Use **PascalCase** for every named value or function whose result is a FrogUI
render description:

```lua
local SpellCard = Frog.component("SpellCard", function(props)
    return Frog.Overlay { ... }
end)

local function BadgeLayer(spell, facing)
    return Frog.Row { ... }
end
```

This makes application components, primitives, and private render helpers read
as one visual vocabulary:

```lua
return Frog.Overlay {
    EndPieces { ... },
    BadgeLayer(spell, facing),
    SpellStatus { spell = spell },
}
```

Use **lowerCamelCase** for functions that return data or perform behavior:

```lua
local function sortedModifiers(spell) return items end
local function validateProps(props) ... end
local function revealFoundation() ... end
```

Use `UPPER_SNAKE_CASE` for immutable module constants and lookup tables. Use
`snake_case.lua` for files and folders. Exported component/actor tokens use
PascalCase and normally match their visible concept.

The rule applies to named application-authoring functions. Framework
algorithms such as `host:_resolve`, lifecycle methods such as `gallery:draw`,
and functions that return internal data nodes retain lower camelCase. Anonymous
`render = function(...)` and `Frog.each(..., function(...) ...)` callbacks do
not need invented names: their component or collection already supplies the
semantic owner.

## 2. Comments state ownership and purpose

Every Lua file under `src/frogui/` and `src/presentation/` starts with a short
comment explaining the file's responsibility. The comment answers “why does
this file exist?” rather than repeating its filename.

Every application component, actor, connected view, and named render helper
has a brief comment immediately above its definition. Describe the visible
responsibility or ownership boundary:

```lua
-- Places one or two stat badges beside the requirement end piece.
local function BadgeLayer(spell, facing, size)
```

Avoid empty narration:

```lua
-- BadgeLayer function.       -- not useful
```

Comment non-obvious geometry with the visual reason or invariant, not a
translation of the arithmetic. Comments should explain facts such as “two
badges bleed three pixels symmetrically” or “status borders paint last.”

Test-only components and actors follow the same rule: either an adjacent
comment or a clearly enclosing test comment must explain what contract the
probe exercises.

## 3. One file reads in a predictable order

Prefer this order for a component module:

1. file-purpose comment;
2. imports;
3. constants;
4. lowerCamelCase data/calculation helpers;
5. PascalCase private render helpers;
6. prop validation;
7. public component or actor;
8. attached addresses/actions/views;
9. one `return`.

Lua local functions must be declared before use. The public component may
therefore appear near the bottom. Its file-purpose comment or component-folder
README should tell a reader where to start.

## 4. Components and private render helpers

Create a real `Frog.component` when a visible concept:

- is reused;
- deserves independent props;
- should appear by name in F6 inspection;
- owns behavior or interaction; or
- becomes clearer when extracted into a small file.

Keep a PascalCase private render helper when the fragment is small, used only
by its owner, and has no independent behavior or identity. A private helper is
not a way to hide a second component-sized implementation inside the file.

If a render helper grows, promote it to a plainly named component in the same
component-family folder. Do not create `init.lua` barrels, adapters,
projections, companion style files, or geometry files.

## 5. Render trees should scan visually

- Put structural props before children.
- Keep child paint/layout order visible in the Lua table.
- Use local names for precomputed descriptions only when they remove real
  noise or are reused.
- Prefer a readable `if` over a dense `and/or` chain when the condition is not
  immediately obvious.
- Conditional children may use `condition and Child { ... }`; FrogUI ignores
  `false` and `nil` children.
- Key every reordered or generated child by stable domain identity.
- Keep semantic colors/fonts/assets in the presentation theme and
  component-specific geometry beside the component.
- Static semantic colors use theme tokens. Animated tint endpoints are numeric
  because FrogUI interpolates them; keep a one-owner endpoint beside its named
  recipe and comment its visual meaning instead of hiding it in framework code.

## 6. Public APIs are discoverable where they are used

- Every public primitive's complete LuaLS contract lives beside its export in
  `src/frogui/init.lua`. Hover and command-click must expose every accepted prop
  without requiring a developer to inspect Host validation.
- Give each primitive a separate multi-line documentation block with a blank
  line before the next primitive. Do not collapse the public vocabulary into
  one continuous comment or assignment run.
- Closed string vocabularies use literal-union aliases. Fields such as
  `justify`, `align`, `fit`, `axis`, and `dismiss` must offer editor completion
  for every accepted value.
- A new or renamed primitive prop updates four places in the same change: the
  inline LuaLS contract, Host validation, the code-reading guide, and a focused
  framework regression.
- Semantic font roles remain the default. Use `Text.fontScale` for deliberate
  local emphasis and keep the multiplier beside its component owner; change the
  theme role only when every semantic user should change.

## 7. Motion and feedback stay declarative

- Components attach named `juice` recipes or wrap content in `Frog.Motion`;
  they do not add per-frame update/draw functions for micro-interactions.
- Use a typed element event reaction with `do_ = Frog.play("name")` for facts
  and `{ recipe = Recipe, key = semanticKey }` for prop-driven one-shots.
- Give commonly reused pulse, flash, shake, and entrance compositions a
  PascalCase recipe name near their visual owner. Do not add a framework tag
  for a composition that is already readable as `Frog.sequence`.
- Select raw, playback, or feedback time explicitly with `Frog.withClock`.
  UI recipes never advance a clock themselves.
- `Frog.Motion` changes presentation only. Its parent allocates the stable
  layout footprint; scaling must not be used to negotiate sibling geometry.
- Removing a prop-driven Motion target restores its neutral presentation;
  do not preserve layout or semantic state in an animation runner.

## 8. Component and folder ownership

- One ordinary visible concept has one directly named file.
- A component with subcomponents owns one folder, such as
  `src/presentation/spell_card/`.
- A single-file owner stays a single file; do not create an otherwise empty
  folder for symmetry.
- SpellCard receives the cooked instance from `src.game.cards`. Its family may
  call the pure read-only display queries in `src.game.actions`, `affinities`,
  `modifiers`, and `requirements`; it must not mutate game state, draw RNG,
  advance simulation, or import Battle/Run command owners.
- Application state belongs to its actor, not App/root props.
- A stateful screen keeps its small typed actions, reducers, and concrete render
  with that actor. Do not extract a `state.lua`, action table, or generic
  render-callback projection to make a line budget appear smaller.
- Use `Button` for keyboard-visible actions and `Pressable` for pointer-only
  inspection/hold surfaces. Do not hide a keyboard shortcut in raw screen key
  handling.
- A `DragSource` owns the domain callback; a `DropTarget` exposes only a typed
  plain-data address and stable key. Never put Run/room policy into a target or
  the FrogUI interaction runtime.
- Keep `onDrop` to one atomic domain call and `return` its result directly. It
  must not send/emit or mutate the Host; UI state reacts in `onDragEnd` or to
  the typed `DragEnded` fact after the captured session is terminal.
- Use `Button.onCommit`/`onResult` only for one irreversible authoritative
  method call. Keep messages/navigation in `onResult`; a successful commit
  spends that exact control even if the follow-up fails. Ordinary Buttons use
  `onPress`.
- Compose drag and Scroll directly. Gesture thresholds and arbitration are
  framework constants, not component props or per-screen recognizer tables.

## 9. Updating this guide

When review creates or changes a convention:

1. update this document in the same change;
2. update the nearest code example and component-folder README;
3. bring the current FrogUI replacement surface into compliance;
4. run `love . --check frogui`, `love . --check docs`, and `git diff --check`.

Review new FrogUI code for these questions:

- Can names alone distinguish UI-returning functions from data helpers?
- Does every file and render owner explain its purpose?
- Can the main component tree be found immediately?
- Is component ownership explicit without a seam or barrel?
- Would promoting or inlining a private render helper make the file easier to
  read?
