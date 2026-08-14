-- Generic default/custom painter conformance for Icon and outlined Text.
-- Application font-file integration has a separate consumer-owned check.

local Frog = require("frogui")
local support = require("tests.support")

local check = {}

local TEST_ICON = support.generatedImage(16, 16)

local function customDescriptors()
    local boxStyles, iconStyles, textStyles = {}, {}, {}
    local painter = {}
    function painter:box(node, style)
        if node.props.testId == "painter-icon" then
            boxStyles[#boxStyles + 1] = style
        end
    end
    function painter:icon(node, asset, style)
        if node.props.testId ~= "painter-icon" then return end
        assert(asset and asset.getWidth and asset.getHeight,
            "custom Icon painter did not receive the resolved asset")
        iconStyles[#iconStyles + 1] = style
    end
    function painter:text(node, value, style)
        if node.props.testId ~= "painter-label" then return end
        assert(value == "Connected", "custom Text painter received wrong copy")
        textStyles[#textStyles + 1] = style
    end

    local host = support.host {
        width = 540,
        height = 960,
        painter = painter,
        assets = { signal = TEST_ICON },
        theme = {
            fonts = { body = 18 },
            colors = {
                ink = { 0.8, 0.9, 1, 0.75 },
                edge = { 0.05, 0.06, 0.08, 0.5 },
            },
        },
    }
    host:mount(Frog.Row {
        Frog.Icon {
            testId = "painter-icon",
            source = "signal",
            width = 24,
            height = 24,
            fit = "contain",
            tint = "ink",
            mirror = true,
            sourceRect = { x = 0, y = 0, width = 16, height = 16 },
            outline = { width = 2, color = "edge" },
        },
        Frog.Text {
            testId = "painter-label",
            color = "ink",
            outlineWidth = 1.5,
            outlineColor = "edge",
            "Connected",
        },
    })
    host:draw()
    local iconNode = assert(support.find(host:tree(), "painter-icon"))
    local worldA = iconNode._worldTransform.a
    local boundsX = iconNode.layout.x
    iconStyles[1].tint[1] = -10
    iconStyles[1].sourceRect.x = -15
    boxStyles[1].transform.world.a = -20
    boxStyles[1].transform.bounds.x = -30
    textStyles[1].color[1] = -40
    assert(iconNode._worldTransform.a == worldA
            and iconNode._visualBounds == nil and iconNode.layout.x == boundsX
            and iconNode.props.sourceRect.x == 0,
        "custom painter style exposed mutable committed geometry")
    host:draw()
    host:unmount()

    local iconStyle = assert(iconStyles[2],
        "custom painter did not receive Icon")
    assert(iconStyles[1] ~= iconStyle
            and iconStyles[1].tint ~= iconStyle.tint
            and iconStyle.tint[1] > 0
            and iconStyle.sourceRect.x == 0,
        "custom Icon painter received retained default-Painter scratch")
    assert(boxStyles[2] ~= boxStyles[1]
            and boxStyles[2].transform ~= boxStyles[1].transform
            and boxStyles[2].transform.world.a == worldA,
        "custom box style was retained or did not detach transforms")
    assert(iconStyle.alphaMask == true and iconStyle.mirror == true
            and iconStyle.fit == "contain",
        "custom Icon descriptor lost mask/mirror/fit semantics")
    assert(iconStyle.outline and iconStyle.outline.width == 2,
        "custom Icon descriptor lost outline width")
    support.near(iconStyle.tint[4], 0.75, "custom Icon tint alpha")
    support.near(iconStyle.outline.color[4], 0.5,
        "custom Icon outline alpha")

    local textStyle = assert(textStyles[2],
        "custom painter did not receive Text")
    assert(textStyles[1] ~= textStyle
            and textStyles[1].color ~= textStyle.color
            and textStyle.color[1] > 0,
        "custom Text painter received retained default-Painter scratch")
    assert(textStyle.outlineWidth == 1.5,
        "custom Text descriptor lost outline width")
    support.near(textStyle.outlineColor[4], 0.5,
        "custom Text outline alpha")
    local expected = love.graphics.newFont(18)
    support.near(textStyle.font:getWidth("Connected"),
        expected:getWidth("Connected"), "theme numeric-font resolution")
end

-- Proves default drawing reuses only ephemeral node-local style storage while
-- still recomputing transient Button state on every draw.
local function defaultStyleScratch()
    local host = support.host {
        width = 540,
        height = 960,
        theme = { colors = {
            idle = { 0.1, 0.2, 0.3, 1 },
            hover = { 0.4, 0.5, 0.6, 1 },
            pressed = { 0.7, 0.2, 0.2, 1 },
            focused = { 0.9, 0.8, 0.2, 1 },
        } },
    }
    host:mount(Frog.Button {
        testId = "scratch-button",
        width = 100,
        height = 50,
        background = "idle",
        hoverBackground = "hover",
        pressedBackground = "pressed",
        focusedBackground = "focused",
        onPress = function() end,
        Frog.Text "Scratch",
    })
    local button = assert(support.find(host:tree(), "scratch-button"))
    host:draw()
    local scratch = assert(button._paintScratch,
        "default Painter did not retain node-local scratch")
    local style = scratch.style
    local background = style.background
    support.near(background[1], 0.1, "default scratch idle color")

    local x, y = support.center(button)
    host:pointerMove(x, y, "mouse")
    host:draw()
    assert(button._paintScratch == scratch and scratch.style == style
            and style.background == background,
        "default Painter replaced reusable style/color scratch")
    support.near(background[1], 0.4,
        "default scratch did not recompute transient hover color")

    host:pointerDown(x, y, "mouse", 1)
    host:draw()
    support.near(background[1], 0.7,
        "default scratch did not recompute transient pressed color")
    host:pointerUp(x, y, "mouse", 1)
    host:pointerMove(button.layout.x + button.layout.width + 10, y, "mouse")
    host:keyDown("tab", "tab", false)
    host:draw()
    support.near(background[1], 0.9,
        "default scratch did not recompute transient focus color")
    host:unmount()
end

-- Reused child scratch must sample ancestor presentation each draw; it cannot
-- freeze the first inherited opacity/tint merely because layout stayed put.
local function inheritedPresentationScratch()
    local clock = Frog.clock()
    local host = support.host {
        width = 540,
        height = 960,
        theme = { colors = { panel = { 0.4, 0.6, 0.8, 1 } } },
    }
    host:mount(Frog.Motion {
        width = 80,
        height = 40,
        juice = { fade = { key = 1,
            recipe = Frog.withClock(clock, Frog.parallel {
                Frog.tween { to = { opacity = 0.5 }, duration = 1 },
                Frog.tween {
                    to = { tint = { 0.5, 0.5, 0.5, 1 } },
                    duration = 1,
                },
            }) } },
        Frog.Box {
            testId = "inherited-scratch",
            width = 80,
            height = 40,
            background = "panel",
            Frog.Text {
                testId = "inherited-text-scratch",
                color = "panel",
                "Inherited",
            },
        },
    })
    local child = assert(support.find(host:tree(), "inherited-scratch"))
    local text = assert(support.find(host:tree(), "inherited-text-scratch"))
    host:draw()
    local style = child._paintScratch.style
    local background = style.background
    local textStyle = text._paintScratch.leaves.text.style
    local textColor = textStyle.color
    support.near(background[1], 0.4, "initial inherited scratch tint")
    support.near(background[4], 1, "initial inherited scratch opacity")

    clock:advance(0.5)
    host:update(0)
    host:draw()
    assert(child._paintScratch.style == style
            and style.background == background
            and text._paintScratch.leaves.text.style == textStyle
            and textStyle.color == textColor,
        "ancestor presentation replaced child paint scratch")
    support.near(background[1], 0.3, "updated inherited scratch tint")
    support.near(background[4], 0.75,
        "updated inherited scratch opacity")
    support.near(textColor[1], 0.3, "updated inherited leaf tint")
    support.near(textColor[4], 0.75, "updated inherited leaf opacity")
    host:unmount()
end

-- Proves outlined/shine text uses one Host-owned scalar stencil program while
-- preserving the exact draw passes and fresh per-call clip rectangles.
local function outlinedShineProgram()
    local host = support.host { width = 540, height = 960 }
    host:mount(Frog.EffectLayer {
        width = 200,
        height = 100,
        Frog.PopupText {
            key = "outlined-shine",
            testId = "outlined-shine",
            text = "Juicy",
            at = { x = 100, y = 50 },
            duration = 10,
            distance = 0,
            width = 120,
            height = 36,
            outlineWidth = 2,
            shadowOffset = 1,
            shine = 0.5,
            shineSplit = 0.4,
            maxLines = 1,
        },
    })
    local node = assert(support.find(host:tree(), "outlined-shine"))
    local g = love.graphics
    local oldPrintf, oldStencil = g.printf, g.stencil
    local stamps, shapes = {}, {}
    g.printf = function(value, x, y, ...)
        stamps[#stamps + 1] = { value = value, x = x, y = y }
        return oldPrintf(value, x, y, ...)
    end
    g.stencil = function(shape, ...)
        shapes[#shapes + 1] = shape
        return oldStencil(shape, ...)
    end
    local ok, reason = pcall(host.draw, host)
    g.printf, g.stencil = oldPrintf, oldStencil
    assert(ok, reason)
    assert(#stamps == 11,
        "outlined/shine Text changed its shadow + eight outline + two face stamps")
    support.near(stamps[2].x, node.layout.x - 2, "outline left stamp")
    support.near(stamps[3].x, node.layout.x + 2, "outline right stamp")
    support.near(stamps[4].y, node.layout.y - 2, "outline top stamp")
    support.near(stamps[5].y, node.layout.y + 2, "outline bottom stamp")
    assert(#shapes == 4 and shapes[1] == shapes[2]
            and shapes[1] == shapes[3] and shapes[1] == shapes[4]
            and shapes[1] == host._paintClipState.drawShape,
        "Text did not share the Host scalar stencil program")

    local scratch = node._paintScratch
    local textLeaf = scratch.leaves.text
    local clipState = host._paintClipState
    local clipProgram = clipState.drawShape
    node.props.shineSplit = 0.6
    local oldRectangle = g.rectangle
    local freshShapes, clipRects = {}, {}
    local inStencil = false
    g.stencil = function(shape, ...)
        freshShapes[#freshShapes + 1] = shape
        inStencil = true
        local results = { oldStencil(shape, ...) }
        inStencil = false
        return unpack(results)
    end
    g.rectangle = function(mode, x, y, width, height, ...)
        if inStencil then
            clipRects[#clipRects + 1] = {
                x = x,
                y = y,
                width = width,
                height = height,
            }
        end
        return oldRectangle(mode, x, y, width, height, ...)
    end
    ok, reason = pcall(host.draw, host)
    g.stencil, g.rectangle = oldStencil, oldRectangle
    assert(ok, reason)
    assert(host._paintClipState == clipState
            and host._paintClipState.drawShape == clipProgram
            and node._paintShapes == nil
            and scratch.leaves.text == textLeaf
            and #freshShapes == 4
            and freshShapes[1] == clipProgram
            and freshShapes[2] == clipProgram
            and freshShapes[3] == clipProgram
            and freshShapes[4] == clipProgram,
        "outlined/shine Text replaced Host stencil or paint scratch")
    assert(#clipRects == 4,
        "outlined/shine Text changed its four stencil rectangles")
    support.near(clipRects[1].height, node.layout.height,
        "max-lines clip height")
    support.near(clipRects[2].height, node.layout.height * 0.6,
        "fresh shine clip height")
    support.near(clipRects[3].height, node.layout.height * 0.6,
        "fresh shine restore height")
    support.near(clipRects[4].height, node.layout.height,
        "max-lines restore height")
    host:unmount()
end

local function defaultPainterSmoke()
    local host = support.host {
        width = 540,
        height = 960,
        assets = { signal = TEST_ICON },
        theme = {
            fonts = { body = 18 },
            colors = {
                ink = { 0.85, 0.92, 1, 1 },
                edge = { 0.03, 0.04, 0.06, 0.9 },
            },
        },
    }
    host:mount(Frog.Row {
        width = 230,
        height = 40,
        gap = 8,
        Frog.Icon {
            testId = "scratch-icon",
            source = "signal",
            width = 32,
            height = 32,
            tint = "ink",
            mirror = true,
            outline = { width = 2, color = "edge" },
        },
        Frog.Image {
            testId = "scratch-image",
            source = "signal",
            width = 32,
            height = 32,
            tint = "ink",
            fit = "contain",
        },
        Frog.Text {
            testId = "scratch-text",
            grow = 1,
            color = "ink",
            outlineWidth = 2,
            outlineColor = "edge",
            "Default painter",
        },
    })
    host:draw() -- exercises the alpha-mask shader and both outline stamp paths
    local icon = assert(support.find(host:tree(), "scratch-icon"))
    local image = assert(support.find(host:tree(), "scratch-image"))
    local text = assert(support.find(host:tree(), "scratch-text"))
    local iconLeaf = icon._paintScratch.leaves.icon
    local imageLeaf = image._paintScratch.leaves.image
    local textLeaf = text._paintScratch.leaves.text
    assert(icon._paintShapes == nil
            and image._paintShapes == nil
            and text._paintShapes == nil,
        "non-cover/non-clipped leaves created stencil callbacks")

    host:draw()
    assert(icon._paintScratch.leaves.icon == iconLeaf
            and image._paintScratch.leaves.image == imageLeaf
            and text._paintScratch.leaves.text == textLeaf,
        "default leaf Painter replaced reusable style storage")

    icon.props.outline = nil
    image.props.fit = "cover"
    image.props.mirror = true
    image.props.sourceRect = { x = 0, y = 0, width = 16, height = 16 }
    local clipProgram = host._paintClipState.drawShape
    host:draw()
    assert(iconLeaf.style.outline == nil,
        "reused Icon style retained a removed optional outline")
    assert(imageLeaf.style.fit == "cover" and imageLeaf.style.mirror
            and imageLeaf.style.sourceRect == image.props.sourceRect
            and image._paintShapes == nil
            and host._paintClipState.drawShape == clipProgram,
        "reused Image style did not refresh fit/mirror/sourceRect semantics")
    host:unmount()
end

function check.run()
    customDescriptors()
    defaultStyleScratch()
    inheritedPresentationScratch()
    outlinedShineProgram()
    defaultPainterSmoke()
end

return check
