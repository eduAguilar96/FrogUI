-- Adversarial checks for the generic controlled RadialDial contract.

local Frog = require("frogui")
local Interaction = require("frogui.interaction")
local support = require("tests.support")

local check = {}
local VALUES = { 0.5, 1, 2 }
local POLICY = Interaction.radialDialPolicy()

assert(POLICY.dragRadians == 0.10 and POLICY.settleSpeed == 10,
    "RadialDial drifted from its code-owned feel policy")

-- Renders one fixed option face so checks can observe upright orbit geometry.
local function option(index, value)
    return Frog.Box {
        key = "value:" .. tostring(value),
        testId = "dial-option-" .. index,
        width = 44,
        height = 44,
        align = "center",
        justify = "center",
        background = index == 2 and { 0.8, 0.7, 0.2, 1 }
            or { 0.2, 0.3, 0.4, 1 },
        Frog.Text { align = "center", "x" .. tostring(value) },
    }
end

-- Builds one readable controlled dial. Optional sibling Buttons are authored
-- after it so their source-ordered shortcuts can prove keyboard precedence.
local function surface(log, options)
    options = options or {}
    local values = options.values or VALUES
    local children = {}
    for index, value in ipairs(values) do
        children[index] = option(index, value)
    end
    local dial = Frog.RadialDial {
        key = "dial",
        testId = "radial-dial",
        ref = options.ref,
        width = options.dialWidth or 240,
        height = options.dialHeight or 240,
        trackRadius = options.trackRadius or 72,
        value = options.value or 1,
        values = values,
        disabled = options.disabled,
        focusedBorder = options.focusedBorder,
        background = options.background,
        border = options.border,
        sound = options.sound,
        spinSound = options.spinSound,
        onChange = function(value)
            log[#log + 1] = value
            if options.fail then error("radial callback sentinel") end
        end,
        unpack(children),
    }
    local rootChildren = { dial }
    for index, shortcut in ipairs(options.shortcuts or {}) do
        rootChildren[#rootChildren + 1] = Frog.Button {
            key = "shortcut:" .. index,
            testId = "dial-shortcut-" .. index,
            width = 40,
            height = 40,
            shortcut = shortcut.key,
            onPress = function() log[#log + 1] = shortcut.result end,
            Frog.Text(shortcut.label or shortcut.key),
        }
    end
    if options.modal then
        rootChildren[#rootChildren + 1] = Frog.Modal {
            key = "takeover",
            dismiss = "none",
            Frog.Box { width = 100, height = 100 },
        }
    end
    return Frog.Overlay {
        testId = "radial-root",
        width = 540,
        height = 960,
        align = "center",
        justify = "center",
        unpack(rootChildren),
    }
end

local function mounted(log, options, hostOptions)
    local host = support.host(hostOptions or {
        width = 540, height = 960,
    })
    host:mount(surface(log, options))
    return host, assert(support.find(host:tree(), "radial-dial"))
end

local dialRootRef

-- Attaches a ref only to the stable dial root; moving option descendants are
-- contractually static and ref-free.
local RootRefDial = Frog.component("RadialDialCheckRootRef", function()
    dialRootRef = Frog.useRef()
    local children = { surface({}, { ref = dialRootRef }) }
    -- Keep the dial branch below the router's conservative whole-tree coverage
    -- fallback, matching its small HUD footprint in a real application tree.
    for index = 1, 48 do
        children[#children + 1] = Frog.Box {
            key = "unrelated:" .. index,
            width = 1,
            height = 1,
        }
    end
    return Frog.Overlay {
        width = 540,
        height = 960,
        unpack(children),
    }
end)

-- Attempts the intentionally unsupported moving-descendant ref shape.
local RefOptionDial = Frog.component("RadialDialCheckRefOption", function()
    local optionRef = Frog.useRef()
    return Frog.RadialDial {
        value = 1,
        values = { 1, 2 },
        onChange = function() end,
        Frog.Box { key = "one", ref = optionRef,
            width = 20, height = 20 },
        Frog.Box { key = "two", width = 20, height = 20 },
    }
end)

-- Proves option settling leaves the root's already-published rectangle exact,
-- so retained orbit animation needs no ref traversal or publication.
local function stableRootRef()
    local host = support.host { width = 540, height = 960, diagnostics = true }
    host:mount(RootRefDial {})
    local dial = assert(support.find(host:tree(), "radial-dial"))
    local before = assert(dialRootRef.current)
    local refRevision = host._arrangedRefRevision
    host:clearDiagnostics()
    dial._radialDial.targetAngle = dial._radialDial.angle + math.pi / 2
    host:update(0.05)
    host:draw({})
    local after = assert(dialRootRef.current)
    assert(after.x == before.x and after.y == before.y
            and after.width == before.width and after.height == before.height
            and after.x == dial.layout.x and after.y == dial.layout.y
            and after.width == dial.layout.width
            and after.height == dial.layout.height,
        "RadialDial orbit invalidated its stable root ref")
    assert(host._arrangedRefRevision == refRevision
            and host._publishedRefRevision == refRevision,
        "RadialDial orbit dirtied the stable arranged-ref revision")
    local trace = host:diagnosticTrace()
    local row = assert(trace[#trace],
        "RadialDial orbit omitted its diagnostic row")
    local transform = assert(row.transformAttribution.interaction)
    assert(transform.branchRuns == 1 and transform.fullRuns == 0
            and transform.fallbackRuns == 0 and transform.dirtyRoots == 1
            and transform.families.RadialDial == 1,
        "RadialDial orbit did not use one exact transform branch")
    host:unmount()
end

local function rejects(label, description, fragment)
    local host = support.host { width = 540, height = 960 }
    local ok, reason = pcall(host.mount, host, description)
    if ok then host:unmount() end
    assert(not ok and tostring(reason):find(fragment, 1, true),
        label .. " rejected for the wrong reason: " .. tostring(reason))
end

local function validation()
    rejects("missing callback", Frog.RadialDial {
        value = 1, values = VALUES,
        option(1, 0.5), option(2, 1), option(3, 2),
    }, "onChange must be a function")
    rejects("legacy callback", Frog.RadialDial {
        value = 1, values = VALUES, onChange = function() end,
        onCommit = function() end,
        option(1, 0.5), option(2, 1), option(3, 2),
    }, "unknown prop onCommit")
    rejects("duplicate values", Frog.RadialDial {
        value = 1, values = { 1, 1 }, onChange = function() end,
        Frog.Box { key = "first", width = 20, height = 20 },
        Frog.Box { key = "second", width = 20, height = 20 },
    }, "values must be unique")
    rejects("non-member value", Frog.RadialDial {
        value = 4, values = VALUES, onChange = function() end,
        option(1, 0.5), option(2, 1), option(3, 2),
    }, "value must be a finite member")
    rejects("missing option", Frog.RadialDial {
        value = 1, values = VALUES, onChange = function() end,
        option(1, 0.5), option(2, 1),
    }, "exactly one child per value")
    rejects("unkeyed option", Frog.RadialDial {
        value = 1, values = { 1, 2 }, onChange = function() end,
        Frog.Box { width = 20, height = 20 }, option(2, 2),
    }, "needs a stable key")
    rejects("interactive option", Frog.RadialDial {
        value = 1, values = { 1, 2 }, onChange = function() end,
        Frog.Button { key = "one", onPress = function() end, Frog.Text "1" },
        option(2, 2),
    }, "static presentation")
    rejects("ref-bearing option", RefOptionDial {},
        "static presentation")
    rejects("public threshold", Frog.RadialDial {
        value = 1, values = VALUES, onChange = function() end,
        dragRadians = 0.01,
        option(1, 0.5), option(2, 1), option(3, 2),
    }, "unknown prop dragRadians")
    rejects("asymmetric center", Frog.RadialDial {
        width = 240, height = 240, padding = { left = 20 },
        value = 1, values = VALUES, onChange = function() end,
        option(1, 0.5), option(2, 1), option(3, 2),
    }, "unknown prop padding")
    rejects("offset option", Frog.RadialDial {
        width = 240, height = 240,
        value = 1, values = VALUES, onChange = function() end,
        Frog.Box { key = "offset", width = 20, height = 20,
            offset = { x = 2 } },
        option(2, 1), option(3, 2),
    }, "option children do not accept offset")
    rejects("overflowing track", Frog.RadialDial {
        width = 100, height = 100, trackRadius = 40,
        value = 1, values = VALUES, onChange = function() end,
        option(1, 0.5), option(2, 1), option(3, 2),
    }, "keep every option child inside")
    rejects("rectangular corner overflow", Frog.RadialDial {
        width = 100, height = 100, trackRadius = 28,
        value = 1, values = { 1, 2 }, onChange = function() end,
        Frog.Box { key = "one", width = 20, height = 40 },
        Frog.Box { key = "two", width = 20, height = 40 },
    }, "keep every option child inside")
end

local function dialGeometry(node)
    local x, y = support.center(node)
    return x, y, math.min(node.layout.width, node.layout.height) / 2
end

local function inspectionEntry(host)
    for _, entry in ipairs(host:inspectionTree().nodes) do
        if entry.testId == "radial-dial" then return entry end
    end
end

-- Center presses establish no meaningless atan2 origin. The first exit only
-- establishes an origin; a later angular move visibly relocates upright items.
local function previewAndDeadZone()
    local log = {}
    local host, dial = mounted(log)
    local x, y, radius = dialGeometry(dial)
    local initial = assert(support.find(host:tree(), "dial-option-1"))
    local initialX, initialY = initial.layout.x, initial.layout.y

    assert(not host:pointerDown(dial.layout.x + 1, dial.layout.y + 1,
        "touch", 1),
        "square corner outside the full circular hit area was claimed")
    assert(host:pointerDown(x, y, "touch", 1),
        "center press did not claim the dial")
    local armed = host:inspectionTree().interaction.session
    assert(armed and not armed.radialOriginEstablished,
        "center press recorded atan2 before leaving the dead-zone")

    host:pointerMove(x + radius * 0.6, y, "touch")
    local exited = host:inspectionTree().interaction.session
    assert(exited.radialOriginEstablished and not exited.radialMoved,
        "first dead-zone exit moved instead of establishing the origin")
    local unchanged = assert(support.find(host:tree(), "dial-option-1"))
    support.near(unchanged.layout.x, initialX, "dead-zone first-exit x")
    support.near(unchanged.layout.y, initialY, "dead-zone first-exit y")

    host:pointerMove(x + math.cos(0.3) * radius * 0.6,
        y + math.sin(0.3) * radius * 0.6, "touch")
    local preview = host:inspectionTree().interaction.session
    assert(preview.radialPhase == "preview" and #log == 0,
        "preview did not stay internal to FrogUI")
    local moved = assert(support.find(host:tree(), "dial-option-1"))
    assert(math.abs(moved.layout.x - initialX) > 1
            or math.abs(moved.layout.y - initialY) > 1,
        "pointer preview did not visibly orbit option positions")
    local entry = assert(inspectionEntry(host))
    support.near(entry.radialDial.visualAngle,
        preview.radialPreviewAngle, "F6 preview angle")
    assert(entry.radialDial.deadZoneRadius > 0
            and entry.radialDial.trackRadius == 72,
        "F6 omitted radial geometry policy")

    local painted
    host:draw({ box = function(_, node)
        if node.props.testId == "dial-option-1" then painted = node end
    end })
    assert(painted and math.abs(painted.x - initialX) > 1,
        "Painter did not consume the preview arrangement")
    host:pointerUp(x + math.cos(0.3) * radius * 0.6,
        y + math.sin(0.3) * radius * 0.6, "touch", 1)
    assert(#log == 1, "release did not emit exactly one value")
    host:unmount()
end

-- Successive normalized deltas cross atan2's branch without a full-turn jump.
local function branchCrossing()
    local log = {}
    local host, dial = mounted(log)
    local x, y, radius = dialGeometry(dial)
    local first, second = 3.08, -3.08
    host:pointerDown(x + math.cos(first) * radius * 0.7,
        y + math.sin(first) * radius * 0.7, "touch", 1)
    host:pointerMove(x + math.cos(second) * radius * 0.7,
        y + math.sin(second) * radius * 0.7, "touch")
    local session = host:inspectionTree().interaction.session
    assert(session.radialPhase == "preview"
            and session.radialAccumulated > 0.1
            and session.radialAccumulated < 0.3,
        "atan2 branch crossing jumped or reversed the preview")
    host:pointerUp(x + math.cos(second) * radius * 0.7,
        y + math.sin(second) * radius * 0.7, "touch", 1)
    assert(#log == 1, "branch-crossing release duplicated its commit")
    host:unmount()

    log = {}
    host, dial = mounted(log)
    x, y, radius = dialGeometry(dial)
    host:pointerDown(x + radius * 0.7, y, "touch", 1)
    for _, angle in ipairs({ 0.8, 1.6, 2.4, 3.0, -2.5, -1.7 }) do
        host:pointerMove(x + math.cos(angle) * radius * 0.7,
            y + math.sin(angle) * radius * 0.7, "touch")
    end
    session = host:inspectionTree().interaction.session
    assert(session.radialAccumulated > math.pi,
        "successive normalized deltas capped rotation at one half-turn")
    host:pointerUp(x + math.cos(-1.7) * radius * 0.7,
        y + math.sin(-1.7) * radius * 0.7, "touch", 1)
    assert(#log == 1, "multi-turn release did not commit exactly once")
    host:unmount()
end

-- Tap direction is fixed from pointer-down, and a drag that snaps to the
-- already controlled option still reports one completed interaction.
local function terminalPointerSemantics()
    local log = {}
    local host, dial = mounted(log)
    local x, y, radius = dialGeometry(dial)
    host:pointerDown(x, y, "touch", 1)
    host:pointerUp(x, y, "touch", 1)
    assert(#log == 0, "exact-center press invented an arbitrary tap direction")

    host:pointerDown(x, y - radius * 0.5, "touch", 1)
    host:pointerUp(x, y - radius * 0.5, "touch", 1)
    assert(#log == 1 and log[1] == 2,
        "vertical-diameter tap lost the shipped forward half")

    host:pointerDown(x - radius * 0.5, y, "touch", 1)
    host:pointerMove(x + math.cos(math.pi - 0.05) * radius * 0.5,
        y + math.sin(math.pi - 0.05) * radius * 0.5, "touch")
    host:pointerUp(x + radius * 0.5, y, "touch", 1)
    assert(#log == 2 and log[2] == 0.5,
        "tap direction did not retain the pointer-down half")

    host:pointerDown(x + radius * 0.6, y, "touch", 1)
    host:pointerMove(x + math.cos(0.2) * radius * 0.6,
        y + math.sin(0.2) * radius * 0.6, "touch")
    local samePreview = host:inspectionTree().interaction.session
    host:pointerUp(x + math.cos(0.2) * radius * 0.6,
        y + math.sin(0.2) * radius * 0.6, "touch", 1)
    assert(#log == 3 and log[3] == 1,
        "same-value drag did not emit exactly one terminal onChange: "
            .. table.concat(log, ",") .. " preview="
            .. tostring(samePreview.radialPreviewIndex) .. " angle="
            .. tostring(samePreview.radialPreviewAngle))
    host:unmount()

    log = {}
    host, dial = mounted(log, { value = 0.5 })
    x, y, radius = dialGeometry(dial)
    host:pointerDown(x - radius * 0.5, y, "touch", 1)
    host:pointerUp(x - radius * 0.5, y, "touch", 1)
    assert(#log == 1 and log[1] == 2,
        "previous tap did not wrap across the ordered values")

    host:pointerDown(x + radius * 0.6, y, "touch", 1)
    host:pointerMove(x + math.cos(0.3) * radius * 0.6,
        y + math.sin(0.3) * radius * 0.6, "touch")
    host:pointerUp(x + radius * 2, y + radius * 2, "touch", 1)
    assert(#log == 2,
        "claimed radial drag lost its terminal release outside the circle")
    host:unmount()

end

local function startPreview(host, dial)
    local x, y, radius = dialGeometry(dial)
    host:pointerDown(x + radius * 0.6, y, "touch", 1)
    host:pointerMove(x + math.cos(0.3) * radius * 0.6,
        y + math.sin(0.3) * radius * 0.6, "touch")
    assert(host:inspectionTree().interaction.session.radialPhase == "preview",
        "test did not establish radial preview")
end

local function cancellation()
    local operations = {
        { "back", function(host) host:keyDown("escape", "escape", false) end },
        { "F6", function(host) host:keyDown("f6", "f6", false) end },
        { "resize", function(host) host:resize(600, 960) end },
        { "route", function(host) host:render(Frog.Box { width = 20, height = 20 }) end },
    }
    for _, probe in ipairs(operations) do
        local log = {}
        local host, dial = mounted(log)
        startPreview(host, dial)
        probe[2](host)
        assert(#log == 0 and host:inspectionTree().interaction.session == nil,
            probe[1] .. " did not cancel silently")
        host:unmount()
    end

    for _, change in ipairs({
        { label = "value", value = 0.5 },
        { label = "list", values = { 1, 2, 4 }, value = 1 },
        { label = "disabled", disabled = true },
        { label = "bounds", dialWidth = 260 },
        { label = "track geometry", trackRadius = 70 },
        { label = "modal", modal = true },
    }) do
        local log = {}
        local host, dial = mounted(log)
        startPreview(host, dial)
        host:render(surface(log, change))
        assert(#log == 0 and host:inspectionTree().interaction.session == nil,
            change.label .. " drift did not cancel silently")
        host:unmount()
    end

    local log = {}
    local host, dial = mounted(log)
    startPreview(host, dial)
    local before = host:inspectionTree().interaction.session.radialPreviewAngle
    host:render(surface(log))
    local retained = host:inspectionTree().interaction.session
    assert(retained and retained.radialPhase == "preview",
        "stable same-contract rerender cancelled the pointer")
    support.near(retained.radialPreviewAngle, before,
        "stable rerender preview angle")
    host:unmount()

    log = {}
    host, dial = mounted(log)
    startPreview(host, dial)
    host:unmount()
    assert(#log == 0, "unmount emitted a dial value")
end

-- Visible sibling shortcuts win before focused-dial fallback. When none claim
-- a key, every accepted fallback key emits exactly one value.
local function keyboardPriority()
    local log = {}
    local host = mounted(log, {
        shortcuts = {
            { key = "left", result = "seek-first" },
            { key = "left", result = "seek-second" },
            { key = "s", result = "speed-shortcut" },
            { key = "right", result = "seek-right" },
            { key = "space", result = "space-control" },
            { key = "return", result = "return-control" },
        },
    })
    host:keyDown("tab", "tab", false)
    assert(host:inspectionTree().interaction.focused ~= nil,
        "Tab did not focus RadialDial")
    host:keyDown("left", "left", false)
    assert(#log == 1 and log[1] == "seek-first",
        "focused dial stole a source-ordered Button shortcut")
    host:keyDown("s", "s", false)
    assert(log[2] == "speed-shortcut", "S shortcut did not remain Button-owned")
    host:keyDown("right", "right", false)
    host:keyDown("space", "space", false)
    host:keyDown("return", "return", false)
    assert(log[3] == "seek-right" and log[4] == "space-control"
            and log[5] == "return-control",
        "focused dial stole Right/Space/Return Button shortcuts")
    host:render(surface(log))
    host:keyDown("left", "left", false)
    host:keyDown("up", "up", false)
    host:keyDown("home", "home", false)
    host:keyDown("end", "end", false)
    host:keyDown("return", "return", false)
    host:keyDown("space", "space", false)
    local beforeRepeat = #log
    host:keyDown("down", "down", true)
    assert(#log == beforeRepeat and beforeRepeat == 11,
        "dial fallback repeated or skipped a keyboard activation")
    host:unmount()
end

-- The default painter draws the authored focus color as a circular outline.
local function focusedPaint()
    local focusColor = { 0.91, 0.22, 0.17, 1 }
    local log = {}
    local host = mounted(log, { focusedBorder = focusColor })
    host:keyDown("tab", "tab", false)
    local customStyle
    host:draw({ box = function(_, node, style)
        if node.props.testId == "radial-dial" then customStyle = style end
    end })
    assert(customStyle and customStyle.border
            and customStyle.border[1] == focusColor[1]
            and customStyle.borderWidth >= 2,
        "focusedBorder did not reach the Painter")

    local g = love.graphics
    local oldSetColor, oldCircle = g.setColor, g.circle
    local current, drewFocus = nil, false
    g.setColor = function(...)
        current = { ... }
        return oldSetColor(...)
    end
    g.circle = function(mode, ...)
        if mode == "line" and current
                and math.abs(current[1] - focusColor[1]) < 0.001
                and math.abs(current[2] - focusColor[2]) < 0.001 then
            drewFocus = true
        end
        return oldCircle(mode, ...)
    end
    local ok, reason = pcall(host.draw, host)
    g.setColor, g.circle = oldSetColor, oldCircle
    assert(ok, reason)
    assert(drewFocus, "default Painter did not draw the circular focus ring")

    local dial = assert(support.find(host:tree(), "radial-dial"))
    host:setInspectorVisible(true)
    local corner = host:inspect(dial.layout.x + 1, dial.layout.y + 1)
    assert(not corner or corner.testId ~= "radial-dial",
        "F6 selected RadialDial through a square corner outside its hit circle")
    local x, y = support.center(dial)
    local selected = host:inspect(x, y)
    assert(selected and selected.testId == "radial-dial"
            and selected.inspectionShape
            and selected.inspectionShape.type == "circle",
        "F6 omitted the dial's shared circular inspection shape")
    host:unmount()
end

local Changed = Frog.action("RadialDialCheck.Changed", function(action)
    assert(type(action.value) == "number", "Changed needs value")
end)

local ControlledDial = Frog.actor("RadialDialCheckControlled", {
    initial = 1,
    actions = {
        [Changed] = function(_, action) return action.value end,
    },
    render = function(props, value, send)
        if props.failAt == value then error("radial actor render sentinel") end
        local dial = Frog.RadialDial {
            testId = "radial-dial", width = 240, height = 240,
            trackRadius = 72, value = value, values = VALUES,
            onChange = function(nextValue)
                props.log[#props.log + 1] = nextValue
                send(Changed { value = nextValue })
            end,
            option(1, 0.5), option(2, 1), option(3, 2),
        }
        if not props.shortcut then return dial end
        return Frog.Overlay {
            width = 540, height = 960, align = "center", justify = "center",
            dial,
            Frog.Button {
                width = 40, height = 40, shortcut = "s",
                onPress = function() send(Changed { value = 2 }) end,
                Frog.Text "S",
            },
        }
    end,
})

local function actorState(host)
    for _, actor in ipairs(host:inspectionTree().actors) do
        if actor.name == "RadialDialCheckControlled" then return actor.state end
    end
end

-- Controlled rerender selects a shortest-path raw-clock settle; reduced motion
-- lands immediately. A failed actor rerender faults its Host terminally.
local function settleAndFault()
    local log = {}
    local host = support.host { width = 540, height = 960 }
    host:mount(ControlledDial { log = log })
    host:keyDown("tab", "tab", false)
    host:keyDown("down", "down", false)
    local entry = assert(inspectionEntry(host)).radialDial
    assert(actorState(host) == 0.5 and entry.targetAngle > entry.angle,
        "controlled previous step did not choose the shortest settle path")
    local before = entry.angle
    host:update(0.05)
    local after = assert(inspectionEntry(host)).radialDial.angle
    assert(after > before and after < entry.targetAngle,
        "raw-clock settle did not advance toward its target")
    host:unmount()

    -- Samples the same raw settle under one requested dt partition.
    local function settledPresentation(parts)
        local values = {}
        local sampleHost = support.host { width = 540, height = 960 }
        sampleHost:mount(ControlledDial { log = values, shortcut = true })
        sampleHost:keyDown("s", "s", false)
        for _, dt in ipairs(parts) do sampleHost:update(dt) end
        local presentation = assert(inspectionEntry(sampleHost)).radialDial
        local sample = {
            angle = presentation.angle,
            bounce = presentation.bounce,
            paintScale = presentation.paintScale,
        }
        sampleHost:unmount()
        return sample
    end
    local whole = settledPresentation({ 0.1 })
    local split = settledPresentation({ 0.04, 0.06 })
    support.near(whole.angle, split.angle,
        "dt-partitioned radial settle angle")
    support.near(whole.bounce, split.bounce,
        "dt-partitioned radial settle bounce")
    support.near(whole.paintScale, split.paintScale,
        "dt-partitioned radial settle paint")

    log = {}
    host = support.host { width = 540, height = 960 }
    host:mount(ControlledDial { log = log, shortcut = true })
    host:keyDown("s", "s", false)
    entry = assert(inspectionEntry(host)).radialDial
    assert(actorState(host) == 2 and entry.bounce == 1,
        "external controlled shortcut change did not arm dial bounce")
    host:update(0.05)
    entry = assert(inspectionEntry(host)).radialDial
    assert(entry.paintScale > 1,
        "external controlled shortcut bounce was not visibly sampled")
    host:unmount()

    log = {}
    host = support.host { width = 540, height = 960 }
    host:mount(ControlledDial { log = log })
    local dial = assert(support.find(host:tree(), "radial-dial"))
    local x, y, radius = dialGeometry(dial)
    host:pointerDown(x + radius * 0.7, y, "touch", 1)
    host:update(0.4)
    for _, angle in ipairs({ 0.8, 1.6, 2.2 }) do
        host:pointerMove(x + math.cos(angle) * radius * 0.7,
            y + math.sin(angle) * radius * 0.7, "touch")
    end
    host:pointerUp(x + math.cos(2.2) * radius * 0.7,
        y + math.sin(2.2) * radius * 0.7, "touch", 1)
    entry = assert(inspectionEntry(host)).radialDial
    assert(actorState(host) == 0.5 and entry.bounce == 0,
        "changed drag incorrectly restarted its completed press bounce")
    host:unmount()

    log = {}
    host = support.host { width = 540, height = 960, reducedMotion = true }
    host:mount(ControlledDial { log = log })
    host:keyDown("tab", "tab", false)
    host:keyDown("down", "down", false)
    entry = assert(inspectionEntry(host)).radialDial
    support.near(entry.angle, entry.targetAngle, "reduced-motion settle")
    assert(entry.bounce == 0 and entry.reducedMotion,
        "reduced motion retained decorative bounce")
    host:unmount()

    log = {}
    host = support.host { width = 540, height = 960 }
    host:mount(ControlledDial { log = log, failAt = 0.5 })
    host:keyDown("tab", "tab", false)
    local ok, reason = pcall(host.keyDown, host, "down", "down", false)
    assert(not ok and tostring(reason):find("radial actor render sentinel", 1, true)
            and #log == 1
            and host:inspectionTree().interaction.session == nil
            and host:inspectionTree().fault,
        "actor failure did not fault its Host terminally")
    local retryOk, retryReason = pcall(host.update, host, 0.01)
    assert(not retryOk and tostring(retryReason):find(
            "FrogUI Host faulted", 1, true),
        "faulted radial actor Host accepted a later update")
    host:unmount()
end

local function soundAndCallbackFailure()
    local sounds, log = {}, {}
    local host, dial = mounted(log, nil, {
        width = 540,
        height = 960,
        theme = { sounds = {
            dialSpin = "dial.swoosh",
            dialCommit = "dial.click",
        } },
        feedback = { sound = function(cue) sounds[#sounds + 1] = cue end },
    })
    local x, y, radius = dialGeometry(dial)
    host:pointerDown(x + radius * 0.6, y, "touch", 1)
    host:update(0.05)
    assert(assert(inspectionEntry(host)).radialDial.paintScale > 1
            and host:inspectionTree().interaction.session ~= nil,
        "raw touch bounce did not advance while the dial was held")
    host:draw()
    local firstPaintScale = dial._paintScratch.style.transform.scale
    host:draw()
    support.near(dial._paintScratch.style.transform.scale, firstPaintScale,
        "reused RadialDial style compounded its transient paint scale")
    host:pointerMove(x + math.cos(0.2) * radius * 0.6,
        y + math.sin(0.2) * radius * 0.6, "touch")
    host:pointerMove(x + math.cos(0.4) * radius * 0.6,
        y + math.sin(0.4) * radius * 0.6, "touch")
    host:pointerUp(x + math.cos(0.4) * radius * 0.6,
        y + math.sin(0.4) * radius * 0.6, "touch", 1)
    assert(table.concat(sounds, ",") == "dial.swoosh,dial.click",
        "dial cues were missing, duplicated, or out of order")
    host:unmount()

    sounds, log = {}, {}
    host, dial = mounted(log, { sound = false, spinSound = false }, {
        width = 540,
        height = 960,
        theme = { sounds = {
            dialSpin = "dial.swoosh", dialCommit = "dial.click",
        } },
        feedback = { sound = function(cue) sounds[#sounds + 1] = cue end },
    })
    x, y, radius = dialGeometry(dial)
    host:pointerDown(x + radius * 0.6, y, "touch", 1)
    host:pointerMove(x + math.cos(0.2) * radius * 0.6,
        y + math.sin(0.2) * radius * 0.6, "touch")
    host:pointerUp(x + math.cos(0.2) * radius * 0.6,
        y + math.sin(0.2) * radius * 0.6, "touch", 1)
    assert(#sounds == 0, "false dial cue overrides did not suppress defaults")
    host:unmount()

    log = {}
    host, dial = mounted(log, nil, {
        width = 540,
        height = 960,
        theme = { sounds = { dialCommit = "dial.click" } },
        feedback = { sound = function() error("dial sound sentinel") end },
    })
    x, y = support.center(dial)
    host:pointerDown(x + 20, y, "touch", 1)
    local soundOk, soundReason = pcall(
        host.pointerUp, host, x + 20, y, "touch", 1)
    assert(not soundOk and tostring(soundReason):find(
            "dial sound sentinel", 1, true)
            and #log == 1
            and host:inspectionTree().interaction.session == nil
            and host:inspectionTree().fault,
        "sound-provider failure did not fault its Host terminally")
    local retryOk, retryReason = pcall(host.update, host, 0.01)
    assert(not retryOk and tostring(retryReason):find(
            "FrogUI Host faulted", 1, true),
        "faulted radial sound Host accepted a later update")
    host:unmount()

    log = {}
    host, dial = mounted(log, { fail = true })
    x, y = support.center(dial)
    host:pointerDown(x + 20, y, "touch", 1)
    local ok, reason = pcall(host.pointerUp, host, x + 20, y, "touch", 1)
    assert(not ok and tostring(reason):find("radial callback sentinel", 1, true)
            and #log == 1
            and host:inspectionTree().interaction.session == nil
            and host:inspectionTree().fault,
        "throwing onChange did not fault its Host terminally")
    retryOk, retryReason = pcall(host.pointerDown, host, x, y, "touch", 2)
    assert(not retryOk and tostring(retryReason):find(
            "FrogUI Host faulted", 1, true),
        "faulted radial callback Host accepted later input")
    host:unmount()
end

function check.run()
    validation()
    stableRootRef()
    previewAndDeadZone()
    branchCrossing()
    terminalPointerSemantics()
    cancellation()
    keyboardPriority()
    focusedPaint()
    settleAndFault()
    soundAndCallbackFailure()
end

return check
