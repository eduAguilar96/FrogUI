-- Adversarial checks for ordered, input-transparent transient text effects.

local Frog = require("frogui")
local support = require("tests.support")

local check = {}

-- Requires a callback to fail with one actionable diagnostic fragment.
local function rejects(label, callback, fragment)
    local ok, err = pcall(callback)
    assert(not ok, label .. " unexpectedly succeeded")
    assert(tostring(err):find(fragment, 1, true),
        label .. " rejected for the wrong reason: " .. tostring(err))
end

-- Returns the inspection record for one visible test id.
local function inspectionEntry(host, testId)
    for _, entry in ipairs(host:inspectionTree().nodes) do
        if entry.testId == testId then return entry end
    end
    error("missing inspection entry " .. testId, 0)
end

local pressed = 0
local completed = 0

-- Places two popups above a real Button to prove ordering and pass-through.
local BasicEffects = Frog.component("EffectCheckBasic", function()
    return Frog.Overlay {
        width = 240,
        height = 140,
        Frog.Button {
            testId = "effect-underlay",
            width = 240,
            height = 140,
            onPress = function() pressed = pressed + 1 end,
            Frog.Text "underlay",
        },
        Frog.EffectLayer {
            testId = "effect-layer",
            width = 240,
            height = 140,
            Frog.PopupText {
                key = "first",
                testId = "popup-first",
                text = "+4",
                at = { x = 70, y = 60 },
                variant = "float",
                onComplete = function() completed = completed + 1 end,
            },
            Frog.PopupText {
                key = "second",
                testId = "popup-second",
                text = "Blocked",
                at = { x = 170, y = 80 },
                variant = "impact",
                onComplete = function() completed = completed + 1 end,
            },
        },
    }
end)

-- Proves geometry, source order, F6 metadata, motion, and input transparency.
local function basicContract()
    pressed, completed = 0, 0
    local host = support.host { width = 240, height = 140 }
    host:mount(BasicEffects {})
    local tree = host:tree()
    local layer = assert(support.find(tree, "effect-layer"))
    local first = assert(support.find(tree, "popup-first"))
    local second = assert(support.find(tree, "popup-second"))
    assert(layer.type == "EffectLayer" and #layer.children == 2,
        "EffectLayer did not retain its ordered children")
    assert(layer.children[1] == first and layer.children[2] == second,
        "EffectLayer changed authored popup paint order")
    support.near(first.layout.x + first.layout.width / 2, 70,
        "first popup center x")
    support.near(first.layout.y + first.layout.height / 2, 60,
        "first popup center y")

    local layerEntry = inspectionEntry(host, "effect-layer")
    local popupEntry = inspectionEntry(host, "popup-second")
    assert(layerEntry.effectLayer.input == "transparent"
            and layerEntry.effectLayer.count == 2,
        "F6 omitted EffectLayer input/order metadata")
    assert(popupEntry.effect.variant == "impact"
            and popupEntry.effect.at.x == 170,
        "F6 omitted PopupText variant/point metadata")
    assert(popupEntry.effect.treatment.role == "impact"
            and popupEntry.effect.treatment.shadowOffset > 0
            and popupEntry.effect.treatment.shine > 0,
        "F6 omitted PopupText treatment metadata")
    assert(second.props.role == "impact"
            and second.props.shadowOffset > 0
            and second.props.shine > 0,
        "impact PopupText omitted its shipped number treatment")
    local impactScale = second.presentation.scale
    assert(popupEntry.motion.active[1] == "lifetime",
        "PopupText did not start its keyed lifetime")
    host:draw() -- exercises the default rim, shadow, and shine paint passes

    local physicalX, physicalY = host._viewport:toPhysical(70, 60)
    assert(host:mousepressed(physicalX, physicalY, 1),
        "EffectLayer prevented its underlay press")
    assert(host:mousereleased(physicalX, physicalY, 1),
        "EffectLayer prevented its underlay release")
    assert(pressed == 1, "EffectLayer stole a pointer activation")

    host:update(0.5)
    first = assert(support.find(host:tree(), "popup-first"))
    second = assert(support.find(host:tree(), "popup-second"))
    assert(first.presentation.y < 0 and first.presentation.opacity < 1,
        "PopupText did not rise and fade")
    support.near(second.presentation.scale, impactScale,
        "impact PopupText changed glyph scale during its flight")
    host:update(1)
    assert(completed == 2,
        "PopupText did not complete each keyed lifetime exactly once")
    host:update(1)
    assert(completed == 2, "PopupText replayed a completed lifetime")
    host:unmount()
end

-- Builds a keyed popup burst with the requested number of concurrent entries.
local RapidEffects = Frog.component("EffectCheckRapidEffects", function(props)
    local items = {}
    for id = 1, props.count do items[id] = id end
    return Frog.EffectLayer {
        testId = "rapid-layer",
        width = 180,
        height = 120,
        Frog.each(items, function(id)
            return Frog.PopupText {
                key = id,
                testId = "rapid-popup-" .. id,
                text = "-8",
                at = { x = 90, y = 70 },
                variant = "impact",
                duration = 1,
            }
        end),
    }
end)

-- Proves keyed insertion cannot restart, resize, or rescale an older flight.
local function rapidInsertionStability()
    local host = support.host { width = 180, height = 120 }
    host:mount(RapidEffects { count = 1 })
    host:update(0.2)
    local first = assert(support.find(host:tree(), "rapid-popup-1"))
    local identity = first.logicalIdentity
    local y, opacity, scale = first.presentation.y,
        first.presentation.opacity, first.presentation.scale
    local elapsed = inspectionEntry(host,
        "rapid-popup-1").motion.activeDetails[1].elapsed

    for count = 2, 4 do
        host:render(RapidEffects { count = count })
        first = assert(support.find(host:tree(), "rapid-popup-1"))
        assert(first.logicalIdentity == identity,
            "rapid insertion replaced the retained popup")
        support.near(first.presentation.y, y,
            "rapid insertion changed retained popup y")
        support.near(first.presentation.opacity, opacity,
            "rapid insertion changed retained popup opacity")
        support.near(first.presentation.scale, scale,
            "rapid insertion changed retained popup scale")
        support.near(inspectionEntry(host,
            "rapid-popup-1").motion.activeDetails[1].elapsed, elapsed,
            "rapid insertion restarted retained popup lifetime")
    end
    local layer = assert(support.find(host:tree(), "rapid-layer"))
    assert(#layer.children == 4,
        "rapid insertion did not retain all keyed popup siblings")
    host:unmount()
end

local Removed = Frog.action("EffectCheck.Removed")

-- Owns a finite popup list and removes it through the completion callback.
local TransientOwner = Frog.actor("EffectCheckTransientOwner", {
    initial = true,
    actions = { [Removed] = { [true] = false } },
    render = function(_, visible, send)
        return Frog.EffectLayer {
            testId = "transient-layer",
            width = 160,
            height = 100,
            visible and Frog.PopupText {
                key = "finite",
                testId = "transient-popup",
                text = "Saved",
                at = { x = 80, y = 50 },
                duration = 0.2,
                onComplete = function() send(Removed {}) end,
            },
        }
    end,
})

-- Proves completion may publish one typed removal without custom update code.
local function transientRemoval()
    local host = support.host { width = 160, height = 100 }
    host:mount(TransientOwner {})
    assert(support.find(host:tree(), "transient-popup"),
        "transient owner omitted its popup")
    host:update(0.3)
    assert(not support.find(host:tree(), "transient-popup"),
        "PopupText completion did not remove the transient through actor state")
    host:unmount()
end

-- Positions a running popup from the current viewport on every reconciliation.
local ResponsiveEffects = Frog.component("EffectCheckResponsive", function()
    local viewport = Frog.useViewport()
    return Frog.EffectLayer {
        width = "100%",
        height = "100%",
        Frog.PopupText {
            key = "responsive",
            testId = "responsive-popup",
            text = "Resize",
            at = { x = viewport.width * 0.75, y = viewport.height * 0.25 },
            duration = 2,
        },
    }
end)

-- Proves resize repositions layout without restarting relative popup motion.
local function responsiveLifetime()
    local host = support.host { width = 200, height = 100 }
    host:mount(ResponsiveEffects {})
    host:update(0.4)
    local beforeNode = assert(support.find(host:tree(), "responsive-popup"))
    local beforeEntry = inspectionEntry(host, "responsive-popup")
    local elapsed = beforeEntry.motion.activeDetails[1].elapsed
    local rise = beforeNode.presentation.y
    host:resize(400, 240)
    local afterNode = assert(support.find(host:tree(), "responsive-popup"))
    local afterEntry = inspectionEntry(host, "responsive-popup")
    local viewport = host:viewport()
    support.near(afterNode.layout.x + afterNode.layout.width / 2,
        viewport.width * 0.75,
        "responsive popup center x")
    support.near(afterNode.layout.y + afterNode.layout.height / 2,
        viewport.height * 0.25,
        "responsive popup center y")
    support.near(afterNode.presentation.y, rise,
        "responsive popup relative rise")
    support.near(afterEntry.motion.activeDetails[1].elapsed, elapsed,
        "responsive popup lifetime elapsed")
    host:unmount()
end

-- Proves an explicit directional popup and its semantic cue share one key.
local function directionalSoundContract()
    local clock = Frog.clock()
    local sounds = {}
    local host = support.host {
        width = 180,
        height = 120,
        feedback = {
            sound = function(cue) sounds[#sounds + 1] = cue end,
        },
    }
    host:mount(Frog.EffectLayer {
        width = 180,
        height = 120,
        Frog.PopupText {
            key = "formula",
            testId = "directional-popup",
            text = "=12",
            at = { x = 90, y = 60 },
            duration = 1,
            travel = { x = 54, y = -18 },
            clock = clock,
            sound = "formula.commit",
        },
    })
    assert(#sounds == 1 and sounds[1] == "formula.commit",
        "directional PopupText did not emit its keyed semantic cue once")
    clock:advance(0.5)
    host:update(0)
    local popup = assert(support.find(host:tree(), "directional-popup"))
    assert(popup.presentation.x > 0 and popup.presentation.y < 0,
        "directional PopupText did not follow its explicit x/y travel")
    host:update(1)
    assert(#sounds == 1,
        "directional PopupText replayed its semantic cue")
    host:unmount()
end

-- Builds one popup against a caller-owned explicit clock.
local function ClockedEffects(clock, callback)
    return Frog.EffectLayer {
        width = 120,
        height = 80,
        Frog.PopupText {
            key = "clocked",
            testId = "clocked-popup",
            text = "Clocked",
            at = { x = 60, y = 40 },
            duration = 0.5,
            clock = clock,
            onComplete = callback,
        },
    }
end

-- Proves explicit clocks and reduced motion retain their documented policies.
local function clockPolicies()
    local clock = Frog.clock()
    local calls = 0
    local host = support.host { width = 120, height = 80 }
    host:mount(ClockedEffects(clock, function() calls = calls + 1 end))
    host:update(0.4)
    local popup = assert(support.find(host:tree(), "clocked-popup"))
    support.near(popup.presentation.y, 0, "paused explicit popup clock")
    clock:advance(0.3)
    host:update(0)
    popup = assert(support.find(host:tree(), "clocked-popup"))
    assert(popup.presentation.y < 0 and calls == 0,
        "explicit popup clock did not control progress")
    clock:advance(0.3)
    host:update(0)
    assert(calls == 1, "explicit popup clock did not complete once")
    host:unmount()

    calls = 0
    host = support.host { width = 120, height = 80, reducedMotion = true }
    host:mount(ClockedEffects(Frog.clock(), function() calls = calls + 1 end))
    popup = assert(support.find(host:tree(), "clocked-popup"))
    assert(#inspectionEntry(host, "clocked-popup").motion.active == 0
            and popup.presentation.opacity == 0,
        "reduced motion left a PopupText runner active")
    host:update(0)
    assert(calls == 1,
        "reduced-motion PopupText did not defer completion to Host update")
    host:unmount()
end

-- Proves the effect vocabulary rejects ambiguous ownership and malformed props.
local function validationContracts()
    rejects("popup outside layer", function()
        support.host { width = 80, height = 80 }:mount(Frog.PopupText {
            key = "outside", text = "No", at = { x = 1, y = 1 },
        })
    end, "must be a direct Frog.EffectLayer child")
    rejects("interactive effect child", function()
        support.host { width = 80, height = 80 }:mount(Frog.EffectLayer {
            Frog.Button { onPress = function() end, Frog.Text "No" },
        })
    end, "accepts only PopupText, Projectile, Flipbook, ParticleBurst, or bounded Canvas children")
    rejects("missing popup key", function()
        support.host { width = 80, height = 80 }:mount(Frog.EffectLayer {
            Frog.PopupText { text = "No", at = { x = 1, y = 1 } },
        })
    end, "requires a stable string/number key")
    rejects("unknown popup variant", function()
        support.host { width = 80, height = 80 }:mount(Frog.EffectLayer {
            Frog.PopupText {
                key = "bad", text = "No", at = { x = 1, y = 1 },
                variant = "battle",
            },
        })
    end, "variant must be float, impact, or notice")
    rejects("unknown popup prop", function()
        support.host { width = 80, height = 80 }:mount(Frog.EffectLayer {
            Frog.PopupText {
                key = "bad", text = "No", at = { x = 1, y = 1 },
                speed = 2,
            },
        })
    end, "unknown prop speed")
    rejects("ambiguous popup trajectory", function()
        support.host { width = 80, height = 80 }:mount(Frog.EffectLayer {
            Frog.PopupText {
                key = "bad", text = "No", at = { x = 1, y = 1 },
                distance = 4, travel = { x = 2 },
            },
        })
    end, "distance and travel are mutually exclusive")
    rejects("empty popup sound", function()
        support.host { width = 80, height = 80 }:mount(Frog.EffectLayer {
            Frog.PopupText {
                key = "bad", text = "No", at = { x = 1, y = 1 },
                sound = "",
            },
        })
    end, "sound must be a non-empty cue or false")
    rejects("negative popup shadow", function()
        support.host { width = 80, height = 80 }:mount(Frog.EffectLayer {
            Frog.PopupText {
                key = "bad", text = "No", at = { x = 1, y = 1 },
                shadowOffset = -1,
            },
        })
    end, "shadowOffset must be finite and non-negative")
    rejects("popup shine above one", function()
        support.host { width = 80, height = 80 }:mount(Frog.EffectLayer {
            Frog.PopupText {
                key = "bad", text = "No", at = { x = 1, y = 1 },
                shine = 1.1,
            },
        })
    end, "shine must be between 0 and 1")
end

function check.run()
    basicContract()
    rapidInsertionStability()
    transientRemoval()
    responsiveLifetime()
    directionalSoundContract()
    clockPolicies()
    validationContracts()
end

return check
