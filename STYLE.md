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

### Code is the single runtime authority

- A tunable value or executable rule lives in exactly one code owner. Do not
  copy its literal into documentation, another component, or a test.
- Documentation explains purpose and names the owning Lua field/function; it
  does not maintain a second numeric table that can drift. When code and prose
  disagree, correct the prose and follow the code.
- Tests import the owner or assert semantic relationships. They do not restate
  production constants as independent expected values.
- Simulation owns every game-state transition. Presentation may consume the
  exact emitted fact and its resulting value for timed display, but it may not
  know or repeat the rule that produced it.
- A pre-implementation design may propose a value temporarily. The slice that
  implements it must move it into its one code owner and replace the document
  literal with that owner's name.

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
- Use `condition and a or b` only when `a` cannot be `false` or `nil`. Prefer an
  explicit `if` when retaining boolean state or other legitimately falsy data.
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
- `PopupText.travel = { x?, y? }` declares a directional trajectory from its
  authored `at` point; use `distance` for the ordinary straight-up float, never
  both. `PopupText.sound` attaches one semantic cue to the same keyed lifetime,
  so a visible transient and its audio cannot drift into separate owners.
- Semantic font roles remain the default. Use `Text.fontScale` for deliberate
  local emphasis and keep the multiplier beside its component owner; change the
  theme role only when every semantic user should change.
- Typed messages cross into the Host as one validated canonical copy. Each
  actor reaction receives a detached delivery copy, so an impure reducer cannot
  alter what later recipients observe. Keep payloads small and semantic. F6
  retains only compact delivery metadata—not payload archives or full
  before/after actor states.
- Actor actions, events, route props, and retained-process revisions reconcile
  the tree. Motion/effect clocks, painting, and process advance stay per-frame
  work and do not manufacture a render loop.

## 7. Committed refs name exact geometry

- Create geometry handles only with `Frog.useRef()` or one
  `Frog.useKeyedRefs(keys)` call inside a component, actor, or addressed-view
  render. Never construct a ref table or inspect a test id/path at runtime.
- Hooks are positional and unconditional. Keep every hook call on its own line,
  in the same order, outside branches and loops. Use `useKeyedRefs` when a
  dynamic authored collection needs handles; do not loop over `useRef`.
- Attach one handle to exactly one primitive with `ref = handle`. Never attach
  it to a component, actor, or view; those owners forward a specifically named
  anchor prop to the exact primitive they own. The public read-only `current`
  property returns a detached copy of that primitive's exact arranged
  `{ x, y, width, height }`, or nil while unattached/unmounted. Mutating the
  returned copy never changes FrogUI.
- Refs describe committed layout, not transient `Frog.Motion` paint transforms.
  Effects consume the stable arranged anchor and apply presentation motion in
  their own explicit layer.
- A candidate render, arrange, or resize never publishes partial rectangles.
  All current handles update together after Host commit; removal and unmount
  clear them together. Host-owned retained Scroll arrangements republish their
  descendant rectangles before observers run. A failed candidate keeps the
  last committed Scroll and ref geometry. Do not use a ref to decide simulation
  or ordinary component layout.
- Source sites make same-callback hook reorder fail loudly. Replacing a render
  callback during hot reload may refresh those sites only when count and kind
  still match; a structural hook edit keeps the last good tree and requires a
  gallery restart.

## 8. Mounted processes are explicit escape hatches

- Use `Frog.useResource` only when one semantic owner must retain a disposable
  external process. Ordinary menus, cards, layout, hover state, and visual
  recipes remain components, actors, primitives, or Motion.
- Keep `useResource` and `useFrame` calls unconditional, one per line, and in a
  stable order. Change the owner's semantic key when its process identity must
  change; do not add dependency arrays or manual caches.
- A resource factory returns `value, cleanup`. Cleanup belongs beside creation,
  is safe to call exactly once, sends no FrogUI messages, and does not change
  presentation. Unpublished-candidate failure, committed removal, compatible
  owner callback reload, and Host unmount are framework-owned lifecycle
  boundaries.
- `useFrame` advances only the retained process. A process with a broad view
  publishes a scalar semantic revision through typed `send` or `emit`; the
  resulting render reads the process's current detached snapshot once. A small
  process may publish one directly useful semantic scalar, never a broad view.
  It never calls Host render directly and never rebuilds the tree merely to
  expose smooth per-frame interpolation.
- Frame callbacks receive raw `dt` under normal and reduced-motion settings.
  Game-specific pause and speed policies belong explicitly inside their process,
  while visual micro-interactions continue to use named Motion clocks.
- Treat a frame callback exception as a development failure. It faults the Host;
  mutable resource internals cannot be rewound by the framework.
- Every mounted-process owner must fit on one readable screen: resource creation
  and cleanup, frame advancement, typed revision publication, one snapshot read,
  and the visible tree.
  Split the process implementation itself only when it is an independently
  named concept such as `BattlePlayback`.

## 9. Transient effects stay declarative

- Keep `EffectLayer` after the stable surface it decorates. It is a feedback
  plane, never a replacement owner for cards, figures, status, controls, or
  scene layout.
- EffectLayer children are direct `PopupText`, `Projectile`, `Flipbook`, or
  bounded `Canvas` leaves. Every generated finite effect has a stable
  authored/event key; later children paint above earlier ones and none
  participate in input.
- Give every `PopupText` a stable authored/event key and one layer-local center
  point. The popup owns its finite recipe; the actor or playback owner owns the
  keyed collection and removes an entry through `onComplete`.
- Use `float`, `impact`, or `notice` before adding custom motion. Override the
  public duration, distance, delay, text styling, or explicit clock only when
  the visible meaning requires it.
- Keep a popup's glyph scale fixed for its whole flight. Use its semantic role
  or `fontScale` to choose size at spawn time; continuously rescaling rasterized
  text shimmers when several independent popups overlap in time.
- Use the `impact` treatment for large result numbers before restating its rim,
  shadow, and top-band shine in an application component. Numeric treatment
  props may be set to zero when a specific surface deliberately needs plain ink.
- Anchor Projectile travel and Flipbook contact art to committed semantic refs
  when the owner can move or reflow. Use layer-local points only for deliberately
  detached feedback. Never query a test id or inspect the tree at runtime.
- Projectile `clock` owns arrival; `feedbackClock` owns its looping skin and
  trail. Flipbook `clock` owns frames, contact, and completion. Production
  playback names these policies explicitly instead of inheriting wall time by
  accident.
- Use `Flipbook.onContact` for the one visible contact beat and `onComplete` for
  keyed artwork removal. If contact intentionally removes the effect, its stale
  completion is canceled. Neither callback calculates a game result.
- Treat each effect key as one immutable timing contract. A changed duration,
  FPS, frame catalog, or contact point gets a new key; moving refs and ordinary
  paint props retain the current key and lifetime.
- EffectLayer is input-transparent and accepts no interactive descendants. Do
  not wrap an effect in Button/Pressable or add a parallel hit-test tree.
- Effects display authoritative event results. They never calculate damage,
  targets, modifiers, rewards, or other simulation state.
- Do not add a per-effect update/draw callback. Smooth lifetime sampling,
  resize reprojection, missing-art fallback, and reduced-motion settlement
  belong to the three effect primitives; owners publish only collection changes.

## 10. Sprite, tiled art, and shaders remain ordinary composition

- Use `Frog.SpriteSheet` for a continuously looping horizontal strip. Declare
  the semantic asset, exact `frameCount`, positive `fps`, and explicit
  `Frog.clock` at the visible call site; one frame owns intrinsic layout size.
- Choose the SpriteSheet clock deliberately. Raw idle motion normally uses an
  owner-advanced raw clock; execution or feedback animation receives that
  explicit clock instead. Reduced motion never silently substitutes a clock.
- SpriteSheet animation is a pure clock sample. Do not add playback keys,
  callbacks, completion events, per-frame rerenders, or component-owned frame
  state. Use finite `Flipbook` effects when completion/contact semantics matter.
- Keep horizontal sheet files exactly divisible by `frameCount`. Prefer the
  default `nearest` filter for pixel art; request `linear` explicitly when the
  authored asset needs it. Never mutate a cached Image's filter in application
  code.
- `Frog.Image { mirror = true }` is the RGB-preserving horizontal flip. Keep
  `Frog.Icon` for alpha-mask recoloring; mirroring is not a reason to use Icon.
- Application figures accept semantic `facing = "left"|"right"`; callers do
  not calculate `mirror`. `CharacterFigure` and `MobFigure` keep that mapping
  beside their own authored crop/sprite correction.
- Give `MobFigure` the explicit clock whose policy the owner intends. Battle
  will pass raw time for authored idle sheets; execution speed must never be
  inferred from component location or a global.
- `HealthBar` paints only authoritative static segments. The readable HP copy,
  name, and later Motion feedback remain visible parent composition;
  `ShieldBadge` is a sibling with a stable slot, not a hidden bar decoration.

- Use `Frog.TiledImage` for repeated authored art. The component declares its
  semantic asset token, arranged rectangle, tile size, repeat axis, phase,
  filter, and—when moving—an explicit clock plus velocity.
- Use `nearest` for the pixel-authored daylight forest. FrogUI snaps the shared
  phase once and keeps adjacent tiles exact; do not independently round tile
  copies or mutate a cached Image's filter from application code.
- The application owns clock meaning. Raw ambience may continue while paused;
  feedback/execution clocks may stop or scale. TiledImage and ShaderImage sample
  clocks but never advance them and never infer reduced-motion behavior.
- Wrap one `Image`, `TiledImage`, or empty `Box` in `Frog.ShaderImage`. Keep the
  unwrapped leaf readable in the same tree; do not create an all-in-one forest
  renderer or pass a custom draw callback.
- Shader source lives under a semantic token in `theme.shaders`. Components
  declare only that token, explicit uniforms, blend, and fallback. Never embed
  shader source, filenames, Battle event names, or hidden timing in a component.
- Use `fallback = "plain"` when the base art is meaningful without its shader.
  Use `hidden` only for optional shader-only decoration. A GPU failure must not
  remove essential world art, stop playback, or change a domain result.
- Use additive blend only for authored light. Ordinary wind, sway, dim, and
  color work remains alpha-composited unless its visible owner says otherwise.
- Build a background from small named visible components/layers whose source
  order is its paint order. Anchors, depth, parallax, and event reactions belong
  to the application composition; tiling and shader mechanics belong to FrogUI.

## 11. Canvas stays bounded and rare

- Use `Frog.Canvas` only when changing vector geometry cannot be expressed as
  ordinary primitives or the finite effect vocabulary. The accepted first use
  is the physical DiceShow; a Canvas never replaces cards, figures, status,
  controls, or background composition.
- Give every Canvas explicit width and height. Its callback draws in local
  coordinates and cannot participate in measurement, own children, or accept
  input. Put it in the same readable tree as the surfaces around it.
- Use only the record-only painter passed to the callback. Do not import
  `love.graphics`, hide another painter module, or retain the ephemeral painter
  after the callback returns.
- Keep physics, clocks, sounds, reduced-motion decisions, and semantic state in
  a plainly named owner outside Canvas. The draw callback reads that state and
  returns nothing; it never sends messages or changes the Host.
- Prefer semantic color tokens. Direct RGB[A] values are appropriate only for
  genuinely local treatment such as a translucent shadow.
- Keep `withTransform` scopes shallow and visible. Extract a lower camelCase
  painter helper when one complete visible shape makes the callback easier to
  scan. Do not create a companion painter/geometry file to hide a whole screen.
- DiceShow demonstrates the complete pattern: a keyed `DiceShowLayer` retains
  the process, advances it from explicit pause/speed policy, and gives Canvas
  only a read-only draw callback. Both the stateful process and its mounted
  owner are restart-only; the ordinary screen and tray components stay live.
  Its plainly named `dice_show_tuning.lua` numeric policy is presentation data
  and hot-reloads in place; use the next roll for one coherent tuned sequence.
  Cosmetic tumble faces are addressed fake values; the canonical `DiceTray`
  remains the only component that receives a newly revealed authoritative face
  and owns its arrival cue.
- A live resize retargets a retained Canvas process. Do not remount it, restart
  its clock, repeat its feedback key, or expose future semantic state merely to
  make custom drawing easier.
- Treat Canvas clipping and geometry safety as separate contracts. Author raw
  shape bounds, rounded corners, line widths, translations, and nested scale
  within the leaf-relative/hard ceilings enforced by `canvas.lua`; never copy
  those numeric ceilings into a component, story, test, or design document.
- Curve tessellation is framework-owned and capped. Never add a `segments`
  prop or hand-roll many tiny shapes to approximate an unbounded curve.

## 12. Motion and feedback stay declarative

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
- Select the owner's named time policy explicitly with `Frog.withClock`.
  Battle distinguishes raw, execution, dice, and feedback; ordinary UI normally
  uses raw. UI recipes never advance a clock themselves.
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

## 13. Component and folder ownership

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
- Use `HorizontalSwipe` only when one broad pointer surface must arbitrate
  against descendant tap/hold. Keep its child literal and its callbacks
  semantic. Place controls that must never compete with the swipe beside the
  surface, not inside it. Never add threshold props or application transfer
  callbacks.
- Use `RadialDial` only for one controlled ordered numeric choice. Author one
  keyed static upright child per value in the same order and keep all other
  controls as siblings. Application code receives only terminal
  `onChange(value)`; never expose angles, coordinates, movement callbacks,
  thresholds, or recognizers. Visible Button shortcuts precede the focused
  dial fallback. Its private bounce is ornamental paint overflow around a
  stable circular hit/layout footprint, and F6 must report that scale. Do not
  pad the dial or offset a direct option child; size the surface and faces.
- A centered selection rail uses Scroll's declarative `scrollPosition`,
  `snapInterval`, and final `onScrollEnd(position)` seam. Convert that settled
  offset into an actor-owned selected index; do not recreate raw drag sessions,
  per-move state, or carousel pointer math inside the component.
- When one actor replaces one visible region, mount it at that region and pass
  the ordinary child directly. When one state change has several visible
  consumers, mount the actor around the smallest common interaction region and
  use named addressed views at those concrete surfaces. For example,
  Liquidation reserves a staged copy in the active stack, drawer, and sale
  surface without copying that state into ShopScreen. Do not mount a hidden
  owner elsewhere or project its state through screen callbacks or generic
  render slots.
- A long-running simulation playback may separate three named responsibilities
  in one feature folder: `playback.lua` owns the event queue and clocks,
  `visible_state.lua` folds only committed events into detached display data,
  and `screen.lua` renders that data. Components never read the simulation,
  the reducer never arranges geometry, and the screen never advances time.
  This is an explicit process boundary, not permission to split ordinary
  component state into generic adapters or hidden state files.

## 14. Updating this guide

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
