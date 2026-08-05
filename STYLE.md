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
- Lua forwards every return value from a final function call. When one value is
  intended inside a child table or another call, assign it to a named local or
  parenthesize it. For example, write `(name:gsub(...))` in `Frog.Text` and do
  not pass `assert(value, message)` directly as another function's last
  argument; both functions return more than one value.
- Key every reordered or generated child by stable domain identity.
- Keep semantic colors/fonts/assets in the presentation theme and
  component-specific geometry beside the component.
- Static semantic colors use theme tokens. Animated tint endpoints are numeric
  because FrogUI interpolates them; keep a one-owner endpoint beside its named
  recipe and comment its visual meaning instead of hiding it in framework code.
- Do not make static identity or already-complete prose clickable. A Button
  must expose distinct value, and deeper rules need an explicit visible
  affordance instead of turning an entire title or paragraph into a surprise
  action.
- Keep actor state semantic. One selected atom may derive several ordered
  reference panels; store the atom identity and derive the panels in its
  presentation owner instead of retaining copied panel arrays in state.

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
- Use a named binding's `onComplete` only when the next semantic action must
  wait for that recipe. Completion is terminal and one-shot; it is not a
  substitute for ordinary actor actions, route state, or per-frame updates.
  Infinite recipes cannot complete; binding restart, key replacement, and
  unmount cancel the older completion generation.
- Give commonly reused pulse, flash, shake, and entrance compositions a
  PascalCase recipe name near their visual owner. Do not add a framework tag
  for a composition that is already readable as `Frog.sequence`.
- Select raw, playback, or feedback time explicitly with `Frog.withClock`.
  UI recipes never advance a clock themselves.
- `Frog.Motion` changes presentation only. Its parent allocates the stable
  layout footprint; scaling must not be used to negotiate sibling geometry.
- Removing a prop-driven Motion target restores its neutral presentation;
  do not preserve layout or semantic state in an animation runner.
- Components declare semantic sound ids, never asset paths or `love.audio`
  calls. Keep generic Button/hover/drag/dismiss behavior inherited from
  `theme.sounds`; override a primitive only when the action has a more precise
  meaning.
- State/event sounds use keyed or reaction-triggered `Frog.sound` recipes.
  Do not call the application audio provider inside actor actions, render
  functions, or domain callbacks.
- A new cue updates the provider catalog, its component owner, the code-reading
  guide, and a focused semantic-cue regression in the same change.

## 8. Component and folder ownership

- One ordinary visible concept has one directly named file.
- A component with subcomponents owns one folder, such as
  `src/presentation/spell_card/`.
- A single-file owner stays a single file; do not create an otherwise empty
  folder for symmetry.
- When two presentations share a substantive visible subtree, give that
  subtree one directly named component and let each shell own only placement.
  The room drawer and ordinary modal both compose `SpellbookBag`; neither
  carries a private copy of its cards, relic rail, targets, or scrolling.
- Extend a reusable source through one specifically named typed seam, never a
  catch-all callback. `onMutationDrop` is invoked only by a
  `spell-mutation` target carrying the exact room, visit and offer address;
  unknown target kinds remain rejected by the owned source.
- Keep visual variants centralized on the canonical component. Smithy supplies
  `variantFor` to the shared SpellCard stack/bag path so full spells use the
  standard dimmed face while remaining draggable for an authoritative refusal.
- SpellCard receives the cooked instance from `src.game.cards`. Its family may
  call the pure read-only display queries in `src.game.actions`, `affinities`,
  `modifiers`, and `requirements`; it must not mutate game state, draw RNG,
  advance simulation, or import Battle/Run command owners.
- Application state belongs to its actor, not App/root props.
- Declare actor `unmount(props, state)` only when that exact actor mount owns
  an external capability that must be released. Cleanup validates its captured
  identity, performs no FrogUI messaging/presentation, and remains safe after
  the capability was already consumed normally.
- Immutable route-issued catalogs/capabilities stay as screen props. Actor
  state stores semantic deltas such as consumed offer ids, exact receipts,
  feedback, and mode, then derives the remaining visible rows. Do not copy a
  full stock/opportunity projection into actor state.
- Name authority precisely. Smithy and Charmer receive immutable route-issued
  offer props; their visible ids only guard the selected drop. Transfiguration
  recipes are revalidated by Run's exact quote/commit authority.
- A stateful screen keeps its small typed actions, reducers, and concrete render
  with that actor. Do not extract a `state.lua`, action table, or generic
  render-callback projection to make a line budget appear smaller.
- Use `Button` for every keyboard-visible action or inspection surface. Its
  optional hold and hover callbacks preserve the same semantic control across
  touch, mouse, and keyboard while focus paint remains visible. Use
  `Pressable` only when the surface is deliberately pointer-only. Do not hide
  a keyboard shortcut in raw screen key handling.
- Keep a reusable visual component free of feature-global state. For spells,
  bare `SpellCard` is the static face and `InspectableSpellCard` is the named
  Button composition. The latter reports `(spell, inspectionKey)` through
  `onInspect`; the screen owns and mounts the one Inspection actor. Do not
  duplicate an anonymous press wrapper in each screen or make drag previews
  interactive.
- A `DragSource` owns the domain callback; a `DropTarget` exposes only a typed
  plain-data address and stable key. Never put Run/room policy into a target or
  the FrogUI interaction runtime.
- Keep `onDrop` to one atomic domain call. Return its boolean/detail result
  directly when the domain already follows that contract. When a read-only
  quote API returns `value, error`, adapt it once in the mounting screen's
  explicit capability to `true, value` or `false, error`; do not add a generic
  adapter or teach `DragSource` the domain's vocabulary. `onDrop` must not
  send/emit or mutate the Host; UI state reacts in `onDragEnd` or to the typed
  `DragEnded` fact after the captured session is terminal.
- Use `Button.onCommit`/`onResult` only for one irreversible authoritative
  method call. Keep messages/navigation in `onResult`; a successful commit
  spends that exact control even if the follow-up fails. Ordinary Buttons use
  `onPress`.
- A reusable scene-exit component may expose mutually exclusive shapes for
  those two meanings: `onPress` for plain route navigation, or
  `onCommit`/`onResult` when leaving must consume an exact domain capability.
  Do not manufacture a successful commit receipt just to reuse the visual.
- Compose drag and Scroll directly. Gesture thresholds and arbitration are
  framework constants, not component props or per-screen recognizer tables.
- When one actor replaces one visible region, mount it at that region and pass
  the ordinary child directly. When one state change has several visible
  consumers, mount the actor around the smallest common interaction region and
  use named addressed views at those concrete surfaces. For example,
  Liquidation reserves a staged copy in the active stack, drawer, and sale
  surface without copying that state into ShopScreen. Do not mount a hidden
  owner elsewhere or project its state through screen callbacks or generic
  render slots.

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
