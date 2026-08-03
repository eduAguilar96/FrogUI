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
| `Frog.Button` | One-child pressable box with theme states | zero or one |
| `Frog.Motion` | Animate one child's paint/input presentation without changing layout | zero or one |

`Overlay` is the important SpellCard primitive. Its first child is painted
first (behind); later children paint on top. It is used for visual layers, not
for application reuse or state.

Common layout props are `width`, `height`, `grow`, `padding`, `offset`, and
`testId`. Containers add `gap`, `align`, `justify`, `wrap`, `clip`, and
`overflow`. See the authoritative prop table in the
[FrogUI guide](../../design/reference/frog-ui.md#layout-used-by-ordinary-screens).

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

## State is a separate concept

`Frog.component` is stateless. `Frog.actor` defines a stateful component with
its initial state, accepted actions, reactions, and render function together.
Do not put menu state into a root component merely because the root can see the
menu.

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
| `Frog.host` | Create the one application tree owner |
| `Frog.clock` | Create a deterministic explicitly advanced clock |
| `Frog.tween` / `spring` / `shake` | Declare reusable visual recipes |
| `Frog.delay` / `sequence` / `parallel` / `loop` | Compose recipes without frame code |
| `Frog.sound` / `haptic` | Declare Host-provided feedback cues |
| `Frog.withClock` / `play` | Bind recipe time and trigger a named recipe |

The actor/message guide and production examples start at
[`design/reference/frog-ui.md` section 3](../../design/reference/frog-ui.md#3-state-belongs-to-the-component).

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

Host raw time drives unbound recipes. `Frog.withClock(clock, recipe)` must wrap
the entire named recipe and selects an explicit clock whose complete API is
`advance(dt)`, `now()`, and `reset(time)`. Motion is sampled from absolute clock time, so splitting a dt
does not change the result and Host updates do not rerender components.

Feedback is injected explicitly:

```lua
Frog.host {
    reducedMotion = accessibility.reduceMotion,
    feedback = {
        sound = function(cue) audio.play(cue) end,
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
| `condition and a or b` | Lua's compact conditional expression |
| `props.value or default` | use the prop, otherwise the default |
| `#items` | array length |
| `ipairs(items)` | ordered array iteration |
| `pairs(map)` | unordered key/value iteration |
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
F7 cycles viewport sizes. Saving the presentation theme, gallery card story, or
any existing component in `src/presentation/spell_card/` reloads it; F5 forces
that scoped set. A bad reload keeps the last good tree. Stateful actor modules
and framework core require a restart.
