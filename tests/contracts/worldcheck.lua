-- Adversarial public-contract checks for tiled images and shader composition.

local Frog = require("frogui")
local support = require("tests.support")

local check = {}

local TILE_IMAGE = support.generatedImage(8, 8, { 0.3, 0.7, 0.4, 1 })

local PASS_THROUGH = [[
    extern number clock;
    extern vec2 nudge;

    vec4 effect(vec4 color, Image texture, vec2 textureCoordinates,
            vec2 screenCoordinates) {
        vec2 uv = textureCoordinates + nudge * 0.0 + clock * 0.0;
        return Texel(texture, uv) * color;
    }
]]

local FRAME_SHIFT = [[
    vec4 effect(vec4 color, Image texture, vec2 textureCoordinates,
            vec2 screenCoordinates) {
        vec4 pixel = Texel(texture, textureCoordinates);
        return vec4(0.0, 0.0, pixel.g, pixel.a) * color;
    }
]]

-- Requires a callback to fail with one actionable diagnostic fragment.
local function rejects(label, callback, fragment)
    local ok, err = pcall(callback)
    assert(not ok, label .. " unexpectedly succeeded")
    assert(tostring(err):find(fragment, 1, true),
        label .. " rejected for the wrong reason: " .. tostring(err))
end

-- Returns one exact F6 inspection record without depending on source paths.
local function inspectionEntry(host, testId)
    for _, entry in ipairs(host:inspectionTree().nodes) do
        if entry.testId == testId then return entry end
    end
    error("missing inspection entry " .. testId, 0)
end

-- Builds a tiny complete host vocabulary for framework-only background tests.
local function newHost(options)
    options = options or {}
    return support.host {
        width = options.width or 180,
        height = options.height or 120,
        painter = options.painter,
        reducedMotion = options.reducedMotion == true,
        assets = { tile = TILE_IMAGE },
        theme = {
            colors = { ink = { 1, 1, 1, 1 } },
            shaders = {
                pass = PASS_THROUGH,
                frameShift = FRAME_SHIFT,
                broken = "this is not valid shader source",
            },
        },
    }
end

-- Creates two four-pixel RGB frames so one readback proves clock selection,
-- shader application, and additive composition on the same SpriteSheet leaf.
local function twoFrameImage()
    local data = love.image.newImageData(8, 4)
    for x = 0, 7 do
        local color = x < 4 and { 1, 0, 0, 1 } or { 0, 1, 0, 1 }
        for y = 0, 3 do data:setPixel(x, y, unpack(color)) end
    end
    local image = love.graphics.newImage(data)
    image:setFilter("nearest", "nearest")
    return image
end

local reducedClock

-- Advances a raw clock under reduced motion to prove policy stays with owner.
local ReducedDrift = Frog.component("WorldCheckReducedDrift", function()
    local clock = Frog.useResource(function()
        return Frog.clock(), function() end
    end)
    reducedClock = clock
    Frog.useFrame(function(dt) clock:advance(dt) end)
    return Frog.TiledImage {
        testId = "reduced-drift",
        source = "tile",
        width = 180,
        height = 120,
        tileWidth = 64,
        velocity = { x = 8 },
        clock = clock,
        repeatAxis = "x",
    }
end)

-- Proves reduced motion never silently suppresses an owner-chosen raw clock.
local function reducedMotionClockPolicy()
    reducedClock = nil
    local host = newHost { reducedMotion = true }
    host:mount(ReducedDrift {})
    host:draw()
    support.near(inspectionEntry(host,
        "reduced-drift").tiledImage.phase.x, 0,
        "reduced-motion initial tile phase")
    host:update(0.5)
    host:draw()
    support.near(inspectionEntry(host,
        "reduced-drift").tiledImage.phase.x, 4,
        "reduced-motion owner clock phase")
    support.near(assert(reducedClock):now(), 0.5,
        "reduced-motion raw clock")
    host:unmount()
end

-- Proves coverage, adjacency, explicit clock sampling, and filter restoration.
local function tiledGeometryAndClock()
    local clock = Frog.clock(0)
    local host = newHost()
    host:mount(Frog.TiledImage {
        testId = "moving-tiles",
        source = "tile",
        width = 180,
        height = 120,
        tileWidth = 64,
        phase = { x = 2.25 },
        velocity = { x = 3.5 },
        clock = clock,
        repeatAxis = "x",
        filter = "nearest",
        tint = "ink",
    })
    local asset = assert(host:_asset("tile"))
    local previousMin, previousMag = asset:getFilter()
    host:draw()
    local entry = inspectionEntry(host, "moving-tiles")
    local geometry = assert(entry.tiledImage)
    assert(geometry.repeatAxis == "x" and geometry.clock == "explicit",
        "TiledImage omitted repeat/clock inspection metadata")
    assert(#geometry.rows == 1 and #geometry.columns >= 3,
        "horizontal TiledImage did not cover its arranged rectangle")
    for index = 2, #geometry.columns do
        support.near(geometry.columns[index] - geometry.columns[index - 1],
            64, "adjacent tile spacing")
    end
    assert(geometry.columns[1] <= 0
            and geometry.columns[#geometry.columns] + 64 >= 180,
        "TiledImage columns left a coverage gap")
    assert(geometry.columns[1] % 1 == 0,
        "nearest TiledImage did not snap its shared phase")
    local restoredMin, restoredMag = asset:getFilter()
    assert(restoredMin == previousMin and restoredMag == previousMag,
        "TiledImage leaked its temporary asset filter")

    clock:advance(1)
    host:draw()
    entry = inspectionEntry(host, "moving-tiles")
    support.near(entry.tiledImage.phase.x, 5.75,
        "TiledImage explicit-clock phase")
    host:unmount()
end

-- Proves a tile phase impulse samples its own clock without tree updates.
local function tiledPhaseImpulse()
    local driftClock = Frog.clock(2)
    local impulseClock = Frog.clock(4)
    local host = newHost()
    host:mount(Frog.TiledImage {
        testId = "impulse-tiles",
        source = "tile",
        width = 180,
        height = 120,
        tileWidth = 64,
        phase = { x = 3 },
        velocity = { x = 2 },
        clock = driftClock,
        phaseImpulse = {
            clock = impulseClock,
            startedAt = 4,
            duration = 1,
            peakAt = 0.25,
            offset = { x = 12, y = -4 },
        },
        repeatAxis = "x",
    })
    host:draw()
    local identity = assert(support.find(
        host:tree(), "impulse-tiles")).identity
    local start = inspectionEntry(host, "impulse-tiles").tiledImage
    support.near(start.phase.x, 7, "phase impulse start x")
    support.near(start.phase.y, 0, "phase impulse start y")
    assert(start.phaseImpulse == "explicit",
        "TiledImage omitted phase-impulse inspection metadata")

    impulseClock:advance(0.25)
    host:draw()
    local peak = inspectionEntry(host, "impulse-tiles").tiledImage
    support.near(peak.phase.x, 19, "phase impulse peak x")
    support.near(peak.phase.y, -4, "phase impulse peak y")
    assert(support.find(host:tree(), "impulse-tiles").identity == identity,
        "paint-time phase impulse rebuilt its TiledImage")

    impulseClock:advance(0.75)
    host:draw()
    local settled = inspectionEntry(host, "impulse-tiles").tiledImage
    support.near(settled.phase.x, 7, "phase impulse settled x")
    support.near(settled.phase.y, 0, "phase impulse settled y")

    driftClock:advance(1)
    host:draw()
    support.near(inspectionEntry(
        host, "impulse-tiles").tiledImage.phase.x, 9,
        "phase impulse interfered with the independent drift clock")
    host:unmount()
end

-- Proves semantic compilation, uniform sampling, and wrapper inspection.
local function shaderLifecycle()
    local clock = Frog.clock(0.4)
    local host = newHost()
    local root = Frog.ShaderImage {
        testId = "shader-wrapper",
        shader = "pass",
        uniforms = { clock = clock, nudge = { 0, 0 } },
        fallback = "plain",
        Frog.TiledImage {
            testId = "shader-tiles",
            source = "tile",
            width = 180,
            height = 120,
            repeatAxis = "x",
        },
    }
    host:mount(root)
    host:draw()
    local entry = inspectionEntry(host, "shader-wrapper")
    assert(entry.shaderImage.status == "active"
            and entry.shaderImage.token == "pass",
        "ShaderImage did not expose successful semantic compilation")
    support.near(entry.shaderImage.uniforms.clock, 0.4,
        "ShaderImage initial clock uniform")
    clock:advance(0.6)
    host:draw()
    entry = inspectionEntry(host, "shader-wrapper")
    support.near(entry.shaderImage.uniforms.clock, 1,
        "ShaderImage paint-time clock uniform")

    local previousProgram = assert(host._shaderCache.pass)
    host:refreshTheme({
        colors = { ink = { 1, 1, 1, 1 } },
        shaders = { pass = PASS_THROUGH .. "\n" },
    }, { tile = TILE_IMAGE }, root)
    host:draw()
    assert(host._shaderCache.pass
            and host._shaderCache.pass ~= previousProgram,
        "theme refresh retained a stale compiled shader")
    host:unmount()
end

-- Proves ShaderImage is ordinary composition over a clock-selected animated
-- frame. The green second frame becomes blue, then adds over a red surface.
local function spriteSheetShaderBlend()
    local sheet = twoFrameImage()
    local clock = Frog.clock(0.51)
    local host = newHost {
        width = 540,
        height = 960,
        reducedMotion = true,
    }
    local canvas = love.graphics.newCanvas(540, 960)
    local previousCanvas = love.graphics.getCanvas()
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    local tree = support.mount(host, Frog.Overlay {
        width = 4,
        height = 4,
        Frog.Box {
            width = 4,
            height = 4,
            background = { 1, 0, 0, 1 },
        },
        Frog.ShaderImage {
            testId = "shader-sprite-wrapper",
            shader = "frameShift",
            blend = "add",
            fallback = "plain",
            Frog.SpriteSheet {
                testId = "shader-sprite",
                source = sheet,
                frameCount = 2,
                fps = 2,
                clock = clock,
                width = 4,
                height = 4,
                fit = "stretch",
            },
        },
    })
    host:draw()
    love.graphics.setCanvas(previousCanvas)

    local wrapper = inspectionEntry(host, "shader-sprite-wrapper").shaderImage
    local sprite = inspectionEntry(host, "shader-sprite").spriteSheet
    assert(wrapper.status == "active" and wrapper.blend == "add",
        "ShaderImage did not activate additive SpriteSheet composition")
    assert(sprite.status == "ready" and sprite.frame == 2,
        "wrapped SpriteSheet did not sample its explicit clock")
    local pixels = canvas:newImageData()
    local pixelScale = pixels:getWidth() / canvas:getWidth()
    local spriteNode = assert(support.find(tree, "shader-sprite"))
    local red, green, blue = pixels:getPixel(
        math.floor((spriteNode.layout.x + spriteNode.layout.width / 2)
            * pixelScale),
        math.floor((spriteNode.layout.y + spriteNode.layout.height / 2)
            * pixelScale))
    assert(red > 0.9 and green < 0.1 and blue > 0.9,
        ("ShaderImage did not shift/add the selected SpriteSheet frame:"
            .. " %.2f/%.2f/%.2f"):format(red, green, blue))
    host:unmount()

    local plainHost = newHost()
    plainHost:mount(Frog.ShaderImage {
        testId = "broken-sprite-plain",
        shader = "broken",
        fallback = "plain",
        Frog.SpriteSheet {
            testId = "broken-sprite-plain-child",
            source = sheet,
            frameCount = 2,
            fps = 2,
            clock = clock,
        },
    })
    plainHost:draw()
    assert(support.find(plainHost:tree(),
            "broken-sprite-plain-child")._spriteSheetGeometry.frame == 2,
        "plain ShaderImage fallback did not preserve SpriteSheet playback")
    plainHost:unmount()

    local hiddenHost = newHost()
    hiddenHost:mount(Frog.ShaderImage {
        shader = "broken",
        fallback = "hidden",
        Frog.SpriteSheet {
            testId = "broken-sprite-hidden-child",
            source = sheet,
            frameCount = 2,
            fps = 2,
            clock = clock,
        },
    })
    hiddenHost:draw()
    assert(not support.find(hiddenHost:tree(),
            "broken-sprite-hidden-child")._spriteSheetGeometry,
        "hidden ShaderImage fallback painted its SpriteSheet child")
    hiddenHost:unmount()
end

-- Proves both safe failure policies without turning malformed GPU code fatal.
local function shaderFallbacks()
    local host = newHost()
    host:mount(Frog.Overlay {
        width = 180,
        height = 120,
        Frog.ShaderImage {
            testId = "broken-plain",
            shader = "broken",
            fallback = "plain",
            Frog.TiledImage {
                testId = "broken-plain-child",
                source = "tile",
                width = 90,
                height = 120,
            },
        },
        Frog.ShaderImage {
            testId = "broken-hidden",
            shader = "broken",
            fallback = "hidden",
            Frog.TiledImage {
                testId = "broken-hidden-child",
                source = "tile",
                width = 90,
                height = 120,
                offset = { x = 90 },
            },
        },
    })
    host:draw()
    assert(inspectionEntry(host, "broken-plain").shaderImage.status == "failed"
            and inspectionEntry(host, "broken-hidden").shaderImage.status
                == "failed",
        "ShaderImage failure did not become stable inspection state")
    assert(support.find(host:tree(), "broken-plain-child")._tileGeometry,
        "plain ShaderImage fallback did not paint its child")
    assert(not support.find(host:tree(), "broken-hidden-child")._tileGeometry,
        "hidden ShaderImage fallback painted its child")
    host:unmount()
end

-- Proves custom painters receive complete generic descriptors, not callbacks.
local function customPainterDescriptors()
    local tiled, wrapped
    local custom = {}
    function custom:tiledImage(node, asset, geometry, style)
        tiled = { node = node, asset = asset, geometry = geometry, style = style }
    end
    function custom:shaderImage(node, inspection)
        wrapped = { node = node, inspection = inspection }
    end
    local host = newHost { painter = custom }
    host:mount(Frog.ShaderImage {
        testId = "custom-shader",
        shader = "pass",
        blend = "add",
        Frog.TiledImage {
            testId = "custom-tiles",
            source = "tile",
            width = 180,
            height = 120,
            tileWidth = 80,
            repeatAxis = "x",
            tint = "ink",
        },
    })
    host:draw()
    assert(tiled and tiled.asset and tiled.geometry.tileWidth == 80,
        "custom painter omitted TiledImage asset or geometry")
    assert(tiled.style.tint[4] == 1,
        "custom painter omitted resolved TiledImage tint")
    assert(wrapped and wrapped.inspection.token == "pass"
            and wrapped.inspection.blend == "add"
            and wrapped.inspection.status == "pending",
        "custom painter omitted ShaderImage semantic descriptor")
    host:unmount()
end

-- Proves invalid authoring fails during tree construction with useful errors.
local function validationFailures()
    local host = newHost()
    rejects("TiledImage velocity without clock", function()
        host:mount(Frog.TiledImage {
            source = "tile", velocity = { x = 2 },
        })
    end, "velocity requires an explicit Frog.clock")
    rejects("subpixel TiledImage dimension", function()
        host:mount(Frog.TiledImage {
            source = "tile", tileWidth = 0.5,
        })
    end, "tileWidth is below its minimum")
    rejects("TiledImage child", function()
        host:mount(Frog.TiledImage {
            source = "tile", Frog.Text "No child",
        })
    end, "does not accept children")
    rejects("TiledImage impulse without clock", function()
        host:mount(Frog.TiledImage {
            source = "tile",
            phaseImpulse = {
                startedAt = 0,
                duration = 1,
                peakAt = 0.5,
                offset = { x = 2 },
            },
        })
    end, "clock must come from Frog.clock")
    rejects("TiledImage impulse endpoint peak", function()
        host:mount(Frog.TiledImage {
            source = "tile",
            phaseImpulse = {
                clock = Frog.clock(),
                startedAt = 0,
                duration = 1,
                peakAt = 1,
                offset = { x = 2 },
            },
        })
    end, "peakAt must be between zero and one")
    rejects("unknown shader token", function()
        host:mount(Frog.ShaderImage {
            shader = "missing", Frog.Image { source = "tile" },
        })
    end, "unknown FrogUI shader token")
    rejects("short shader vector", function()
        host:mount(Frog.ShaderImage {
            shader = "pass", uniforms = { nudge = { 0 } },
            Frog.Image { source = "tile" },
        })
    end, "two through four numbers")
    rejects("interactive shader child", function()
        host:mount(Frog.ShaderImage {
            shader = "pass", Frog.Text "Not a paint leaf",
        })
    end, "child must resolve to Image, SpriteSheet, TiledImage,"
        .. " or an empty Box")

    local budgetHost = newHost { painter = {} }
    budgetHost:mount(Frog.TiledImage {
        source = "tile",
        width = 180,
        height = 120,
        tileWidth = 1,
        tileHeight = 1,
        repeatAxis = "both",
    })
    rejects("TiledImage copy budget", function()
        budgetHost:draw()
    end, "per-leaf copy budget")
    budgetHost:unmount()
end

function check.run()
    tiledGeometryAndClock()
    tiledPhaseImpulse()
    shaderLifecycle()
    spriteSheetShaderBlend()
    shaderFallbacks()
    customPainterDescriptors()
    validationFailures()
    reducedMotionClockPolicy()
end

return check
