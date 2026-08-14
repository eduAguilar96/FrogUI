-- Deterministic public-contract checks for the single Host input path and its
-- source/bounds inspector. Pointer and keyboard activate the same Button.

local Frog = require("frogui")
local support = require("tests.support")

local check = {}

-- Exposes every supported input primitive in one deterministic test tree.
local RenderProbe = Frog.component("InputRenderProbe", function(props)
    props.onRender()
    return Frog.Button {
        testId = "render-probe",
        onPress = props.onPress,
        Frog.Text(props.label),
    }
end)

-- Builds the shared pointer/keyboard target tree used by the input checks.
local function InputTree(onPress, disabled)
    return Frog.Column {
        padding = 20,
        Frog.Button {
            testId = "input-button",
            disabled = disabled,
            shortcut = "g",
            onPress = onPress,
            Frog.Text "Activate",
        },
    }
end

local function sameColor(actual, expected, label)
    for channel = 1, 4 do
        support.near(actual[channel], expected[channel],
            label .. " channel " .. channel)
    end
end

-- Proves one accessible Button owns hover, press, hold, and visible focus.
local function buttonInteractionStates()
    local colors = {
        base = { 0.10, 0.11, 0.12, 1 },
        hover = { 0.20, 0.21, 0.22, 1 },
        pressed = { 0.30, 0.31, 0.32, 1 },
        focused = { 0.40, 0.41, 0.42, 1 },
        edge = { 0.50, 0.51, 0.52, 1 },
        hoverEdge = { 0.60, 0.61, 0.62, 1 },
        pressedEdge = { 0.70, 0.71, 0.72, 1 },
        focusedEdge = { 0.80, 0.81, 0.82, 1 },
    }
    local latestStyle
    local painter = {}
    function painter:box(node, style)
        if node.props.testId == "state-button" then latestStyle = style end
    end
    local presses, holds, hoverEdges = 0, 0, {}
    local host = support.host {
        width = 540,
        height = 960,
        painter = painter,
        theme = {
            colors = colors,
            controls = { button = {
                background = "base",
                border = "edge",
                hover = "hover",
                pressed = "pressed",
                focused = "focused",
                focusedBorder = "focusedEdge",
            } },
        },
    }
    local tree = support.mount(host, Frog.Button {
        testId = "state-button",
        width = 120,
        height = 48,
        hoverBorder = "hoverEdge",
        pressedBorder = "pressedEdge",
        onPress = function() presses = presses + 1 end,
        onLongPress = function() holds = holds + 1 end,
        onHoverChange = function(value)
            hoverEdges[#hoverEdges + 1] = value
        end,
        Frog.Text "Inspect",
    })
    local button = assert(support.find(tree, "state-button"))
    local x, y = support.center(button)

    host:pointerMove(x, y, "mouse")
    host:draw()
    sameColor(latestStyle.border, colors.hoverEdge,
        "Button hover border")
    host:pointerDown(x, y, "mouse", 1)
    host:draw()
    sameColor(latestStyle.border, colors.pressedEdge,
        "Button pressed border")
    host:pointerUp(x, y, "mouse", 1)
    host:pointerMove(500, 900, "mouse")
    assert(presses == 1 and #hoverEdges == 2
            and hoverEdges[1] == true and hoverEdges[2] == false,
        "Button did not preserve exact press and hover-edge callbacks")

    host:pointerDown(x, y, "touch", 1)
    host:update(0.36)
    host:pointerUp(x, y, "touch", 1)
    assert(holds == 1 and presses == 1,
        "Button hold did not suppress its release activation")
    host:keyDown("tab", "tab", false)
    host:draw()
    sameColor(latestStyle.border, colors.focusedEdge,
        "Button keyboard-focus border")
    host:keyDown("return", "return", false)
    assert(presses == 2,
        "focused Button did not retain keyboard activation")
    host:unmount()
end

function check.run()
    buttonInteractionStates()
    local presses = 0
    local function onPress() presses = presses + 1 end
    local host = support.host { width = 540, height = 960 }
    local tree = support.mount(host, InputTree(onPress, false))
    local button = assert(support.find(tree, "input-button"))
    local x, y = support.center(button)
    assert(host:pointerDown(x, y, "mouse", 1),
        "pointer down did not reach Button")
    assert(host:pointerUp(x, y, "mouse", 1),
        "pointer up did not complete Button")
    assert(presses == 1, "pointer press did not activate exactly once")

    assert(host:keyDown("space", "space", false),
        "focused Button did not handle Space")
    assert(host:keyDown("return", "return", false),
        "focused Button did not handle Return")
    assert(host:keyDown("g", "g", false),
        "Button shortcut did not use the Host keyboard path")
    assert(presses == 4, "keyboard did not share Button activation")

    host:pointerDown(x, y, "mouse", 1)
    host:keyDown("f6", "f6", false)
    host:pointerUp(x, y, "mouse", 1)
    assert(presses == 4,
        "enabling F6 after pointer down completed the captured press")
    host:keyUp("f6", "f6")

    host:pointerDown(x, y, "mouse", 1)
    host:setInspectorVisible(true)
    host:pointerUp(x, y, "mouse", 1)
    assert(presses == 4,
        "programmatic inspector activation completed the captured press")
    host:setInspectorVisible(false)

    host:pointerDown(x, y, "mouse", 1)
    host:pointerUp(539, 959, "mouse", 1)
    assert(presses == 4, "release outside Button completed a press")

    host:pointerDown(x, y, "mouse", 1)
    host:resize(1080, 1920)
    host:pointerUp(x * 2, y * 2, "mouse", 1)
    assert(presses == 4, "resize did not cancel pointer capture")

    tree = support.render(host, InputTree(onPress, true))
    button = assert(support.find(tree, "input-button"))
    x, y = support.center(button)
    host:pointerDown(x * 2, y * 2, "mouse", 1)
    host:pointerUp(x * 2, y * 2, "mouse", 1)
    host:keyDown("space", "space", false)
    host:keyDown("return", "return", false)
    host:keyDown("g", "g", false)
    assert(presses == 4,
        "disabled Button accepted pointer or keyboard activation")

    assert(host:keyDown("f6", "f6", false), "Host did not handle F6")
    local inspection = assert(host:inspectionTree(),
        "F6 did not expose the committed inspection tree")
    local hit = assert(host:inspect(x * 2, y * 2),
        "F6 inspector did not find the Button at its painted bounds")
    assert(inspection.visible and #inspection.nodes > 0,
        "F6 did not expose a visible flattened tree")
    local inspectedButton
    for _, entry in ipairs(inspection.nodes) do
        if entry.testId == "input-button" then inspectedButton = entry break end
    end
    inspectedButton = assert(inspectedButton,
        "inspection tree omitted the authored Button")
    assert(inspectedButton.owner and inspectedButton.source
            and inspectedButton.bounds
            and inspectedButton.bounds.width > 0
            and inspectedButton.bounds.height > 0,
        "inspection entry omitted owner, source or painted bounds")
    assert(hit.source and hit.bounds,
        "topmost inspection hit omitted source or bounds")
    assert(host:keyUp("f6", "f6"), "Host did not handle F6 release")
    assert(not host:inspectionTree().visible,
        "F6 release left the inspection tree visible")

    tree = support.render(host, InputTree(onPress, false))
    button = assert(support.find(tree, "input-button"))
    x, y = support.center(button)
    host:keyDown("f6", "f6", false)
    assert(host:pointerDown(x * 2, y * 2, "mouse", 1),
        "visible F6 inspector did not intercept pointer down")
    assert(host:inspectionTree().selected,
        "F6 pointer inspection did not select an entry")
    host:pointerUp(x * 2, y * 2, "mouse", 1)
    assert(presses == 4, "F6 pointer inspection invoked the Button")
    host:keyUp("f6", "f6")

    host:pointerDown(x * 2, y * 2, "mouse", 1)
    host:unmount()
    host:mount(InputTree(onPress, false))
    host:pointerUp(x * 2, y * 2, "mouse", 1)
    assert(presses == 4, "unmount retained stale pointer capture")
    host:unmount()

    local scaledPresses = 0
    local scaledHost = support.host { width = 1080, height = 1920 }
    tree = support.mount(scaledHost, Frog.Row {
        justify = "end",
        padding = 20,
        Frog.Button {
            width = 80,
            testId = "scaled-button",
            onPress = function() scaledPresses = scaledPresses + 1 end,
            Frog.Text "Scaled",
        },
    })
    button = assert(support.find(tree, "scaled-button"))
    x, y = support.center(button)
    scaledHost:pointerDown(x * 2, y * 2, "mouse", 1)
    scaledHost:pointerUp(x * 2, y * 2, "mouse", 1)
    assert(scaledPresses == 1,
        "physical pointer was not converted into virtual Host coordinates")
    scaledHost:unmount()

    -- `offset` is a controlled visual bleed: it leaves flow allocation in
    -- place but the translated committed bounds own paint, F6 and input.
    local bleedPresses = 0
    -- Builds offset overflow in clipped/unclipped variants for hit-test parity.
    local function BleedTree(clipped)
        return Frog.Box {
            testId = "bleed-parent",
            width = 40,
            height = 40,
            clip = clipped,
            Frog.Button {
                testId = "bleed-button",
                width = 30,
                height = 20,
                offset = { x = 50, y = 5 },
                onPress = function() bleedPresses = bleedPresses + 1 end,
                Frog.Text { testId = "bleed-label", "Out" },
            },
        }
    end
    local bleedHost = support.host { width = 540, height = 960 }
    tree = support.mount(bleedHost, BleedTree(false))
    button = assert(support.find(tree, "bleed-button"))
    x, y = support.center(button)
    assert(x > 40, "bleed input story did not leave its parent bounds")
    assert(bleedHost:pointerDown(x, y, "mouse", 1),
        "offset Button outside an unclipped parent was not hittable")
    bleedHost:pointerUp(x, y, "mouse", 1)
    assert(bleedPresses == 1,
        "offset Button did not activate at its committed bounds")
    bleedHost:setInspectorVisible(true)
    local bleedHit = assert(bleedHost:inspect(x, y),
        "F6 could not inspect offset bleed outside its parent")
    assert(bleedHit.testId == "bleed-label"
            and bleedHit.bounds.x >= button.layout.x
            and bleedHit.bounds.y >= button.layout.y,
        "F6 did not select the deepest translated Button content")
    bleedHost:setInspectorVisible(false)

    tree = support.render(bleedHost, BleedTree(true))
    button = assert(support.find(tree, "bleed-button"))
    x, y = support.center(button)
    assert(not bleedHost:pointerDown(x, y, "mouse", 1),
        "clipped parent leaked input to an offset child")
    bleedHost:pointerUp(x, y, "mouse", 1)
    assert(bleedPresses == 1,
        "clipped offset child unexpectedly activated")
    bleedHost:unmount()

    local renderCount, label = 0, "Before"
    local renderHost
    -- Builds the current keyed probe description after each controller change.
    local function RenderProbeTree()
        return RenderProbe {
            label = label,
            onRender = function() renderCount = renderCount + 1 end,
            onPress = function()
                label = "After"
                renderHost:render(RenderProbeTree())
            end,
        }
    end
    renderHost = support.host { width = 540, height = 960 }
    tree = support.mount(renderHost, RenderProbeTree())
    button = assert(support.find(tree, "render-probe"))
    x, y = support.center(button)
    renderHost:pointerDown(x, y, "mouse", 1)
    renderHost:pointerUp(x, y, "mouse", 1)
    assert(renderCount == 2,
        "one input callback reconciled more than once")
    assert(assert(support.find(renderHost:tree(), "render-probe"))
            .children[1].props.text == "After",
        "callback render did not commit its new props")
    renderHost:unmount()
end

return check
