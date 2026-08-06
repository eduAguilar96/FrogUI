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
| `Frog.Icon` | Draw and recolor an alpha silhouette | none |
| `Frog.Button` | Keyboard-focusable tap/hold box with visible theme states | zero or one |
| `Frog.Motion` | Animate one child's paint/input presentation without changing layout | zero or one |
| `Frog.Pressable` | Add pointer tap, hold, and mouse-hover to one child | exactly one |
| `Frog.Scroll` | Retain clipped wheel/touch scrolling on one axis | exactly one |
| `Frog.Chrome` | Root-host the one persistent application navigation surface | exactly one |
| `Frog.Modal` | Root-host one focus/input-isolated surface | exactly one |
| `Frog.DragSource` | Own a plain payload, preview, and domain drop callback | exactly one |
| `Frog.DropTarget` | Advertise one typed address to the deepest matching source | exactly one |

`Image` and `Icon` accept an optional source-pixel
`sourceRect = { x, y, width, height }`. The crop controls intrinsic size and
`fit`, stays deterministic when an asset is unavailable, and must remain
inside a loaded asset. This keeps sprite-sheet/cropped-art math declarative.

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
rollback restore each republish the newly arranged descendant rectangles before
their observers run. A failed surrounding transaction restores the previous
Scroll position and ref rectangles together.

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
    local revision, snapshot = playback:update(dt)
    if revision then
        send(SnapshotCommitted { revision = revision, view = snapshot })
    end
end)
```

`useResource(create)` calls `create` once for that component, actor, or
addressed-view lifetime. The function must return a non-nil value and one
cleanup closure. Ordinary rerenders, state changes, responsive Row/Column
switches, theme refreshes, and resizes retain the value. Changing the semantic
owner's key creates a new lifetime. A compatible owner-callback hot reload also
creates a fresh value; the old cleanup runs only after the replacement commits.
Stateful owner modules remain restart-only in the current gallery hot-reloader.

Failed candidate renders clean their unpublished resources and leave the live
resource alone. Failed outer callbacks also dispose any resource created by a
nested render and restore the previous lifetime. Successful removal and Host
unmount call cleanup exactly once. Cleanup is terminal: FrogUI tries every
pending cleanup, surfaces the first failure, never replays a disposed cleanup,
and forbids cleanup from sending messages or changing presentation.

`useFrame(callback)` receives the raw non-negative `dt` exactly once for every
Host update. It remains active under reduced motion; pausing a process is an
explicit condition inside the callback. Rerenders replace the closure without
adding a second subscription. Multiple frame callbacks run in semantic source
order against the tree committed at the start of the update.

Publish visible changes with typed `send` or `Frog.emit`. FrogUI queues every
frame publication, then reconciles once after all subscribers finish. Calling
`Host:render` directly from a frame callback rejects. If a callback fails, its
queued UI publications roll back. FrogUI cannot and does not pretend to roll
back arbitrary mutations already made inside the owned resource; a frame error
is therefore a development failure that must be fixed, not normal control flow.

Both hooks are positional and unconditional. Keep them on separate lines and
never put them behind a branch or loop. Hold F6 on the owner's visible root to
see its stable resource id, frame id, and mounted state. The generic gallery
story demonstrates pause, resize retention, snapshot publication, and explicit
resource reset without importing game code.

## Transient effect text

`Frog.EffectLayer` is a dedicated paint plane for finite visual effects. Put it
after the stable surface it decorates. It paints children in source order and
is always input-transparent, so a popup can cross a Button, drag target, or
scroll area without stealing that interaction.

`Frog.PopupText` owns the complete pop/rise/fade recipe. Application code owns
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
EffectLayer child, and the layer accepts only effect children; this is what
makes accidental interactive descendants impossible. Stable keys preserve
source ordering and guarantee one finite lifetime per entry.

The public variants are `float`, `impact`, and `notice`. Their defaults live in
[`effects/popup_text.lua`](effects/popup_text.lua); component code may override
`duration`, upward `distance`, or `delay` without rebuilding the recipe. Text
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

## State is a separate concept

`Frog.component` is stateless. `Frog.actor` defines a stateful component with
its initial state, accepted actions, reactions, render function, and optional
mount cleanup together.
Do not put menu state into a root component merely because the root can see the
menu.

An actor may declare `unmount(props, state)` when the actor itself owns an
external capability that must be released if its exact mount leaves the
committed tree. Cleanup runs once after a successful removal or Host teardown,
never for a failed render, same-key rerender, or resize. It is a terminal
domain boundary: use the actor's captured token and validate that it is still
current; do not send FrogUI messages or change presentation from cleanup.

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
keyboard focus order. `Scroll`, `Modal`, `DragSource`, and `DropTarget` own
generic mechanics; they never import Run, Reward, Spellbook, or another game
concept. A drag source alone calls the domain operation after FrogUI supplies
the deepest matching `{ address, key }` target.

Inside a Scroll, movement along its axis scrolls while cross-axis movement
drags. The fixed 8px/1.25-bias rule is Host-owned, so components never assemble
recognizers or receive raw pointer coordinates. Ordinary lists omit
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

An ordinary `Button.onPress` is reversible UI work. Use the explicit
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
plain data before delivery; a malformed successful result remains spent while
a malformed rejection remains retryable. If notification, navigation, or the first truthful
render then throws, FrogUI still settles queued actor state and never exposes
the spent control for a retry. A rejected call remains available. This narrow
boundary is for authoritative mutations only, not ordinary menu callbacks.

Platform input is root-only and cannot be called again from an active callback.
Messages drain breadth-first to quiescence: if a dirty render opens a Modal or
removes a drag source, the resulting cancellation fact drains before the input
transaction completes instead of being discarded.

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

The presentation theme defines six generic interaction defaults:

| Theme field | Used by | Current cue |
|---|---|---|
| `sounds.activate` | Button/Pressable tap, hold, or successful commit | `ui.activate` |
| `sounds.hover` | mouse entry into Button/Pressable | `ui.hover` |
| `sounds.reject` | rejected Button commit or drag drop | `ui.reject` |
| `sounds.dismiss` | Modal back/outside dismissal | `ui.close` |
| `sounds.dragGrab` | DragSource claiming the gesture | `drag.grab` |
| `sounds.dragDrop` | DragSource committing a drop | `drag.drop` |

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

The key must be a stable scalar that changes once per semantic occurrence. A
rerender with the same key does not replay the sound. A typed event reaction
may instead use `do_ = Frog.play("claimed")` on an element with that named
recipe. Both paths use the Host feedback transaction: failed callbacks,
messages, or renders emit no sound.

### Registering a new sound

Follow all five steps in one change:

1. Add the `.wav` under `assets/audio/`. Replacement UI assets keep the
   existing `ui_*` filename convention; components still never mention it.
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

Run `love . --frogui gallery`. F6 shows the resolved component/primitive tree.
F7 cycles viewport sizes. Saving the presentation theme, gallery/card story,
or a static component under `src/presentation/spell_card/`, `spellbook/`, or
`relic/` reloads it; F5 forces that scoped set. This includes the ordinary
`SpellbookOverlay` and shared bag surface, but not the stateful Spellbook actor.
A bad reload keeps the last good tree. Stateful actor modules and framework
core require a restart.

The generic committed-ref story appears between SpellCard motion and the
foundation story. Reverse its three keyed boxes with R, switch Row/Column with
F7, and use F6 to verify that each authored key keeps its ref id while its
arranged rectangle follows the new position.
