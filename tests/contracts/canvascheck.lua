-- Focused contract checks for the bounded, record-only Frog.Canvas painter.

local Frog = require("frogui")
local support = require("tests.support")

local check = {}

local THEME = {
    colors = {
        ink = { 0.82, 0.9, 1, 1 },
        ground = { 0.04, 0.05, 0.07, 1 },
        signal = { 0.95, 0.3, 0.22, 1 },
    },
}

local CanvasBranchOwner = Frog.actor("CanvasCheckBranchOwner", {
    initial = "ready",
    render = function()
        return Frog.Box { width = 10, height = 10 }
    end,
})
local CanvasBranchAddress = CanvasBranchOwner:address(
    "CanvasCheckBranchAddress")
local CanvasBranchView = CanvasBranchOwner:view(
    "CanvasCheckBranchView", function()
        return Frog.Canvas {
            testId = "deferred-branch-canvas",
            width = 20,
            height = 20,
            draw = function() end,
        }
    end)

-- Proves Canvas preflight ownership is folded into deferred resolution,
-- including an addressed view that appears before its actor owner.
local function branchPreflightOwnership()
    local host = support.host { width = 100, height = 100, theme = THEME }
    local tree = support.mount(host, Frog.Column {
        CanvasBranchView { target = CanvasBranchAddress },
        Frog.Box { testId = "canvas-free-branch", width = 10, height = 10 },
        CanvasBranchOwner { address = CanvasBranchAddress },
    })
    local canvas = assert(support.find(tree, "deferred-branch-canvas"))
    local plain = assert(support.find(tree, "canvas-free-branch"))
    assert(tree._containsCanvas and canvas._containsCanvas
            and not plain._containsCanvas,
        "deferred resolution lost exact Canvas branch preflight ownership")
    host:draw()
    host:unmount()
end

local function expectMountFailure(label, description, pattern)
    local host = support.host { width = 540, height = 960, theme = THEME }
    local ok, reason = pcall(host.mount, host, description)
    if ok then host:unmount() end
    assert(not ok and tostring(reason):find(pattern, 1, true),
        label .. " was not rejected: " .. tostring(reason))
end

local function expectDrawFailure(label, draw, pattern)
    local host = support.host { width = 540, height = 960, theme = THEME }
    host:mount(Frog.Canvas { width = 80, height = 60, draw = draw })
    local ok, reason = pcall(host.draw, host)
    local entry = host:inspectionTree().nodes[1]
    host:unmount()
    assert(not ok and tostring(reason):find(pattern, 1, true),
        label .. " was not rejected: " .. tostring(reason))
    assert(entry.canvas and entry.canvas.status == "failed",
        label .. " did not leave failed F6 metadata")
end

-- Rejects ambiguous layout, children, unknown props, and malformed draw values.
local function validation()
    expectMountFailure("missing Canvas width",
        Frog.Canvas { height = 20, draw = function() end },
        "explicit width and height")
    expectMountFailure("missing Canvas draw",
        Frog.Canvas { width = 20, height = 20 },
        "draw must be a function")
    expectMountFailure("Canvas child",
        Frog.Canvas { width = 20, height = 20, draw = function() end,
            Frog.Text "hidden" },
        "does not accept children")
    expectMountFailure("Canvas clock creep",
        Frog.Canvas { width = 20, height = 20, draw = function() end,
            clock = Frog.clock() },
        "unknown prop clock")

    expectDrawFailure("missing shape color", function(painter)
        painter:fillCircle { x = 10, y = 10, radius = 4 }
    end, "requires color")
    expectDrawFailure("unknown color token", function(painter)
        painter:fillCircle {
            x = 10, y = 10, radius = 4, color = "missing-token",
        }
    end, "unknown FrogUI color token")
    expectDrawFailure("malformed direct color", function(painter)
        painter:fillCircle {
            x = 10, y = 10, radius = 4,
            color = { 1, 0.5, 0.2, 1, 0 },
        }
    end, "unknown channel")
    expectDrawFailure("non-finite geometry", function(painter)
        painter:fillRect {
            x = 0 / 0, y = 0, width = 10, height = 10, color = "ink",
        }
    end, "finite number")
    expectDrawFailure("negative geometry", function(painter)
        painter:fillCircle {
            x = 5, y = 5, radius = -1, color = "ink",
        }
    end, "at least 0")
    expectDrawFailure("non-numeric optional geometry", function(painter)
        painter:fillRect {
            x = 1, y = 1, width = 10, height = 10,
            radius = false, color = "ink",
        }
    end, "finite number")
    expectDrawFailure("draw callback return", function()
        return true
    end, "must not return a value")
    expectDrawFailure("transform callback return", function(painter)
        painter:withTransform({}, function() return "hidden state" end)
    end, "must not return a value")
end

-- Records the exact shipped-derived vocabulary in local coordinates and gives
-- custom painters detached commands rather than the application callback.
local function recordedVocabulary()
    local captured, metadata, callbackCount, receivedRect
    local firstXs = {}
    local custom = {}
    function custom:canvas(_, commands, inspection)
        captured, metadata = commands, inspection
        firstXs[#firstXs + 1] = commands[1].x
        commands[1].x = 999 -- must not mutate framework-owned inspection/state
    end
    local host = support.host {
        width = 540, height = 960, theme = THEME, painter = custom,
    }
    host:mount(Frog.Canvas {
        testId = "canvas-vocabulary",
        width = 160,
        height = 90,
        draw = function(painter, rect)
            callbackCount = (callbackCount or 0) + 1
            receivedRect = rect
            painter:fillRect {
                x = 2, y = 3, width = 20, height = 14,
                radius = 3, color = "ink",
            }
            painter:strokeRect {
                x = 24, y = 3, width = 20, height = 14,
                radius = 3, lineWidth = 2, color = "signal",
            }
            painter:fillCircle {
                x = 55, y = 10, radius = 6, color = { 0.2, 0.8, 0.4, 1 },
            }
            painter:strokeCircle {
                x = 72, y = 10, radius = 6,
                lineWidth = 1.5, color = "ink",
            }
            painter:fillEllipse {
                x = 94, y = 10, radiusX = 9, radiusY = 4,
                color = { r = 0.1, g = 0.2, b = 0.3, a = 0.4 },
            }
            painter:withTransform({
                x = 120, y = 45, rotation = math.pi / 4, scale = 1.2,
            }, function(scoped)
                scoped:fillRect {
                    x = -6, y = -6, width = 12, height = 12,
                    color = "signal",
                }
            end)
        end,
    })
    host:draw()
    assert(callbackCount == 1 and receivedRect.x == 0 and receivedRect.y == 0
            and receivedRect.width == 160 and receivedRect.height == 90,
        "Canvas callback did not receive its detached local arranged rectangle")
    assert(#captured == 6 and captured[6].kind == "transform"
            and #captured[6].commands == 1,
        "Canvas custom painter lost the bounded shape program")
    assert(metadata.status == "ready" and metadata.commandCount == 7
            and metadata.transformDepth == 1 and metadata.clipped
            and metadata.arrangedBounds.width == 160,
        "Canvas custom painter lost lifecycle/bounds metadata")
    host:draw()
    assert(captured[1].x == 999 and callbackCount == 2
            and firstXs[1] == 2 and firstXs[2] == 2,
        "custom Canvas commands were not detached on every draw")
    local entry = host:inspectionTree().nodes[1]
    assert(entry.canvas.status == "ready"
            and entry.canvas.localBounds.width == 160
            and entry.canvas.commandCount == 7,
        "F6 omitted Canvas bounds/command metadata")
    host:unmount()
end

-- Selects a real Canvas under the default painter and proves F6 paints the
-- human-facing status line, rather than only storing programmatic metadata.
local function defaultInspectorCanvasDetail()
    local g = love.graphics
    local target = g.newCanvas(540, 960, { dpiscale = 1 })
    local previous = g.getCanvas()
    g.setCanvas { target, stencil = true }
    local host = support.host { width = 540, height = 960, theme = THEME }
    host:mount(Frog.Canvas {
        testId = "canvas-f6-detail",
        width = 40,
        height = 30,
        draw = function(painter)
            painter:fillCircle {
                x = 20, y = 15, radius = 5, color = "ink",
            }
        end,
    })
    host:draw()
    host:setInspectorVisible(true)
    assert(host:inspect(20, 15), "F6 could not select the Canvas detail probe")

    local lines = {}
    local realPrint = g.print
    g.print = function(value, ...)
        lines[#lines + 1] = tostring(value)
        return realPrint(value, ...)
    end
    local ok, reason = pcall(host.draw, host)
    g.print = realPrint
    host:unmount()
    g.setCanvas(previous)
    assert(ok, "default F6 Canvas detail paint failed: " .. tostring(reason))
    local output = table.concat(lines, "\n")
    assert(output:find("canvas ready", 1, true)
            and output:find("1 commands", 1, true)
            and output:find("depth 0", 1, true)
            and output:find("local 40.0x30.0", 1, true),
        "default F6 omitted Canvas status/command/depth/local-bounds detail")
end

-- The public painter is an opaque six-method capability. Raw facade fields
-- cannot inject commands, replace the shared budget, or reopen a stale scope.
local function opaquePainterAuthority()
    local captured, retainedRoot, retainedChild
    local custom = {}
    function custom:canvas(_, commands)
        captured = commands
    end
    local host = support.host {
        width = 540, height = 960, theme = THEME, painter = custom,
    }
    host:mount(Frog.Canvas {
        width = 80, height = 60,
        draw = function(painter)
            retainedRoot = painter
            local seen = {}
            for key in pairs(painter) do seen[#seen + 1] = key end
            assert(#seen == 0, "Canvas painter exposed mutable public state")
            assert(getmetatable(painter) == "FrogUICanvasPainter",
                "Canvas painter metatable was not protected")
            local replaced = pcall(setmetatable, painter, {})
            assert(not replaced, "Canvas painter metatable was replaceable")
            for _, method in ipairs({
                "fillRect", "strokeRect", "fillCircle", "strokeCircle",
                "fillEllipse", "withTransform",
            }) do
                assert(type(painter[method]) == "function",
                    "Canvas painter omitted " .. method)
            end
            assert(painter.commands == nil and painter.close == nil,
                "Canvas painter exposed authority beyond its six methods")

            rawset(painter, "_commands", {
                { kind = "fillCircle", x = 1, y = 1, radius = 999 },
            })
            rawset(painter, "_budget", { count = -100000 })
            rawset(painter, "_closed", false)
            painter:fillCircle {
                x = 10, y = 10, radius = 4, color = "ink",
            }
            painter:withTransform({ x = 20, y = 20 }, function(child)
                retainedChild = child
                child:fillRect {
                    x = -2, y = -2, width = 4, height = 4, color = "signal",
                }
            end)
        end,
    })
    host:draw()
    assert(#captured == 2 and captured[1].radius == 4
            and captured[2].kind == "transform"
            and #captured[2].commands == 1,
        "raw Canvas facade fields injected or replaced recorded commands")

    rawset(retainedRoot, "_closed", false)
    rawset(retainedChild, "_closed", false)
    for label, painter in pairs({ root = retainedRoot, child = retainedChild }) do
        local ok, reason = pcall(painter.fillCircle, painter, {
            x = 1, y = 1, radius = 1, color = "ink",
        })
        assert(not ok and tostring(reason):find("no longer active", 1, true),
            "raw fields reopened stale Canvas " .. label .. " painter")
    end
    host:unmount()

    expectDrawFailure("raw Canvas budget replacement", function(painter)
        rawset(painter, "_budget", { count = -100000 })
        for _ = 1, 10000 do
            painter:fillCircle {
                x = 1, y = 1, radius = 1, color = "ink",
            }
        end
    end, "command budget")
end

local function containsReference(value, target, seen)
    if value == target then return true end
    if type(value) ~= "table" then return false end
    seen = seen or {}
    if seen[value] then return false end
    seen[value] = true
    for key, child in pairs(value) do
        if containsReference(key, target, seen)
                or containsReference(child, target, seen) then return true end
    end
    return false
end

-- No custom-painter callback can walk an ancestor, preview, or drag session
-- back to the application-owned Canvas draw closure.
local function customPainterIsolation()
    local function Draw(painter)
        painter:fillCircle { x = 10, y = 10, radius = 3, color = "ink" }
    end
    local inspected = 0
    local expectedPress
    local custom = {}
    local function inspect(label, value)
        inspected = inspected + 1
        assert(not containsReference(value, Draw),
            label .. " reached the authored Canvas callback")
        if value.type then
            assert(value.children == nil and value._dragPreview == nil,
                label .. " received a framework child graph")
        end
    end
    function custom:box(node) inspect("custom:box", node) end
    function custom:canvas(node, commands, inspection)
        inspect("custom:canvas node", node)
        inspect("custom:canvas commands", commands)
        inspect("custom:canvas inspection", inspection)
        assert(node.props.draw == nil,
            "custom:canvas received Canvas props.draw")
    end
    function custom:dragPreview(node, session)
        inspect("custom:dragPreview node", node)
        inspect("custom:dragPreview session", session)
        assert(session.source == nil,
            "custom:dragPreview received the raw drag source")
        assert(session.press == expectedPress,
            "custom:dragPreview lost the sanitized press identity")
        assert(session.payloadKind == "canvas-isolation",
            "custom:dragPreview lost the sanitized payload kind")
    end

    local host = support.host {
        width = 540, height = 960, theme = THEME, painter = custom,
    }
    host:mount(Frog.Overlay {
        width = 200, height = 120,
        Frog.DragSource {
            testId = "canvas-isolation-source",
            payload = { kind = "canvas-isolation" },
            preview = Frog.Canvas {
                width = 40, height = 30, draw = Draw,
            },
            onDrop = function() return true end,
            Frog.Pressable {
                testId = "canvas-isolation-press",
                onPress = function() end,
                Frog.Box { width = 100, height = 70 },
            },
        },
        Frog.Canvas { width = 30, height = 30, draw = Draw },
    })
    host:draw()
    local source = assert(support.find(host:tree(), "canvas-isolation-source"))
    expectedPress = assert(support.find(
        host:tree(), "canvas-isolation-press")).identity
    local x, y = support.center(source)
    host:pointerDown(x, y, "touch", 1)
    host:pointerMove(x + 20, y, "touch")
    host:draw()
    assert(inspected > 0, "custom painter isolation probe did not run")
    host:pointerUp(x + 20, y, "touch", 1)
    host:unmount()
end

-- Repaint never rerenders or advances state; resize/replacement update only
-- callback inputs while retaining the same resolved primitive identity.
local function identityAndRepaint()
    local renders, draws = 0, 0
    local clock = Frog.clock()
    local bounds = {}
    local function Draw(_, rect)
        draws = draws + 1
        bounds[#bounds + 1] = { width = rect.width, height = rect.height }
        local _ = clock:now()
    end
    local Probe = Frog.component("CanvasIdentityProbe", function(props)
        renders = renders + 1
        return Frog.Overlay {
            width = "100%", height = "100%",
            Frog.Canvas {
                testId = "canvas-identity",
                width = "50%", height = "50%", draw = props.draw,
            },
        }
    end)
    local host = support.host { width = 540, height = 960, theme = THEME }
    host:mount(Probe { draw = Draw })
    local node = support.find(host:tree(), "canvas-identity")
    local identity, generation = node.identity, host._generation
    host:draw()
    host:draw()
    assert(renders == 1 and draws == 2 and host._generation == generation
            and clock:now() == 0,
        "Canvas repaint rerendered or advanced caller-owned state")

    host:resize(960, 540)
    host:draw()
    node = support.find(host:tree(), "canvas-identity")
    assert(node.identity == identity and bounds[3].width ~= bounds[2].width,
        "Canvas resize replaced identity or retained stale callback bounds")

    local replacementDraws = 0
    host:render(Probe {
        draw = function() replacementDraws = replacementDraws + 1 end,
    })
    local replacement = support.find(host:tree(), "canvas-identity")
    host:draw()
    assert(replacement.identity == identity and replacementDraws == 1,
        "Canvas callback replacement changed primitive identity or stayed stale")
    host:unmount()
end

-- EffectLayer preserves both numeric and percentage explicit Canvas sizing.
local function effectLayerSizing()
    local seen = {}
    local custom = {}
    function custom:canvas(node, _, inspection)
        seen[node.props.testId] = inspection.localBounds
    end
    local host = support.host {
        width = 540, height = 960, theme = THEME, painter = custom,
    }
    host:mount(Frog.EffectLayer {
        width = 200,
        height = 120,
        Frog.Canvas {
            testId = "canvas-numeric", width = 70, height = 30,
            draw = function() end,
        },
        Frog.Canvas {
            testId = "canvas-percent", width = "50%", height = "25%",
            draw = function() end,
        },
    })
    host:draw()
    assert(seen["canvas-numeric"].width == 70
            and seen["canvas-numeric"].height == 30,
        "EffectLayer overwrote numeric Canvas bounds")
    assert(seen["canvas-percent"].width == 100
            and seen["canvas-percent"].height == 30,
        "EffectLayer did not resolve percentage Canvas bounds")
    host:unmount()
end

-- A Canvas paints above a Button without becoming an input target.
local function inputTransparency()
    local pressed = 0
    local host = support.host { width = 540, height = 960, theme = THEME }
    host:mount(Frog.Overlay {
        width = 120,
        height = 80,
        Frog.Button {
            testId = "canvas-underlay",
            onPress = function() pressed = pressed + 1 end,
            Frog.Text "Underlay",
        },
        Frog.Canvas {
            width = "100%", height = "100%",
            draw = function(painter, rect)
                painter:strokeRect {
                    x = 1, y = 1, width = rect.width - 2,
                    height = rect.height - 2, color = "ink",
                }
            end,
        },
    })
    host:pointerDown(60, 40, "mouse", 1)
    host:pointerUp(60, 40, "mouse", 1)
    assert(pressed == 1, "Canvas intercepted its interactive underlay")
    host:unmount()
end

-- Oversized commands are clipped to the exact arranged leaf on the GPU.
local function gpuClipping()
    local target = love.graphics.newCanvas(540, 960, { dpiscale = 1 })
    local previous = love.graphics.getCanvas()
    love.graphics.setCanvas { target, stencil = true }
    love.graphics.clear(0, 0, 0, 1)
    local host = support.host { width = 540, height = 960, theme = THEME }
    host:mount(Frog.Overlay {
        width = 540, height = 960,
        Frog.Box { width = "100%", height = "100%", background = "ground" },
        Frog.Box {
            width = 40, height = 40, offset = { x = 100, y = 100 },
            clip = true,
            Frog.Motion {
                x = 20,
                Frog.Canvas {
                    width = 40, height = 40,
                    draw = function(painter)
                        painter:fillRect {
                            x = -100, y = -100, width = 240, height = 240,
                            color = "signal",
                        }
                    end,
                },
            },
        },
    })
    host:draw()
    host:unmount()
    love.graphics.setCanvas(previous)
    local pixels = target:newImageData()
    local beforeCanvas = pixels:getPixel(110, 110)
    local visible = pixels:getPixel(130, 110)
    local afterParent = pixels:getPixel(150, 110)
    assert(visible > 0.8 and beforeCanvas < 0.2 and afterParent < 0.2,
        "Canvas lost its own clip, parent clip, or Motion transform")
end

-- A rejected finite-but-hostile program fails during preflight, before the
-- frame clear or any other GPU work can touch the caller's render target.
local function expectGeometryPreflightFailure(label, draw, pattern, size)
    local target = love.graphics.newCanvas(64, 64, { dpiscale = 1 })
    local previous = love.graphics.getCanvas()
    love.graphics.setCanvas { target, stencil = true }
    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.setStencilTest()
    love.graphics.clear(0.17, 0.28, 0.39, 0.5)
    love.graphics.pop()

    local host = support.host { width = 540, height = 960, theme = THEME }
    host:mount(Frog.Canvas {
        width = size and size.width or 80,
        height = size and size.height or 60,
        draw = draw,
    })
    local ok, reason = pcall(host.draw, host)
    host:unmount()
    love.graphics.setCanvas(previous)
    local pixel = { target:newImageData():getPixel(32, 32) }
    assert(not ok and tostring(reason):find(pattern, 1, true),
        label .. " was not rejected before replay: " .. tostring(reason))
    local expected = { 0.17, 0.28, 0.39, 0.5 }
    for index = 1, 4 do
        assert(math.abs(pixel[index] - expected[index]) < 0.01,
            label .. " touched the render target before rejection")
    end
end

-- Finite values are still bounded by one leaf-relative envelope and hard
-- ceiling, including nested transform expansion.
local function geometryCeilings()
    local huge = 1e100
    expectGeometryPreflightFailure("huge Canvas rectangle", function(painter)
        painter:fillRect {
            x = 0, y = 0, width = huge, height = 1, color = "ink",
        }
    end, "geometry ceiling")
    expectGeometryPreflightFailure("huge Canvas circle", function(painter)
        painter:fillCircle {
            x = 1, y = 1, radius = huge, color = "ink",
        }
    end, "geometry ceiling")
    expectGeometryPreflightFailure("huge Canvas ellipse", function(painter)
        painter:fillEllipse {
            x = 1, y = 1, radiusX = huge, radiusY = 1, color = "ink",
        }
    end, "geometry ceiling")
    expectGeometryPreflightFailure("huge Canvas line width", function(painter)
        painter:strokeRect {
            x = 1, y = 1, width = 10, height = 10,
            lineWidth = huge, color = "ink",
        }
    end, "geometry ceiling")
    expectGeometryPreflightFailure("huge Canvas transform scale",
        function(painter)
            painter:withTransform({ scale = huge }, function() end)
        end, "geometry ceiling")
    expectGeometryPreflightFailure("nested Canvas transform product",
        function(painter)
            painter:withTransform({ scale = 10 }, function(child)
                child:withTransform({ scale = 10 }, function() end)
            end)
        end, "geometry ceiling")
    expectGeometryPreflightFailure("zero-scale huge Canvas circle",
        function(painter)
            painter:withTransform({ scale = 0 }, function(child)
                child:fillCircle {
                    x = 0, y = 0, radius = huge, color = "ink",
                }
            end)
        end, "geometry ceiling")
    expectGeometryPreflightFailure("tiny-scale huge Canvas ellipse",
        function(painter)
            painter:withTransform({ scale = 1e-100 }, function(child)
                child:fillEllipse {
                    x = 0, y = 0,
                    radiusX = huge, radiusY = 1, color = "ink",
                }
            end)
        end, "geometry ceiling")
    expectGeometryPreflightFailure("zero-scale huge rounded rectangle",
        function(painter)
            painter:withTransform({ scale = 0 }, function(child)
                child:fillRect {
                    x = 0, y = 0, width = huge, height = huge,
                    radius = huge / 2, color = "ink",
                }
            end)
        end, "geometry ceiling")
    expectGeometryPreflightFailure("zero-scale huge Canvas translation",
        function(painter)
            painter:withTransform({ scale = 0 }, function(child)
                child:withTransform({ x = huge }, function() end)
            end)
        end, "geometry ceiling")
    expectGeometryPreflightFailure("huge Canvas arranged bounds",
        function() end, "geometry ceiling", { width = huge, height = 60 })
end

-- Canvas callbacks run in authored source order before later sibling paint.
local function sourceOrder()
    local order = {}
    local custom = {}
    function custom:canvas(node)
        order[#order + 1] = node.props.testId
    end
    function custom:text(node)
        if node.props.testId then order[#order + 1] = node.props.testId end
    end
    local host = support.host {
        width = 540, height = 960, theme = THEME, painter = custom,
    }
    host:mount(Frog.Overlay {
        width = 100, height = 100,
        Frog.Canvas {
            testId = "canvas-order-a", width = 20, height = 20,
            draw = function() end,
        },
        Frog.Canvas {
            testId = "canvas-order-b", width = 20, height = 20,
            draw = function() end,
        },
        Frog.Text { testId = "canvas-order-label", "later" },
    })
    host:draw()
    assert(table.concat(order, ",")
            == "canvas-order-a,canvas-order-b,canvas-order-label",
        "Canvas paint did not preserve authored source order")
    host:unmount()
end

local function sameGraphicsState(before, label)
    local color = { love.graphics.getColor() }
    local compare, value = love.graphics.getStencilTest()
    local x, y = love.graphics.transformPoint(0, 0)
    assert(math.abs(color[1] - before.color[1]) < 0.001
            and math.abs(color[2] - before.color[2]) < 0.001
            and math.abs(color[3] - before.color[3]) < 0.001
            and math.abs(color[4] - before.color[4]) < 0.001
            and love.graphics.getLineWidth() == before.lineWidth
            and compare == before.compare and value == before.value
            and math.abs(x - before.x) < 0.001
            and math.abs(y - before.y) < 0.001,
        label .. " leaked graphics color/line/stencil/transform state")
end

-- Both successful recording and loud callback failure restore all caller state.
local function graphicsStateRestoration()
    local target = love.graphics.newCanvas(540, 960, { dpiscale = 1 })
    local previous = love.graphics.getCanvas()
    love.graphics.setCanvas { target, stencil = true }
    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.translate(7, 9)
    love.graphics.setColor(0.12, 0.23, 0.34, 0.45)
    love.graphics.setLineWidth(7)
    love.graphics.setStencilTest("greater", 0)
    local before = {
        color = { love.graphics.getColor() },
        lineWidth = love.graphics.getLineWidth(),
        compare = "greater",
        value = 0,
        x = 7,
        y = 9,
    }

    local host = support.host { width = 540, height = 960, theme = THEME }
    host:mount(Frog.Canvas {
        width = 30, height = 30,
        draw = function(painter)
            painter:strokeCircle {
                x = 15, y = 15, radius = 7,
                lineWidth = 2, color = "ink",
            }
        end,
    })
    host:draw()
    sameGraphicsState(before, "successful Canvas draw")
    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.setStencilTest()
    love.graphics.clear(0.31, 0.42, 0.53, 0.64)
    love.graphics.pop()
    host:render(Frog.Canvas {
        width = 30, height = 30,
        draw = function() error("record failure sentinel") end,
    })
    local ok, reason = pcall(host.draw, host)
    assert(not ok and tostring(reason):find("record failure sentinel", 1, true),
        "Canvas record failure was not surfaced loudly")
    sameGraphicsState(before, "failed Canvas draw")
    host:unmount()

    love.graphics.pop()
    love.graphics.setCanvas(previous)
    local sentinelAfter = { target:newImageData():getPixel(400, 700) }
    local expected = { 0.31, 0.42, 0.53, 0.64 }
    for index = 1, 4 do
        assert(math.abs(sentinelAfter[index] - expected[index]) < 0.01,
            "Canvas record failure touched the render target")
    end
end

local function actorValue(host, name)
    for _, actor in ipairs(host:inspectionTree().actors or {}) do
        if actor.name == name then return actor.state end
    end
end

-- Every send path converges on Host:_enqueue, including render-captured actor
-- and addressed-view send closures that bypass the public Frog.send helper.
local function capturedSendsRespectDrawingBoundary()
    local BumpActor = Frog.action("CanvasCheckCapturedActor.Bump")
    local actorSend
    local ActorOwner = Frog.actor("CanvasCheckCapturedActor", {
        initial = 0,
        actions = {
            [BumpActor] = function(state) return state + 1 end,
        },
        render = function(_, _, send)
            actorSend = send
            return Frog.Box { width = 1, height = 1 }
        end,
    })
    local host = support.host { width = 540, height = 960, theme = THEME }
    host:mount(Frog.Overlay {
        ActorOwner {},
        Frog.Canvas {
            width = 20, height = 20,
            draw = function() actorSend(BumpActor {}) end,
        },
    })
    local beforeTrace = #host:messageTrace()
    local ok, reason = pcall(host.draw, host)
    assert(not ok and tostring(reason):find("drawing phase", 1, true)
            and actorValue(host, "CanvasCheckCapturedActor") == 0
            and #host:messageTrace() == beforeTrace,
        "actor-local captured send dispatched during drawing: "
            .. tostring(reason))
    host:unmount()

    local BumpView = Frog.action("CanvasCheckCapturedView.Bump")
    local viewSend
    local ViewOwner = Frog.actor("CanvasCheckCapturedView", {
        initial = 0,
        actions = {
            [BumpView] = function(state) return state + 1 end,
        },
        render = function() return nil end,
    })
    local Address = ViewOwner:address("canvas-check-captured-view")
    local Connected = ViewOwner:view("CanvasCheckCapturedViewSurface",
        function(_, _, send)
            viewSend = send
            return Frog.Box { width = 1, height = 1 }
        end)
    host = support.host { width = 540, height = 960, theme = THEME }
    host:mount(Frog.Overlay {
        ViewOwner { address = Address },
        Connected { target = Address },
        Frog.Canvas {
            width = 20, height = 20,
            draw = function() viewSend(BumpView {}) end,
        },
    })
    beforeTrace = #host:messageTrace()
    ok, reason = pcall(host.draw, host)
    assert(not ok and tostring(reason):find("drawing phase", 1, true)
            and actorValue(host, "CanvasCheckCapturedView") == 0
            and #host:messageTrace() == beforeTrace,
        "view-local captured send dispatched during drawing: "
            .. tostring(reason))
    host:unmount()
end

local function closeEnough(left, right)
    return math.abs(left - right) < 0.001
end

-- Injects a real replay-time graphics failure. The Canvas leaf must unwind its
-- clip and graphics frame, paint its later sibling, and let the Host unwind the
-- outer frame before surfacing the error.
local function gpuReplayFailureRestoration()
    local g = love.graphics
    local target = g.newCanvas(540, 960, { dpiscale = 1 })
    local previousCanvas = g.getCanvas()
    g.setCanvas { target, stencil = true }
    g.push("all")
    g.origin()
    g.setShader()
    g.setBlendMode("alpha", "alphamultiply")
    g.setScissor()
    g.setStencilTest()
    g.clear(0.04, 0.05, 0.07, 1)
    g.pop()

    local shader = g.newShader([[
        vec4 effect(vec4 color, Image texture, vec2 texture_coords,
                vec2 screen_coords) {
            return color;
        }
    ]])
    g.push("all")
    g.origin()
    g.translate(7, 9)
    g.setShader(shader)
    g.setBlendMode("add", "premultiplied")
    g.setScissor(2, 3, 100, 80)
    g.setStencilTest("greater", 0)
    g.setColor(0.12, 0.23, 0.34, 0.45)
    g.setLineWidth(7)
    local before = {
        canvas = g.getCanvas(),
        shader = g.getShader(),
        blend = { g.getBlendMode() },
        scissor = { g.getScissor() },
        stencil = { g.getStencilTest() },
        color = { g.getColor() },
        lineWidth = g.getLineWidth(),
        origin = { g.transformPoint(0, 0) },
        xAxis = { g.transformPoint(1, 0) },
        yAxis = { g.transformPoint(0, 1) },
    }

    local host = support.host { width = 540, height = 960, theme = THEME }
    host:mount(Frog.Overlay {
        width = 540, height = 960,
        Frog.Canvas {
            width = 20, height = 20,
            offset = { x = 5, y = 5 },
            draw = function(painter)
                painter:fillCircle {
                    x = 10, y = 10, radius = 6, color = "ink",
                }
            end,
        },
        Frog.Box {
            width = 20, height = 20,
            offset = { x = 40, y = 30 },
            background = "signal",
        },
    })

    local realCircle = g.circle
    g.circle = function()
        error("GPU replay sentinel")
    end
    local ok, reason = pcall(host.draw, host)
    g.circle = realCircle

    local after = {
        canvas = g.getCanvas(),
        shader = g.getShader(),
        blend = { g.getBlendMode() },
        scissor = { g.getScissor() },
        stencil = { g.getStencilTest() },
        color = { g.getColor() },
        lineWidth = g.getLineWidth(),
        origin = { g.transformPoint(0, 0) },
        xAxis = { g.transformPoint(1, 0) },
        yAxis = { g.transformPoint(0, 1) },
    }
    local drawingCleared = host._drawing == nil
    host:unmount()
    g.pop()
    g.setCanvas(previousCanvas)
    local pixels = target:newImageData()
    local sibling = { pixels:getPixel(57, 49) }

    assert(not ok and tostring(reason):find("GPU replay sentinel", 1, true),
        "GPU replay failure was not surfaced after cleanup: "
            .. tostring(reason))
    assert(drawingCleared, "GPU replay failure left Host._drawing active")
    assert(after.canvas == before.canvas and after.shader == before.shader
            and after.blend[1] == before.blend[1]
            and after.blend[2] == before.blend[2]
            and after.scissor[1] == before.scissor[1]
            and after.scissor[2] == before.scissor[2]
            and after.scissor[3] == before.scissor[3]
            and after.scissor[4] == before.scissor[4]
            and after.stencil[1] == before.stencil[1]
            and after.stencil[2] == before.stencil[2]
            and after.lineWidth == before.lineWidth,
        "GPU replay failure leaked canvas/shader/blend/scissor/stencil/line state")
    for index = 1, 4 do
        assert(closeEnough(after.color[index], before.color[index]),
            "GPU replay failure leaked graphics color state")
    end
    for _, point in ipairs({ "origin", "xAxis", "yAxis" }) do
        assert(closeEnough(after[point][1], before[point][1])
                and closeEnough(after[point][2], before[point][2]),
            "GPU replay failure leaked graphics transform state")
    end
    assert(sibling[1] > 0.8 and sibling[2] < 0.5,
        "GPU replay failure prevented the later sibling from painting")
end

-- Uses one helper rather than duplicating the Host draw-boundary assertions.
local function drawBoundary()
    local operations = {
        { "send", function() Frog.send({}, {}) end, "may not send" },
        { "emit", function() Frog.emit({}) end, "may not emit" },
        { "render", function(host) host:render() end, "may not render" },
        { "resize", function(host) host:resize(540, 960) end, "may not resize" },
        { "update", function(host) host:update(0) end, "may not advance" },
        { "pointer", function(host) host:pointerDown(1, 1) end,
            "may not route pointer input through" },
        { "unmount", function(host) host:unmount() end, "may not unmount" },
        { "draw", function(host) host:draw() end, "cannot re-enter" },
    }
    for _, probe in ipairs(operations) do
        local host = support.host { width = 540, height = 960, theme = THEME }
        host:mount(Frog.Canvas {
            width = 20, height = 20,
            draw = function() probe[2](host) end,
        })
        local ok, reason = pcall(host.draw, host)
        assert(not ok and tostring(reason):find(probe[3], 1, true),
            "Canvas draw boundary allowed " .. probe[1] .. ": "
                .. tostring(reason))
        -- The deferred failure occurs only after painter scopes unwind.
        host:render(Frog.Canvas {
            width = 20, height = 20,
            draw = function(painter)
                painter:fillCircle {
                    x = 10, y = 10, radius = 4, color = "ink",
                }
            end,
        })
        host:draw()
        host:unmount()
    end

    local retained
    local host = support.host { width = 540, height = 960, theme = THEME }
    host:mount(Frog.Canvas {
        width = 20, height = 20,
        draw = function(painter) retained = painter end,
    })
    host:draw()
    local ok, reason = pcall(retained.fillCircle, retained, {
        x = 1, y = 1, radius = 1, color = "ink",
    })
    assert(not ok and tostring(reason):find("no longer active", 1, true),
        "Canvas painter escaped its draw callback")
    host:unmount()
end

-- Command and transform budgets stop adversarial callback work deterministically.
local function budgets()
    expectDrawFailure("Canvas command budget", function(painter)
        for _ = 1, 10000 do
            painter:fillCircle {
                x = 1, y = 1, radius = 1, color = "ink",
            }
        end
    end, "command budget")

    expectDrawFailure("Canvas transform-depth budget", function(painter)
        local function nested(scope, depth)
            if depth == 100 then return end
            scope:withTransform({}, function(child)
                nested(child, depth + 1)
            end)
        end
        nested(painter, 0)
    end, "transform-depth budget")
end

-- Reduced motion does not invent hidden Canvas time or suppress drawing.
local function reducedMotionIsCallerOwned()
    local draws = 0
    local host = support.host {
        width = 540, height = 960, theme = THEME, reducedMotion = true,
    }
    host:mount(Frog.Canvas {
        width = 30, height = 30,
        draw = function(painter)
            draws = draws + 1
            painter:fillCircle { x = 15, y = 15, radius = 5, color = "ink" }
        end,
    })
    host:update(1)
    host:draw()
    assert(draws == 1,
        "reduced motion suppressed a caller-owned settled Canvas frame")
    host:unmount()
end

function check.run()
    validation()
    branchPreflightOwnership()
    recordedVocabulary()
    defaultInspectorCanvasDetail()
    opaquePainterAuthority()
    customPainterIsolation()
    identityAndRepaint()
    effectLayerSizing()
    inputTransparency()
    gpuClipping()
    geometryCeilings()
    sourceOrder()
    graphicsStateRestoration()
    gpuReplayFailureRestoration()
    drawBoundary()
    capturedSendsRespectDrawingBoundary()
    budgets()
    reducedMotionIsCallerOwned()
end

return check
