-- Adversarial public-contract checks for mirrored RGB images and the stateless
-- horizontal SpriteSheet leaf.

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

-- Creates four two-by-four-pixel frames with distinct colors.
local function fourFrameImage()
    local data = love.image.newImageData(8, 4)
    local colors = {
        { 1, 0, 0, 1 },
        { 0, 1, 0, 1 },
        { 0, 0, 1, 1 },
        { 1, 1, 0, 1 },
    }
    for frame, color in ipairs(colors) do
        for x = (frame - 1) * 2, frame * 2 - 1 do
            for y = 0, 3 do data:setPixel(x, y, unpack(color)) end
        end
    end
    return love.graphics.newImage(data)
end

-- Returns one exact F6 record without coupling the check to source paths.
local function inspectionEntry(host, testId)
    for _, entry in ipairs(host:inspectionTree().nodes) do
        if entry.testId == testId then return entry end
    end
    error("missing inspection entry " .. testId, 0)
end

-- Proves ordinary Image exposes the same horizontal mirror control as Icon.
local function imageMirrorContract(sheet)
    local received
    local painter = {}
    function painter:image(node, asset, style)
        if node.props.testId == "mirrored-image" then
            received = { asset = asset, style = style }
        end
    end
    local host = support.host { painter = painter }
    host:mount(Frog.Image {
        testId = "mirrored-image",
        source = sheet,
        width = 8,
        height = 2,
        fit = "stretch",
        mirror = true,
    })
    host:draw()
    host:unmount()
    assert(received and received.asset == sheet
            and received.style.mirror == true
            and received.style.fit == "stretch",
        "Image custom painter lost RGB mirror semantics")

    rejects("non-boolean Image mirror", function()
        support.host {
            width = 540, height = 960,
        }:mount(Frog.Image { source = sheet, mirror = "yes" })
    end, "Image mirror must be a boolean")
end

-- Reads the default GPU painter back to prove Image really flips authored RGB
-- and SpriteSheet really selects the requested source frame.
local function defaultPainterPixels(sheet)
    local mirrorData = love.image.newImageData(8, 2)
    for x = 0, 3 do
        for y = 0, 1 do mirrorData:setPixel(x, y, 1, 0, 0, 1) end
    end
    for x = 4, 7 do
        for y = 0, 1 do mirrorData:setPixel(x, y, 0, 0, 1, 1) end
    end
    local sourceLeftR, _, sourceLeftB = mirrorData:getPixel(1, 0)
    local sourceRightR, _, sourceRightB = mirrorData:getPixel(6, 0)
    assert(sourceLeftR > 0.9 and sourceLeftB < 0.1
            and sourceRightR < 0.1 and sourceRightB > 0.9,
        "default Image mirror fixture lost its two RGB regions")
    local mirrorImage = love.graphics.newImage(mirrorData)
    mirrorImage:setFilter("nearest", "nearest")

    local canvas = love.graphics.newCanvas(10, 6)
    local previousCanvas = love.graphics.getCanvas()
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    local imageHost = support.host { width = 540, height = 960 }
    local imageTree = support.mount(imageHost, Frog.Image {
        source = mirrorImage,
        width = 8,
        height = 2,
        fit = "stretch",
        mirror = true,
    })
    imageHost:draw()
    imageHost:unmount()
    love.graphics.setCanvas(previousCanvas)
    local imagePixels = canvas:newImageData()
    local pixelScale = imagePixels:getWidth() / canvas:getWidth()
    local leftR, _, leftB = imagePixels:getPixel(
        math.floor(1 * pixelScale), 0)
    local rightR, _, rightB = imagePixels:getPixel(
        math.floor(6 * pixelScale), 0)
    assert(leftB > 0.9 and leftR < 0.1
            and rightR > 0.9 and rightB < 0.1,
        ("default Image painter did not mirror authored RGB:"
            .. " left %.2f/%.2f right %.2f/%.2f size %.1fx%.1f")
            :format(leftR, leftB, rightR, rightB,
                imageTree.layout.width, imageTree.layout.height))

    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    local clock = Frog.clock(0.26)
    local spriteHost = support.host { width = 540, height = 960 }
    spriteHost:mount(Frog.SpriteSheet {
        source = sheet,
        frameCount = 4,
        fps = 4,
        clock = clock,
        width = 2,
        height = 4,
        fit = "stretch",
    })
    spriteHost:draw()
    spriteHost:unmount()
    love.graphics.setCanvas(previousCanvas)
    local spritePixels = canvas:newImageData()
    pixelScale = spritePixels:getWidth() / canvas:getWidth()
    local frameR, frameG, frameB = spritePixels:getPixel(
        math.floor(0.5 * pixelScale), math.floor(0.5 * pixelScale))
    assert(frameG > 0.9 and frameR < 0.1 and frameB < 0.1,
        "default SpriteSheet painter drew the wrong clock-selected frame")
end

-- Proves natural measurement is one frame, not the entire horizontal strip.
local function oneFrameLayout(sheet)
    local clock = Frog.clock()
    local host = support.host { width = 540, height = 960 }
    local tree = support.mount(host, Frog.Row {
        width = 20,
        height = 10,
        align = "start",
        Frog.SpriteSheet {
            testId = "natural-sheet",
            source = sheet,
            frameCount = 4,
            fps = 8,
            clock = clock,
        },
    })
    local node = assert(support.find(tree, "natural-sheet"))
    support.near(node.layout.measuredWidth, 2, "SpriteSheet natural frame width")
    support.near(node.layout.measuredHeight, 4, "SpriteSheet natural frame height")
    support.near(node.layout.width, 2, "SpriteSheet arranged frame width")
    support.near(node.layout.height, 4, "SpriteSheet arranged frame height")
    host:unmount()

    host = support.host { width = 540, height = 960 }
    tree = support.mount(host, Frog.Row {
        width = 100,
        height = 100,
        align = "start",
        Frog.SpriteSheet {
            testId = "height-sized-sheet",
            source = sheet,
            frameCount = 4,
            fps = 8,
            clock = clock,
            height = 30,
        },
        Frog.SpriteSheet {
            testId = "width-sized-sheet",
            source = sheet,
            frameCount = 4,
            fps = 8,
            clock = clock,
            width = 24,
        },
    })
    local heightSized = assert(support.find(tree, "height-sized-sheet"))
    local widthSized = assert(support.find(tree, "width-sized-sheet"))
    support.near(heightSized.layout.width, 15,
        "height-only SpriteSheet preserved frame aspect")
    support.near(heightSized.layout.height, 30,
        "height-only SpriteSheet kept authored height")
    support.near(widthSized.layout.width, 24,
        "width-only SpriteSheet kept authored width")
    support.near(widthSized.layout.height, 48,
        "width-only SpriteSheet preserved frame aspect")
    host:unmount()

    host = support.host { width = 540, height = 960 }
    tree = support.mount(host, Frog.Overlay {
        width = 30,
        height = 100,
        overflow = "visible",
        align = "center",
        justify = "start",
        Frog.SpriteSheet {
            testId = "overflow-sheet",
            source = sheet,
            frameCount = 4,
            fps = 8,
            clock = clock,
            height = 80,
        },
    })
    local overflow = assert(support.find(tree, "overflow-sheet"))
    support.near(overflow.layout.width, 40,
        "constrained height-only SpriteSheet kept derived width")
    support.near(overflow.layout.height, 80,
        "constrained height-only SpriteSheet kept authored height")
    support.near(overflow.layout.x, -5,
        "constrained SpriteSheet stayed centered while overflowing")
    host:unmount()

    local defaultParents = {
        Frog.Column {
            width = 30,
            height = 100,
            Frog.SpriteSheet {
                testId = "column-stretch-sheet",
                source = sheet,
                frameCount = 4,
                fps = 8,
                clock = clock,
                height = 80,
            },
        },
        Frog.Row {
            width = 100,
            height = 30,
            Frog.SpriteSheet {
                testId = "row-stretch-sheet",
                source = sheet,
                frameCount = 4,
                fps = 8,
                clock = clock,
                width = 40,
            },
        },
        Frog.Overlay {
            width = 30,
            height = 30,
            Frog.SpriteSheet {
                testId = "overlay-stretch-sheet",
                source = sheet,
                frameCount = 4,
                fps = 8,
                clock = clock,
                height = 80,
            },
        },
    }
    local expectations = {
        { "column-stretch-sheet", 40, 80 },
        { "row-stretch-sheet", 40, 80 },
        { "overlay-stretch-sheet", 40, 80 },
    }
    for index, description in ipairs(defaultParents) do
        host = support.host { width = 540, height = 960 }
        tree = support.mount(host, description)
        local expected = expectations[index]
        local child = assert(support.find(tree, expected[1]))
        support.near(child.layout.width, expected[2],
            expected[1] .. " preserved derived width")
        support.near(child.layout.height, expected[3],
            expected[1] .. " preserved derived height")
        host:unmount()
    end
end

-- Proves frame selection is a pure looping function of explicit clock time.
local function explicitClockFrames(sheet)
    local clock = Frog.clock()
    local captures = {}
    local painter = {}
    function painter:spriteSheet(node, asset, geometry, style)
        captures[#captures + 1] = {
            node = node,
            asset = asset,
            geometry = geometry,
            style = style,
        }
    end
    local host = support.host {
        painter = painter,
        reducedMotion = true,
        theme = { colors = { wash = { 0.5, 0.75, 1, 0.8 } } },
    }
    host:mount(Frog.SpriteSheet {
        testId = "clocked-sheet",
        source = sheet,
        frameCount = 4,
        fps = 4,
        clock = clock,
        width = 10,
        height = 6,
        fit = "cover",
        filter = "linear",
        mirror = true,
        tint = "wash",
    })
    host:draw()
    clock:advance(0.26)
    host:draw()
    clock:reset(1.01)
    host:draw()
    clock:reset(0)
    host:draw()

    assert(captures[1].geometry.frame == 1
            and captures[2].geometry.frame == 2
            and captures[3].geometry.frame == 1
            and captures[4].geometry.frame == 1,
        "SpriteSheet did not select/wrap/rewind from clock time")
    local latest = captures[#captures]
    assert(latest.asset == sheet
            and latest.geometry.frameCount == 4
            and latest.geometry.clock == "explicit"
            and latest.geometry.filter == "linear"
            and latest.geometry.fit == "cover"
            and latest.geometry.mirror == true,
        "SpriteSheet custom painter lost resolved playback geometry")
    support.near(latest.geometry.frameWidth, 2,
        "SpriteSheet custom frame width")
    support.near(latest.geometry.frameHeight, 4,
        "SpriteSheet custom frame height")
    support.near(latest.style.tint[4], 0.8,
        "SpriteSheet custom tint alpha")
    assert(latest.node.props.clock == nil,
        "SpriteSheet custom descriptor leaked its mutable clock")

    local inspection = inspectionEntry(host, "clocked-sheet").spriteSheet
    assert(inspection.status == "ready" and inspection.frame == 1
            and inspection.frameCount == 4 and inspection.fps == 4
            and inspection.clock == "explicit"
            and inspection.filter == "linear"
            and inspection.mirror == true,
        "F6 omitted SpriteSheet playback metadata")

    host:update(3)
    host:draw()
    assert(captures[#captures].geometry.frame == 1,
        "Host time advanced an explicit SpriteSheet clock")
    clock:advance(0.5)
    host:draw()
    assert(captures[#captures].geometry.frame == 3,
        "reduced motion suppressed an explicitly advanced SpriteSheet clock")
    host:unmount()
end

-- Proves the default painter restores a shared Image filter and handles a
-- missing declared file through the same crossed-box fallback as Frog.Image.
local function defaultPainterAndFallback(sheet)
    sheet:setFilter("linear", "linear")
    local clock = Frog.clock(0.5)
    local host = support.host {
        assets = {
            missing = "tests/fixtures/__frogui_missing_sprite_sheet__.png",
        },
    }
    host:mount(Frog.Overlay {
        width = 20,
        height = 10,
        Frog.SpriteSheet {
            testId = "default-sheet",
            source = sheet,
            frameCount = 4,
            fps = 4,
            clock = clock,
            width = 8,
            height = 8,
        },
        Frog.SpriteSheet {
            testId = "missing-sheet",
            source = "missing",
            frameCount = 4,
            fps = 4,
            clock = clock,
            width = 8,
            height = 8,
            offset = { x = 10 },
        },
    })
    host:draw()
    local minFilter, magFilter = sheet:getFilter()
    assert(minFilter == "linear" and magFilter == "linear",
        "SpriteSheet leaked its temporary nearest filter")
    local missing = inspectionEntry(host, "missing-sheet").spriteSheet
    assert(missing.status == "missing" and missing.frame == 3,
        "missing SpriteSheet lost deterministic playback metadata")
    host:unmount()
end

-- Proves the visible built-in F6 label prints the structured SpriteSheet
-- record instead of leaving its useful playback metadata developer-invisible.
local function visibleInspectorMetadata(sheet)
    local clock = Frog.clock(0.26)
    local host = support.host { width = 540, height = 960 }
    host:mount(Frog.SpriteSheet {
        testId = "visible-inspector-sheet",
        source = sheet,
        frameCount = 4,
        fps = 4,
        clock = clock,
        width = 2,
        height = 4,
        mirror = true,
    })
    host:setInspectorVisible(true)
    assert(host:inspect(1, 1),
        "F6 could not select a concrete SpriteSheet leaf")
    local printed = {}
    local originalPrint = love.graphics.print
    love.graphics.print = function(value)
        printed[#printed + 1] = tostring(value)
    end
    local ok, reason = pcall(host.draw, host)
    love.graphics.print = originalPrint
    host:unmount()
    assert(ok, "visible SpriteSheet inspector failed: " .. tostring(reason))
    local output = table.concat(printed, "\n")
    assert(output:find("sprite ready / frame 2/4", 1, true)
            and output:find("explicit clock", 1, true)
            and output:find("contain / nearest / mirrored", 1, true),
        "F6 did not print complete SpriteSheet playback metadata")
end

-- Proves all malformed sheet contracts fail at mount with actionable errors.
local function validationFailures(sheet)
    local clock = Frog.clock()
    local function mount(props)
        support.host {
            width = 540, height = 960,
        }:mount(Frog.SpriteSheet(props))
    end
    rejects("missing frameCount", function()
        mount { source = sheet, fps = 4, clock = clock }
    end, "frameCount must be a positive integer")
    rejects("fractional frameCount", function()
        mount { source = sheet, frameCount = 2.5, fps = 4, clock = clock }
    end, "frameCount must be a positive integer")
    rejects("zero fps", function()
        mount { source = sheet, frameCount = 4, fps = 0, clock = clock }
    end, "fps must be positive")
    rejects("infinite fps", function()
        mount { source = sheet, frameCount = 4, fps = math.huge, clock = clock }
    end, "fps must be finite")
    rejects("missing explicit clock", function()
        mount { source = sheet, frameCount = 4, fps = 4 }
    end, "clock must come from Frog.clock")
    rejects("invalid fit", function()
        mount {
            source = sheet, frameCount = 4, fps = 4, clock = clock,
            fit = "inside",
        }
    end, "SpriteSheet fit has unsupported value")
    rejects("invalid filter", function()
        mount {
            source = sheet, frameCount = 4, fps = 4, clock = clock,
            filter = "pixel",
        }
    end, "SpriteSheet filter has unsupported value")
    rejects("invalid mirror", function()
        mount {
            source = sheet, frameCount = 4, fps = 4, clock = clock,
            mirror = 1,
        }
    end, "mirror must be a boolean")
    rejects("non-divisible horizontal sheet", function()
        mount { source = sheet, frameCount = 3, fps = 4, clock = clock }
    end, "source width must divide exactly by frameCount")
    rejects("SpriteSheet child", function()
        mount {
            source = sheet, frameCount = 4, fps = 4, clock = clock,
            Frog.Text "No child",
        }
    end, "does not accept children")
    rejects("SpriteSheet callback", function()
        mount {
            source = sheet, frameCount = 4, fps = 4, clock = clock,
            onComplete = function() end,
        }
    end, "unknown prop onComplete on SpriteSheet")
    rejects("SpriteSheet sourceRect", function()
        mount {
            source = sheet, frameCount = 4, fps = 4, clock = clock,
            sourceRect = { x = 0, y = 0, width = 2, height = 2 },
        }
    end, "unknown prop sourceRect on SpriteSheet")
end

function check.run()
    local sheet = fourFrameImage()
    imageMirrorContract(sheet)
    defaultPainterPixels(sheet)
    oneFrameLayout(sheet)
    explicitClockFrames(sheet)
    defaultPainterAndFallback(sheet)
    visibleInspectorMetadata(sheet)
    validationFailures(sheet)
end

return check
