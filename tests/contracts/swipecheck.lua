-- Adversarial checks for HorizontalSwipe's pre-claim ownership arbitration.

local Frog = require("frogui")
local Interaction = require("frogui.interaction")
local support = require("tests.support")

local check = {}
local POLICY = Interaction.horizontalSwipePolicy()

-- This single assertion locks the shipped feel oracle; every path probe below
-- derives its boundaries from FrogUI's code-owned policy.
assert(POLICY.claimDistance == 12
        and POLICY.commitDistance == 60
        and POLICY.axisBias == 1.5,
    "HorizontalSwipe drifted from the shipped interaction threshold oracle")

local function rejects(label, description, fragment)
    local host = support.host { width = 540, height = 960 }
    local ok, reason = pcall(host.mount, host, description)
    if ok then host:unmount() end
    assert(not ok and tostring(reason):find(fragment, 1, true),
        label .. " rejected for the wrong reason: " .. tostring(reason))
end

local function validation()
    rejects("missing child", Frog.HorizontalSwipe {
        onSwipe = function() end,
    }, "accepts exactly one child")
    rejects("extra child", Frog.HorizontalSwipe {
        onSwipe = function() end,
        Frog.Box {}, Frog.Box {},
    }, "accepts exactly one child")
    rejects("missing callback", Frog.HorizontalSwipe {
        Frog.Box {},
    }, "onSwipe must be a function")
    rejects("threshold escape hatch", Frog.HorizontalSwipe {
        onSwipe = function() end,
        claimDistance = 1,
        Frog.Box {},
    }, "unknown prop claimDistance")
    rejects("invalid optional callback", Frog.HorizontalSwipe {
        onSwipe = function() end,
        onPress = true,
        Frog.Box {},
    }, "onPress must be a function")
end

local function append(log, value)
    log[#log + 1] = value
end

-- Builds one readable broad surface with a descendant inspection stand-in.
local function arena(log, options)
    options = options or {}
    return Frog.HorizontalSwipe {
        key = options.key or "arena",
        testId = "swipe-arena",
        width = 300,
        height = 160,
        onPress = function() append(log, "background") end,
        onSwipe = function(direction)
            if options.fail then error("swipe callback sentinel") end
            append(log, "swipe-" .. direction)
        end,
        Frog.Row {
            width = "100%",
            height = "100%",
            align = "center",
            gap = 20,
            Frog.Pressable {
                testId = "swipe-card",
                onPress = function() append(log, "card-tap") end,
                onLongPress = function() append(log, "card-hold") end,
                Frog.Box { width = 80, height = 80, background = { 1, 1, 1 } },
            },
            Frog.Box { grow = 1, height = "100%" },
        },
    }
end

local function mounted(log, options)
    local host = support.host { width = 540, height = 960 }
    host:mount(arena(log, options))
    local surface = assert(support.find(host:tree(), "swipe-arena"))
    local card = assert(support.find(host:tree(), "swipe-card"))
    local cardX, cardY = support.center(card)
    local blankX = surface.layout.x + surface.layout.width - 20
    local blankY = surface.layout.y + surface.layout.height / 2
    return host, cardX, cardY, blankX, blankY
end

-- Confirms a runtime swipe failure faults the Host and blocks any retry.
local function expectFault(host, retry, label)
    local fault = host:inspectionTree().fault
    assert(fault and fault.origin:find("HorizontalSwipe:", 1, true),
        label .. " did not record its terminal Host fault")
    local ok, reason = pcall(retry)
    assert(not ok and tostring(reason):find("FrogUI Host faulted", 1, true),
        label .. " allowed input after its terminal Host fault")
end

local function tapAndHoldOwnership()
    local log = {}
    local host, cardX, cardY, blankX, blankY = mounted(log)

    host:pointerDown(cardX, cardY, "touch", 1)
    local pressed = host:inspectionTree().interaction.session
    assert(pressed and pressed.press,
        "card pointer-down did not retain Pressable candidate at "
            .. tostring(cardX) .. "," .. tostring(cardY))
    host:pointerUp(cardX, cardY, "touch", 1)
    assert(table.concat(log, ",") == "card-tap",
        "descendant Pressable tap did not own the short gesture: "
            .. table.concat(log, ","))

    host:pointerDown(cardX, cardY, "touch", 1)
    host:update(Interaction.HOLD_SECONDS)
    host:pointerUp(cardX, cardY, "touch", 1)
    assert(table.concat(log, ",") == "card-tap,card-hold",
        "terminal hold leaked a tap or ancestor action")

    host:pointerDown(cardX, cardY, "touch", 1)
    host:pointerMove(cardX + POLICY.claimDistance, cardY, "touch")
    host:pointerUp(cardX + POLICY.claimDistance, cardY, "touch", 1)
    assert(log[#log] == "card-tap" and #log == 3,
        "descendant tap lost the shipped claim-boundary tolerance")

    host:pointerDown(cardX, cardY, "touch", 1)
    host:pointerMove(cardX, cardY + POLICY.claimDistance, "touch")
    host:update(Interaction.HOLD_SECONDS)
    host:pointerUp(cardX, cardY + POLICY.claimDistance, "touch", 1)
    assert(log[#log] == "card-hold" and #log == 4,
        "descendant hold lost the shipped claim-boundary tolerance")

    host:pointerDown(cardX, cardY, "touch", 1)
    host:pointerMove(cardX, cardY + POLICY.commitDistance - 1, "touch")
    host:update(Interaction.HOLD_SECONDS)
    host:pointerUp(cardX, cardY + POLICY.commitDistance - 1, "touch", 1)
    assert(log[#log] == "card-hold" and #log == 5,
        "moderate off-axis jitter no longer permits the shipped hold")

    host:pointerDown(cardX, cardY, "touch", 1)
    host:pointerMove(cardX, cardY + POLICY.claimDistance + 1, "touch")
    host:pointerMove(cardX, cardY, "touch")
    host:pointerUp(cardX, cardY, "touch", 1)
    assert(#log == 5,
        "off-axis excursion resurrected a descendant tap after returning")

    host:pointerDown(blankX, blankY, "mouse", 1)
    host:pointerUp(blankX, blankY, "mouse", 1)
    assert(log[#log] == "background",
        "blank short tap did not reach HorizontalSwipe onPress")

    host:pointerDown(blankX, blankY, "touch", 1)
    host:pointerMove(blankX - POLICY.claimDistance, blankY, "touch")
    host:pointerUp(blankX - POLICY.claimDistance, blankY, "touch", 1)
    assert(log[#log] == "background" and #log == 7,
        "blank press lost the shipped claim-boundary tolerance")

    host:pointerDown(blankX, blankY, "touch", 1)
    host:pointerMove(blankX, blankY + POLICY.claimDistance + 1, "touch")
    host:pointerMove(blankX, blankY, "touch")
    host:pointerUp(blankX, blankY, "touch", 1)
    assert(#log == 7,
        "off-axis excursion resurrected a blank tap after returning")

    local surface = assert(support.find(host:tree(), "swipe-arena"))
    local edgeX = surface.layout.x + surface.layout.width - 1
    host:pointerDown(edgeX, blankY, "touch", 1)
    host:pointerMove(edgeX + 2, blankY, "touch")
    host:pointerUp(edgeX + 2, blankY, "touch", 1)
    assert(log[#log] == "background" and #log == 7,
        "blank tap completed after its release left the surface")

    host:pointerDown(blankX, blankY, "touch", 1)
    host:pointerUp(blankX - POLICY.commitDistance - 1, blankY, "touch", 1)
    assert(log[#log] == "swipe-left" and #log == 8,
        "release-only horizontal swipe was lost or became a blank tap")
    host:unmount()
end

local function swipeBandsAndDirections()
    local log = {}
    local host, x, y, blankX, blankY = mounted(log)

    host:pointerDown(x, y, "touch", 1)
    host:pointerMove(x + POLICY.claimDistance, y, "touch")
    local boundary = host:inspectionTree().interaction.session
    assert(boundary and boundary.claimed == nil,
        "HorizontalSwipe claimed at its strict claim boundary")
    host:pointerMove(x + POLICY.claimDistance + 1, y, "touch")
    local session = host:inspectionTree().interaction.session
    assert(session and session.claimed == "horizontal-swipe"
            and session.swipePhase == "claimed",
        "qualifying card motion did not claim its ancestor swipe candidate")
    host:pointerUp(x + POLICY.commitDistance, y, "touch", 1)
    assert(#log == 0,
        "claim-only movement fired a tap, hold, or semantic swipe")

    host:pointerDown(x, y, "touch", 1)
    host:pointerMove(x + POLICY.commitDistance + 1, y, "touch")
    host:pointerUp(x + POLICY.commitDistance + 1, y, "touch", 1)
    assert(log[1] == "swipe-right",
        "qualifying right release did not emit exactly one direction")

    host:pointerDown(x, y, "touch", 1)
    host:pointerMove(x - POLICY.commitDistance - 1, y, "touch")
    host:pointerUp(x - POLICY.commitDistance - 1, y, "touch", 1)
    assert(log[2] == "swipe-left" and #log == 2,
        "qualifying left release duplicated or lost its direction")

    host:pointerDown(x, y, "touch", 1)
    host:pointerMove(x + POLICY.commitDistance + 1, y, "touch")
    host:pointerMove(x, y, "touch")
    host:pointerUp(x, y, "touch", 1)
    assert(#log == 2, "drag-return became a tap or swipe")

    local dx = POLICY.claimDistance * 2.5
    local dy = dx / POLICY.axisBias
    host:pointerDown(x, y, "touch", 1)
    host:pointerMove(x + dx, y + dy, "touch")
    assert(host:inspectionTree().interaction.session.swipePhase == "pending",
        "exact axis bias was claimed instead of remaining pending")
    host:pointerMove(x + POLICY.commitDistance + 1, y, "touch")
    assert(host:inspectionTree().interaction.session.swipePhase == "claimed",
        "diagonal-first path could not recover into a horizontal swipe")
    host:pointerUp(x + POLICY.commitDistance + 1, y, "touch", 1)
    assert(log[3] == "swipe-right" and #log == 3,
        "recovered diagonal-first path did not emit one semantic swipe")

    host:pointerDown(x, y, "touch", 1)
    host:pointerMove(x, y + POLICY.commitDistance - 1, "touch")
    host:pointerMove(x + POLICY.commitDistance + 1, y, "touch")
    host:pointerUp(x + POLICY.commitDistance + 1, y, "touch", 1)
    assert(log[4] == "swipe-right" and #log == 4,
        "sub-terminal off-axis path could not recover into a swipe")

    host:pointerDown(x, y, "touch", 1)
    host:pointerMove(x, y + POLICY.commitDistance, "touch")
    assert(host:inspectionTree().interaction.session.swipePhase == "blocked",
        "terminal off-axis movement did not block swipe ownership")
    host:pointerMove(x + POLICY.commitDistance + 1, y, "touch")
    host:pointerUp(x + POLICY.commitDistance + 1, y, "touch", 1)
    assert(#log == 4,
        "terminal off-axis movement later recovered into a swipe")

    host:pointerDown(blankX, blankY, "touch", 1)
    host:pointerMove(blankX, blankY + POLICY.commitDistance, "touch")
    host:pointerMove(blankX + POLICY.commitDistance + 1, blankY, "touch")
    host:pointerUp(blankX + POLICY.commitDistance + 1, blankY, "touch", 1)
    assert(log[5] == "swipe-right" and #log == 5,
        "blank arena path inherited descendant inspection's terminal block")
    host:unmount()
end

local function buttonOwnership()
    local log = {}
    local host = support.host { width = 540, height = 960 }
    host:mount(Frog.HorizontalSwipe {
        width = 300,
        height = 160,
        onSwipe = function(direction) append(log, "swipe-" .. direction) end,
        Frog.Button {
            testId = "swipe-button",
            width = 100,
            height = 80,
            onPress = function() append(log, "button") end,
            Frog.Text "Inspect",
        },
    })
    local button = assert(support.find(host:tree(), "swipe-button"))
    local x, y = support.center(button)
    host:pointerDown(x, y, "touch", 1)
    host:pointerMove(x + POLICY.claimDistance, y, "touch")
    host:pointerUp(x + POLICY.claimDistance, y, "touch", 1)
    host:pointerDown(x, y, "touch", 1)
    host:pointerMove(x + POLICY.commitDistance + 1, y, "touch")
    host:pointerUp(x + POLICY.commitDistance + 1, y, "touch", 1)
    assert(table.concat(log, ",") == "button,swipe-right",
        "Button child did not arbitrate tap versus ancestor swipe exactly once")
    host:unmount()
end

-- A later control plane is a sibling, not a descendant candidate. Starting
-- on it can never arm or steal the arena swipe underneath.
local function overlappingControlWins()
    local log = {}
    local host = support.host { width = 540, height = 960 }
    host:mount(Frog.Overlay {
        width = 300,
        height = 160,
        Frog.HorizontalSwipe {
            testId = "covered-swipe",
            width = "100%",
            height = "100%",
            onSwipe = function(direction)
                append(log, "swipe-" .. direction)
            end,
            Frog.Box { width = "100%", height = "100%" },
        },
        Frog.Button {
            testId = "overlapping-control",
            width = 100,
            height = 80,
            onPress = function() append(log, "control") end,
            Frog.Text "Play",
        },
    })
    local control = assert(support.find(host:tree(), "overlapping-control"))
    local x, y = support.center(control)
    host:pointerDown(x, y, "touch", 1)
    local session = host:inspectionTree().interaction.session
    assert(session and session.press and not session.swipe,
        "overlapping sibling control armed the covered swipe surface")
    host:pointerUp(x, y, "touch", 1)
    host:pointerDown(x, y, "touch", 1)
    host:pointerMove(x + POLICY.commitDistance + 1, y, "touch")
    host:pointerUp(x + POLICY.commitDistance + 1, y, "touch", 1)
    assert(table.concat(log, ",") == "control",
        "covered arena stole a gesture that began on its control sibling")
    host:unmount()
end

local function deepestSurfaceWins()
    local log = {}
    local host = support.host { width = 540, height = 960 }
    host:mount(Frog.HorizontalSwipe {
        testId = "outer-swipe",
        width = 300,
        height = 160,
        onSwipe = function(direction) append(log, "outer-" .. direction) end,
        Frog.HorizontalSwipe {
            testId = "inner-swipe",
            width = 200,
            height = 120,
            onSwipe = function(direction) append(log, "inner-" .. direction) end,
            Frog.Box { width = "100%", height = "100%" },
        },
    })
    local inner = assert(support.find(host:tree(), "inner-swipe"))
    local x, y = support.center(inner)
    host:pointerDown(x, y, "touch", 1)
    host:pointerMove(x + POLICY.commitDistance + 1, y, "touch")
    host:pointerUp(x + POLICY.commitDistance + 1, y, "touch", 1)
    assert(table.concat(log, ",") == "inner-right",
        "nested swipe ownership was not deepest and deterministic")
    host:unmount()
end

local function dragAndScrollPrecedence()
    local swipes, drags = {}, 0
    local host = support.host { width = 540, height = 960 }
    host:mount(Frog.HorizontalSwipe {
        width = 300,
        height = 160,
        onSwipe = function(direction) append(swipes, direction) end,
        Frog.DragSource {
            testId = "swipe-drag",
            payload = { kind = "probe" },
            preview = Frog.Box { width = 20, height = 20 },
            onDrop = function() return false end,
            onDragStart = function() drags = drags + 1 end,
            Frog.Box { width = 100, height = 80 },
        },
    })
    local source = assert(support.find(host:tree(), "swipe-drag"))
    local x, y = support.center(source)
    host:pointerDown(x, y, "touch", 1)
    host:pointerUp(x + POLICY.commitDistance + 1, y, "touch", 1)
    assert(drags == 0 and #swipes == 0,
        "release-only arbitration broadened DragSource ownership")
    host:pointerDown(x, y, "touch", 1)
    host:pointerMove(x + POLICY.commitDistance + 1, y, "touch")
    assert(host:inspectionTree().interaction.session.claimed == "drag",
        "DragSource did not retain its earlier framework claim")
    host:pointerUp(x + POLICY.commitDistance + 1, y, "touch", 1)
    assert(drags == 1 and #swipes == 0,
        "DragSource handed a claimed gesture to HorizontalSwipe")
    host:unmount()

    local scrollEnds = 0
    host = support.host { width = 540, height = 960 }
    host:mount(Frog.HorizontalSwipe {
        width = 300,
        height = 100,
        onSwipe = function(direction) append(swipes, direction) end,
        Frog.Scroll {
            testId = "swipe-scroll",
            axis = "vertical",
            onScrollEnd = function() scrollEnds = scrollEnds + 1 end,
            Frog.Box { width = 300, height = 300 },
        },
    })
    local scroll = assert(support.find(host:tree(), "swipe-scroll"))
    x, y = support.center(scroll)
    host:pointerDown(x, y, "touch", 1)
    host:pointerUp(x + POLICY.commitDistance + 1, y, "touch", 1)
    assert(scrollEnds == 0 and #swipes == 0,
        "release-only arbitration broadened Scroll ownership")
    host:pointerDown(x, y, "touch", 1)
    host:pointerMove(x + POLICY.commitDistance + 1, y, "touch")
    assert(host:inspectionTree().interaction.session.claimed == "scroll",
        "active Scroll did not retain its earlier framework claim")
    host:pointerUp(x, y - POLICY.claimDistance, "touch", 1)
    assert(scrollEnds == 1 and #swipes == 0,
        "Scroll handed a claimed gesture to HorizontalSwipe")
    host:unmount()
end

local function captureAndCancellation()
    local log = {}
    local host, x, y = mounted(log)
    local surface = assert(support.find(host:tree(), "swipe-arena"))
    local outsideX = surface.layout.x + surface.layout.width + POLICY.commitDistance + 1
    host:pointerDown(x, y, "touch", 1)
    host:pointerDown(x, y, "other-touch", 1)
    host:pointerMove(outsideX, y, "other-touch")
    assert(host:inspectionTree().interaction.session.claimed == nil,
        "second pointer changed the active swipe session")
    host:pointerMove(outsideX, y, "touch")
    host:pointerUp(outsideX, y, "touch", 1)
    assert(log[1] == "swipe-right",
        "captured swipe did not survive leaving its original bounds")

    host:pointerDown(x, y, "touch", 1)
    host:pointerMove(x + POLICY.claimDistance + 1, y, "touch")
    host:resize(360, 200)
    host:pointerUp(x + POLICY.commitDistance + 1, y, "touch", 1)
    assert(#log == 1, "resize cancellation emitted a semantic swipe")

    host:pointerDown(x, y, "touch", 1)
    host:pointerMove(x + POLICY.claimDistance + 1, y, "touch")
    host:keyDown("f6")
    host:keyUp("f6")
    host:pointerUp(x + POLICY.commitDistance + 1, y, "touch", 1)
    assert(#log == 1, "F6 cancellation emitted a semantic swipe")

    host:pointerDown(x, y, "touch", 1)
    host:pointerMove(x + POLICY.claimDistance + 1, y, "touch")
    host:unmount()
    assert(#log == 1, "unmount cancellation emitted a semantic swipe")
end

local function rerenderAndModalOwnership()
    local log = {}
    local host, x, y = mounted(log)
    host:pointerDown(x, y, "touch", 1)
    host:render(arena(log))
    host:pointerMove(x + POLICY.commitDistance + 1, y, "touch")
    host:pointerUp(x + POLICY.commitDistance + 1, y, "touch", 1)
    assert(log[1] == "swipe-right",
        "stable rerender did not preserve the unresolved swipe candidate")

    host:pointerDown(x, y, "touch", 1)
    local failed, reason = pcall(host.render, host, Frog.HorizontalSwipe {
        key = "arena",
        Frog.Box { width = 300, height = 160 },
    })
    assert(not failed and tostring(reason):find("onSwipe", 1, true),
        "failed rerender probe did not fail at the authored contract")
    host:pointerMove(x + POLICY.commitDistance + 1, y, "touch")
    host:pointerUp(x + POLICY.commitDistance + 1, y, "touch", 1)
    assert(log[2] == "swipe-right",
        "failed rerender did not restore the unresolved swipe candidate")

    host:pointerDown(x, y, "touch", 1)
    host:pointerMove(x + POLICY.claimDistance + 1, y, "touch")
    host:render(arena(log, { key = "replacement" }))
    host:pointerUp(x + POLICY.commitDistance + 1, y, "touch", 1)
    assert(#log == 2, "keyed route replacement emitted a stale swipe")

    host:pointerDown(x, y, "touch", 1)
    host:pointerMove(x + POLICY.claimDistance + 1, y, "touch")
    host:render(Frog.Overlay {
        arena(log),
        Frog.Modal {
            dismiss = "none",
            Frog.Box { width = 100, height = 100 },
        },
    })
    host:pointerUp(x + POLICY.commitDistance + 1, y, "touch", 1)
    assert(#log == 2, "modal takeover emitted a base-tree swipe")
    host:unmount()
end

local function inspectionAndCallbackFailure()
    local log = {}
    local host, x, y = mounted(log)
    local entry
    for _, node in ipairs(host:inspectionTree().nodes) do
        if node.testId == "swipe-arena" then entry = node break end
    end
    assert(entry and entry.gesture
            and entry.gesture.kind == "horizontal-swipe",
        "F6 tree omitted HorizontalSwipe ownership metadata")
    host:pointerDown(x, y, "touch", 1)
    assert(host:inspectionTree().interaction.session.swipePhase == "candidate",
        "F6 session omitted the unresolved swipe candidate")
    host:pointerMove(x + POLICY.claimDistance + 1, y, "touch")
    assert(host:inspectionTree().interaction.session.swipePhase == "claimed",
        "F6 session omitted claimed swipe ownership")
    host:unmount()

    local failureCalls = 0
    host, x, y = mounted(log, { fail = true })
    local surface = assert(support.find(host:tree(), "swipe-arena"))
    surface.props.onSwipe = function()
        failureCalls = failureCalls + 1
        error("swipe callback sentinel")
    end
    host:pointerDown(x, y, "touch", 1)
    host:pointerMove(x + POLICY.commitDistance + 1, y, "touch")
    local ok, reason = pcall(host.pointerUp, host,
        x + POLICY.commitDistance + 1, y, "touch", 1)
    assert(not ok and tostring(reason):find("swipe callback sentinel", 1, true)
            and host:inspectionTree().interaction.session == nil,
        "throwing swipe completion retained authority or hid its failure")
    expectFault(host, function()
        host:pointerUp(x + POLICY.commitDistance + 1, y, "touch", 1)
    end, "throwing swipe completion")
    assert(failureCalls == 1,
        "throwing swipe completion retried its semantic callback")
    host:unmount()
end

local FaultSwipe = Frog.action("SwipeCheck.FaultSwipe")
local faultUnmounts = 0
local FaultOwner = Frog.actor("SwipeCheckFaultOwner", {
    initial = 0,
    actions = {
        [FaultSwipe] = function(state) return state + 1 end,
    },
    unmount = function() faultUnmounts = faultUnmounts + 1 end,
    render = function(_, state, send)
        if state > 0 then error("swipe actor render sentinel") end
        return Frog.HorizontalSwipe {
            testId = "fault-swipe",
            width = 300,
            height = 160,
            onSwipe = function() send(FaultSwipe {}) end,
            Frog.Box { width = "100%", height = "100%" },
        }
    end,
})

local function actorState(host, name)
    for _, actor in ipairs(host:inspectionTree().actors or {}) do
        if actor.name == name then return actor.state end
    end
end

-- A typed state change whose rerender fails faults the Host without pretending
-- to rewind actor state; the released pointer cannot retry the action.
local function actorCallbackFault()
    faultUnmounts = 0
    local host = support.host { width = 540, height = 960 }
    host:mount(FaultOwner {})
    local surface = assert(support.find(host:tree(), "fault-swipe"))
    local x, y = support.center(surface)
    host:pointerDown(x, y, "touch", 1)
    host:pointerMove(x + POLICY.commitDistance + 1, y, "touch")
    local ok, reason = pcall(host.pointerUp, host,
        x + POLICY.commitDistance + 1, y, "touch", 1)
    assert(not ok and tostring(reason):find("swipe actor render sentinel", 1, true)
            and actorState(host, "SwipeCheckFaultOwner") == 1
            and host:inspectionTree().interaction.session == nil,
        "swipe callback fault rewound state or retained its pointer")
    expectFault(host, function()
        host:pointerUp(x + POLICY.commitDistance + 1, y, "touch", 1)
    end, "swipe actor render failure")
    assert(actorState(host, "SwipeCheckFaultOwner") == 1,
        "faulted swipe actor retried its semantic transition")
    host:unmount()
    assert(faultUnmounts == 1,
        "faulted swipe Host did not clean its actor exactly once")
end

function check.run()
    validation()
    tapAndHoldOwnership()
    swipeBandsAndDirections()
    buttonOwnership()
    overlappingControlWins()
    deepestSurfaceWins()
    dragAndScrollPrecedence()
    captureAndCancellation()
    rerenderAndModalOwnership()
    inspectionAndCallbackFailure()
    actorCallbackFault()
end

return check
