# FrogUI: code-reading guide

This is the short, code-adjacent guide to the FrogUI vocabulary that exists
today. The longer design and application rules live in
[`design/reference/frog-ui.md`](../../design/reference/frog-ui.md).
Naming, comments, file structure, and review conventions live in the
continuously updated [`STYLE.md`](STYLE.md).

## The 30-second mental model

A **primitive** is a built-in layout or paint instruction understood directly
by FrogUI:

```lua
Frog.Text "Victory!"
Frog.Row { gap = 8, childA, childB }
Frog.Overlay { background, foreground }
```

A **component** is an application function that gives a readable name to a
tree of primitives and other components:

```lua
local RewardTitle = Frog.component("RewardTitle", function(props)
    return Frog.Column {
        Frog.Text { role = "title", "Victory!" },
        Frog.Text(("Gained %d gold"):format(props.gold)),
    }
end)

return RewardTitle
```

Calling either one creates a lightweight **description** of UI. It does not
draw immediately. The single mounted **Host** expands component descriptions,
validates primitive props, measures the resulting tree, paints it, and routes
input through it.

```text
RewardTitle { gold = 12 }       component description
              |
              | Host calls RewardTitle's render function
              v
Frog.Column { Text, Text }      primitive descriptions
              |
              | Host measures and arranges
              v
resolved nodes with x/y/w/h     painted and hit-tested tree
```

Each fresh candidate has one layout session. Within that single
`Layout.run`, a node may reuse only its immediately preceding measurement for
the exact normalized width/height constraints and portal mode. The result and
all measurement side effects already live on that fresh node. Arrangement
always still runs and invalidates the node's own entry before descendants can
be measured under final allocations.

This is traversal-local reuse, not retained layout caching. It never crosses a
candidate, frame, viewport, or theme refresh. Host-owned retained Scroll and
RadialDial arrangements deliberately run outside the candidate session and
measure normally.

## Component versus primitive

`Frog.component` and `Frog.Overlay` are not alternatives at the same level.

| Expression | What it is | Who understands it |
|---|---|---|
| `Frog.component("Name", render)` | Defines one reusable stateless component | Host calls `render(props)` |
| `Name { ... }` | Uses that component and supplies props/children | Host expands it |
| `Frog.Overlay { ... }` | Uses a built-in primitive | Host lays it out and paints it directly |
| `local function Layer(...) return Frog.Row {...} end` | Ordinary private render helper | Lua calls it; Host only sees the returned primitive description |

A component gives application meaning to UI: `SpellCard`, `SpellRequirement`,
or `RewardOffer`. A primitive only says how a box behaves: stack, flow, text,
image, or button.

Use a component when the concept is reused, deserves independent props, should
appear by name in the inspector, or is easier to understand as a visible
concept. Use a private helper only for a small, one-owner calculation or
one-use fragment that does not deserve its own public identity.

## Implemented primitives

These are created in [`init.lua`](init.lua). Their exact props are validated by
the Host, so unknown props fail loudly.

| Primitive | Purpose | Children |
|---|---|---|
| `Frog.Box` | Paint/pad one rectangular region | zero or one |
| `Frog.Row` | Lay children left-to-right | many |
| `Frog.Column` | Lay children top-to-bottom | many |
| `Frog.Overlay` | Give every child the same region; paint in listed order | many |
| `Frog.Text` | Draw text using a theme font/color role | none |
| `Frog.Image` | Draw an authored image while preserving its RGB | none |
| `Frog.SpriteSheet` | Loop equal-width frames from one horizontal strip | none |
| `Frog.TiledImage` | Repeat authored art with explicit phase/clock motion | none |
| `Frog.ShaderImage` | Apply a semantic shader and safe fallback to one paint leaf | exactly one |
| `Frog.Icon` | Draw and recolor an alpha silhouette | none |
| `Frog.Canvas` | Record bounded local vector shapes for rare custom drawing | none |
| `Frog.Button` | Keyboard-focusable tap/hold box with visible theme states | zero or one |
| `Frog.Motion` | Animate one child's paint/input presentation without changing layout | zero or one |
| `Frog.Pressable` | Add pointer tap, hold, and mouse-hover to one child | exactly one |
| `Frog.HorizontalSwipe` | Arbitrate a broad horizontal swipe against descendant tap/hold | exactly one |
| `Frog.RadialDial` | Select one controlled numeric value with internal circular preview | one keyed upright option per value |
| `Frog.Scroll` | Retain clipped wheel/touch scrolling on one axis | exactly one |
| `Frog.EffectLayer` | Paint ordered transient feedback without accepting input | many effect leaves |
| `Frog.PopupText` | Run one finite rising/fading text lifetime | none |
| `Frog.Projectile` | Travel once between committed refs or authored points | none |
| `Frog.Flipbook` | Play one finite frame sequence with an optional contact beat | none |
| `Frog.Chrome` | Root-host the one persistent application navigation surface | exactly one |
| `Frog.Modal` | Root-host one focus/input-isolated surface | exactly one |
| `Frog.DragSource` | Own a plain payload, preview, and domain drop callback | exactly one |
| `Frog.DropTarget` | Advertise one typed address to the deepest matching source | exactly one |

`Image` and `Icon` accept an optional source-pixel
`sourceRect = { x, y, width, height }`. The crop controls intrinsic size and
`fit`, stays deterministic when an asset is unavailable, and must remain
inside a loaded asset. Both also accept `mirror = true`; Image retains authored
RGB while Icon continues to recolor from alpha.

`Overlay` is the important SpellCard primitive. Its first child is painted
first (behind); later children paint on top. It is used for visual layers, not
for application reuse or state.

Common layout props are `width`, `height`, `grow`, `padding`, `offset`, and
`testId`. Containers add `gap`, `align`, `justify`, `wrap`, `clip`, and
`overflow`. See the authoritative prop table in the
[FrogUI guide](../../design/reference/frog-ui.md#layout-used-by-ordinary-screens).

### Discovering primitive props in the editor

Every FrogUI primitive has a dedicated, line-spaced LuaLS comment and complete
props type beside its public export in [`init.lua`](init.lua). With the
repository-recommended Lua extension, hover or command-click `Frog.Box`,
`Frog.Text`, `Frog.Button`, or another primitive to see what it does and every
accepted prop. Closed values are literal unions, so completion for `justify`,
`align`, `fit`, `axis`, and `dismiss` offers the legal options rather than an
unexplained string.

Runtime validation mirrors those contracts. An unknown prop or unsupported
value still fails loudly even when an editor is not present.

Alignment names describe how a parent places its child or children. To center
a button inside an Overlay:

```lua
Frog.Overlay {
    align = "center",   -- horizontal placement
    justify = "center", -- vertical placement
    Frog.Button { Frog.Text "Close" },
}
```

Changing `justify` on a Box moves the Box's child; it does not move that Box
inside its own parent. Change the surrounding Row, Column, Overlay, or Box when
the control itself needs to move.

Text begins at the semantic size selected by `role`. To tune one use without
changing every user of that role, apply a positive local multiplier:

```lua
Frog.Text {
    role = "spellLabel",
    fontScale = 1.25, -- this value only; still follows responsive role changes
    fitDown = true,   -- may shrink to fit, never grows the text
    "+8",
}
```

This sizing is dynamic: each render resolves the current theme role and then
multiplies it by `fontScale`. Change the role in the presentation theme when a
semantic class should change everywhere; use `fontScale` for intentional,
component-local emphasis.

## What `Frog.component` actually returns

```lua
local SpellCard = Frog.component("SpellCard", function(props)
    return Frog.Overlay { ... }
end)
```

`SpellCard` is a callable Lua table, sometimes called a component token. It
stores three important fields:

```lua
SpellCard.kind    -- "component"
SpellCard.name    -- "SpellCard"
SpellCard.render  -- the function above
```

This use:

```lua
SpellCard { spell = reward, facing = "left" }
```

returns a description containing the token and props. Later, during a Host
render, FrogUI calls `SpellCard.render(props)`. The function must return one
primitive or component description. A stateless component does not keep state
between renders and should not call `love.graphics`.

The callable-table trick is ordinary Lua metatable behavior implemented in
[`element.lua`](element.lua). FrogUI uses it only to make component trees read
like tags without adding a template language or compiler.

## Committed geometry refs

Effects sometimes need the exact arranged rectangle of a visible primitive.
Create one stable handle while its semantic owner renders, then attach it to
that exact primitive:

```lua
local Fighter = Frog.component("Fighter", function(props)
    local root = Frog.useRef()

    return Frog.Box {
        ref = root,
        width = props.width,
        height = props.height,
        CharacterFigure { character = props.character },
    }
end)
```

A newly mounted `root.current` is nil during its first candidate render. A
retained handle continues to expose its previous committed rectangle while a
later candidate builds. After the Host successfully measures, arranges, and
commits the whole tree, the read-only `current` property returns a detached
rectangle copy:

```lua
local rect = root.current
-- { x = ..., y = ..., width = ..., height = ... }
```

A failed render, arrange, or resize leaves the previous rectangle untouched.
Removing the attachment, removing its owner, or unmounting the Host clears it
back to nil. Mutating the returned copy never changes FrogUI. A handle may be
attached to only one exact primitive; putting `ref` on a component, actor, or
view rejects loudly, so a reusable component forwards named anchor props to
the primitives it owns. Refs report stable arranged layout geometry; a
transient `Frog.Motion` paint transform does not rewrite them.

Host-owned retained layout changes do update refs without rerendering the
component. Scroll drag, snap, wheel, momentum, keyboard focus reveal, and
other committed arrangements republish the newly arranged descendant
rectangles before their observers run. A failed candidate render or resize
never publishes its tree, Scroll geometry, or ref rectangles, so the previous
committed geometry remains readable.

For dynamic authored atoms, call one keyed hook instead of looping over
`useRef`:

```lua
local badgeRefs = Frog.useKeyedRefs(view.badgeKeys)

return Frog.each(view.badges, function(badge)
    return Frog.Box {
        key = badge.authoredIndex,
        ref = badgeRefs[badge.authoredIndex],
        Badge { badge = badge },
    }
end)
```

Retained scalar keys keep the same handle through reorders and resizes. Removed
keys clear their old handles; a later re-add receives a new handle. Ref hooks
are positional and unconditional, so put each hook call on its own line and do
not branch, reorder, or loop around calls. Hook count, kind, and same-callback
source reorder fail loudly rather than binding the wrong identity. A compatible
hot-reloaded render callback may move source lines while preserving count and
kind; structural hook edits require restarting the gallery.

## Mounted resources and frame callbacks

Ordinary components should remain pure render trees. Use a mounted process only
when one semantic owner must hold an external value and advance it over time,
such as Battle playback. The complete shape is intentionally two lines:

```lua
local playback = Frog.useResource(function()
    local value = Playback.new(props.route)
    return value, function() value:dispose() end
end)

Frog.useFrame(function(dt)
    local revision = playback:update(dt)
    if revision then
        send(RevisionPublished { revision = revision })
    end
end)

local view = playback:snapshot() -- once in the semantic render
assert(view.revision == state.revision)
```

`useResource(create)` calls `create` once for that component, actor, or
addressed-view lifetime. The function must return a non-nil value and one
cleanup closure. Ordinary rerenders, state changes, responsive Row/Column
switches, theme refreshes, and resizes retain the value. Changing the semantic
owner's key creates a new lifetime. A compatible owner-callback hot reload also
creates a fresh value; the old cleanup runs only after the replacement commits.
Stateful owner modules remain restart-only in the current gallery hot-reloader.

Failed candidate renders clean their unpublished resources and leave the live
resource alone. Successful removal and Host unmount call cleanup exactly once.
Cleanup is terminal: FrogUI tries every pending cleanup, surfaces the first
failure, never replays a disposed cleanup, and forbids cleanup from sending
messages or changing presentation.

`useFrame(callback)` receives the raw non-negative `dt` exactly once for every
Host update. It remains active under reduced motion; pausing a process is an
explicit condition inside the callback. Rerenders replace the closure without
adding a second subscription. Multiple frame callbacks run in semantic source
order against the tree committed at the start of the update.

When a retained process exposes a broad view, publish only a scalar semantic
revision with typed `send` or `Frog.emit`, then read the process's current
detached snapshot once during the resulting render. A small process may publish
a directly useful semantic scalar such as an elapsed checkpoint; it must not
put a broad view into actor state or message history. FrogUI queues every frame
publication, then reconciles once after all subscribers finish. Calling
`Host:render` directly from a frame callback rejects. A frame callback or
runtime reconciliation error fails loudly and faults that Host; FrogUI never
pretends it can rewind process internals.

Semantic reconciliation and per-frame advance are separate jobs. Actor
actions, events, route props, and process revisions rebuild the readable tree.
Motion, effects, clocks, painting, and a retained process's internal advance do
not rebuild it merely because another frame elapsed.

Both hooks are positional and unconditional. Keep them on separate lines and
never put them behind a branch or loop. Hold F6 on the owner's visible root to
see its stable resource id, frame id, and mounted state. The generic gallery
story demonstrates pause, resize retention, scalar revision publication, and
explicit resource reset without importing game code.

## Images, sprite sheets, and shader wrappers

`Frog.SpriteSheet` is the small, stateless choice for an infinitely looping
horizontal animation. The source must contain exactly `frameCount` equal-width
frames. Its width must divide exactly at mount when the asset is available:

```lua
Frog.SpriteSheet {
    source = "mob-idle",
    frameCount = 6,
    fps = 8,
    clock = props.rawClock,
    width = 144,
    height = 168,
    fit = "contain",
    mirror = props.facing == "left",
}
```

`frameCount`, positive `fps`, and a `Frog.clock` are required. The selected
frame is exactly `floor(clock:now() * fps) % frameCount + 1`; changing or
rewinding the clock changes the visible frame without rerendering. There is no
playback key, callback, completion event, or hidden lifetime. This primitive is
for continuous idle/environment animation; finite timed feedback still belongs
in `Flipbook`.

One frame supplies intrinsic layout size. When only `width` or `height` is
authored, FrogUI derives the other dimension from that frame's aspect ratio;
this makes height-owned character art readable without a parallel width
calculation. That implicit partner behaves like an authored dimension through
parent measurement and default stretch alignment, so a constrained parent does
not distort the frame. `fit` uses the same `contain`, `cover`, and `stretch` policies as
Image, `mirror` flips horizontally, `tint`
multiplies the authored RGB, and `filter` is `nearest` by default or explicitly
`linear`. FrogUI restores the shared asset's previous filter after drawing.
Missing declared art paints the standard crossed-box fallback while clock/frame
inspection remains available. Custom painters receive
`spriteSheet(node, asset, geometry, style)` with a sanitized node, current frame
geometry, and resolved tint. F6 reports frame, time, FPS, frame count, fit,
filter, mirror, clock ownership, and asset status.

`Frog.TiledImage` is a normal image leaf that repeats inside its arranged
rectangle. It owns tile coverage, one shared seam-free phase, clipping, filter
selection, and optional clock-sampled velocity. The application still owns the
clock and decides when that clock advances:

```lua
Frog.TiledImage {
    source = "forest-ground",
    width = "100%",
    height = 320,
    tileWidth = 448,
    repeatAxis = "x",
    phase = { x = props.parallax },
    velocity = { x = -4 },
    clock = props.rawClock,
    filter = "nearest",
}
```

`repeatAxis` is `x`, `y`, `both`, or `none`. An explicit tile dimension is at
least one logical pixel; supplying only one preserves the source aspect ratio.
Every leaf has a framework-owned finite copy budget, so invalid tiling fails
loudly instead of hanging a frame. `phase` is a static logical-pixel offset;
`velocity` requires a `Frog.clock` and is sampled during paint, so smooth drift
does not rerender the component tree. Nearest filtering snaps the shared phase
once to whole logical pixels before placing adjacent tiles. It never rounds
each copy independently, which would create moving seams.

`Frog.ShaderImage` is a one-child wrapper, not another background renderer.
The child resolves to an `Image`, `TiledImage`, or empty `Box`, so the visible
tree remains literal:

```lua
Frog.ShaderImage {
    shader = "background-sway",
    uniforms = {
        clock = props.rawClock,
        strength = props.windStrength,
        direction = { props.windDirection, 0 },
    },
    fallback = "plain",
    Frog.TiledImage {
        source = "forest-top",
        width = "100%",
        height = 320,
        tileWidth = 448,
        repeatAxis = "x",
        filter = "nearest",
    },
}
```

The `shader` value is a semantic token in `theme.shaders`; component files do
not embed GPU source. Uniforms are finite numbers, booleans, numeric vectors of
two through four values, or explicit clocks. A clock is sampled at paint time.
Use `blend = "add"` only for additive light; ordinary art defaults to alpha.

`fallback = "plain"` preserves the child unshaded after compilation, uniform,
or draw failure. This is the normal policy for forest wind and color effects.
`fallback = "hidden"` omits shader-only decoration such as optional light.
FrogUI logs the first failure for a semantic shader token, caches the failure,
and keeps the Host usable. F6 shows tile coverage/phase/clock and shader token,
status, uniforms, blend, and fallback.

Reduced motion does not secretly stop a SpriteSheet, TiledImage, or shader
clock. The owner defines that policy by advancing or pausing its explicit clock
in `useFrame`. This makes raw ambience, feedback time, and execution time
visibly different choices instead of framework guesses.

## Bounded Canvas drawing

`Frog.Canvas` is the narrow escape hatch for a visual whose already-owned
state must be painted as changing vector shapes. It is not a component model,
layout system, input surface, physics owner, or replacement for normal FrogUI
trees. Cards, characters, status, controls, and backgrounds remain ordinary
components and primitives.

A Canvas has explicit width and height, no children, and local coordinates
from `(0, 0)` through its arranged size:

```lua
Frog.Canvas {
    width = "100%",
    height = 240,
    draw = function(painter, rect)
        painter:fillEllipse {
            x = rect.width / 2,
            y = rect.height / 2 + 20,
            radiusX = 34,
            radiusY = 9,
            color = { 0, 0, 0, 0.3 },
        }
        painter:withTransform({
            x = rect.width / 2,
            y = rect.height / 2,
            rotation = props.angle,
            scale = props.scale,
        }, function(scoped)
            scoped:fillRect {
                x = -18, y = -18, width = 36, height = 36,
                radius = 7, color = "dieFace",
            }
            scoped:fillCircle {
                x = 0, y = 0, radius = 4, color = "diePip",
            }
        end)
    end,
}
```

The callback receives only an ephemeral record-only painter and a detached
local rectangle. Its vocabulary is `fillRect`, `strokeRect`, `fillCircle`,
`strokeCircle`, `fillEllipse`, and scoped `withTransform` with translation,
rotation, and uniform scale. Every shape declares a semantic theme token or
exact RGB[A] color; stroke shapes may declare `lineWidth`. Commands outside the
rectangle are clipped rather than changing layout.

The callback is paint-only and returns nothing. It may read presentation state
or an explicit application-owned clock, but it cannot send/emit, render,
resize, update, route input, unmount, or recursively draw the Host. Canvas owns
no clock and does not infer reduced-motion behavior: the state owner supplies a
settled value when reduced motion requires one. Repainting does not rerender a
component or advance time.

FrogUI validates, copies, and budgets commands before touching the GPU. A
malformed callback or replay restores color, line, transform, and stencil state
before `Host:draw` fails loudly. Raw geometry, stroke widths, rounded corners,
translations, and nested scale are bounded by one code-owned leaf-relative
envelope plus a hard absolute backstop; clipping never authorizes huge finite
GPU inputs. Rounded-rectangle radius is capped at half the smaller dimension.
Curves use one internal capped tessellation count; Canvas exposes no segment
control to application authors.
F6 shows local bounds, clipping, command count, transform depth, and ready
status. Failure metadata remains available to focused harnesses and recovery
checks, but a persistent preflight failure aborts before the F6 overlay can
paint. A custom Host painter receives detached commands and sanitized node
metadata, never the application callback or a framework child/session graph.

## Transient effects

`Frog.EffectLayer` is a dedicated paint plane for finite visual effects. Put it
after the stable surface it decorates. It paints children in source order and
is always input-transparent, so a popup can cross a Button, drag target, or
scroll area without stealing that interaction.

`Frog.PopupText` owns the complete rise/fade recipe. Application code owns
only a small keyed collection and removes an entry when its lifetime completes:

```lua
local PopupRemoved = Frog.action("PopupRemoved")

local function removePopup(state, key)
    local popups = {}
    for _, popup in ipairs(state.popups) do
        if popup.key ~= key then popups[#popups + 1] = popup end
    end
    return { popups = popups }
end

local Effects = Frog.actor("Effects", {
    initial = function(props) return { popups = props.popups or {} } end,
    actions = {
        [PopupRemoved] = function(state, action)
            return removePopup(state, action.key)
        end,
    },
    render = function(_, state, send)
        return Frog.EffectLayer {
            width = "100%",
            height = "100%",
            Frog.each(state.popups, function(popup)
                return Frog.PopupText {
                    key = popup.key,
                    text = popup.text,
                    at = popup.at,
                    variant = popup.variant,
                    color = popup.color,
                    onComplete = function()
                        send(PopupRemoved { key = popup.key })
                    end,
                }
            end),
        }
    end,
})
```

`at` is the popup box's center measured from the EffectLayer content's top-left
origin. A layer may use padding to move that origin. PopupText must be a direct
EffectLayer child. The layer accepts only effect leaves plus bounded Canvas;
all are input-transparent, which makes accidental interactive descendants
impossible. Stable keys preserve
source ordering and guarantee one finite lifetime per entry.

The public variants are `float`, `impact`, and `notice`. Their defaults live in
[`effects/popup_text.lua`](effects/popup_text.lua); component code may override
`duration`, upward `distance`, or `delay` without rebuilding the recipe. Use
`travel = { x?, y? }` instead of `distance` for an explicit directional path.
`sound = "semantic.cue"` emits that cue once with the same keyed lifetime, so
the visible transient and its audio cannot be authored as drifting siblings. Text
styling uses the same roles, colors, fitting, wrapping, and outline props as
`Frog.Text`. The `impact` default also owns the shipped combat-number treatment:
an impact font role, dark rim, drop shadow, and a brighter band across the top
of the glyph. `shadowOffset`, `shadowColor`, `shine`, and `shineSplit` are
explicit overrides; set the numeric treatment props to zero to disable them.

Popup glyph scale is fixed for its lifetime. Motion moves and fades the whole
rendered word, so rapidly inserted siblings cannot make older rasterized text
appear to vibrate through independent scale resampling. Choose `fontScale` once
when authoring the entry if one result needs more visual weight.

Omitting `clock` uses Host raw time. Supplying a `Frog.clock` makes the caller's
time policy explicit; the Host samples it but never advances it. Reduced motion
settles the popup immediately and delivers `onComplete` on the next Host update.
Resize recomputes the layer position without restarting the relative lifetime.
F6 shows layer count/input policy plus each popup's point, variant, treatment,
trajectory, clock, elapsed time, and progress.

Popups do not compute simulation results and do not run custom update/draw
callbacks. The simulation or playback owner creates plain display entries from
already-authoritative events. Sample committed refs when creating/reprojecting
those entries; PopupText only displays the resulting layer-local point.

### Travel and frame effects

`Frog.Projectile` and `Frog.Flipbook` are direct EffectLayer leaves. A
Projectile travels once from `from` to `to`; either anchor may be a committed
ref or a point local to the layer. A Flipbook plays a finite ordered frame list
at one ref or local point:

```lua
local source = Frog.useRef()
local target = Frog.useRef()

return Frog.Overlay {
    Frog.Row {
        Frog.Box { ref = source, SourceFace() },
        Frog.Box { ref = target, TargetFace() },
    },
    Frog.EffectLayer {
        width = "100%",
        height = "100%",
        Frog.Projectile {
            key = effect.id,
            from = source,
            to = target,
            duration = effect.travelTime,
            clock = props.executionClock,
            feedbackClock = props.feedbackClock,
            frames = effect.projectileFrames,
            onComplete = function()
                send(Arrived { id = effect.id })
            end,
        },
        impact and Frog.Flipbook {
            key = impact.id,
            at = target,
            frames = impact.frames,
            fps = impact.fps,
            clock = props.executionClock,
            contactAt = impact.contactAt,
            onContact = function()
                send(Contacted { id = impact.id })
            end,
            onComplete = function()
                send(Removed { id = impact.id })
            end,
        },
    },
}
```

The actor or playback owner keeps the small keyed collections. `onComplete`
normally sends the action that removes the exact entry; Projectile arrival may
instead replace it with a keyed Flipbook. `Flipbook.onContact` marks a visible
beat such as slash contact, while `onComplete` removes the artwork. If contact
removes the effect immediately, its now-stale completion is deliberately
canceled.

A stable key also retains the effect's timing contract. Change the key when a
Projectile's duration/FPS/frames or a Flipbook's FPS/frames/contact point must
change; FrogUI rejects those changes on an active key instead of silently
warping its visible lifetime. Endpoint refs, offsets, callbacks, dimensions,
and paint props may update while that lifetime remains mounted.

Projectile `clock` owns travel and arrival. Its optional `feedbackClock` owns
animated skin frames and trail aging, so visual feedback can remain readable
while execution is paused or accelerated according to the caller's explicit
policy. Flipbook has one `clock` for frame, contact, and completion timing.
Omitting a clock uses Host raw time; production playback should pass the named
policy whose meaning owns the beat.

Refs resolve to their committed primitive centers. When layout reflows, a live
Projectile preserves its current physical head, resolves the new semantic
target, and travels the remaining duration from there; its trail samples are
reprojected too. A Flipbook follows its ref while keeping its current frame and
already-fired contact bit. Rerender and resize never replay either callback.
Removing or replacing a key cancels stale callbacks. A ref must be attached to
one primitive when its effect first mounts; an unattached handle fails loudly.
If that primitive leaves later, an already-visible effect finishes at its last
resolved point instead of jumping or disappearing.

`frames` contain ordinary semantic asset tokens. Projectile frames loop while
it travels; Flipbook frames run once. Explicit `width`, `height`, `anchor`,
rotation/mirroring, and tint props style the art. Missing art keeps the same
timing and paints a primitive head or contact-ring fallback, so presentation
assets cannot stall playback. Reduced motion settles at the target/final frame
on the next Host update and delivers each still-mounted callback once. Hold F6
to inspect elapsed time, progress, frame, head/target, trail count, contact,
completion, and reduced-motion state.

## State is a separate concept

`Frog.component` is stateless. `Frog.actor` defines a stateful component with
its initial state, accepted actions, reactions, render function, and optional
mount cleanup together.
Do not put menu state into a root component merely because the root can see the
menu.

Typed actions and events become one validated canonical copy when they cross
into the Host. Each actor reaction receives a detached delivery copy, so one
impure reducer cannot alter the event observed by later recipients. Reducers
return replacement semantic state; a non-nil result requests one
reconciliation. F6 keeps a bounded diagnostic trace of token, origin, ordered
recipients, acceptance, and reconciliation only. It deliberately retains no
message payloads or full before/after actor states.

An actor may declare `unmount(props, state)` when the actor itself owns an
external capability that must be released if its exact mount leaves the
committed tree. Cleanup runs once after a successful removal or Host teardown,
never for an unpublished candidate, same-key rerender, or resize. If a
post-commit cleanup itself fails, the removal remains committed and the Host
faults. Cleanup is a terminal domain boundary: use the actor's captured token
and validate that it is still current; do not send FrogUI messages or change
presentation from cleanup.

The current public vocabulary is:

| API | Meaning |
|---|---|
| `Frog.component` | Stateless reusable component |
| `Frog.actor` | Stateful component owner |
| `Frog.action` / `Frog.send` | Typed request to one actor |
| `Frog.event` / `Frog.emit` | Typed fact broadcast to interested actors |
| `Frog.on`, `Frog.go`, `Frog.prop`, `Frog.oneOf` | Declarative actor transition helpers |
| `Frog.each` | Render a keyed array without losing item identity |
| `Frog.useViewport` | Read responsive viewport values while rendering |
| `Frog.useRef` | Retain one exact arranged primitive rectangle |
| `Frog.useKeyedRefs` | Retain exact primitive refs by authored scalar key |
| `Frog.useResource` | Own one disposable value for a semantic mount |
| `Frog.useFrame` | Advance that process once per Host update |
| `Frog.EffectLayer` | Paint ordered effects without accepting input |
| `Frog.PopupText` | Run one keyed finite text effect |
| `Frog.Projectile` | Travel one keyed effect between refs or points |
| `Frog.Flipbook` | Run one keyed frame sequence with a contact beat |
| `Frog.Canvas` | Record validated local shapes inside explicit bounds |
| `Frog.host` | Create the one application tree owner |
| `Frog.clock` | Create a deterministic explicitly advanced clock |
| `Frog.tween` / `spring` / `shake` | Declare reusable visual recipes |
| `Frog.delay` / `sequence` / `parallel` / `loop` | Compose recipes without frame code |
| `Frog.sound` / `haptic` | Declare Host-provided feedback cues |
| `Frog.withClock` / `play` | Bind recipe time and trigger a named recipe |
| `Frog.events.DragStarted` / `DragEnded` | Typed facts emitted by the Host-wide drag lifecycle |

The actor/message guide and production examples start at
[`design/reference/frog-ui.md` section 3](../../design/reference/frog-ui.md#3-state-belongs-to-the-component).

## Persistent application chrome

`src/presentation/hud/connected.lua` is the application-facing bottom
navigation layer. Its sibling `hud.lua` owns placement and `button.lua` owns
the icon face. Mount the connected component once after the current screen so
Book and Settings occupy the same lower-left/lower-right corners on every
route, leaving the center available to scene controls:

```lua
Frog.Overlay {
    CurrentScreen { run = run },
    Spellbook {
        address = Spellbook.Run,
        initial = "closed",
        run = run,
        -- screen-specific drawer and transaction callbacks stay here
    },
    Settings { address = Settings.App },
    ConnectedHud {
        run = run,
        bookDisabled = false,
        settingsDisabled = false,
    },
}
```

`ConnectedHud` is stateless. It places the shared HUD inside the application's
one `Frog.Chrome` portal. Its Book view observes the screen-owned Spellbook
actor, so
the root never receives or mirrors `bookOpen`. If that actor is absent, the
Book icon stays in place but is disabled. Passing `run` lets the closed Book
control request attention when the bag contains spells; `bookAttention`
overrides that derived value. `bookDisabled`, `settingsDisabled`, `bookHidden`,
and `settingsHidden` express route context without inventing another actor.
The application root mounts exactly one `Settings.App` actor beside the HUD;
the HUD's Settings view observes it directly. Each current screen mounts its
own Spellbook actor because its Run, presentation, and transaction callbacks
belong to that screen.

`Frog.Chrome` normally paints above the screen and below every Modal. An
ordinary modal Spellbook sets `allowChrome = true`, so that exact same root HUD
remains visible and usable: Book stays selected and closes the Spellbook, while
Settings opens its own isolated Modal above both. Inspection and liquidation
keep the default and therefore cover/block the HUD. This is generic portal
behavior; the Spellbook never receives or constructs a second HUD.

Scene actions remain separate. Room commerce contains Sell Spell, Sell Health,
and the shared `ExitButton`; it sits above the HUD and disappears behind an
open drawer. `hud.lua` exports `actionY` and `drawerInset` so screens share
those two clearances instead of copying coordinates. Use `CancelButton` for
every temporary-surface close control. It uses the authored cancel icon and
rejects hit targets smaller than 44px:

```lua
CancelButton {
    testId = "spellbook-close",
    onPress = closeSpellbook,
}
```

Book, cog, cancel, and exit image paths are semantic assets in
`src/presentation/theme.lua`. Application components refer to those tokens
through `Frog.Icon`; they do not load image files themselves.

## Interaction stays small

`Button` owns keyboard focus, shortcuts, disabled state, and activation. It
also accepts `onLongPress` and `onHoverChange` when the same accessible control
needs touch-hold or transient mouse inspection. Local
`hoverBackground`/`hoverBorder`, `pressedBackground`/`pressedBorder`,
`focusedBackground`/`focusedBorder`, and
`selectedBackground`/`selectedBorder` keep every interaction state visible.
Precedence is disabled, pressed, keyboard focus, selected, mouse hover, then
base. This is generic state paint, not an application painter hook.
Return, Space, and keypad Enter activate the focused Button before consulting
another control's shortcut; shortcuts are the fallback when no actionable
Button is focused. This prevents a screen-level default from stealing an
accessible component's activation.

`Pressable` remains pointer-only for a surface that deliberately must not enter
keyboard focus order. `HorizontalSwipe`, `RadialDial`, `Scroll`, `Modal`,
`DragSource`, and `DropTarget` own generic mechanics; they never import Run,
Reward, Spellbook, or another game concept. A drag source alone calls the
domain operation after FrogUI supplies the deepest matching
`{ address, key }` target.

`HorizontalSwipe` is the narrow broad-surface exception needed by the Battle
arena and similar paging regions. Its child stays completely readable:

```lua
Frog.HorizontalSwipe {
    onPress = props.dismissInspection,
    onSwipe = props.stepPage, -- receives "left" or "right" once
    Frog.Overlay {
        Background {},
        InspectableItems {},
    },
}
```

A descendant Button or Pressable remains the provisional tap/hold candidate.
Horizontal motion may claim the ancestor before either action completes; this
is Host arbitration before claim, not an ownership transfer. A claimed
swipe/drag/scroll/hold never transfers. The shorter claim band and longer
semantic completion band are one private code policy, so a small accidental
move can suppress inspection without changing application state. An active
Scroll or DragSource claims through the existing earlier policy and cannot
hand the gesture to HorizontalSwipe. Nesting selects the deepest swipe surface
deterministically. Keep named controls outside the broad surface when they must
never compete with it. HorizontalSwipe is pointer-only; keyboard actions still
use visible Buttons.

`RadialDial` is the controlled circular selector. Values and keyed option faces
are written together in the same order; FrogUI orbits each complete face
without rotating it:

```lua
Frog.RadialDial {
    width = 240,
    height = 240,
    value = state.speed,
    values = { 0.5, 1, 2 },
    trackRadius = 72,
    onChange = props.changeSpeed,
    SpeedOption { key = "slow", value = 0.5 },
    SpeedOption { key = "normal", value = 1 },
    SpeedOption { key = "fast", value = 2 },
}
```

Pointer movement changes only Host-owned preview positions. A completed release
emits one numeric `onChange(value)`, including a settled value equal to the
controlled value; cancellation emits nothing and restores toward controlled
state. A tap on the left half chooses the previous value and a tap on the right
chooses the next, with that direction fixed at pointer-down. An exact-center
tap does nothing. A drag that starts or crosses the center establishes its
angular origin only after leaving the dead-zone, preventing a jump. The
children are static presentation, so controls remain siblings. The circular
hit, center dead-zone, threshold, shortest-path raw-clock settle, and small
ornamental bounce are private policy. Reduced motion snaps the settle and
removes the bounce; direct pointer tracking remains truthful. `trackRadius` is
visual-only and must keep every option inside the circle.
RadialDial itself does not accept `padding`, and its direct option children do
not accept `offset`; size the circular surface and each option explicitly so
paint, hit testing, and F6 share one center.

Tab includes the dial in focus order and its focus ring is always visible.
Keyboard priority is deliberate: an actionable focused Button activates first,
then source-ordered Button shortcuts, then a focused RadialDial may handle
Left/Down as previous, Right/Up/Enter/Space as next, Home as first, and End as
last. A screen such as Analyze therefore keeps its visible seek Buttons
authoritative.
No application component receives an angle, pointer coordinate, movement
callback, threshold, or recognizer.

Inside a Scroll, movement along its axis scrolls while cross-axis movement
drags. Claim distance and directional bias are Host-owned, so components never
assemble recognizers or receive raw pointer coordinates. Ordinary lists omit
`scrollPosition` and retain their current offset. A selection carousel can set
`scrollPosition`, `snapInterval`, and `onScrollEnd`: arrows declaratively move
the selected item, a completed touch swipe snaps to one interval, and the
callback receives that final offset. FrogUI still owns pointer math; the
component only converts an offset into its semantic selected index. See the
exact constructors and cancellation order in [section 5 of the guide](../../design/reference/frog-ui.md#5-m4am4b-mobile-interaction-recipes).

`onDrop` is deliberately narrower than an ordinary UI callback: it calls one
atomic domain operation and returns its result. FrogUI ends capture before the
call, forbids messages and Host mutation inside it, then delivers
`onDragEnd`/`DragEnded`; later UI failure can never retry or claim to roll back
the domain operation. A Modal is likewise a real root portal: ancestor Motion
and Scroll do not move or clip it, and covered input is consumed. Several
independent Modals may compose in one tree. They paint in source order; only
the last portal receives pointer, wheel, keyboard, or text input. Closing it
restores the previous layer's keyboard focus before the base tree is exposed.
The sole `Chrome` portal is also Host-owned. It joins the top input plane only
when that Modal explicitly sets `allowChrome = true`; any later ordinary Modal
isolates it again.

An ordinary `Button.onPress` is presentation work. Use the explicit
`onCommit`/`onResult` pair only when one press crosses an irreversible domain
boundary such as claiming or skipping a Reward:

```lua
Frog.Button {
    shortcut = "s",
    onCommit = function()
        return run:commitSkipReward(quote) -- exactly one domain call
    end,
    onResult = function(status, receipt)
        if status == "committed" then
            send(Claimed { receipt = receipt })
        else
            send(Rejected { message = receipt })
        end
    end,
    Frog.Text "Skip",
}
```

`onCommit` cannot send messages, rerender, route input, or mutate the Host; it
must return `ok, detail`. A successful call spends that exact mounted Button
before `onResult` runs. `detail` is defensively snapshotted as finite, acyclic
plain data before delivery. Malformed detail faults the Host; a successful
authority remains spent, while a rejected result has made no authoritative
mutation but still requires a fresh Host. If notification, navigation, or the
first truthful render then throws, the Host faults and the spent control cannot
retry the committed domain call. A rejected call remains available after valid,
successful UI follow-up. This narrow boundary is for authoritative mutations
only, not ordinary menu callbacks.

Platform input is root-only and cannot be called again from an active callback.
Messages establish their canonical snapshot at the typed delivery boundary,
then drain breadth-first to quiescence through detached actor deliveries. If a
dirty render opens a Modal or removes a drag
source, the resulting cancellation fact follows in the next semantic batch.
Runtime callback, reducer, or reconciliation failures fault the Host instead of
restoring a broad pre-input snapshot.

After a fault, use `tree`, `viewport`, `inspectionTree`, `messageTrace`, or
`draw` only to diagnose the last committed presentation. The Host rejects
render, resize, theme refresh, update, messages, and input. Call `unmount`;
faulted unmount skips authored interaction callbacks while still cleaning every
mounted actor/resource exactly once. Then create a fresh Host. Never resume the
faulted instance.

An actor's local `send` keeps one mount-lifetime identity across ordinary
reconciliation, so a retained drag callback may safely report its result after
another actor rerenders. Unmount/remount creates a new lifetime; an old callback
then fails instead of reaching the new owner.

## Adding sound to a component

FrogUI components declare **semantic cue ids**, never asset paths and never
`love.audio` calls. The replacement application owns the cue-to-file mapping
in [`src/presentation/audio.lua`](../presentation/audio.lua), and its one Host
receives that provider once. This gives mute, volume, missing-file handling,
caching, and overlapping playback one owner.

### Controls already sound correct by default

The presentation theme defines eight generic interaction defaults:

| Theme field | Used by | Current cue |
|---|---|---|
| `sounds.activate` | Button/Pressable tap, hold, or successful commit | `ui.activate` |
| `sounds.hover` | mouse entry into Button/Pressable | `ui.hover` |
| `sounds.reject` | rejected Button commit or drag drop | `ui.reject` |
| `sounds.dismiss` | Modal back/outside dismissal | `ui.close` |
| `sounds.dragGrab` | DragSource claiming the gesture | `drag.grab` |
| `sounds.dragDrop` | DragSource committing a drop | `drag.drop` |
| `sounds.dialSpin` | RadialDial first entering free rotation | `dial.swoosh` |
| `sounds.dialCommit` | RadialDial terminal release/key activation | `dial.click` |

Most components therefore add no sound prop:

```lua
Frog.Button {
    onPress = props.onContinue,
    Frog.Text "Continue",
}
```

Use a semantic override when the action has more precise meaning. Editor hover
on `Frog.Button`, `Frog.Pressable`, `Frog.Modal`, or `Frog.DragSource` lists
every supported sound prop:

```lua
Frog.Button {
    sound = props.open and "ui.close" or "ui.open",
    onPress = props.onToggle,
    Frog.Text "Spellbook",
}

Frog.Button {
    sound = "shop.sell",
    onCommit = props.commitExactSaleQuote,
    onResult = props.onSaleResult,
    Frog.Text "Confirm Sale",
}

Frog.DragSource {
    grabSound = "drag.grab",       -- optional; already the default
    dropSound = "shop.purchase",  -- only after onDrop commits
    rejectSound = "ui.reject",    -- only after onDrop rejects
    payload = props.payload,
    preview = props.preview,
    onDrop = props.onDrop,
    props.content,
}
```

`Button.sound` covers an ordinary activation or successful `onCommit`;
`Button.rejectSound` covers a rejected `onCommit`; `hoverSound` covers mouse
entry. `Pressable` supports `sound` and `hoverSound`. `Modal.dismissSound`
covers both keyboard-back and outside-pointer dismissal. Pass `false` to any
sound prop to deliberately suppress that one inherited/default cue.
`RadialDial.spinSound` and `sound` override its start and terminal cues;
passing `false` suppresses either one.

### State changes and events use keyed juice

A cue that is not the direct result of a primitive interaction belongs beside
the semantic state or event that owns it. Use `Frog.sound` in a named recipe;
do not hide `audio:play()` inside an actor action:

```lua
Frog.Box {
    juice = {
        claimed = {
            key = props.claimReceipt.sequence,
            recipe = Frog.sound { cue = "reward.claim" },
        },
    },
    RewardSummary { receipt = props.claimReceipt },
}
```

When the state change is already represented by one keyed `Frog.PopupText`,
put the cue directly on that popup. It is shorthand for the same keyed juice
rule and cannot replay on an ordinary rerender:

```lua
Frog.PopupText {
    key = event.address,
    text = "=12",
    at = event.origin,
    travel = { x = 120, y = 0 },
    sound = "battle.execution.damage.1.total",
}
```

The key must be a stable scalar that changes once per semantic occurrence. A
rerender with the same key does not replay the sound. A typed event reaction
may instead use `do_ = Frog.play("claimed")` on an element with that named
recipe. Both paths stage feedback until their successful semantic commit. A
runtime failure discards unplayed staged feedback and faults the Host.

### Registering a new sound

Follow all five steps in one change:

1. Add the `.wav` under `assets/audio/`. Replacement UI assets keep the
   existing `ui_*` filename convention; gameplay cues may instead reuse a
   shared pool in `src/presentation/audio_assets.lua`. Components never mention
   either filename form.
2. Add one semantic cue entry to `CATALOG` in
   [`src/presentation/audio.lua`](../presentation/audio.lua). Name the event
   (`shop.purchase`, `spell.execute`), not the file (`ui_hold_drop`). A cue may
   list several files; the provider chooses one per play.
3. Declare the cue at its owner: use a primitive sound prop for an input
   interaction, or keyed/event-driven `Frog.sound` for a state/event outcome.
   Change `theme.sounds` only when the generic default should change for every
   component.
4. Add or update a focused check that asserts the semantic cue id. Device
   audio is not required for deterministic tests.
5. Restart the gallery after adding/replacing an asset or changing the catalog;
   the provider intentionally caches static Sources. Theme defaults and
   watched component cue props continue to hot-reload normally.

The provider fails loudly for an unregistered cue, skips a registered cue whose
file is absent, clones its cached base Source so rapid interactions overlap,
and reads `theme.audio.muted`/`volume` at play time. The gallery wires it like
this; the eventual application root will use the same single injection:

```lua
local Audio = require("src.presentation.audio")
local audio = Audio.new {
    settings = function() return theme.audio end,
}

local host = Frog.host {
    theme = theme,
    assets = theme.assets,
    feedback = audio:feedback(),
}
```

Run `love . --check frogui` after changing sound authoring. The focused
`tools/frogui/audiocheck.lua` verifies provider caching/overlap/settings and
the Button, hover, modal, and drag cue lifecycle.

## Motion and juice

`Frog.Motion` is a primitive, not a state owner. It keeps layout dimensions
fixed while its presentation moves, rotates, scales, fades, or tints. A scalar
is immediate; `{ target = value, spring = "snappy" }` animates when the target
changes. Removing a Motion target cancels that target animation and restores
its neutral presentation value; unrelated named juice keeps running. Motion
never chooses layout size—the parent always owns the stable footprint:

```lua
Frog.Motion {
    scale = { target = props.hovered and 1.04 or 1, spring = "snappy" },
    opacity = props.dimmed and 0.45 or 1,
    SpellCard { spell = props.spell },
}
```

The current presentation properties are `x`, `y`, `rotation` in radians,
non-negative `scale`, `opacity` from 0–1, and `tint`. Animated tint endpoints
must be numeric `{ r = ..., g = ..., b = ..., a = ... }` tables or
`{ red, green, blue, alpha? }` arrays because FrogUI interpolates their
channels; semantic theme-token strings remain valid for
ordinary static paint props but are not Motion targets.

Tween eases are exactly `linear`, `in_quad`, `out_quad`, and `in_out_quad`.
`Frog.spring` accepts explicit positive `frequency` and `damping`. A continuous
Motion target instead accepts either a plain `{ frequency, damping }` table or
one of these built-in preset names:

| Preset | Frequency | Damping | Intended feel |
|---|---:|---:|---|
| `gentle` | 8 | 1 | restrained settling |
| `snappy` | 14 | 0.82 | quick UI response |
| `bouncy` | 11 | 0.55 | visible overshoot |

An application theme may replace a named preset without changing components:

```lua
theme.motion = { springs = {
    snappy = { frequency = 16, damping = 0.9 },
} }
```

Juice attaches reusable named recipes to any element. An element reaction may
only respond to a typed event and may only run `Frog.play`; it cannot change
application state:

```lua
Frog.Box {
    juice = {
        impact = Frog.shake { x = 6, duration = 0.18 },
        appear = { key = props.appearKey, recipe = AppearRecipe },
    },
    reactions = {
        Frog.on(Events.DamageLanded) {
            match = { side = props.side },
            do_ = Frog.play("impact"),
        },
    },
    content,
}
```

The direct recipe form plays only when requested. The explicit
`{ recipe, key }` binding plays once when a non-nil scalar key changes,
including its first mount; an ordinary rerender with the same key does not
restart it. Recipes with the same name replace each other. Simultaneous names
compose in stable start order: shake contributes x, y, and rotation additively;
the later recipe owns a shared non-additive property.

A binding may add `onComplete = function() ... end` for one terminal follow-up
that inherently waits for the recipe, such as leaving a recovery screen after
its heal beat. FrogUI spends the completion before invoking it, after the Host
update commits. Replacing/restarting the binding or unmounting cancels the old
generation—even if an earlier completion rerenders during the same update.
Infinite recipes reject `onComplete`. Reduced motion settles immediately but
defers completion until the next update so render remains pure. A failed
callback is surfaced and never retried.

Host raw time drives unbound recipes. `Frog.withClock(clock, recipe)` must wrap
the entire named recipe and selects an explicit clock whose complete API is
`advance(dt)`, `now()`, and `reset(time)`. Motion is sampled from absolute clock time, so splitting a dt
does not change the result and Host updates do not rerender components.

Juice feedback uses the same provider described above. The low-level Host
shape is:

```lua
local host = Frog.host {
    reducedMotion = accessibility.reduceMotion,
    feedback = {
        sound = function(cue) audio:play(cue) end,
        haptic = function(cue) device.haptic(cue) end,
    },
}
```

Missing services are silent; unknown fields fail. Reduced motion snaps visual
recipes, removes shake, cancels the runner, and still delivers every declared
sound/haptic leaf once in deterministic recipe order. Feedback is staged until
the triggering callback, message batch, and render commit; failed work emits
nothing.

Cue names are opaque application identifiers. FrogUI neither searches for an
audio file nor decides whether an unknown cue is valid. The presentation/audio
integration owns the cue catalog and the injected callbacks decide whether an
unknown cue fails, logs, or skips. If the entire `sound` or `haptic` Host
service is absent, that feedback kind is a deliberate no-op.

F6 shows each element's declared recipe names, clock and keyed binding, its
reaction count, and every active recipe's clock, elapsed time, duration and
progress. It also marks the Host's reduced-motion mode.

The concrete [`card_motion_story.lua`](../../tools/frogui/card_motion_story.lua)
is an isolated laboratory proof, not a production Battle contract. It shows
the intended ownership split: a feature/card wrapper owns the semantic
`executing` prop and temporary recipe, while the canonical static `SpellCard`
only renders the supplied variant. The wrapper, not the animation runner,
decides when semantic execution starts and ends.

```lua
local function AnimatedSpellCard(props)
    return Frog.Motion {
        juice = {
            execute = { recipe = ExecuteRecipe, key = props.executionKey },
        },
        SpellCard {
            spell = props.spell,
            variant = props.executing and "executing" or "normal",
        },
    }
end
```

The feature's actor or playback owner supplies both props. `executionKey`
starts temporary feedback exactly once; `executing` remains the authoritative
semantic state and may last longer or shorter than the recipe.

## Lua syntax commonly seen in component trees

Some visual noise is Lua rather than FrogUI:

| Code | Read it as |
|---|---|
| `{ name = value, childA, childB }` | named props plus ordered children in one Lua table |
| `condition and child` | include `child` when true; FrogUI ignores `false` children |
| `condition and a or b` | Lua's compact conditional expression; safe only when `a` cannot be `false`/`nil` |
| `props.value or default` | use the prop, otherwise the default |
| `#items` | array length |
| `ipairs(items)` | ordered array iteration |
| `pairs(map)` | unordered key/value iteration |
| final `someFunction()` in a table/call | Lua may forward multiple return values; parenthesize or assign a local when exactly one is intended |
| `local function Name(...)` | private render helper visible only in this file |
| `local function name(...)` | private data/behavior helper visible only in this file |

Lua requires a local helper to be declared before code that calls it. That is
why a component's main render definition often appears near the bottom of its
file. When reading such a file, start at the exported component near the bottom
and follow helpers only as needed.

## File and ownership rules

- One directly named file owns one ordinary visible concept.
- A component family with real subcomponents owns one folder, such as
  `src/presentation/spell_card/`.
- Do not add `init.lua` barrels, adapters, projections, companion style files,
  or geometry files to hide ordinary composition.
- Shared semantic colors, font roles, and assets belong to the presentation
  theme. Component-specific geometry stays beside the component.
- A private helper is not automatically a component. Promote it when naming it
  makes the visible tree or inspector clearer.

## Development loop

Run `love . --frogui gallery`. Press L in the gallery to open the deterministic
Battle load acceptance fixture, then Space to play, R to replay the exact
captured fight, and the speed dial to increase playback pressure. It uses a
code-owned seed, pinned full-board spell deal, increasing dice pressure, large
HP pools, and a bounded long fight; its exact identity and pressure inputs stay
visible in the trace and live only in `tools/frogui/battle_load_fixture.lua`.
F3 toggles the development frame-rate
overlay; it reports LÖVE's real render FPS and average frame duration,
independent of Battle playback speed. F4 expands it into the FrogUI execution
profiler. F6 shows the resolved component/primitive tree. F7 cycles viewport
sizes. The gallery polls watched file contents and reloads
saved presentation theme/data tables, stories, and stateless components in
place; F5 forces that same scoped set. A bad candidate reload keeps the last
good tree. Failed candidate renders and resizes likewise leave the previously
committed tree, viewport, resources, and refs active. Runtime callback,
process, or effect failures are different: they fail loudly and fault the Host
instead of attempting to resume from a partial runtime advance.
Stateful actors/processes and FrogUI framework core require a restart because
their live instance schema cannot be safely replaced.

Battle follows the same split. Ordinary Battle components hot-reload.
`battle/dice_show_tuning.lua` and `battle/execution_tuning.lua` are named
`presentation-data` tables, so numeric DiceShow/execution edits reload without
restarting the gallery; press R or wait for the next semantic beat to see one
coherent updated sequence. Structural edits to
`dice_show.lua`, `dice_show_layer.lua`, `playback.lua`, or `visible_state.lua`
remain restart-only.

The generic committed-ref, process, transient-text, travel/frame, world-art,
and bounded-Canvas stories appear before the foundation story. The world-art story composes the
five daylight-forest assets from ordinary `TiledImage` leaves, wraps only its
canopy in `ShaderImage`, pauses its explicit clock with 1, toggles the wrapper
with 2, and reflows with F7. The Canvas story paints a rotating abstract marker
over a real Button, pauses its caller-owned clock with 1, and reflows with F7.
F6 shows each primitive contract in the exact tree.

The Battle sequence ends with a real `BattlePlayback` lifecycle story after
the static field/chrome story. It starts paused; Space plays or pauses the
ordered event trace, R rebuilds round zero with the same captured seed, and F7
rearranges the existing owner. The trace is deliberately bounded and displays
only committed event addresses. `src/presentation/battle/playback.lua` is a
stateful process, so edits to it require restarting the gallery; Battle's
ordinary visible component files remain hot-reloadable.

### Reading the F4 profiler

The gallery opts its Host into a fixed 180-frame diagnostic ring. Ordinary
Hosts retain no profiling history unless explicitly enabled. The expanded
overlay reports current, 95th-percentile, and maximum FrogUI CPU time, then
shows current/p95 update and paint cost plus p95 attribution by phase:

| Label | Work it includes |
|---|---|
| `frame` | Retained `useFrame` callbacks, including BattlePlayback advancement |
| `msg` | Typed action/event validation and reducer delivery |
| `action` / `event` | The corresponding typed-message validation, routing, and processing inside `msg` |
| `transition` | Actor reducer/transition work inside action or event processing |
| `reconcile` | The complete dirty semantic rebuild and publication |
| `expand` | Component/actor/view execution and primitive-tree construction |
| `layout` | Two-pass measure and arrange of that candidate tree |
| `runtime` | Retained interaction, Motion, refs, and Effect updates |
| `motion` | Motion runner sampling plus committed-tree visual transforms |
| `refs` | Republish arranged ref rectangles after retained updates |
| `effects` | Projectile/Flipbook anchor refresh, advancement, and bounds |
| `observer` | The profiler-only committed-tree counting walk performed on a rebuild |
| `external` | Complete public input routing, direct render, resize, or Host theme-refresh work before update |
| `paint` | Painter traversal and LÖVE draw submission |

`FrogUI CPU` is `external + update + paint`; nested phase lines are attribution,
not additional work. `reconcile` contains `expand`, `layout`, and the smaller
commit work; do not add
those numbers together. `runtime` contains the retained per-frame interaction,
Motion, ref, and effect work; `motion` also attributes whole-tree transforms
performed inside a semantic event or candidate reconciliation, so it may be
nested under `msg` or `reconcile` instead. `msg` deliberately excludes
reconciliation. `action`, `event`, and `transition` are nested within `msg`.
`observer` is profiler overhead, not application work; it remains visible so
it cannot be mistaken for unlabelled reconciliation cost. The
activity line shows semantic messages and rebuilds for the most recently
sampled frame plus the retained tree's nodes, render owners, effects, and
motions. `dirty` ranks the rolling window's typed message/reflow causes without
retaining their payloads. The overlay refreshes this aggregate four times per second so reading
the profiler does not become its own hot path. The Lua-memory delta is the net
heap change for the sampled frame, so a large negative value normally means
collection rather than free work.

`slowest` keeps one correlated completed frame from that same rolling window:
its total, frame callback, reconcile/layout, runtime, and paint timings stay
beside the exact dirty causes that occurred in that frame. Use it to distinguish
a simulation/playback spike from a rebuild or steady traversal cost; unlike
independent phase p95 values, these numbers all describe one frame.

This profiler answers where a spike lives; it is not a production telemetry
system and stores no props, actor states, messages, simulation events, or
component descriptions. A standalone development Host can opt in explicitly
and read the same detached aggregate. The read returns completed frames only;
an update that has not reached draw never contaminates rolling statistics:

```lua
local host = Frog.host {
    diagnostics = true,
}

local profile = host:diagnostics()
```

The detached snapshot also groups its rolling samples into `reconciled` and
`quiet` cohorts and exposes per-cohort activity totals. `increment()` activity
is aggregated separately from retained tree counts, so a node count is never
misreported as per-frame work.

One-shot measurement tools may clear setup history and export the bounded ring
in chronological order:

```lua
host:clearDiagnostics()
-- Run the fixed measurement window, including draw for every sample.
local frames = host:diagnosticTrace()
```

`diagnosticTrace()` allocates one detached row per retained frame. Call it once
after a bounded measurement; never poll it from an overlay or normal update.
It contains timings, activity, structural counts, and compact dirty causes,
not component descriptions, messages, actor state, or simulation payloads.
Both one-shot methods require a mounted, operational, diagnostics-enabled Host
at a quiet public boundary: never call them during update, draw, a component
callback, or external input routing.

### Battle performance gate

Run `love . --frogui battle-performance` for the explicit B4p comparison. It
mounts the reviewed deterministic 6v6 load fixture twice: once through the
shipped retained Battle presenter and once through FrogUI's real
`BattlePlayback` and `BattleScreen`. Both use a 540×960 battle-screen-only
scope with app HUD, Inspection, hot reload, profiler instrumentation, and audio
excluded from both acceptance measurements. Afterward, fresh opt-in FrogUI-only
early/late sessions clear setup history and export one bounded diagnostic trace;
those observer-inflated timings provide attribution and never affect pass/fail.
Per-frame `last_event` and `last_address` fields identify only the latest
presented Playback record for context; they are not asserted as the cause of a
rebuild. Revision-stable rows are labelled `(no playback change)`, while an
unchanged address with a new revision is labelled `(clock-only)`.
The command owns its warmup, frame counts, late-round boundary, and
provisional pass targets in `tools/frogui/battle_performance.lua`; do not copy
those values into documentation or another check.

The command is deliberately self-bounding: late-round setup alone uses the
fastest supported playback speed, then both presenters return to one-times
speed before measurement. Console/window heartbeats keep the synchronous run
visible and cancellable; setup and whole-command wall clocks, an advance-frame
limit, and a GC-stopped allocation cap abort a runaway probe. Every exit
restarts collection, releases the active Host or retained Battle tree, and
restores the shipped audio policy. A window close cancels the probe cleanly.

The printed timing window runs with normal garbage collection and separates
update from draw. A second, shorter window stops collection to report gross Lua
allocation per frame, then reports the full cleanup time separately. Timing is
machine-specific, so acceptance uses shipped/FrogUI mean and p95 ratios, a
one-frame budget, and the fraction of over-budget frames; allocation has ratio
and absolute ceilings. The late sample is aligned at the committed-round level,
not to an identical within-round event address, so treat it as coarse pressure
evidence. An `alloc_capped=yes` row stopped at the safety ceiling: its printed
per-frame rate is a censored lower bound, not a complete-window mean. The
command exits nonzero while any
B4p target is missed. It is deliberately not part of `--check frogui` and is
unavailable in fused builds. This compares the currently implemented presenter
surfaces, not final visual parity: FrogUI does not yet carry the remaining B5
feel/FX work, so current ratios are conservative and must be re-run as parity
lands.
