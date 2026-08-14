# FrogUI

FrogUI is a small, nested-component UI framework for LÖVE games. It keeps
screens readable, puts semantic state in actors, and provides responsive
layout, input, motion, feedback, transient effects, and diagnostics through one
Host. `0.1.0-beta.1` is application-capable but intentionally not a stable 1.0
API.

## Requirements

- LÖVE 11.5
- Lua 5.1 or LuaJIT (the runtime shipped by LÖVE 11.5)

## Install

Pin the repository as a submodule so every consumer uses an exact revision:

```sh
git submodule add https://github.com/eduAguilar96/FrogUI.git vendor/frogui
git -C vendor/frogui checkout v0.1.0-beta.1
git add .gitmodules vendor/frogui
```

Add the dependency root once in the game's bootstrap:

```lua
package.path = table.concat({
    "vendor/frogui/?.lua",
    "vendor/frogui/?/init.lua",
    package.path,
}, ";")

local Frog = require("frogui")
```

A tagged source archive may instead be unpacked at `vendor/frogui`; record its
tag and checksum in the game build. Do not copy or edit only the `frogui/`
runtime: that creates an unversioned fork.

## A component in 60 seconds

```lua
local Frog = require("frogui")

local RewardCard = Frog.component("RewardCard", function(props)
    return Frog.Box {
        width = 260,
        padding = 16,
        background = "panel",
        radius = 12,
        Frog.Column {
            gap = 8,
            Frog.Text { role = "heading", props.title },
            Frog.Text { role = "body", props.description },
            Frog.Button {
                onPress = function() props.onChoose(props.id) end,
                Frog.Text "Choose",
            },
        },
    }
end)

local Rewards = Frog.component("Rewards", function(props)
    return Frog.Column {
        gap = 12,
        Frog.Text { role = "heading", "Victory!" },
        Frog.each(props.rewards, function(reward)
            return RewardCard {
                key = reward.id,
                id = reward.id,
                title = reward.title,
                description = reward.description,
                onChoose = props.onChoose,
            }
        end),
    }
end)
```

Components are ordinary Lua functions that return descriptions. Box, Row,
Column, and Overlay own layout; visible concepts keep plainly named files.

## Wire one Host to LÖVE

```lua
local Frog = require("frogui")
local App = require("app")
local host

function love.load()
    local width, height = love.graphics.getDimensions()
    host = Frog.host {
        width = width,
        height = height,
        designWidth = 540,
        designHeight = 960,
        theme = require("theme"),
        assets = require("assets"),
    }
    host:mount(App {})
end

function love.update(dt) host:update(dt) end
function love.draw() host:draw() end
function love.resize(w, h) host:resize(w, h) end
function love.mousepressed(...) host:mousepressed(...) end
function love.mousemoved(...) host:mousemoved(...) end
function love.mousereleased(...) host:mousereleased(...) end
function love.touchpressed(...) host:touchpressed(...) end
function love.touchmoved(...) host:touchmoved(...) end
function love.touchreleased(...) host:touchreleased(...) end
function love.keypressed(...) host:keypressed(...) end
function love.keyreleased(...) host:keyreleased(...) end
function love.textinput(...) host:textinput(...) end
function love.wheelmoved(...) host:wheelmoved(...) end
```

Only one Host may be mounted in a Lua VM. Mount/render publish atomically and
do not return FrogUI's mutable committed tree.

## Actor, action, and event

```lua
local Increment = Frog.action("Counter.Increment")
local ResetRequested = Frog.event("counter.reset")

local Counter = Frog.actor("Counter", {
    initial = 0,
    actions = {
        [Increment] = function(count) return count + 1 end,
    },
    reactions = {
        Frog.on(ResetRequested) { transition = Frog.go(0) },
    },
    render = function(_, count, send)
        return Frog.Button {
            onPress = function() send(Increment {}) end,
            Frog.Text("Count: " .. count),
        }
    end,
})

Counter.App = Counter:address("app-counter")

local CounterApp = Frog.component("CounterApp", function()
    return Frog.Column {
        gap = 12,
        Counter { address = Counter.App },
        Frog.Button {
            onPress = function() Frog.emit(ResetRequested {}) end,
            Frog.Text "Reset every listener",
        },
    }
end)

-- Mount CounterApp {} from the one application Host.
```

`Counter { address = Counter.App }` mounts the actor at one stable address.
Its local `send` targets that actor; `Frog.emit` broadcasts a typed fact to
mounted reactions in deterministic breadth-first order. Simulation/domain
state stays outside FrogUI and supplies authoritative facts to presentation.

## Services and game feel

- `theme` owns semantic colors, font roles, control states, shaders, sound
  defaults, breakpoints, and motion presets.
- `assets` maps semantic ids to image paths or loaded images.
- `feedback.sound(cue)` and `feedback.haptic(cue)` map semantic cues to the
  consumer's platform services. Omitting either is a deliberate no-op.
- `reducedMotion = true` settles finite visual feedback while preserving
  terminal callbacks.
- Explicit clocks make pause and playback-speed policies visible.

FrogUI never imports a game audio catalog, simulation, content, or asset path.

## Run tests and examples

From the repository root:

```sh
love . --headless
love . --graphical
love . --example hello
love . --example gallery
```

CI runs both automated suites on LÖVE 11.5. This first beta is locally verified
on macOS; Windows, Android, and iOS consumer smoke passes remain explicitly
unverified rather than being implied by the tag.

## Guides

- [Getting started](docs/getting-started.md)
- [Host and LÖVE](docs/host-and-love.md)
- [Components and primitives](docs/components-and-primitives.md)
- [Actors, actions, and events](docs/actors-actions-and-events.md)
- [Responsive layout](docs/layout-and-responsive-ui.md)
- [Input, drag, and modal](docs/input-drag-and-modal.md)
- [Motion, effects, and feedback](docs/motion-effects-and-feedback.md)
- [Themes, assets, and fonts](docs/themes-assets-and-fonts.md)
- [Diagnostics](docs/diagnostics.md)
- [Architecture](docs/architecture.md)
- [Compatibility](docs/compatibility.md)
- [Authoring style](STYLE.md)

## Beta limitations

The default LÖVE painter is supported. `Host:tree()`, underscore-prefixed
allocation/replay probes, and the custom-painter callback protocol are internal
test seams during 0.x. FrogUI is not a retained document editor, simulation
framework, or general scene router. LuaRocks packaging is deferred until real
consumers demonstrate a need.

FrogUI is available under the [MIT License](LICENSE).
