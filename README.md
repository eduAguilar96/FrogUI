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

Each component, actor, and addressed view captures its definition `file:line`
once. Primitive descriptions created while that owner renders share the same
source object across every rebuild, including primitives returned by private
helpers. F6 therefore points to the readable semantic owner instead of paying
for a debugger stack scan on every temporary leaf. A primitive tree constructed
directly outside any semantic owner retains a one-shot caller source fallback.
Render and callback failures still report Lua's exact failing line. Positional
hooks remain the deliberate exception: their exact callsites are checked on
each render so a same-kind reorder cannot silently bind the wrong state or ref.

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

Calling a FrogUI tag detaches its top-level authored input into one framework-
owned props table. The returned description and its resolved primitive share
that exact table; FrogUI never copies it again and never mutates it. Treat
descriptions, `description.props`, and the nodes returned by `Host:tree()` as
read-only inspection values. To change UI, create a new description through a
component render or send an actor action. Nested tables and capabilities keep
their authored identity unless their specific API says it snapshots them.
Childless resolved primitives also share one read-only empty children
collection; containers with authored children retain private arrays. This
ownership keeps ordinary component syntax inexpensive without a proxy, deep
comparison, freeze walk, or hidden memo API.

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

The Host tracks one private scalar revision for arranged geometry plus ref
membership and one for the last complete publication. Candidate commits and
retained layout changes advance the first; successful ref publication
synchronizes the second. Ordinary `Frog.Motion` changes only visual transforms,
so matching revisions let the Host skip a redundant full-tree ref walk and
rectangle copies. This is automatic framework bookkeeping, not a component
revision or dependency API.

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

`Frog.ShaderImage` is a one-child wrapper, not another renderer. The child
resolves to an `Image`, `SpriteSheet`, `TiledImage`, or empty `Box`, so both
static and animated visible trees remain literal:

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
Wrapping a `SpriteSheet` does not create another animation clock or frame
lifetime. The sheet still samples its own explicit clock exactly once during
ordinary leaf painting; the wrapper changes only that selected frame's paint.

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
into the Host. FrogUI evaluates declarative reaction matches against that
read-only canonical record. Each reducer whose match accepts then receives its
own detached delivery copy, so one impure reducer cannot alter the event
observed by later recipients. Reducers return replacement semantic state; a
non-nil result requests one reconciliation. F6 keeps a bounded diagnostic trace
of token, origin, ordered recipients, acceptance, and reconciliation only. It
deliberately retains no message payloads or full before/after actor states.

FrogUI schedules that reconciliation at the actors whose typed state changed.
The changed actor and its semantic descendants rerun; quiet component, actor,
and view owners retain their last committed descriptions. FrogUI still
materializes, validates, measures, and arranges one fresh primitive tree, so a
changed child's size can reflow an untouched sibling correctly. Mount, direct
`Host:render`, resize, theme refresh, and hot reload always take a complete
semantic render. There is no memo API, equality callback, dependency list, or
authored dirty flag.

This makes ownership observable: a callback must not mutate a captured Lua
local and expect some unrelated actor's message to rerun the enclosing
component. Put visible mutable state in the actor that renders it, publish a
typed event to another owner, or pass a new root prop through explicit
`Host:render`. Stateless helpers remain ordinary `Frog.component` functions.

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

Uniform `scale` composes multiplicatively with independent `scaleX` and
`scaleY`. `pivot` is a normalized point inside the arranged box and defaults
to its center. Character reactions use a bottom-center pivot so squash,
stretch, and recoil keep the figure's feet on its standing line:

```lua
Frog.Motion {
    pivot = { x = 0.5, y = 1 },
    scaleX = { target = props.bracing and 1.08 or 1, spring = "snappy" },
    scaleY = { target = props.bracing and 0.92 or 1, spring = "snappy" },
    CharacterFigure { character = props.character },
}
```

All three scale values must be non-negative. The effective horizontal scale is
`scale * scaleX`; the effective vertical scale is `scale * scaleY`. Paint,
hit testing, and F6 use the same affine transform. A ref on Motion deliberately
continues to expose the stable arranged rectangle, not transient visual bounds;
use F6/inspection for transformed development geometry and refs for stable
effect/layout anchors.

A Motion with only immediate scalar/color values is fixed presentation. It
does not mount an animation process, even when `juice = {}` or
`reactions = {}` is present. Adding a spring target, a named recipe, or an
element reaction mounts retained runtime automatically; removing all of them
returns the same keyed element to fixed presentation. Component authors do not
manage that lifecycle or choose a separate primitive.

The current presentation properties are `x`, `y`, `rotation` in radians,
non-negative `scale`, `scaleX`, and `scaleY`, `opacity` from 0–1, and `tint`.
Animated tint endpoints must be numeric `{ r = ..., g = ..., b = ..., a = ... }` tables or
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

Recipe constructors detach mutable property tables and recipe arrays once.
The returned recipe is an immutable declarative value by authoring contract:
store it in a clearly named local or compose it inline, but never edit it after
construction. Create a new recipe to express a change. FrogUI retains that
validated value directly; `{ recipe, key, onComplete }` remains a fresh
candidate-owned binding, so keys and callbacks are not shared runtime state.
Like render purity, this is a lightweight Lua contract rather than a per-frame
deep comparison or proxy system.

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
F3 toggles the development frame-rate overlay. It reports LÖVE's real render
FPS plus rolling 180-frame average, p95, maximum, and over-25-ms count,
independent of Battle playback speed. FPS and average alone do not diagnose
uneven delivery. F4 expands it into the FrogUI execution profiler; that mode
adds observer work and its timings must not be read as player-mode frame
pacing. F6 shows the resolved component/primitive tree. F7 cycles viewport
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
rearranges the existing owners. One Playback publishes exact changed row and
flow addresses to stable actors in the ordinary `battle/screen.lua` and
`battle/board.lua`; it does not publish a complete visible snapshot to a
screen-level actor. The trace is a separate bounded diagnostic actor and
displays only committed event addresses. `src/presentation/battle/playback.lua`
is a stateful process, so edits to it require restarting the gallery; Battle's
ordinary visible component files remain hot-reloadable. The explicitly named
`static_screen.lua` and `static_board.lua` exist only for fixture/equivalence
checks and static component stories.

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
| `reconcile` | Dirty actor semantic scheduling, complete primitive expansion/layout, and publication |
| `expand` | Retained quiet-owner descriptions plus changed-owner callbacks expanded into one fresh primitive tree |
| `semantic` | Component/actor/view callback bodies only; hook setup/finalization is excluded |
| `prepare` / `bookkeeping` | Owner-local props/state copies versus actor/view/hook/path administration; neither wraps descendant resolution |
| `primitive validation/materialization/post` | Primitive prop validation, resolved-node/ref construction, then child-dependent validation |
| `Scroll/Radial/Motion/Effect reconcile` | Retention work for those exact primitive families during expansion |
| `deferred/ownership/order` | Deferred-view traversal, effect ownership validation, and event/hidden-actor ordering |
| `layout` | Two-pass measure and arrange of that candidate tree |
| `candidate transform` | The arranged candidate's post-layout Motion geometry walk |
| `interaction transform` | An immediate Scroll/RadialDial transform consumed during input or settling, before the next committed update |
| `runtime` | Retained interaction, Motion, refs, and Effect updates |
| `motion` | Runtime Motion runner sampling plus its committed-tree transform; the two child phases are also exposed |
| `refs` | Republish arranged ref rectangles after retained updates |
| `effects` | Projectile/Flipbook refresh, advancement, and bounds; each child phase is also exposed |
| `observer` | The profiler-only committed-tree counting walk performed on a rebuild |
| `external` | Complete public input routing, direct render, resize, or Host theme-refresh work before update |
| `paint` | Painter traversal and LÖVE draw submission |

`FrogUI CPU` is `external + update + paint`; parent and child phase lines are
attribution, not additional work. `reconcile` contains `expand`, `layout`, the
candidate transform, and commit. `expand` contains the semantic, preparation,
bookkeeping, primitive, retained-reconciliation, and post-walk buckets.
`runtime` contains interaction, Motion, refs, and effects; Motion and effects
then expose their own children. A transform caused directly by event delivery
has a separate `messageTransform` bucket and cannot inflate runtime Motion.
An immediate Scroll or RadialDial mutation likewise uses
`interactionTransform`; if it consumes the dirty bit, the later committed call
is truthfully recorded as a zero-visit skip.
`msg` deliberately excludes reconciliation. `action`, `event`, and
`transition` are nested within `msg`.
`observer` is profiler overhead, not application work; it remains visible so
it cannot be mistaken for unlabelled reconciliation cost. The
activity line shows semantic messages and rebuilds for the most recently
sampled frame plus the retained tree's nodes, render owners, effects, and
motions. The detached profile also retains descriptor/primitive totals, a
primitive histogram, identity/logical-path byte pressure, a source-attributed
description count, and the five semantic token kinds/names with the most
callback time. Source attribution is provenance coverage, not a capture-work
or duration proxy: descriptions normally share their semantic owner's one
definition source.
`dirty` ranks the rolling window's typed message/reflow causes without
retaining their payloads. The overlay refreshes this aggregate four times per second so reading
the profiler does not become its own hot path. Frame and runtime-phase heap
deltas are signed, observer-sensitive **net** movement. A negative value is GC
context, not negative allocation; these values are neither additive nor a
substitute for the separate GC-stopped gross-allocation pass.

`slowest` keeps one correlated completed frame from that same rolling window:
its total, frame callback, reconcile/layout, runtime, and paint timings stay
beside the exact dirty causes that occurred in that frame. Use it to distinguish
a simulation/playback spike from a rebuild or steady traversal cost; unlike
independent phase p95 values, these numbers all describe one frame.
The bounded Battle performance report additionally ranks five quiet frames by
runtime, breaking ties by chronological frame number, and prints their complete
Motion/transform/ref/Effect split plus signed frame heap delta. Rebuilt frames
therefore cannot crowd the quiet-runtime regression out of the evidence.

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
It contains timings, signed heap context, bounded semantic-owner rankings,
activity, structural counts, and compact dirty causes—not component
descriptions, messages, actor state, or simulation payloads.

Each trace row also has two transform/ref observer tables:

- `transformAttribution.candidate|message|committed|interaction` reports calls,
  runs/skips, nodes visited, exact invalidation/coalescing counts, source-family
  counts, changing Motion owners, dirty roots, LCA/branch coverage, and active
  geometry Motion owners. B4p.8 adds the chosen route, branch/full/fallback
  runs and visits, complete pending-target count, surviving/suppressed roots,
  routing-tree visits, and a bounded fallback-reason category. Motion labels
  are an exact count/name-ranked top five plus `other`; they contain only the
  semantic owner and each active geometry recipe on a changing owner as its
  declared name, root recipe kind, and geometry mask. They never contain paths,
  keys, props, state, or payloads.
  The Battle TSV writes every nonempty bounded category beside its exact phase,
  context, and frame. It preserves the row's named top five plus `other`
  without phase aggregation, reranking, or a second truncation, so owner/recipe
  evidence remains correlated with the locality and Battle activity row.
- `refAttribution.committed|interaction` reports refresh calls, revision-proven
  skips, collection visits, handles published/cleared, rectangles actually
  changed, and whether the decision followed visual Motion or a retained
  interaction invalidation. The latter is a cause flag, not proof that layout
  values differed; `changedRectangles` is the exact arranged-geometry
  comparison. Visual Motion can run while the already-published arranged-ref
  revision remains current; the two facts deliberately remain separate.

A committed run without an exact invalidation family is a framework invariant
failure. A skipped call always reports zero visits. Candidate layout is the one
explicit exception because a new tree needs its first transform before it can
be committed. Committed Motion-only invalidations may use the exact branch route
described below. Candidate, message, interaction, mixed, stale, unsafe, and
over-limit cases retain the full transform. Ref publication remains complete
after every candidate commit and retained arrangement. A committed update may
skip only when the Host's arranged/ref-membership revision exactly matches the
last complete publication.

Transform geometry still has one implementation: a non-recursive node writer
shared by full production recursion, exact branch recursion, and the
diagnostics-only observed recursion. Exact routing reads only the bounded
pending Motion-instance set and then the selected subtrees; it performs no
ancestor-discovery or full-tree routing pass. An ordinary run carries no
observer tables or category maps.
Static identity chains use their authoritative layout rectangles directly.
Only nodes below a private transformed boundary retain mutable visual-bounds
storage, and only a transformed clipping node retains transformed content
bounds. Custom painters still receive detached rectangle values; this storage
policy is invisible to component authors.
Both one-shot methods require a mounted, operational, diagnostics-enabled Host
at a quiet public boundary: never call them during update, draw, a component
callback, or external input routing.

### Battle performance gate

On macOS, run `tools/frogui/run_battle_performance_macos.sh` from any directory.
This exact-PID launcher is the only supported source of B4p evidence. The raw
`--frogui battle-performance acceptance|diagnostics` modes are internal halves
of the launcher and reject an unbounded direct invocation.

The launcher creates one task-specific directory under `build/frogui/`, then
runs two fresh LÖVE processes. `acceptance` mounts the reviewed deterministic
6v6 load fixture through the shipped retained Battle presenter and through
FrogUI's real `BattlePlayback` and `BattleScreen`. Both use a 540×960
battle-screen-only scope with app HUD, Inspection, hot reload, profiler
instrumentation, and audio excluded. `diagnostics` then runs fresh opt-in
FrogUI-only early/late observer sessions. The split prevents diagnostic history,
heap pressure, and retained engine state from contaminating pass/fail timing.
Observer-inflated timings provide attribution only.

Acceptance prints compact tables to the terminal and its captured stdout log.
Diagnostics prints only completion and artifact path, while writing the large
trace to `diagnostics-*.tsv.partial`. It atomically renames that file to
`diagnostics-*.tsv` only after every row, flush, and close succeeds. A partial
file, missing final file, missing completion stage, killed process, canceled
run, or machine restart is **INVALID evidence**. It may help diagnose a harness
failure but supports no FrogUI performance conclusion or optimization.

The pair becomes durable evidence only when the launcher atomically publishes
`battle-performance.complete`. That manifest records both statuses, every
result/artifact name and digest, the Git commit, whether the checkout was dirty,
and digests for tracked changes, status, and untracked source contents. A dirty
pre-commit checkpoint is valid because its exact source identity is explicit;
the commit name alone is never treated as the measured source. The launcher
recaptures the same identity after diagnostics and requires an exact match, so
an edit between the two processes invalidates the pair. It also requires each
child stderr log to contain its exact report-complete and quit-complete stages.
No manifest is published after source drift, a missing completion stage,
invalid acceptance, diagnostic failure, timeout, or launcher interruption.

Every expensive boundary writes and immediately flushes a structured stderr
stage containing elapsed time and cooperative-deadline state. Stages begin in
`src/game.lua` before the heavy probe module is required and cover window
creation, engine factory/setup, each measurement, diagnostic export, disposal,
GC, reporting, and quit. Lua cooperatively refuses new work after its code-owned
deadline. The outer launcher independently applies a longer code-owned deadline,
sends TERM, waits its short code-owned grace, then sends KILL to that PID only.
It captures child stdout and stderr byte-for-byte in separate regular files,
then replays each to its original terminal channel; no pipe or `tee` enters the
measurement. It always cancels/reaps its own watchdog and never uses a process
name, process group, `pkill`, or `killall`.
HUP, INT, or TERM sent to the outer launcher is forwarded to its one active
watchdog; the launcher boundedly reaps that exact process, which in turn stops
and reaps its exact LÖVE child. Cancellation gives the watchdog a short bounded
chance to run its TERM cleanup and reap its private deadline sleeper before an
exact-PID KILL fallback.

The non-graphical harness checks are
`tools/frogui/exact_pid_watchdog_check.sh` and
`tools/frogui/battle_performance_launcher_check.sh`. They use deterministic
shell fixtures, including a fake LÖVE executable; neither opens a game window.

Exit status has one meaning across the launcher: `0` is a completed acceptance
PASS plus completed diagnostics, `1` is a completed and valid acceptance target
miss plus completed diagnostics, `2` is invalid input/runtime/harness failure,
and `124` is the external deadline. Diagnostics still runs after acceptance
status 0 or 1, but not after 2 or 124. On any timeout or runtime failure cleanup
restarts a stopped collector but deliberately skips explicit full collection;
process exit reclaims the heap without adding another unbounded cleanup step.

Only diagnostic engines time `BattlePlayback:update()` and
`BattlePlayback:snapshot()` with tool-local cumulative scalars; the trace joins
their per-frame deltas after the sampled loop. FrogUI exposes no domain-call
registry or profiling API, and profiler-free acceptance calls both methods
directly without a timer. Disabled Hosts allocate no diagnostic
histogram/counter tables and perform no diagnostic timer or heap calls.
Expansion still crosses cheap nil-profiler guards so one implementation remains
authoritative; the Battle tool likewise crosses false observer-selection
branches instead of duplicating its root. Per-frame `last_event` and
`last_address` identify only the latest presented Playback record for context;
they are not asserted as the cause of a rebuild. Revision-stable rows are
labelled `(no playback change)`, while an unchanged address with a new revision
is labelled `(clock-only)`.

Late-round setup alone uses the fastest supported playback speed, then both
presenters return to one-times speed before measurement. Heartbeats sit outside
the timed update/draw interval. Setup clocks, an advance-frame limit, and a
GC-stopped allocation cap provide narrower fail-fast boundaries inside the two
process-level deadlines. Completed runs release the active Host or retained
Battle tree and restore shipped audio/window policy. A window close is a
runtime cancellation and therefore invalid evidence.

The timing window runs with normal garbage collection and separates update
from draw. A second, shorter window stops collection to report gross Lua
allocation per frame, then reports full cleanup time separately. Timing is
machine-specific, so acceptance uses shipped/FrogUI mean and p95 ratios, a
one-frame budget, and the fraction of over-budget frames; allocation has ratio
and absolute ceilings. The late sample is aligned at the committed-round level,
not to an identical within-round event address, so treat it as coarse pressure
evidence. An `alloc_capped=yes` row stopped at the safety ceiling: its printed
per-frame rate is a censored lower bound, not a complete-window mean. The
launcher exits 1 while any B4p target is missed. It is deliberately not part of
`--check frogui` and is unavailable in fused builds. This compares the currently
implemented presenter surfaces, not final visual parity: FrogUI does not yet
carry the remaining B5 feel/FX work, so current ratios are conservative and
must be re-run as parity lands. Warmup, frame counts, late-round boundary, and
provisional targets live only in `tools/frogui/battle_performance.lua`; do not
copy them into documentation or another check.

Three private, globally exclusive allocation modes provide causal construction
evidence without becoming public FrogUI APIs. `source` and `identity` retain
their established provenance/path controls. `structure` measures the semantic
application callback, descriptor normalization as a nested subset, and the
separate resolved primitive-node boundary. Primitive detail distinguishes the
base node/props copy, immediate child-array growth, and the later deferred-view
array pass. Every counter is preallocated and scalar while collection is
stopped; report rows are created only after collection restarts. These nested
facts must be interpreted correctly: descriptor bytes are already inside the
semantic total, while primitive materialization is disjoint and may be added to
the semantic total.

The pipeline allocation probe reports FrogUI's internal incremental-layout
path. It accepts only exact topology, stable values from the closed layout-prop
catalog, identical measurement constraints, an exact incoming arranged
rectangle, and branches outside Modal/Chrome, Scroll, RadialDial, EffectLayer,
and portal boundaries. Stable branches may share the immediately previous
immutable `node.layout` records; every mismatch performs ordinary layout.
`layout_incremental` rows report candidates, marked maximal branches, measure
hits, conservative misses, and committed branches/nodes. This is framework
evidence, not a component memoization API. Components declare no dependencies
or revisions.

That same private pipeline window also partitions `Painter.draw` without
adding another Battle replay. One preallocated row receives quiet draws and a
second receives draws whose immediately preceding update published a
candidate. Parent counters cover Canvas preflight, frame setup, visible-tree
traversal, inspector work, and finish; nested counters name first-draw storage
for the node scratch root, base style/transform/colors, Text and image leaves,
Icon outline treatment, PopupText shine color, and the one Host stencil
program. The nested cold sites are already inside preflight/tree and must not
be added to the Painter parent. Normal Hosts perform one nil probe lookup at
the start of a draw and never allocate these rows, call `collectgarbage`, or
retain attribution data. The default Painter may carry only callback-free
ephemeral scratch across a successful publication between the same logical
identity and primitive type. Default clipping uses one Host-lifetime callback
over synchronous scalar rectangle scratch; it never captures a component
node. The focused contract proves warm draw, equivalent render, resize,
rejected build, incompatible replacement, custom-painter isolation, and exact
Host cleanup.

The pipeline window also partitions `Host:update` into frame-subscriber
delivery, the retained runtime, feedback, completion delivery, and diagnostic
finish. The retained-runtime parent is split again into interaction,
Motion/committed transform, refs, and the three Effect phases. Quiet and
rebuilt updates use separate preallocated scalar rows. These rows are causal
allocation evidence only: ordinary Hosts retain no runtime observer table and
components receive no profiler or lifecycle API.

#### Current measured checkpoint

B4p.51 retains B4p.46's conservative incremental-layout implementation and
B4p.49's commit-safe continuity for callback-free default Painter scratch.
Default bounds, content, and text-shine clipping now share one Host-owned
synchronous stencil program. The callback closes over only scalar rectangle
scratch and nesting depth, never a committed or candidate node. Components
declare no cache, revision, or paint dependency.

Every primitive has one readable `node.layout` result. The candidate keeps its
fresh node shell, props, children, validation, reconciliation, transform,
input, refs, and commit boundary; only proven-stable layout records are shared.
Resize, theme/asset refresh, hot reload, portals, Scroll, RadialDial, and
EffectLayer remain full-layout boundaries. Focused tests prove reflow, shifted
siblings, changed text, barriers, rollback, and removal of temporary markers.

| Allocation boundary | B4p.48 early | B4p.49 early | Saved | B4p.48 late | B4p.49 late | Saved |
|---|---:|---:|---:|---:|---:|---:|
| rebuilt Painter draw | 722.884 KB | 46.272 KB | 93.60% | 884.808 KB | 63.210 KB | 92.86% |
| all frames | 205.103 KB | 159.895 KB | 22.04% | 905.152 KB | 604.048 KB | 33.27% |

The source-exact B4p.49 manifest is
`build/frogui/battle-performance-20260812T060909Z-82604`. It records stable
source identity, acceptance status 1 (completed cross-presenter target miss),
diagnostics status 0, no untracked source, uncapped allocation windows, and a
published 3,816-row artifact. Its publication probe transferred scratch for
2,364 primitive instances early and 20,724 late while allocating exactly 0 KB.
Timing is `1.843/4.967 ms` mean/p95 early and `3.346/10.078 ms` late, with zero
FrogUI over-budget frames; timing is machine-variable and B4p.49 claims only
the allocation recovery.

The attribution-only B4p.50 manifest is
`build/frogui/battle-performance-20260812T062207Z-86022`. Its same-window
expansion partition names 1,414.996 of 1,487.379 KB/rebuild early and 690.878
of 714.809 KB/rebuild late. The late total consists of 340.144 KB already owned
by semantic/validation/reconciliation phases, 285.869 KB of readable primitive
materialization, 49.357 KB of exact physical/logical paths, and 15.509 KB of
child publication; only 23.930 KB remains. The independent structure and
identity controls agree exactly. Standard allocation remains B4p.49-flat at
160.062 KB/frame early and 604.155 KB/frame late. This evidence rejects a
mutable retained-node/subtree cache; the flat candidate tree and rollback
boundary remain authoritative.

The source-exact B4p.51 manifest is
`build/frogui/battle-performance-20260812T063358Z-89357`. Relative to B4p.50,
rebuilt Painter draw allocation fell from 46.272 to 37.027 KB early and from
63.347 to 50.447 KB late. All-frame allocation fell from 160.062 to 159.361
KB/frame early and from 604.155 to 599.355 KB/frame late. The three early and
22 late publications reused the same Host stencil program; all clip-shape,
shine-shape, and measured-window stencil-program creation counters are exactly
zero. A separate cold-Host contract proves exactly one program is created on
first default draw and released on unmount. No node callbacks remain on the
candidate tree.

The source-exact B4p.52 manifest is
`build/frogui/battle-performance-20260812T064541Z-94616`. The arranged-ref
revision gate eliminated all 180 redundant committed collection/publication
walks in both early and late diagnostic windows while preserving all 60 late
RadialDial interaction publications: 56,701 tree visits, 2,520 handles, and no
skips. All-frame allocation fell from 38.286/159.361/599.355 to
23.764/144.716/584.861 KB/frame paused/early/late. Quiet-update allocation fell
from 16.682/17.439/77.003 to 2.057/2.814/62.441 KB per cohort frame. Candidate,
resize, failed-build, interaction, Motion, clean-frame, and cleanup contracts
all retain exact ref behavior.

The attribution-only B4p.53 manifest is
`build/frogui/battle-performance-20260812T070138Z-873`. Its stopped-collector
runtime partition explains the complete late quiet update: 62.503 KB/frame
measured, 62.503 KB/frame inside `Host:update`, and zero update-parent
remainder. Frame delivery owns 1.897 KB, the retained runtime owns 60.543 KB,
and feedback owns 0.063 KB. Inside the runtime, Motion plus committed
transform owns 41.283 KB, RadialDial interaction owns 18.542 KB, refs own only
0.063 KB, Effect update owns 0.203 KB, and the runtime wrapper remainder is
0.453 KB. Rebuilt late frames show the same two runtime leaders at
39.297/27.884 KB. This is transient presentation-process scratch, not
simulation state, component rendering, refs, or layout publication.

The attribution-only B4p.54 manifest is
`build/frogui/battle-performance-20260812T070729Z-3502`. It locates the Motion
cost without changing behavior: late quiet Motion remains 41.283 KB/frame,
of which runner sampling owns 30.430 KB, value seeding 3.428 KB, presentation
publication 3.408 KB, runner ordering 2.678 KB, and completion scratch/finalize
0.945 KB. Instance registry and completion sorting own another 0.395 KB; the
measured parent remainder is zero. Rebuilt frames repeat the same shape at
39.293 KB/frame, with runner sampling again dominant at 28.966 KB. The next
implementation therefore targets recipe sampling first and keeps deterministic
runner/completion order and candidate-isolated Motion state intact.

The source-exact B4p.55 manifest is
`build/frogui/battle-performance-20260812T071739Z-7171`. Retained runners now
compile immutable duration/write metadata once and reuse private value,
parallel-branch, and feedback-budget scratch. Late quiet Motion fell from
41.283 to 10.767 KB/frame; its runner sampler fell from 30.430 to 0.002
KB/frame. Rebuilt Motion fell from 39.293 to 16.062 KB/frame, with 5.831 KB of
first-use runner scratch still visible. Complete late FrogUI allocation fell
from 585.210 to 560.051 KB/frame (4.30%); paused and early remain flat because
they carry almost no active Motion. Recipes remain inert immutable data,
candidate runners remain isolated, and the complete Motion, feedback,
completion, transform, and rollback contract passes unchanged.

The source-exact B4p.56 manifest is
`build/frogui/battle-performance-20260812T072309Z-8977`. Compatible candidate
clones retain committed-only warm scratch while candidate composition uses
isolated temporary values. Each committed Motion owner reuses runner-order
entries, completion storage, an alternate value buffer, and its node's
presentation record. Late quiet/rebuilt Motion fell from 10.767/16.062 to
0.397/0.401 KB/frame. Ordering, value seeding, completion scratch, and
presentation publication are zero-allocation in quiet frames; complete late
FrogUI allocation fell another 14.245 KB/frame, from 560.051 to 545.806.
The remaining 0.356 KB/frame instance registry is deliberately deferred.

The attribution-only B4p.57 manifest is
`build/frogui/battle-performance-20260812T072834Z-11441`. It proves the late
interaction cost is not generic input or Scroll work: the settling RadialDial
owns the complete 18.542/27.884 KB per quiet/rebuilt frame. Its immediate
refresh spends 14.750 KB/frame republishing the complete Host ref surface,
2.633/4.883 arranging the dial, and 0.987/8.080 updating transforms. Session,
Scroll update, and invalidation allocate zero; the two registry lists together
cost 0.172 KB/frame. RadialDial's enforced contract makes option descendants
static and ref-free; its root rectangle does not move. The next implementation
therefore removes this false ref invalidation instead of adding a subtree-ref
capability the primitive currently rejects.

The source-exact B4p.58 manifest is
`build/frogui/battle-performance-20260812T073952Z-16027`. RadialDial orbit no
longer republishes refs or dirties the arranged-ref revision: option descendants
are still enforced static/ref-free, and an explicit root-ref contract proves
the fixed dial rectangle remains exact through settling. Late quiet/rebuilt
interaction fell from 18.542/27.884 to 3.792/13.134 KB/frame; both immediate
and end-of-update ref work are now zero/skip paths. Complete late FrogUI
allocation fell from 545.739 to 531.030 KB/frame (2.70%). Arrangement and
transform now explain the remaining active dial cost.

The source-exact B4p.59 run is
`build/frogui/battle-performance-20260812T074401Z-17634`. Full candidate layout
still measures every option, validates circular containment, and publishes the
controlled-change geometry signature. Retained drag/settle motion reuses those
committed immutable sizes and track radius, repositioning only the upright
static option subtrees. Late quiet/rebuilt arrangement fell from 2.633/4.883
to 1.125/3.375 KB/frame; complete late allocation fell from 531.030 to
529.502 KB/frame. Resize, rerender, failed candidates, input, and inspection
remain on their existing exact paths.

The source-exact B4p.60 run is
`build/frogui/battle-performance-20260812T075103Z-20261`. Retained RadialDial
instances now carry the same committed topology and transform-boundary record
already proven by Motion, so orbit changes transform exactly the dial subtree.
Synthetic diagnostic causes, Scroll, mixed causes, large-coverage requests,
portals, and stale topology retain the full authoritative fallback. Late quiet
RadialDial transform allocation fell from 0.987 to zero KB/frame; late rebuilt
transform fell from 8.080 to 3.906 KB/frame. Complete late allocation fell
from 529.502 to 528.156 KB/frame. This shares one transform router rather than
introducing a RadialDial-specific traversal.

The attribution-only B4p.61 run is
`build/frogui/battle-performance-20260812T075950Z-23330`. It separates the
frame-subscriber boundary without changing scheduling. On a late rebuilt
frame, FrogUI snapshot/wrapper plumbing costs about 1.001 KB, authored frame
callbacks 5.523 KB, typed delivery 39.050 KB, and the actor-local candidate
render 1,244.221 KB. The candidate owns 96.47% of the complete 1,289.794 KB
frame boundary; `useFrame` registry copying is not a material cause. Quiet
late frames likewise spend only 0.101 KB on the subscriber snapshot. The next
bounded runtime target is typed message delivery, while the already-attributed
fresh-candidate pipeline remains subject to the earlier ownership constraints.

The source-exact B4p.62 attribution run is
`build/frogui/battle-performance-20260812T080720Z-25958`. Of 38.231 KB typed
delivery allocation per late rebuilt frame, detached per-recipient event
snapshots own 22.312 KB, repeated receiver registry construction/sorting owns
9.247, trace publication 1.235, validation 0.567, actor reactions 0.035, and
the parent remainder 4.835. Transform and Motion reaction paths allocate zero
in this sample.

The source-exact B4p.63 run is
`build/frogui/battle-performance-20260812T081413Z-28536`. Each complete
candidate now publishes one ordered actor/Motion receiver list atomically on
mount, render, and resize. Event delivery reads that committed order directly,
so receiver ordering fell from 9.247 to zero KB/rebuilt frame and complete
typed delivery fell to 28.984 KB. Complete late allocation fell from 528.215
to 525.194 KB/frame. Per-recipient snapshots remain intentionally detached.

B4p.64 rejected a two-generation primitive-shell/child-array arena before
benchmarking. `Host:mount` and `Host:render` expose readable committed trees;
recycling a retired shell mutated a node retained by a caller and failed the
focused descriptor-props ownership contract. No arena remains. FrogUI keeps
old returned trees stable instead of adding proxies, epoch handles, or a hidden
public-tree lifetime rule.

The source-exact B4p.65 run is
`build/frogui/battle-performance-20260812T082804Z-32761`. Declarative reaction
matches now read the validated canonical event before FrogUI allocates a
private delivery. The 515 late matching-token reactions accepted only 54
reducers, so detached snapshot allocation fell from 22.312 to 2.339
KB/rebuilt frame and complete typed delivery fell from 28.984 to 9.012.
Complete late allocation fell from 525.194 to 517.686 KB/frame. Every accepted
reducer remains isolated by its own detached record.

The source-exact B4p.66 run is
`build/frogui/battle-performance-20260812T083343Z-34476`. The bounded Host
message trace now retains one recipient list plus compact transition statuses;
`messageTrace()` and F6 expand the same detached readable records on demand.
Complete late rebuilt delivery fell from 9.012 to 5.354 KB and late all-frame
allocation fell from 517.686 to 516.264 KB/frame. No diagnostic field or
recipient was removed.

The source-exact B4p.67 run is
`build/frogui/battle-performance-20260812T083903Z-36224`. A Host queue boundary
now creates one recursively detached, validated canonical record and retains
its already-known typed token. It no longer feeds that record through the
public constructor for a second top-level copy/validation or rediscovers its
token during delivery. Accepted reducers remain independently detached.
Complete late rebuilt delivery fell from 5.354 to 3.751 KB and late all-frame
allocation fell from 516.264 to 515.542 KB/frame.

The source-exact B4p.68 run is
`build/frogui/battle-performance-20260812T084237Z-37339`. Retained trace
provenance now stores the already-captured token/origin path and line as four
private scalars; `messageTrace()` and F6 reconstruct the same detached nested
source records on demand. Trace publication fell from 1.235 to 0.935 KB per
late rebuilt frame and late all-frame allocation fell from 515.542 to 515.401
KB/frame.

The source-exact B4p.69 run is
`build/frogui/battle-performance-20260812T084605Z-38427`. Rejected reactions
remain ordered public trace recipients, but their default false/false status is
no longer stored explicitly in the private parallel status table. Complete
late rebuilt message delivery fell from 3.451 to 3.099 KB/frame; public F6 and
`messageTrace()` records are unchanged.

The source-exact B4p.70 run is
`build/frogui/battle-performance-20260812T085316Z-40905`. Canvas still records
and validates every dynamic callback before every draw, but each command color
now uses static channel catalogs and one Canvas-owned tint/opacity output
instead of temporary validation, tint, fade, and detached-copy tables. Late
Canvas preflight fell 4.611 KB/quiet frame and 4.351 KB/rebuilt frame. Complete
late allocation fell from 515.365 to 510.878 KB/frame and now passes the
code-owned 512 KB target.

B4p closed on 2026-08-12 after the source-exact B4p.79 saturation audit. The
probe continues to print shipped-relative mean, p95, and allocation ratios as
comparison telemetry, but absolute FrogUI p95, over-budget frequency, uncapped
measurement, and the 512 KB/frame ceiling now own pass/fail. B5 must stop if an
absolute gate fails. The full ownership decision, rejected experiments, and
source hashes live in `design/reference/frog-ui-battle-migration.md`.
