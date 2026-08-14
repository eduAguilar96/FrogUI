-- Adversarial checks for ref-following Projectile and finite Flipbook effects.

local Frog = require("frogui")
local support = require("tests.support")

local check = {}

local ASSETS = {
    ["slash-a"] = support.generatedImage(4, 4, { 1, 0.2, 0.2, 1 }),
    ["slash-b"] = support.generatedImage(4, 4, { 0.2, 0.7, 1, 1 }),
    ["missing-frame"] = "tests/fixtures/__frogui_missing_frame__.png",
}
local FRAMES = { "slash-a", "slash-b" }

-- Requires one malformed authoring shape to fail with an actionable fragment.
local function rejects(label, callback, fragment)
    local ok, err = pcall(callback)
    assert(not ok, label .. " unexpectedly succeeded")
    assert(tostring(err):find(fragment, 1, true),
        label .. " rejected for the wrong reason: " .. tostring(err))
end

-- Finds one F6 entry without exposing the Host's effect registry.
local function inspectionEntry(host, testId)
    for _, entry in ipairs(host:inspectionTree().nodes) do
        if entry.testId == testId then return entry end
    end
    error("missing inspection entry " .. testId, 0)
end

-- Mounts stable source/target refs and one optional projectile above them.
local AnchoredProjectile = Frog.component("TravelCheckAnchoredProjectile",
    function(props)
        local source = Frog.useRef()
        local target = Frog.useRef()
        return Frog.Overlay {
            width = "100%",
            height = 200,
            Frog.Row {
                width = "100%",
                height = 60,
                justify = "space-between",
                Frog.Box {
                    testId = "travel-source",
                    ref = source,
                    width = 40,
                    height = 40,
                    background = "panel",
                },
                Frog.Box {
                    testId = "travel-target",
                    ref = target,
                    width = 40,
                    height = 40,
                    offset = { x = props.targetShift or 0 },
                    background = "panel",
                },
            },
            Frog.EffectLayer {
                testId = "travel-layer",
                width = "100%",
                height = 200,
                props.show ~= false and Frog.Projectile {
                    key = props.effectKey or "flight",
                    testId = "travel-projectile",
                    from = source,
                    to = target,
                    duration = 1,
                    clock = props.clock,
                    feedbackClock = props.feedbackClock,
                    color = { 0.4, 0.8, 1, 1 },
                    onComplete = props.onComplete,
                },
            },
        }
    end)

-- Proves explicit clocks, ref centers, trails, F6 data, and arrival once.
local function projectileLifecycle()
    local travelClock, feedbackClock = Frog.clock(), Frog.clock()
    local arrivals = 0
    local host = support.host {
        width = 540,
        height = 960,
        assets = ASSETS,
        theme = { colors = {
            panel = { 0.1, 0.2, 0.2, 1 },
            ink = { 0.4, 0.8, 1, 1 },
        } },
    }
    local function View(targetShift)
        return AnchoredProjectile {
            clock = travelClock,
            feedbackClock = feedbackClock,
            targetShift = targetShift,
            onComplete = function() arrivals = arrivals + 1 end,
        }
    end
    host:mount(View())
    local source = assert(support.find(host:tree(), "travel-source"))
    local target = assert(support.find(host:tree(), "travel-target"))
    local projectile = assert(support.find(host:tree(), "travel-projectile"))
    local sourceX, sourceY = support.center(source)
    local targetX, targetY = support.center(target)
    support.near(projectile._effect.head.x, sourceX, "projectile source x")
    support.near(projectile._effect.head.y, sourceY, "projectile source y")
    support.near(projectile._effect.target.x, targetX, "projectile target x")
    support.near(projectile._effect.target.y, targetY, "projectile target y")

    host:update(0.4)
    support.near(projectile._effect.elapsed, 0,
        "paused explicit projectile clock")
    travelClock:advance(0.25)
    feedbackClock:advance(0.1)
    host:update(0)
    projectile = assert(support.find(host:tree(), "travel-projectile"))
    support.near(projectile._effect.head.x,
        sourceX + (targetX - sourceX) * 0.25, "projectile quarter flight")
    assert(#projectile._effect.trail == 1,
        "projectile omitted its feedback-clock trail")
    local inspected = inspectionEntry(host, "travel-projectile")
    assert(inspected.effect.kind == "Projectile"
            and inspected.effect.progress == 0.25
            and inspected.effect.trailCount == 1,
        "F6 omitted projectile lifecycle metadata")

    local heldX, heldY = projectile._effect.head.x, projectile._effect.head.y
    host:render(View(70))
    projectile = assert(support.find(host:tree(), "travel-projectile"))
    support.near(projectile._effect.head.x, heldX,
        "target reflow moved the projectile head")
    support.near(projectile._effect.head.y, heldY,
        "target reflow moved the projectile head y")
    target = assert(support.find(host:tree(), "travel-target"))
    targetX, targetY = support.center(target)
    support.near(projectile._effect.target.x, targetX,
        "projectile did not resolve its moved target ref")

    local oldPhysicalX, oldPhysicalY = host._viewport:toPhysical(
        projectile._effect.head.x, projectile._effect.head.y)
    local elapsed = projectile._effect.elapsed
    host:resize(960, 540)
    projectile = assert(support.find(host:tree(), "travel-projectile"))
    local newPhysicalX, newPhysicalY = host._viewport:toPhysical(
        projectile._effect.head.x, projectile._effect.head.y)
    support.near(newPhysicalX, oldPhysicalX,
        "resize changed projectile physical head x")
    support.near(newPhysicalY, oldPhysicalY,
        "resize changed projectile physical head y")
    support.near(projectile._effect.elapsed, elapsed,
        "resize restarted projectile elapsed time")

    travelClock:advance(0.75)
    feedbackClock:advance(0.2)
    host:update(0)
    assert(arrivals == 1, "projectile did not arrive exactly once")
    host:update(1)
    assert(arrivals == 1, "projectile replayed its arrival")
    host:draw() -- exercises primitive projectile/trail painting
    host:unmount()
end

-- Mounts one owner ref and a contact-bearing finite frame sequence.
local AttachedFlipbook = Frog.component("TravelCheckAttachedFlipbook",
    function(props)
        local owner = Frog.useRef()
        return Frog.Overlay {
            width = 240,
            height = 180,
            Frog.Box {
                testId = "flipbook-owner",
                ref = owner,
                width = 80,
                height = 80,
                offset = { x = props.shift or 0, y = 30 },
                background = "panel",
            },
            Frog.EffectLayer {
                width = 240,
                height = 180,
                Frog.Flipbook {
                    key = "contact",
                    testId = "travel-flipbook",
                    frames = FRAMES,
                    at = owner,
                    fps = 10,
                    clock = props.clock,
                    contactAt = 0.5,
                    width = 100,
                    height = 100,
                    tint = "ink",
                    onContact = props.onContact,
                    onComplete = props.onComplete,
                },
            },
        }
    end)

-- Proves frame/contact bits survive ref movement and resize without replay.
local function flipbookLifecycle()
    local clock = Frog.clock()
    local contacts, completions = 0, 0
    local host = support.host {
        width = 540,
        height = 960,
        assets = ASSETS,
        theme = { colors = {
            panel = { 0.1, 0.2, 0.2, 1 },
            ink = { 1, 0.6, 0.2, 1 },
        } },
    }
    local function View(shift)
        return AttachedFlipbook {
            clock = clock,
            shift = shift,
            onContact = function() contacts = contacts + 1 end,
            onComplete = function() completions = completions + 1 end,
        }
    end
    host:mount(View())
    clock:advance(0.1)
    host:update(0)
    local flipbook = assert(support.find(host:tree(), "travel-flipbook"))
    assert(contacts == 1 and completions == 0
            and flipbook._effect.contactFired,
        "Flipbook did not fire its contact beat once")
    local frame, elapsed = flipbook._effect.frame, flipbook._effect.elapsed
    host:render(View(50))
    host:resize(960, 540)
    flipbook = assert(support.find(host:tree(), "travel-flipbook"))
    assert(flipbook._effect.frame == frame
            and flipbook._effect.elapsed == elapsed
            and flipbook._effect.contactFired,
        "Flipbook movement/resize restarted its frame or contact bit")
    local owner = assert(support.find(host:tree(), "flipbook-owner"))
    local ownerX, ownerY = support.center(owner)
    support.near(flipbook._effect.center.x, ownerX,
        "Flipbook did not follow its owner ref")
    support.near(flipbook._effect.center.y, ownerY,
        "Flipbook did not follow its owner ref y")
    host:draw() -- exercises frame painting

    clock:advance(0.1)
    host:update(0)
    assert(contacts == 1 and completions == 1,
        "Flipbook did not preserve one contact and one completion")
    host:update(1)
    assert(contacts == 1 and completions == 1,
        "Flipbook replayed a terminal callback")
    host:unmount()
end

-- Proves removal cancels stale arrival and reduced motion settles once.
local function cancellationAndReducedMotion()
    local clock = Frog.clock()
    local calls = 0
    local host = support.host { width = 180, height = 100, assets = ASSETS }
    local function View(show)
        return AnchoredProjectile {
            clock = clock,
            feedbackClock = clock,
            show = show,
            onComplete = function() calls = calls + 1 end,
        }
    end
    host:mount(View(true))
    clock:advance(0.4)
    host:update(0)
    host:render(View(false))
    clock:advance(1)
    host:update(0)
    assert(calls == 0, "removed projectile delivered a stale arrival")
    host:unmount()

    local arrivals, contacts, finishes = 0, 0, 0
    host = support.host {
        width = 180,
        height = 100,
        assets = ASSETS,
        reducedMotion = true,
    }
    host:mount(Frog.EffectLayer {
        width = 180,
        height = 100,
        Frog.Projectile {
            key = "reduced-projectile",
            from = { x = 10, y = 20 },
            to = { x = 170, y = 80 },
            duration = 4,
            onComplete = function() arrivals = arrivals + 1 end,
        },
        Frog.Flipbook {
            key = "reduced-flipbook",
            frames = FRAMES,
            at = { x = 90, y = 50 },
            contactAt = 0.5,
            onContact = function() contacts = contacts + 1 end,
            onComplete = function() finishes = finishes + 1 end,
        },
    })
    host:update(0)
    assert(arrivals == 1 and contacts == 1 and finishes == 1,
        "reduced motion did not settle each semantic callback once")
    host:update(1)
    assert(arrivals == 1 and contacts == 1 and finishes == 1,
        "reduced motion replayed an effect callback")
    host:unmount()
end

-- Proves missing declared art preserves timing and malformed APIs fail loudly.
local function fallbacksAndValidation()
    local completed = 0
    local host = support.host { width = 120, height = 80, assets = ASSETS }
    host:mount(Frog.EffectLayer {
        width = 120,
        height = 80,
        Frog.Flipbook {
            key = "missing",
            frames = { "missing-frame" },
            at = { x = 60, y = 40 },
            fps = 2,
            onComplete = function() completed = completed + 1 end,
        },
    })
    host:draw() -- paints the missing-art ring fallback
    host:update(0.5)
    assert(completed == 1, "missing Flipbook art changed declared timing")
    host:unmount()

    -- Describes one same-key flight used to challenge timing mutation rollback.
    local function Flight(duration)
        return Frog.EffectLayer {
            width = 120,
            height = 80,
            Frog.Projectile {
                key = "retained-contract",
                testId = "retained-projectile",
                from = { x = 10, y = 40 },
                to = { x = 110, y = 40 },
                duration = duration,
            },
        }
    end
    host = support.host { width = 120, height = 80, assets = ASSETS }
    host:mount(Flight(1))
    rejects("same-key duration mutation", function()
        host:render(Flight(2))
    end, "duration changed without a new key")
    assert(inspectionEntry(host, "retained-projectile").effect.duration == 1,
        "rejected timing mutation did not restore the prior effect")
    host:unmount()

    rejects("projectile outside layer", function()
        support.host { width = 80, height = 80, assets = ASSETS }:mount(
            Frog.Projectile {
                key = "outside",
                from = { x = 0, y = 0 }, to = { x = 1, y = 1 },
                duration = 1,
            })
    end, "must be a direct Frog.EffectLayer child")
    rejects("zero projectile duration", function()
        support.host { width = 80, height = 80, assets = ASSETS }:mount(
            Frog.EffectLayer { Frog.Projectile {
                key = "bad",
                from = { x = 0, y = 0 }, to = { x = 1, y = 1 },
                duration = 0,
            } })
    end, "duration must be positive")
    rejects("empty flipbook", function()
        support.host { width = 80, height = 80, assets = ASSETS }:mount(
            Frog.EffectLayer { Frog.Flipbook {
                key = "bad", frames = {}, at = { x = 1, y = 1 },
            } })
    end, "frames must not be empty")
    rejects("malformed effect anchor", function()
        support.host { width = 80, height = 80, assets = ASSETS }:mount(
            Frog.EffectLayer { Frog.Projectile {
                key = "bad", from = { x = 0 }, to = { x = 1, y = 1 },
                duration = 1,
            } })
    end, "from.x/.y must be finite numbers")
    rejects("unattached effect ref", function()
        local Unattached = Frog.component("TravelCheckUnattachedRef",
            function()
                local nowhere = Frog.useRef()
                return Frog.EffectLayer {
                    width = 80,
                    height = 80,
                    Frog.Projectile {
                        key = "bad",
                        from = nowhere,
                        to = { x = 1, y = 1 },
                        duration = 1,
                    },
                }
            end)
        support.host { width = 80, height = 80, assets = ASSETS }:mount(
            Unattached {})
    end, "from ref is not attached to a primitive")
end

function check.run()
    projectileLifecycle()
    flipbookLifecycle()
    cancellationAndReducedMotion()
    fallbacksAndValidation()
end

return check
