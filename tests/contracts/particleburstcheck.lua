-- Adversarial public-contract checks for deterministic finite ParticleBurst.

local Frog = require("frogui")
local support = require("tests.support")

local check = {}

-- Creates generic in-memory art so this framework check borrows no game asset.
local function generatedImage()
    local data = love.image.newImageData(3, 2)
    for x = 0, 2 do
        for y = 0, 1 do data:setPixel(x, y, 0.2, 0.8, 1, 1) end
    end
    return love.graphics.newImage(data)
end

local ASSETS = {
    ["particle"] = generatedImage(),
    ["missing-particle"] = "tests/fixtures/__missing_particle.png",
}

-- Requires malformed public authoring to fail with one actionable fragment.
local function rejects(label, callback, fragment)
    local ok, reason = pcall(callback)
    assert(not ok, label .. " unexpectedly succeeded")
    assert(tostring(reason):find(fragment, 1, true),
        label .. " rejected for the wrong reason: " .. tostring(reason))
end

-- Finds one exact F6 entry without exposing the complete Host effect registry.
local function inspectionEntry(host, testId)
    for _, entry in ipairs(host:inspectionTree().nodes) do
        if entry.testId == testId then return entry end
    end
    error("missing inspection entry " .. testId, 0)
end

-- Returns an immutable scalar fingerprint of one sampled particle catalog.
local function fingerprint(node)
    local values = {}
    for index, particle in ipairs(node._effect.particles) do
        values[index] = ("%.6f:%.6f:%.6f:%.6f:%.6f")
            :format(particle.angle, particle.distance, particle.radiusScale,
                particle.x, particle.y)
    end
    return table.concat(values, "|")
end

-- Builds one point-anchored burst whose exact clock and seed are controlled.
local function Burst(clock, seed, complete, overrides)
    overrides = overrides or {}
    return Frog.EffectLayer {
        width = 240,
        height = 180,
        Frog.ParticleBurst {
            key = overrides.key or "burst",
            testId = overrides.testId or "particle-burst",
            at = overrides.at or { x = 120, y = 90 },
            seed = seed,
            clock = clock,
            duration = overrides.duration or 1,
            count = overrides.count or 9,
            distance = overrides.distance or 60,
            angle = overrides.angle,
            spread = overrides.spread,
            gravity = overrides.gravity,
            radius = overrides.radius or 5,
            endRadius = overrides.endRadius,
            color = overrides.color or "spark",
            source = overrides.source,
            onComplete = complete,
        },
    }
end

-- Proves one seed/clock produces one retained, partition-independent catalog.
local function deterministicLifetime()
    local clock = Frog.clock()
    local completions = 0
    local host = support.host {
        width = 240,
        height = 180,
        assets = ASSETS,
        theme = { colors = { spark = { 0.3, 0.8, 1, 1 } } },
    }
    host:mount(Burst(clock, 481516, function()
        completions = completions + 1
    end, { gravity = 24, spread = math.pi }))
    local burst = assert(host:tree().children[1])
    assert(burst.type == "ParticleBurst"
            and #burst._effect.particles == 9,
        "ParticleBurst omitted its bounded generated catalog")
    local known = burst._effect.particles[1]
    assert(("%.12f:%.12f:%.12f"):format(
            known.angle, known.distance, known.radiusScale)
            == "-1.317220900750:48.253024483894:1.224617132158",
        "ParticleBurst changed its published known-seed catalog")
    local initial = fingerprint(burst)
    local retainedParticles = burst._effect.particles
    host:render(Burst(clock, 481516, function()
        completions = completions + 1
    end, { gravity = 24, spread = math.pi }))
    burst = assert(host:tree().children[1])
    assert(burst._effect.particles == retainedParticles
            and fingerprint(burst) == initial,
        "quiet rerender copied or rerolled a keyed ParticleBurst")

    clock:advance(0.5)
    host:update(0)
    burst = assert(host:tree().children[1])
    local particle = burst._effect.particles[1]
    assert(burst._effect.elapsed == 0.5
            and particle.alpha == 0.5
            and particle.radius > 0 and particle.radius < 5 * 1.28,
        "ParticleBurst did not sample absolute half-life geometry")
    local half = fingerprint(burst)
    local inspection = inspectionEntry(host, "particle-burst")
    assert(inspection.effect.kind == "ParticleBurst"
            and inspection.effect.seed == 481516
            and inspection.effect.particleCount == 9
            and inspection.effect.progress == 0.5,
        "F6 omitted ParticleBurst seed/count/progress")
    host:draw()

    clock:advance(0.5)
    host:update(0)
    assert(completions == 1,
        "ParticleBurst did not complete exactly once")
    local settled = inspectionEntry(host, "particle-burst")
    assert(settled.bounds.x > -math.huge and settled.bounds.x < math.huge
            and settled.bounds.y > -math.huge
            and settled.bounds.y < math.huge
            and settled.bounds.width == 0
            and settled.bounds.height == 0,
        "completed ParticleBurst published non-finite F6 bounds")
    host:update(1)
    assert(completions == 1,
        "ParticleBurst replayed its terminal callback")
    host:unmount()

    local clock2 = Frog.clock()
    local host2 = support.host {
        width = 240,
        height = 180,
        assets = ASSETS,
        theme = { colors = { spark = { 0.3, 0.8, 1, 1 } } },
    }
    host2:mount(Burst(clock2, 481516, nil,
        { gravity = 24, spread = math.pi }))
    clock2:advance(0.2)
    host2:update(0)
    clock2:advance(0.3)
    host2:update(0)
    assert(fingerprint(host2:tree().children[1]) == half,
        "ParticleBurst changed when clock time was partitioned")
    host2:unmount()
end

-- Proves the private renderer seam receives the new primitive deliberately.
-- This is regression coverage, not a promise that custom painters are public.
local function customPainterContract()
    local clock = Frog.clock()
    local received
    local custom = {}
    function custom:particleBurst(node, state, style)
        received = { node = node, state = state, style = style }
    end
    local host = support.host {
        width = 240,
        height = 180,
        assets = ASSETS,
        painter = custom,
        theme = { colors = { spark = { 0.3, 0.8, 1, 1 } } },
    }
    host:mount(Burst(clock, 29))
    clock:advance(0.25)
    host:update(0)
    host:draw()
    assert(received and received.node.type == "ParticleBurst"
            and received.node.props.testId == "particle-burst"
            and received.state.props.seed == 29
            and #received.state.particles == 9
            and received.style.color[4] == 1,
        "private custom painter omitted ParticleBurst state or style")
    host:unmount()
end

-- Proves seeds differ, optional art falls back, and resize preserves lifetime.
local function seedArtAndResize()
    local firstClock, secondClock = Frog.clock(), Frog.clock()
    local first = support.host {
        width = 240, height = 180, assets = ASSETS,
        theme = { colors = { spark = { 1, 0.4, 0.2, 1 } } },
    }
    first:mount(Burst(firstClock, 7, nil, { source = "particle" }))
    local firstFingerprint = fingerprint(first:tree().children[1])
    firstClock:advance(0.35)
    first:update(0)
    local elapsed = first:tree().children[1]._effect.elapsed
    first:resize(960, 540)
    assert(first:tree().children[1]._effect.elapsed == elapsed,
        "resize restarted ParticleBurst elapsed time")
    first:draw()
    first:unmount()

    local second = support.host {
        width = 240, height = 180, assets = ASSETS,
        theme = { colors = { spark = { 1, 0.4, 0.2, 1 } } },
    }
    second:mount(Burst(secondClock, 8, nil,
        { source = "missing-particle" }))
    assert(firstFingerprint ~= fingerprint(second:tree().children[1]),
        "different ParticleBurst seeds produced one catalog")
    second:draw() -- missing art must retain the semantic circle fallback
    second:unmount()
end

-- Proves removal cancels stale completion and reduced motion settles invisibly.
local function cancellationAndReducedMotion()
    local clock = Frog.clock()
    local calls = 0
    local host = support.host {
        width = 240, height = 180, assets = ASSETS,
        theme = { colors = { spark = { 1, 1, 1, 1 } } },
    }
    host:mount(Burst(clock, 11, function() calls = calls + 1 end))
    clock:advance(0.4)
    host:update(0)
    host:render(Frog.EffectLayer { width = 240, height = 180 })
    clock:advance(1)
    host:update(0)
    assert(calls == 0,
        "removed ParticleBurst delivered stale completion")
    host:unmount()

    local reducedClock = Frog.clock()
    host = support.host {
        width = 240, height = 180, assets = ASSETS,
        theme = { colors = { spark = { 1, 1, 1, 1 } } },
        reducedMotion = true,
    }
    host:mount(Burst(reducedClock, 12, function() calls = calls + 1 end))
    local burst = host:tree().children[1]
    host:update(0)
    assert(calls == 1 and burst._effect.completeFired
            and not burst._effect.visible,
        "reduced motion did not settle ParticleBurst invisibly once")
    host:update(1)
    assert(calls == 1,
        "reduced ParticleBurst replayed completion")
    host:unmount()
end

-- Proves the safety budget, explicit determinism, and keyed contract fail loud.
local function validationContract()
    local function mount(props)
        support.host { width = 120, height = 80, assets = ASSETS,
            theme = { colors = { spark = { 1, 1, 1, 1 } } },
        }:mount(Frog.EffectLayer {
            Frog.ParticleBurst(props),
        })
    end
    rejects("burst outside layer", function()
        support.host { width = 120, height = 80 }:mount(Frog.ParticleBurst {
            key = "bad", at = { x = 1, y = 1 }, seed = 1,
            clock = Frog.clock(), duration = 1,
        })
    end, "must be a direct Frog.EffectLayer child")
    rejects("missing seed", function()
        mount { key = "bad", at = { x = 1, y = 1 },
            clock = Frog.clock(), duration = 1 }
    end, "seed must be an integer")
    rejects("zero seed", function()
        mount { key = "bad", at = { x = 1, y = 1 }, seed = 0,
            clock = Frog.clock(), duration = 1 }
    end, "ParticleBurst seed")
    rejects("imitated clock", function()
        mount { key = "bad", at = { x = 1, y = 1 }, seed = 1,
            clock = { now = function() return 0 end }, duration = 1 }
    end, "clock must come from Frog.clock")
    rejects("excessive particle count", function()
        mount { key = "bad", at = { x = 1, y = 1 }, seed = 1,
            clock = Frog.clock(), duration = 1, count = 65 }
    end, "ParticleBurst count")

    local clock = Frog.clock()
    local host = support.host {
        width = 120, height = 80, assets = ASSETS,
        theme = { colors = { spark = { 1, 1, 1, 1 } } },
    }
    host:mount(Burst(clock, 22))
    rejects("same-key seed mutation", function()
        host:render(Burst(clock, 23))
    end, "seed changed without a new key")
    assert(inspectionEntry(host, "particle-burst").effect.seed == 22,
        "rejected ParticleBurst mutation did not restore prior lifetime")
    host:unmount()

    local defaultClock = Frog.clock()
    host = support.host { width = 120, height = 80 }
    host:mount(Frog.EffectLayer {
        Frog.ParticleBurst {
            key = "defaults", at = { x = 30, y = 30 }, seed = 25,
            clock = defaultClock, duration = 1,
        },
    })
    host:render(Frog.EffectLayer {
        Frog.ParticleBurst {
            key = "defaults", at = { x = 30, y = 30 }, seed = 25,
            clock = defaultClock, duration = 1,
            count = 12, distance = 52, angle = 0,
            spread = math.pi * 2, gravity = 0,
            radius = 4, endRadius = 0,
        },
    })
    host:unmount()
end

function check.run()
    deterministicLifetime()
    customPainterContract()
    seedArtAndResize()
    cancellationAndReducedMotion()
    validationContract()
end

return check
