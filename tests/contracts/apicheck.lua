-- Pins FrogUI 0.1 beta's public table, Host surface, service validation, and
-- explicit viewport/lifecycle policy without importing consumer code.

local Frog = require("frogui")
local support = require("tests.support")

local check = {}

local PUBLIC_FROG = {
    VERSION = true,
    Box = true, Button = true, Canvas = true, Chrome = true, Column = true,
    DragSource = true, DropTarget = true, EffectLayer = true, Flipbook = true,
    HorizontalSwipe = true, Icon = true, Image = true, Modal = true,
    Motion = true, Overlay = true, ParticleBurst = true, PopupText = true,
    Pressable = true, Projectile = true, RadialDial = true, Row = true,
    Scroll = true, ShaderImage = true, SpriteSheet = true, Text = true,
    TextInput = true, TiledImage = true,
    action = true, actor = true, clock = true, component = true, delay = true,
    each = true, emit = true, event = true, events = true, go = true,
    haptic = true, host = true, loop = true, on = true, oneOf = true,
    parallel = true, play = true, prop = true, pulse = true, send = true,
    sequence = true,
    shake = true, sound = true, spring = true, tween = true,
    useEvent = true, useFrame = true, useKeyedRefs = true, useRef = true,
    useResource = true, useViewport = true, withClock = true,
}

local PUBLIC_HOST = {
    "mount", "render", "refreshTheme", "viewport", "update", "draw",
    "resize", "pointerDown", "pointerMove", "pointerUp", "keyDown",
    "keyUp", "textInput", "wheelMoved", "mousepressed", "mousemoved",
    "mousereleased", "touchpressed", "touchmoved", "touchreleased",
    "keypressed", "keyreleased", "textinput", "wheelmoved",
    "setInspectorVisible", "inspect", "inspectionTree", "messageTrace",
    "diagnostics", "setDiagnosticsEnabled", "clearDiagnostics",
    "diagnosticTrace", "unmount",
}

local function rejects(label, callback, fragment)
    local ok, reason = pcall(callback)
    assert(not ok, label .. " unexpectedly succeeded")
    assert(tostring(reason):find(fragment, 1, true),
        label .. " rejected for the wrong reason: " .. tostring(reason))
end

local function options(extra)
    local result = {
        width = 540, height = 960,
        designWidth = 540, designHeight = 960,
    }
    for key, value in pairs(extra or {}) do result[key] = value end
    return result
end

local function publicInventory()
    assert(Frog.VERSION == "0.1.0-beta.1",
        "Frog.VERSION drifted from the release owner")
    for name in pairs(Frog) do
        assert(PUBLIC_FROG[name], "undocumented Frog export: " .. tostring(name))
    end
    for name in pairs(PUBLIC_FROG) do
        assert(Frog[name] ~= nil, "missing documented Frog export: " .. name)
    end
    local host = Frog.host(options())
    for _, name in ipairs(PUBLIC_HOST) do
        assert(type(host[name]) == "function",
            "missing documented FrogUIHost method: " .. name)
    end
    assert(type(host.tree) == "function",
        "internal Host:tree test seam disappeared without test migration")
end

local function serviceValidation()
    rejects("missing design dimensions", function()
        Frog.host { width = 100, height = 100 }
    end, "designWidth")
    rejects("partial physical dimensions", function()
        Frog.host { width = 100, designWidth = 100, designHeight = 100 }
    end, "both width and height")
    rejects("mixed viewport dimensions", function()
        Frog.host {
            width = 100, height = 100,
            viewport = { width = 80, height = 80 },
            designWidth = 100, designHeight = 100,
        }
    end, "either")
    rejects("invalid asset source", function()
        Frog.host(options { assets = { icon = false } })
    end, "must be a non-empty path or image object")
    rejects("unknown feedback service", function()
        Frog.host(options { feedback = { flash = function() end } })
    end, "unknown FrogUI feedback service")
    rejects("invalid reduced motion", function()
        Frog.host(options { reducedMotion = "yes" })
    end, "reducedMotion must be a boolean")
    rejects("invalid custom painter", function()
        Frog.host(options { painter = function() end })
    end, "experimental FrogUICustomPainter")
    rejects("unknown Host option", function()
        Frog.host(options { magicWidth = 12 })
    end, "unknown FrogUI Host option")
    rejects("invalid inspector flag", function()
        Frog.host(options { inspectorActive = "yes" })
    end, "inspectorActive must be a boolean")
    rejects("unknown viewport field", function()
        Frog.host {
            viewport = { width = 100, height = 100, surprise = true },
            designWidth = 100, designHeight = 100,
        }
    end, "unknown options.viewport field")
    rejects("unknown safe-area field", function()
        Frog.host(options { safe = { left = 1, surprise = true } })
    end, "unknown options.safe field")
    rejects("unknown button theme field", function()
        Frog.host(options { theme = { controls = {
            button = { surprise = "text" },
        } } })
    end, "unknown theme.controls.button field")
    rejects("unknown motion spring field", function()
        Frog.host(options { theme = { motion = { springs = {
            quick = { frequency = 10, damping = 1, surprise = true },
        } } } })
    end, "unknown theme.motion.springs.quick field")

    -- Root theme namespaces intentionally remain application-extensible.
    Frog.host(options { theme = { gameSpecific = { spacing = 12 } } })
end

local function viewportAndLifecycle()
    local derived = Frog.host {
        designWidth = 320,
        designHeight = 180,
    }
    local derivedViewport = derived:viewport()
    assert(derivedViewport.width >= 320 and derivedViewport.height >= 180,
        "LÖVE drawable derivation did not honor explicit design dimensions")

    local first = support.host {
        width = 1080, height = 1920,
        safe = { left = 3, bottom = 7 },
    }
    local second = support.host()
    local description = Frog.Box { width = "100%", height = "100%" }
    assert(first:mount(description) == nil,
        "Host:mount leaked its mutable committed node")
    rejects("second mounted Host", function()
        second:mount(description)
    end, "only one mounted Host")
    assert(first:render() == nil,
        "Host:render leaked its mutable committed node")
    local snapshot = first:viewport()
    assert(snapshot.scale == 2 and snapshot.safe.left == 3
            and snapshot.safe.bottom == 7,
        "explicit responsive viewport contract drifted")
    snapshot.safe.left = 999
    assert(first:viewport().safe.left == 3,
        "Host:viewport returned live safe-area state")
    first:resize(1920, 1080)
    assert(first:viewport().wide,
        "explicit wide resize did not rebuild responsive state")
    first._fontCache[14] = { retained = true }
    first._assetCache["fixture.png"] = { retained = true }
    first:unmount()
    assert(next(first._fontCache) == nil
            and next(first._assetCache) == nil,
        "unmounted Host retained its owned font or asset cache")
    second:mount(description)
    second:unmount()
end

function check.run()
    publicInventory()
    serviceValidation()
    viewportAndLifecycle()
    return true
end

return check
