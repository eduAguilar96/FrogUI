-- Focused M4A checks for Pressable, retained Scroll, Modal isolation, and the
-- source-owned drag/drop lifecycle. These use only public Host input methods.

local Frog = require("frogui")
local support = require("tests.support")

local check = {}

local function rejects(label, description, fragment)
    local host = support.host { width = 540, height = 960 }
    local ok, err = pcall(function() host:mount(description) end)
    if ok then host:unmount() end
    assert(not ok, label .. " unexpectedly succeeded")
    assert(tostring(err):find(fragment, 1, true),
        label .. " failed unclearly: " .. tostring(err))
end

local function node(host, testId)
    return assert(support.find(host:tree(), testId), testId)
end

local function center(host, testId)
    return support.center(node(host, testId))
end

-- Confirms one runtime failure is terminal for its Host and cannot re-enter
-- authored interaction code before the caller unmounts it.
local function expectFault(host, origin, retry, label)
    local fault = host:inspectionTree().fault
    assert(fault and fault.origin:find(origin, 1, true),
        label .. " did not record its terminal Host fault")
    local ok, reason = pcall(retry)
    assert(not ok and tostring(reason):find("FrogUI Host faulted", 1, true),
        label .. " allowed input after its terminal Host fault")
end

local function definitionContracts()
    rejects("Pressable children", Frog.Pressable { onPress = function() end },
        "exactly one child")
    rejects("Scroll axis", Frog.Scroll {
        axis = "diagonal", Frog.Box { height = 20 },
    }, "unsupported")
    rejects("Scroll position", Frog.Scroll {
        axis = "horizontal", scrollPosition = -1,
        Frog.Box { width = 200, height = 20 },
    }, "non-negative")
    rejects("Scroll snap interval", Frog.Scroll {
        axis = "horizontal", snapInterval = 0,
        Frog.Box { width = 200, height = 20 },
    }, "positive")
    rejects("Scroll end callback", Frog.Scroll {
        axis = "horizontal", onScrollEnd = true,
        Frog.Box { width = 200, height = 20 },
    }, "must be a function")
    rejects("Modal dismissal", Frog.Modal {
        dismiss = "both", Frog.Box { width = 20, height = 20 },
    }, "requires onDismiss")
    rejects("Modal offset", Frog.Modal {
        dismiss = "none", offset = { x = 10 },
        Frog.Box { width = 20, height = 20 },
    }, "does not accept offset")
    rejects("Chrome children", Frog.Chrome {}, "exactly one child")
    rejects("Modal allowChrome", Frog.Modal {
        dismiss = "none", allowChrome = "yes",
        Frog.Box { width = 20, height = 20 },
    }, "must be a boolean")
    rejects("duplicate Chrome", Frog.Overlay {
        Frog.Chrome { Frog.Box { width = 20, height = 20 } },
        Frog.Chrome { Frog.Box { width = 20, height = 20 } },
    }, "only one Frog.Chrome")
    rejects("Chrome inside Modal", Frog.Modal {
        dismiss = "none",
        Frog.Chrome { Frog.Box { width = 20, height = 20 } },
    }, "root portals cannot be nested")
    rejects("Modal inside Chrome", Frog.Chrome {
        Frog.Modal {
            dismiss = "none",
            Frog.Box { width = 20, height = 20 },
        },
    }, "root portals cannot be nested")
    local cycle = { kind = "cycle" }
    cycle.self = cycle
    rejects("drag payload cycle", Frog.DragSource {
        payload = cycle, preview = Frog.Box { width = 20, height = 20 },
        onDrop = function() return true end,
        Frog.Box { width = 20, height = 20 },
    }, "acyclic")
    rejects("target key", Frog.DropTarget {
        accepts = "spell", address = { slot = 1 },
        Frog.Box { width = 20, height = 20 },
    }, "stable string/number key")
    rejects("TextInput value", Frog.TextInput {
        value = 12, onChange = function() end,
        Frog.Text "Search",
    }, "value must be a string")
    rejects("TextInput child", Frog.TextInput {
        value = "", onChange = function() end,
        Frog.Box { width = 20, height = 20 },
    }, "child must resolve to Frog.Text")
end

local TextChanged = Frog.action("InteractionTextInput.Changed", function(action)
    assert(type(action.value) == "string",
        "InteractionTextInput.Changed needs a value")
end)

-- Keeps the field controlled while exposing terminal callbacks to the check.
local TextInputOwner = Frog.actor("InteractionTextInputOwner", {
    initial = "",
    actions = {
        [TextChanged] = function(_, action) return action.value end,
    },
    render = function(props, value, send)
        return Frog.Row {
            width = 360,
            height = 60,
            gap = 12,
            Frog.TextInput {
                testId = "controlled-text-input",
                width = 240,
                height = 48,
                padding = 8,
                value = value,
                onChange = function(nextValue)
                    send(TextChanged { value = nextValue })
                end,
                onSubmit = props.onSubmit,
                onCancel = props.onCancel,
                Frog.Text {
                    role = "body",
                    value ~= "" and value .. "_" or "Type to search...",
                },
            },
            Frog.Button {
                testId = "text-input-shortcut",
                width = 80,
                height = 48,
                shortcut = "x",
                onPress = props.onShortcut,
                Frog.Text "Other",
            },
        }
    end,
})

-- Covers pointer/Tab focus, controlled UTF-8 edits, and shortcut isolation.
local function controlledTextInput()
    local submitted, cancelled, shortcuts = {}, {}, 0
    local host = support.host { width = 540, height = 960 }
    host:mount(TextInputOwner {
        onSubmit = function(value) submitted[#submitted + 1] = value end,
        onCancel = function(value) cancelled[#cancelled + 1] = value end,
        onShortcut = function() shortcuts = shortcuts + 1 end,
    })

    local x, y = center(host, "controlled-text-input")
    assert(host:pointerDown(x, y, "mouse", 1),
        "TextInput pointer-down was not consumed")
    host:pointerUp(x, y, "mouse", 1)
    assert(host:textInput("frog"), "focused TextInput rejected text")
    assert(node(host, "controlled-text-input").props.value == "frog",
        "TextInput did not publish its controlled value")

    host:textInput("🐸")
    host:keyDown("backspace", "backspace", false)
    assert(node(host, "controlled-text-input").props.value == "frog",
        "TextInput Backspace split a UTF-8 character")
    host:keyDown("x", "x", false)
    assert(shortcuts == 0,
        "focused TextInput leaked a Button shortcut")

    host:keyDown("return", "return", false)
    host:keyDown("escape", "escape", false)
    assert(submitted[1] == "frog" and cancelled[1] == "frog",
        "TextInput did not report its controlled terminal value")

    host:keyDown("tab", "tab", false)
    host:keyDown("x", "x", false)
    assert(shortcuts == 1,
        "TextInput did not yield focus through Tab")
    host:unmount()
end

local failStartedReaction = false
local failEndedReaction = false

-- Injects reaction failures after the typed fact enters the ordinary
-- breadth-first message transaction.
local LifecycleBomb = Frog.actor("InteractionLifecycleBomb", {
    initial = 0,
    reactions = {
        Frog.on(Frog.events.DragStarted) {
            transition = function(state)
                if failStartedReaction then error("intentional DragStarted reaction") end
                return state + 1
            end,
        },
        Frog.on(Frog.events.DragEnded) {
            transition = function(state)
                if failEndedReaction then error("intentional DragEnded reaction") end
                return state + 1
            end,
        },
    },
    render = function() return nil end,
})

-- Opens a Modal from DragStarted, then observes the cancellation generated by
-- that reconciliation. This proves one callback drains to quiescence.
local CascadeOwner = Frog.actor("InteractionCascadeOwner", {
    initial = "waiting",
    reactions = {
        Frog.on(Frog.events.DragStarted) {
            transition = Frog.go("modal", { from = "waiting" }),
        },
        Frog.on(Frog.events.DragEnded) {
            transition = Frog.go("closed", { from = "modal" }),
        },
    },
    render = function(_, state)
        if state ~= "modal" then return nil end
        return Frog.Modal {
            testId = "cascade-modal", dismiss = "none",
            Frog.Box { width = 100, height = 60 },
        }
    end,
})

-- Removes its own source from DragStarted and records the navigation
-- cancellation generated by reconciliation.
local RemovalOwner = Frog.actor("InteractionRemovalOwner", {
    initial = "waiting",
    reactions = {
        Frog.on(Frog.events.DragStarted) {
            transition = Frog.go("removed", { from = "waiting" }),
        },
        Frog.on(Frog.events.DragEnded) {
            transition = Frog.go("closed", { from = "removed" }),
        },
    },
    render = function(props, state)
        if state ~= "waiting" then
            return Frog.Box { testId = "removed-source", width = 100, height = 60 }
        end
        return Frog.DragSource {
            testId = "removing-source",
            payload = { kind = "removing-spell" },
            preview = Frog.Box { width = 40, height = 30 },
            onDrop = function() return true end,
            onDragEnd = props.onDragEnd,
            Frog.Box { width = 100, height = 60 },
        }
    end,
})

-- Builds one compact drag surface used by the throwing lifecycle probes.
local function LifecycleTree(callbacks, modal)
    callbacks = callbacks or {}
    return Frog.Overlay {
        width = 360, height = 240,
        LifecycleBomb { key = "lifecycle-bomb" },
        Frog.Row {
            align = "start", gap = 40,
            Frog.DragSource {
                key = "lifecycle-source", testId = "lifecycle-source",
                payload = { kind = "lifecycle-spell", option = 1 },
                preview = Frog.Box { width = 50, height = 30 },
                onDrop = callbacks.onDrop or function() return true end,
                onDragStart = callbacks.onDragStart,
                onDragEnd = callbacks.onDragEnd,
                Frog.Box { width = 100, height = 70, background = "panel" },
            },
            callbacks.target ~= false and Frog.DropTarget {
                key = "lifecycle-target", testId = "lifecycle-target",
                accepts = "lifecycle-spell", address = { kind = "slot", slot = 2 },
                Frog.Box { width = 100, height = 70, background = "panel" },
            } or nil,
        },
        modal and Frog.Modal {
            key = "lifecycle-modal", testId = "lifecycle-modal",
            dismiss = "none", Frog.Box { width = 120, height = 80 },
        } or nil,
    }
end

local function beginLifecycleDrag(host)
    local x, y = center(host, "lifecycle-source")
    host:pointerDown(x, y, "touch", 1)
    host:pointerMove(x + 20, y, "touch")
    return x, y
end

-- Proves runtime interaction failures fault their Host, while a reached
-- onDrop boundary stays terminal and cannot retry authoritative work.
local function atomicDragLifecycle()
    local host = support.host { width = 540, height = 960 }
    local throwStart = true
    host:mount(LifecycleTree {
        onDragStart = function()
            if throwStart then error("intentional onDragStart") end
        end,
    })
    local x, y = center(host, "lifecycle-source")
    host:pointerDown(x, y, "touch", 1)
    local ok = pcall(function() host:pointerMove(x + 20, y, "touch") end)
    assert(not ok, "throwing onDragStart unexpectedly succeeded")
    expectFault(host, "DragSource:start", function()
        host:pointerMove(x + 20, y, "touch")
    end, "throwing onDragStart")
    host:unmount()

    failStartedReaction = true
    host = support.host { width = 540, height = 960 }
    host:mount(LifecycleTree {})
    x, y = center(host, "lifecycle-source")
    host:pointerDown(x, y, "touch", 1)
    ok = pcall(function() host:pointerMove(x + 20, y, "touch") end)
    assert(not ok, "throwing DragStarted reaction unexpectedly succeeded")
    expectFault(host, "DragSource:start", function()
        host:pointerMove(x + 20, y, "touch")
    end, "throwing DragStarted reaction")
    failStartedReaction = false
    host:unmount()

    local domainCalls, throwEnd = 0, true
    host = support.host { width = 540, height = 960 }
    host:mount(LifecycleTree {
        onDrop = function()
            domainCalls = domainCalls + 1
            return true, { receipt = domainCalls }
        end,
        onDragEnd = function()
            if throwEnd then error("intentional onDragEnd") end
        end,
    })
    beginLifecycleDrag(host)
    local tx, ty = center(host, "lifecycle-target")
    host:pointerMove(tx, ty, "touch")
    ok = pcall(function() host:pointerUp(tx, ty, "touch", 1) end)
    assert(not ok and domainCalls == 1
            and host:inspectionTree().interaction.session == nil,
        "post-domain onDragEnd failure resurrected a committed drag")
    expectFault(host, "DragSource:end", function()
        host:pointerUp(tx, ty, "touch", 1)
    end, "post-domain onDragEnd failure")
    assert(domainCalls == 1,
        "terminal committed drag retried its domain callback")
    host:unmount()

    domainCalls, failEndedReaction = 0, true
    host = support.host { width = 540, height = 960 }
    host:mount(LifecycleTree {
        onDrop = function()
            domainCalls = domainCalls + 1
            return true
        end,
    })
    beginLifecycleDrag(host)
    tx, ty = center(host, "lifecycle-target")
    host:pointerMove(tx, ty, "touch")
    ok = pcall(function() host:pointerUp(tx, ty, "touch", 1) end)
    assert(not ok and domainCalls == 1
            and host:inspectionTree().interaction.session == nil,
        "DragEnded reaction failure pretended to roll back domain authority")
    expectFault(host, "DragSource:end", function()
        host:pointerUp(tx, ty, "touch", 1)
    end, "throwing DragEnded reaction")
    assert(domainCalls == 1,
        "throwing DragEnded reaction retried domain authority")
    failEndedReaction = false
    host:unmount()

    host = support.host { width = 540, height = 960 }
    host:mount(LifecycleTree {
        onDrop = function()
            Frog.emit(Frog.events.DragStarted {
                pointerId = "forbidden", payload = { kind = "nested" },
            })
            return true
        end,
    })
    beginLifecycleDrag(host)
    tx, ty = center(host, "lifecycle-target")
    host:pointerMove(tx, ty, "touch")
    ok = pcall(function() host:pointerUp(tx, ty, "touch", 1) end)
    assert(not ok and host:inspectionTree().interaction.session == nil,
        "onDrop message refusal left a retryable captured session")
    expectFault(host, "DragSource onDrop", function()
        host:pointerUp(tx, ty, "touch", 1)
    end, "onDrop message refusal")
    host:unmount()

    host = support.host { width = 540, height = 960 }
    host:mount(LifecycleTree {
        onDrop = function()
            host:render(Frog.Box { width = 20, height = 20 })
            return true
        end,
    })
    beginLifecycleDrag(host)
    tx, ty = center(host, "lifecycle-target")
    host:pointerMove(tx, ty, "touch")
    ok = pcall(function() host:pointerUp(tx, ty, "touch", 1) end)
    assert(not ok and support.find(host:tree(), "lifecycle-source")
            and host:inspectionTree().interaction.session == nil,
        "onDrop presentation mutation was not refused at the terminal boundary")
    expectFault(host, "DragSource onDrop", function()
        host:pointerUp(tx, ty, "touch", 1)
    end, "onDrop presentation mutation")
    host:unmount()

    host = support.host { width = 540, height = 960 }
    host:mount(LifecycleTree {
        onDrop = function()
            host:pointerDown(1, 1, "mouse", 1)
            return true
        end,
    })
    beginLifecycleDrag(host)
    tx, ty = center(host, "lifecycle-target")
    host:pointerMove(tx, ty, "touch")
    ok = pcall(function() host:pointerUp(tx, ty, "touch", 1) end)
    assert(not ok and host:inspectionTree().interaction.session == nil,
        "onDrop input re-entry was not refused at the terminal boundary")
    expectFault(host, "DragSource onDrop", function()
        host:pointerUp(tx, ty, "touch", 1)
    end, "onDrop input re-entry")
    host:unmount()

    local malformedCalls = 0
    host = support.host { width = 540, height = 960 }
    host:mount(LifecycleTree {
        onDrop = function()
            malformedCalls = malformedCalls + 1
            return "not-a-boolean"
        end,
    })
    beginLifecycleDrag(host)
    tx, ty = center(host, "lifecycle-target")
    host:pointerMove(tx, ty, "touch")
    ok = pcall(function() host:pointerUp(tx, ty, "touch", 1) end)
    assert(not ok and malformedCalls == 1
            and host:inspectionTree().interaction.session == nil,
        "malformed onDrop result was hidden or retained its session")
    expectFault(host, "DragSource onDrop", function()
        host:pointerUp(tx, ty, "touch", 1)
    end, "malformed onDrop result")
    assert(malformedCalls == 1, "malformed onDrop retried after terminal error")
    host:unmount()

    local throwingCalls = 0
    host = support.host { width = 540, height = 960 }
    host:mount(LifecycleTree {
        onDrop = function()
            throwingCalls = throwingCalls + 1
            error("intentional authority throw")
        end,
    })
    beginLifecycleDrag(host)
    tx, ty = center(host, "lifecycle-target")
    host:pointerMove(tx, ty, "touch")
    ok = pcall(function() host:pointerUp(tx, ty, "touch", 1) end)
    assert(not ok and throwingCalls == 1
            and host:inspectionTree().interaction.session == nil,
        "throwing onDrop remained retryable")
    expectFault(host, "DragSource onDrop", function()
        host:pointerUp(tx, ty, "touch", 1)
    end, "throwing onDrop")
    assert(throwingCalls == 1, "throwing onDrop retried after terminal error")
    host:unmount()

    local malformedDetails = {
        function()
            local cycle = {}
            cycle.self = cycle
            return cycle
        end,
        function() return function() end end,
        function() return 0 / 0 end,
    }
    for index, makeDetail in ipairs(malformedDetails) do
        local calls = 0
        host = support.host { width = 540, height = 960 }
        host:mount(LifecycleTree {
            onDrop = function()
                calls = calls + 1
                return true, makeDetail()
            end,
        })
        beginLifecycleDrag(host)
        tx, ty = center(host, "lifecycle-target")
        host:pointerMove(tx, ty, "touch")
        ok = pcall(function() host:pointerUp(tx, ty, "touch", 1) end)
        assert(not ok and calls == 1
                and host:inspectionTree().interaction.session == nil,
            "malformed completion detail " .. index
                .. " was hidden or retained its session")
        expectFault(host, "DragSource onDrop", function()
            host:pointerUp(tx, ty, "touch", 1)
        end, "malformed completion detail " .. index)
        assert(calls == 1,
            "malformed completion detail " .. index .. " retried authority")
        host:unmount()
    end
end

-- Refuses platform input re-entry from onDragStart before it can cross the
-- authority boundary, even when a later DragStarted reaction also refuses.
local function inputReentryAndQuiescence()
    local domainCalls = 0
    local host = support.host { width = 540, height = 960 }
    local targetX, targetY
    failStartedReaction = true
    host:mount(LifecycleTree {
        onDragStart = function()
            local ok, err = pcall(function()
                host:pointerUp(targetX, targetY, "touch", 1)
            end)
            assert(not ok and tostring(err):find("may not re%-enter"),
                "onDragStart platform re-entry was not refused")
        end,
        onDrop = function()
            domainCalls = domainCalls + 1
            return true
        end,
    })
    targetX, targetY = center(host, "lifecycle-target")
    local x, y = center(host, "lifecycle-source")
    host:pointerDown(x, y, "touch", 1)
    local ok = pcall(function() host:pointerMove(x + 20, y, "touch") end)
    assert(not ok and domainCalls == 0,
        "re-entrant start plus reaction failure reached authority")
    for _, entry in ipairs(host:messageTrace()) do
        assert(entry.token ~= "frog.drag-ended",
            "input re-entry delivered DragEnded before DragStarted")
    end
    expectFault(host, "DragSource:start", function()
        host:pointerMove(x + 20, y, "touch")
    end, "re-entrant start plus reaction failure")
    failStartedReaction = false
    assert(domainCalls == 0, "refused input re-entry later retried authority")
    host:unmount()

    local endStatus
    host = support.host { width = 540, height = 960 }
    host:mount(Frog.Overlay {
        CascadeOwner { key = "cascade-owner" },
        Frog.DragSource {
            testId = "cascade-source", key = "cascade-source",
            payload = { kind = "cascade-spell" },
            preview = Frog.Box { width = 40, height = 30 },
            onDrop = function() return true end,
            onDragEnd = function(status) endStatus = status end,
            Frog.Box { width = 100, height = 60 },
        },
    })
    x, y = center(host, "cascade-source")
    host:pointerDown(x, y, "touch", 1)
    host:pointerMove(x + 20, y, "touch")
    assert(endStatus == "cancelled"
            and host:inspectionTree().interaction.session == nil,
        "render-created Modal cancellation did not settle in the same callback")
    local trace = host:messageTrace()
    assert(trace[#trace - 1].token == "frog.drag-started"
            and trace[#trace].token == "frog.drag-ended",
        "render-created cancellation trace lost Started -> Ended order")
    local actor
    for _, value in ipairs(host:inspectionTree().actors) do
        if value.name == "InteractionCascadeOwner" then actor = value end
    end
    assert(actor and actor.state == "closed"
            and not support.find(host:tree(), "cascade-modal"),
        "render-created DragEnded reaction was discarded before reconciliation")
    host:unmount()

    endStatus = nil
    host = support.host { width = 540, height = 960 }
    host:mount(RemovalOwner {
        onDragEnd = function(status) endStatus = status end,
    })
    x, y = center(host, "removing-source")
    host:pointerDown(x, y, "touch", 1)
    host:pointerMove(x + 20, y, "touch")
    trace = host:messageTrace()
    assert(endStatus == "cancelled"
            and trace[#trace - 1].token == "frog.drag-started"
            and trace[#trace].token == "frog.drag-ended",
        "source removal did not settle Started -> cancelled Ended")
    actor = host:inspectionTree().actors[1]
    assert(actor and actor.name == "InteractionRemovalOwner"
            and actor.state == "closed"
            and host:inspectionTree().interaction.session == nil,
        "source-removal DragEnded reaction did not reconcile to quiescence")
    host:unmount()
end

local function pressHoldHover()
    local taps, holds, hover = 0, 0, {}
    local host = support.host { width = 540, height = 960 }
    host:mount(Frog.Box {
        align = "start", justify = "start",
        Frog.Pressable {
            testId = "pressable", onPress = function() taps = taps + 1 end,
            onLongPress = function() holds = holds + 1 end,
            onHoverChange = function(value) hover[#hover + 1] = value end,
            Frog.Box { width = 100, height = 60 },
        },
    })
    local x, y = center(host, "pressable")
    host:pointerMove(x, y, "mouse")
    host:pointerMove(300, 250, "mouse")
    assert(#hover == 2 and hover[1] == true and hover[2] == false,
        "Pressable hover did not emit exact edge changes")
    host:pointerDown(x, y, "mouse", 1)
    host:pointerUp(x, y, "mouse", 1)
    assert(taps == 1 and holds == 0, "tap did not remain distinct from hold")
    host:pointerDown(x, y, "touch", 1)
    host:update(0.36)
    host:pointerUp(x, y, "touch", 1)
    assert(taps == 1 and holds == 1,
        "completed hold also pressed or fired more than once")
    assert(host:inspectionTree().interaction.session == nil,
        "release retained the hold session")
    host:unmount()
end

-- Proves Button's explicit domain boundary cannot retry an irreversible call
-- when notification, navigation, or the first truthful rerender fails.
local function authorityButtons()
    local Committed = Frog.action("InteractionAuthority.Committed")
    local Owner = Frog.actor("InteractionAuthorityOwner", {
        initial = "choosing",
        actions = { [Committed] = { choosing = "claimed" } },
        unmount = function(props)
            if props.cleanup then props.cleanup() end
        end,
        render = function(props, state)
            if state == "claimed" then
                if props.throwRender() then
                    error("intentional authority render failure")
                end
                return Frog.Text { testId = "authority-claimed", "Claimed" }
            end
            return Frog.Button {
                testId = "authority-button", shortcut = "a",
                onCommit = props.commit,
                onResult = function(status)
                    if status == "committed" then
                        Frog.send(props.address, Committed {})
                    end
                    props.result(status)
                end,
                Frog.Text "Authority",
            }
        end,
    })
    local Address = Owner:address("authority-owner")

    local function committedCase(throwResult, throwRender)
        local calls, results, cleanups = 0, 0, 0
        local host = support.host { width = 540, height = 960 }
        host:mount(Owner {
            address = Address,
            commit = function()
                calls = calls + 1
                return true, { receipt = calls }
            end,
            result = function()
                results = results + 1
                if throwResult then error("intentional authority result failure") end
            end,
            throwRender = function()
                if not throwRender then return false end
                throwRender = false
                return true
            end,
            cleanup = function() cleanups = cleanups + 1 end,
        })
        local ok = pcall(function() host:keyDown("a", "a", false) end)
        assert(not ok and calls == 1 and results == 1,
            "post-commit failure retried authority or skipped notification")
        expectFault(host, "Button:onResult", function()
            host:keyDown("a", "a", false)
        end, "post-commit Button failure")
        assert(calls == 1 and results == 1,
            "faulted authority Button retried committed work")
        host:unmount()
        assert(cleanups == 1,
            "faulted authority Button did not clean its actor exactly once")
    end

    committedCase(true, false)
    committedCase(false, true)

    local calls, results = 0, 0
    local host = support.host { width = 540, height = 960 }
    host:mount(Owner {
        address = Address,
        commit = function()
            calls = calls + 1
            return false, "try again"
        end,
        result = function(status)
            assert(status == "rejected")
            results = results + 1
        end,
        throwRender = function() return false end,
    })
    host:keyDown("a", "a", false)
    host:keyDown("a", "a", false)
    assert(calls == 2 and results == 2
            and support.find(host:tree(), "authority-button"),
        "rejected authority Button was incorrectly spent")
    host:unmount()

    calls, results = 0, 0
    host = support.host { width = 540, height = 960 }
    host:mount(Frog.Button {
        testId = "malformed-committed-authority", shortcut = "m",
        onCommit = function()
            calls = calls + 1
            return true, function() end
        end,
        onResult = function() results = results + 1 end,
        Frog.Text "Malformed committed detail",
    })
    local ok, message = pcall(function()
        host:keyDown("m", "m", false)
    end)
    assert(not ok and tostring(message):find("plain data", 1, true)
            and calls == 1 and results == 0,
        "malformed committed detail was hidden or reached onResult")
    expectFault(host, "Button onCommit", function()
        host:keyDown("m", "m", false)
    end, "malformed committed detail")
    assert(calls == 1 and results == 0,
        "malformed committed detail retried or reached onResult")
    host:unmount()

    calls, results = 0, 0
    host = support.host { width = 540, height = 960 }
    host:mount(Frog.Button {
        testId = "malformed-rejected-authority", shortcut = "m",
        onCommit = function()
            calls = calls + 1
            return false, function() end
        end,
        onResult = function() results = results + 1 end,
        Frog.Text "Malformed rejected detail",
    })
    ok, message = pcall(function() host:keyDown("m", "m", false) end)
    assert(not ok and tostring(message):find("plain data", 1, true)
            and calls == 1 and results == 0,
        "malformed rejected detail failed unclearly or reached onResult")
    expectFault(host, "Button onCommit", function()
        host:keyDown("m", "m", false)
    end, "malformed rejected detail")
    assert(calls == 1 and results == 0,
        "malformed rejected detail retried on its faulted Host")
    host:unmount()

    calls = 0
    host = support.host { width = 540, height = 960 }
    host:mount(Frog.Button {
        testId = "malformed-authority-result", shortcut = "m",
        onCommit = function()
            calls = calls + 1
            return "not-a-boolean"
        end,
        onResult = function() error("malformed authority reached onResult") end,
        Frog.Text "Malformed authority result",
    })
    ok, message = pcall(function() host:keyDown("m", "m", false) end)
    assert(not ok and tostring(message):find("must return ok, detail", 1, true),
        "malformed Button result failed unclearly")
    expectFault(host, "Button onCommit", function()
        host:keyDown("m", "m", false)
    end, "malformed Button result")
    assert(calls == 1, "malformed Button result retried authority")
    host:unmount()

    local responsiveCalls = 0
    local ResponsiveAuthority = Frog.component(
        "InteractionResponsiveAuthority", function()
            local viewport = Frog.useViewport()
            if viewport.wide then
                return Frog.Box { testId = "wide-authority" }
            end
            return Frog.Button {
                testId = "responsive-authority", shortcut = "r",
                onCommit = function()
                    responsiveCalls = responsiveCalls + 1
                    return true
                end,
                onResult = function() end,
                Frog.Text "Responsive authority",
            }
        end)
    host = support.host { width = 540, height = 960 }
    host:mount(ResponsiveAuthority {})
    host:keyDown("r", "r", false)
    host:resize(960, 540)
    assert(support.find(host:tree(), "wide-authority"),
        "wide resize retained responsive authority Button")
    host:resize(540, 960)
    host:keyDown("r", "r", false)
    assert(responsiveCalls == 2,
        "resize retained a spent authority across its removed lifetime")
    host:unmount()
end

local function InteractionTree(log, rejected, horizontal, modal)
    local axis = horizontal and "horizontal" or "vertical"
    local Content = horizontal and Frog.Row or Frog.Column
    local scrollWidth, scrollHeight = horizontal and 150 or 180,
        horizontal and 80 or 100
    local sourceWidth, sourceHeight = horizontal and 70 or 180,
        horizontal and 80 or 40
    local fillerWidth, fillerHeight = horizontal and 180 or 180,
        horizontal and 80 or 180
    return Frog.Overlay {
        width = 400, height = 300,
        Frog.Row {
            align = "start", gap = 30,
            Frog.Scroll {
                key = "retained-scroll", testId = "scroll",
                width = scrollWidth, height = scrollHeight,
                axis = axis, bar = true,
                Content {
                    Frog.DragSource {
                        key = "source", testId = "source",
                        payload = { kind = "reward-spell", option = 2 },
                        preview = Frog.Box {
                            testId = "preview", width = 60, height = 30,
                            background = "panel",
                        },
                        onDragStart = function(payload)
                            log[#log + 1] = "start:" .. payload.option
                        end,
                        onDrop = function(payload, target)
                            log[#log + 1] = "drop:" .. target.address.slot
                            return not rejected(), { option = payload.option }
                        end,
                        onDragEnd = function(status, detail)
                            log[#log + 1] = "end:" .. status .. ":"
                                .. tostring(type(detail) == "table"
                                    and detail.option or detail)
                        end,
                        Frog.Pressable {
                            onPress = function() log[#log + 1] = "tap" end,
                            onLongPress = function() log[#log + 1] = "hold" end,
                            Frog.Box {
                                width = sourceWidth, height = sourceHeight,
                                background = "panel",
                            },
                        },
                    },
                    Frog.Box { width = fillerWidth, height = fillerHeight },
                },
            },
            Frog.Motion {
                x = 12,
                Frog.DropTarget {
                    key = "slot-3", testId = "target",
                    accepts = "reward-spell", address = { slot = 3 },
                    Frog.Box {
                        width = 100, height = 100, background = "panel",
                    },
                },
            },
        },
        modal and Frog.Modal {
            key = "test-modal", testId = "modal", dismiss = "both",
            onDismiss = modal.dismiss,
            align = "center", justify = "center", padding = 10,
            background = "panel",
            Frog.Button {
                testId = "modal-button", width = 100, height = 60,
                shortcut = "m", onPress = modal.press,
                Frog.Text "Modal",
            },
        } or nil,
    }
end

-- Refuses wide layout so an active gesture can exercise resize rollback.
local InteractionResizeGuard = Frog.component("InteractionResizeGuard",
    function(props)
        if Frog.useViewport().wide then
            error("intentional wide interaction resize refusal")
        end
        return props.tree
    end)

local function dragAndScroll()
    local log, reject = {}, false
    local rejected = function() return reject end
    local host = support.host { width = 540, height = 960 }
    host:mount(InteractionTree(log, rejected, false))
    local sx, sy = center(host, "source")
    local scrollRootRevision = host:tree()._motionTransformRevision
    local sourceNode = node(host, "source")
    local sourceVisualY = (sourceNode._visualBounds or sourceNode.layout).y

    -- Along-axis movement belongs to the nearest vertical Scroll.
    host:pointerDown(sx, sy, "touch", 1)
    host:pointerMove(sx, sy - 20, "touch")
    assert(host:inspectionTree().interaction.session.claimed == "scroll",
        "vertical movement inside Scroll did not claim scrolling")
    host:pointerMove(sx, sy - 45, "touch")
    assert(host:tree()._motionTransformRevision > scrollRootRevision
            and (sourceNode._visualBounds or sourceNode.layout).y < sourceVisualY,
        "retained Scroll movement did not invalidate transformed bounds")
    host:pointerUp(sx, sy - 45, "touch", 1)
    assert(#log == 0, "scroll also tapped, held, or dragged")
    local before = host:inspectionTree().interaction.scrolls[1].offset
    assert(before > 0, "touch pan did not retain a Scroll offset")

    -- Ordinary reconciliation retains the keyed Scroll state.
    host:render(InteractionTree(log, rejected, false))
    local after = host:inspectionTree().interaction.scrolls[1].offset
    support.near(after, before, "keyed Scroll offset across reconciliation")
    local scrollX, scrollY = center(host, "scroll")
    host:pointerMove(scrollX, scrollY, "mouse")
    host:wheelMoved(0, 1)

    -- The exact 1.25 boundary belongs to Scroll; a neutral diagonal belongs
    -- to DragSource so the framework never leaves an ambiguous tie.
    sx, sy = center(host, "source")
    host:pointerDown(sx, sy, "touch", 1)
    host:pointerMove(sx + 8, sy - 10, "touch")
    assert(host:inspectionTree().interaction.session.claimed == "scroll",
        "1.25 axis-bias boundary did not select Scroll")
    host:pointerUp(sx + 8, sy - 10, "touch", 1)
    host:pointerMove(scrollX, scrollY, "mouse")
    host:wheelMoved(0, 1)
    sx, sy = center(host, "source")
    host:pointerDown(sx, sy, "touch", 1)
    host:pointerMove(sx + 9, sy - 9, "touch")
    assert(host:inspectionTree().interaction.session.claimed == "drag",
        "neutral diagonal did not deterministically select DragSource")
    host:pointerUp(390, 280, "touch", 1)
    log = {}
    host:render(InteractionTree(log, rejected, false))

    sx, sy = center(host, "source")
    local tx, ty = center(host, "target")
    host:pointerDown(sx, sy, "touch", 1)
    host:pointerMove(sx + 24, sy, "touch")
    assert(host:inspectionTree().interaction.session.claimed == "drag",
        "cross-axis movement did not claim DragSource")
    host:draw()
    local previews = 0
    host:draw({
        dragPreview = function() previews = previews + 1 end,
    })
    assert(previews == 1, "root drag preview did not paint exactly once")
    host:pointerMove(tx, ty, "touch")
    host:pointerUp(tx, ty, "touch", 1)
    assert(log[1] == "start:2" and log[2] == "drop:3"
            and log[3] == "end:committed:2",
        "committed drag lifecycle order/detail is wrong: "
            .. table.concat(log, ","))
    local trace = host:messageTrace()
    assert(trace[#trace - 1].token == "frog.drag-started"
            and trace[#trace].token == "frog.drag-ended",
        "typed drag lifecycle facts were not delivered in order")

    log, reject = {}, true
    host:render(InteractionTree(log, rejected, false))
    sx, sy = center(host, "source")
    tx, ty = center(host, "target")
    host:pointerDown(sx, sy, "touch", 1)
    host:pointerMove(sx + 24, sy, "touch")
    host:pointerMove(tx, ty, "touch")
    host:pointerUp(tx, ty, "touch", 1)
    assert(log[#log] == "end:rejected:2",
        "false onDrop did not produce rejected completion")

    log, reject = {}, false
    host:render(InteractionTree(log, rejected, false))
    sx, sy = center(host, "source")
    host:pointerDown(sx, sy, "touch", 1)
    host:pointerMove(sx + 24, sy, "touch")
    host:pointerUp(390, 280, "touch", 1)
    assert(log[#log] == "end:cancelled:no-target",
        "release without a target did not cancel")

    host:unmount()
end

-- Proves a selection carousel can request an exact offset and receive one
-- snapped completion without application-owned pointer math.
local function controlledSnapScroll()
    local ended = {}
    local function tree(position)
        return Frog.Scroll {
            key = "carousel", testId = "snap-scroll",
            width = 100, height = 60, axis = "horizontal",
            scrollPosition = position, snapInterval = 50,
            onScrollEnd = function(offset) ended[#ended + 1] = offset end,
            Frog.Box { width = 300, height = 60, background = "panel" },
        }
    end
    local host = support.host { width = 540, height = 960 }
    host:mount(tree(30))
    support.near(node(host, "snap-scroll")._scroll.offset, 30,
        "controlled Scroll position")

    local x, y = center(host, "snap-scroll")
    host:pointerDown(x, y, "touch", 1)
    host:pointerMove(x - 12, y, "touch")
    host:pointerMove(x - 67, y, "touch")
    host:pointerUp(x - 67, y, "touch", 1)
    assert(#ended == 1 and ended[1] == 100,
        "Scroll did not snap and report one final offset")
    support.near(node(host, "snap-scroll")._scroll.offset, 100,
        "snapped Scroll position")

    host:render(tree(150))
    support.near(node(host, "snap-scroll")._scroll.offset, 150,
        "reconciled controlled Scroll position")
    host:unmount()

    local rawEnd
    host = support.host { width = 540, height = 960 }
    host:mount(Frog.Scroll {
        testId = "raw-end-scroll", width = 100, height = 60,
        axis = "horizontal", onScrollEnd = function(offset) rawEnd = offset end,
        Frog.Box { width = 300, height = 60 },
    })
    x, y = center(host, "raw-end-scroll")
    host:pointerDown(x, y, "touch", 1)
    host:pointerMove(x - 12, y, "touch")
    host:pointerMove(x - 62, y, "touch")
    host:pointerUp(x - 62, y, "touch", 1)
    local released = node(host, "raw-end-scroll")._scroll.offset
    support.near(rawEnd, released, "unsnapped Scroll completion")
    host:update(1)
    support.near(node(host, "raw-end-scroll")._scroll.offset, released,
        "onScrollEnd terminal position")
    host:unmount()
end

local function lifecycleRollbackAndModal()
    local log, reject = {}, false
    local rejected = function() return reject end
    local host = support.host { width = 540, height = 960 }
    host:mount(InteractionResizeGuard {
        tree = InteractionTree(log, rejected, false),
    })
    local sx, sy = center(host, "source")
    host:pointerDown(sx, sy, "touch", 1)
    host:pointerMove(sx + 24, sy, "touch")
    local activeSource = host:inspectionTree().interaction.session.source
    host:render(InteractionResizeGuard {
        tree = InteractionTree(log, rejected, false),
    })
    assert(host:inspectionTree().interaction.session.source == activeSource,
        "successful hot reconciliation discarded the captured drag")
    local resized = pcall(function() host:resize(960, 540) end)
    assert(not resized
            and host:inspectionTree().interaction.session.claimed == "drag",
        "failed resize discarded the captured drag")
    local bad = Frog.component("InteractionBadRender", function()
        error("intentional interaction render refusal")
    end)
    local ok = pcall(function() host:render(bad {}) end)
    assert(not ok and host:inspectionTree().interaction.session.claimed == "drag",
        "failed render discarded the captured drag")

    local modalPresses, dismisses = 0, 0
    local modal = {
        press = function() modalPresses = modalPresses + 1 end,
        dismiss = function() dismisses = dismisses + 1 end,
    }
    host:render(InteractionTree(log, rejected, false, modal))
    assert(log[#log] == "end:cancelled:modal-takeover",
        "Modal takeover did not cancel the drag exactly once")
    assert(host:keyDown("m", "m", false) and modalPresses == 1,
        "Modal did not own its shortcut")
    assert(host:keyDown("x", "x", false),
        "Modal leaked an unmatched key")
    host:pointerDown(5, 5, "mouse", 1)
    host:pointerUp(5, 5, "mouse", 1)
    assert(dismisses == 1, "outside Modal release did not dismiss once")

    -- Resize cancellation happens only after a successful rebuild.
    host:render(InteractionTree(log, rejected, false))
    sx, sy = center(host, "source")
    host:pointerDown(sx, sy, "touch", 1)
    host:pointerMove(sx + 24, sy, "touch")
    host:resize(800, 600)
    assert(log[#log] == "end:cancelled:resize",
        "resize did not cancel the retained drag")
    host:unmount()
end

-- Proves route/resize/unmount cancellation callbacks are terminal after the
-- new structure commits; they fault the Host and never retry notification.
local function cancellationTransactions()
    local function runCase(kind)
        local endCalls = 0
        local host = support.host { width = 540, height = 960 }
        host:mount(LifecycleTree {
            target = false,
            onDragEnd = function()
                endCalls = endCalls + 1
                error("intentional cancellation refusal")
            end,
        })
        beginLifecycleDrag(host)
        local oldWidth, oldHeight = host:viewport().width,
            host:viewport().height
        local ok
        if kind == "modal" then
            ok = pcall(function() host:render(LifecycleTree({
                target = false,
                onDragEnd = function()
                    endCalls = endCalls + 1
                    error("intentional cancellation refusal")
                end,
            }, true)) end)
            assert(not ok and host:inspectionTree().interaction.modal,
                "faulting modal takeover did not retain its committed portal")
        elseif kind == "navigation" then
            ok = pcall(function()
                host:render(Frog.Box { testId = "replacement", width = 40, height = 40 })
            end)
            assert(not ok and support.find(host:tree(), "replacement"),
                "faulting navigation did not retain its committed tree")
        elseif kind == "resize" then
            ok = pcall(function() host:resize(960, 540) end)
            assert(not ok and (host:viewport().width ~= oldWidth
                    or host:viewport().height ~= oldHeight),
                "faulting resize did not retain its committed viewport")
        else
            ok = pcall(function() host:unmount() end)
            assert(not ok and host:tree(),
                "faulting unmount discarded the mounted Host before cleanup")
        end
        assert(host:inspectionTree().interaction.session == nil
                and endCalls == 1,
            kind .. " cancellation was not terminal exactly once")
        expectFault(host, kind == "unmount" and "DragSource:end"
                or kind == "resize" and "Host:resize"
                or "Host:render", function()
            host:pointerUp(350, 220, "touch", 1)
        end, kind .. " cancellation refusal")
        assert(endCalls == 1,
            kind .. " cancellation callback retried after fault")
        host:unmount()
    end
    for _, kind in ipairs({ "modal", "navigation", "resize", "unmount" }) do
        runCase(kind)
    end
end

-- Proves Modal's portal is detached from authored Motion/Scroll ancestry and
-- owns every keyboard/text edge while active.
local function modalPortalAndInput()
    local presses = 0
    local host = support.host { width = 540, height = 960 }
    host:mount(Frog.Motion {
        x = 120, y = 80,
        Frog.Scroll {
            testId = "portal-scroll", width = 180, height = 80,
            axis = "vertical", bar = false,
            Frog.Column {
                Frog.Box { testId = "portal-filler", width = 180, height = 220 },
                Frog.Modal {
                    testId = "detached-modal", dismiss = "none",
                    align = "center", justify = "center",
                    Frog.Button {
                        testId = "detached-modal-button",
                        width = 120, height = 60,
                        onPress = function() presses = presses + 1 end,
                        Frog.Text "Portal",
                    },
                },
            },
        },
    })
    local modal = node(host, "detached-modal")
    local modalBounds = modal._visualBounds or modal.layout
    support.near(modalBounds.x, 0, "Modal portal visual x")
    support.near(modalBounds.y, 0, "Modal portal visual y")
    support.near(modalBounds.width, 540, "Modal portal visual width")
    support.near(modalBounds.height, 960, "Modal portal visual height")
    local x, y = center(host, "detached-modal-button")
    host:pointerDown(x, y, "mouse", 1)
    host:pointerUp(x, y, "mouse", 1)
    assert(presses == 1, "detached Modal input disagreed with portal paint")
    local inspection = host:inspectionTree()
    assert(inspection.nodes[1].testId == "detached-modal"
            and not support.find({ children = inspection.nodes }, "portal-scroll"),
        "F6 did not expose only the active Modal z-plane")
    host:unmount()

    host = support.host { width = 540, height = 960 }
    host:mount(Frog.Modal {
        testId = "empty-modal", dismiss = "none",
        Frog.Box { width = 100, height = 60 },
    })
    assert(host:keyDown("x", "x", true), "Modal leaked repeat key-down")
    assert(host:keyDown("tab", "tab", false), "empty Modal leaked Tab")
    assert(host:keyUp("x", "x"), "Modal leaked key-up")
    assert(host:textInput("frog"), "Modal leaked text input")
    host:unmount()

    local backDismissed = 0
    host = support.host { width = 540, height = 960 }
    host:mount(Frog.Modal {
        testId = "back-modal", dismiss = "back",
        onDismiss = function() backDismissed = backDismissed + 1 end,
        Frog.Box { width = 100, height = 60 },
    })
    assert(host:keyDown("escape", "escape", false)
            and backDismissed == 1,
        "Escape did not invoke the active Modal back dismissal exactly once")
    host:unmount()

    host = support.host { width = 540, height = 960 }
    host:mount(Frog.Scroll {
        testId = "inspect-scroll", width = 120, height = 45,
        axis = "vertical", bar = false,
        Frog.Column {
            Frog.Box { testId = "inspect-visible", width = 120, height = 40 },
            Frog.Box { testId = "inspect-clipped", width = 120, height = 80 },
        },
    })
    inspection = host:inspectionTree()
    local clipped
    for _, entry in ipairs(inspection.nodes) do
        if entry.testId == "inspect-clipped" then clipped = entry end
    end
    assert(clipped and clipped.bounds.height == 5,
        "F6 did not clip a partially visible Scroll child")
    host:unmount()
end

-- Proves one root Chrome portal, explicit top-Modal sharing, default modal
-- isolation, and deterministic paint order when a second Modal takes over.
local function chromePortalAndModalIsolation()
    local chromePresses, modalPresses = 0, 0
    local function Tree(allowChrome, upper)
        return Frog.Overlay {
            width = 540,
            height = 960,
            Frog.Box { testId = "chrome-base", width = 540, height = 960 },
            Frog.Modal {
                key = "chrome-lower",
                testId = "chrome-lower-modal",
                dismiss = "none",
                allowChrome = allowChrome,
                align = "center",
                justify = "center",
                Frog.Button {
                    testId = "chrome-modal-button",
                    width = 120,
                    height = 50,
                    shortcut = "m",
                    onPress = function() modalPresses = modalPresses + 1 end,
                    Frog.Text "Modal",
                },
            },
            upper and Frog.Modal {
                key = "chrome-upper",
                testId = "chrome-upper-modal",
                dismiss = "none",
                Frog.Box { width = 180, height = 100 },
            } or nil,
            Frog.Chrome {
                testId = "chrome-portal",
                Frog.Overlay {
                    width = 540,
                    height = 960,
                    align = "start",
                    justify = "start",
                    Frog.Button {
                        testId = "chrome-button",
                        width = 100,
                        height = 60,
                        shortcut = "h",
                        onPress = function()
                            chromePresses = chromePresses + 1
                        end,
                        Frog.Text "Chrome",
                    },
                },
            },
        }
    end

    local host = support.host { width = 540, height = 960 }
    host:mount(Tree(false, false))
    local x, y = center(host, "chrome-button")
    host:pointerDown(x, y, "mouse", 1)
    host:pointerUp(x, y, "mouse", 1)
    host:keyDown("h", "h", false)
    assert(chromePresses == 0,
        "default Modal leaked pointer or keyboard input to Chrome")

    host:render(Tree(true, false))
    x, y = center(host, "chrome-button")
    host:pointerDown(x, y, "mouse", 1)
    host:pointerUp(x, y, "mouse", 1)
    host:keyDown("h", "h", false)
    host:keyDown("m", "m", false)
    assert(chromePresses == 2 and modalPresses == 1,
        "opted-in Modal did not share pointer/keyboard with Chrome")
    local modalButton = node(host, "chrome-modal-button")
    local inspected = host:inspect(
        modalButton.layout.x + 4, modalButton.layout.y + 4)
    assert(inspected and inspected.testId == "chrome-modal-button",
        "transparent Chrome prevented F6 from selecting Modal content")
    local chromeButton = node(host, "chrome-button")
    inspected = host:inspect(
        chromeButton.layout.x + 4, chromeButton.layout.y + 4)
    assert(inspected and inspected.testId == "chrome-button",
        "F6 did not preserve Chrome priority over its visible control")
    host:render(Frog.Overlay {
        width = 540,
        height = 960,
        Frog.Modal {
            dismiss = "none",
            allowChrome = true,
            align = "start",
            justify = "start",
            Frog.Button {
                testId = "covered-small-modal-button",
                width = 40,
                height = 40,
                onPress = function() end,
            },
        },
        Frog.Chrome {
            Frog.Button {
                testId = "covering-large-chrome-button",
                width = 100,
                height = 60,
                onPress = function() end,
            },
        },
    })
    inspected = host:inspect(4, 4)
    assert(inspected and inspected.testId == "covering-large-chrome-button",
        "F6 specificity overrode a concrete top-plane Chrome control")
    host:render(Tree(true, false))
    local paintOrder = {}
    host:draw {
        box = function(_, painted)
            local id = painted.props.testId
            if id == "chrome-lower-modal" or id == "chrome-portal" then
                paintOrder[#paintOrder + 1] = id
            end
        end,
    }
    assert(paintOrder[1] == "chrome-lower-modal"
            and paintOrder[2] == "chrome-portal",
        "opted-in Chrome did not paint above its Modal")

    host:render(Tree(true, true))
    host:keyDown("h", "h", false)
    x, y = center(host, "chrome-button")
    host:pointerDown(x, y, "mouse", 1)
    host:pointerUp(x, y, "mouse", 1)
    assert(chromePresses == 2,
        "higher default Modal did not isolate covered Chrome")
    paintOrder = {}
    host:draw {
        box = function(_, painted)
            local id = painted.props.testId
            if id == "chrome-lower-modal" or id == "chrome-upper-modal"
                    or id == "chrome-portal" then
                paintOrder[#paintOrder + 1] = id
            end
        end,
    }
    assert(paintOrder[1] == "chrome-portal"
            and paintOrder[2] == "chrome-lower-modal"
            and paintOrder[3] == "chrome-upper-modal",
        "higher default Modal did not paint above Chrome and lower Modal")

    host:render(Frog.Overlay {
        width = 540,
        height = 960,
        Frog.Chrome {
            testId = "inspect-chrome-portal",
            Frog.Button {
                testId = "inspect-chrome-button",
                width = 100,
                height = 60,
                onPress = function() end,
            },
        },
        Frog.Button {
            testId = "inspect-base-button",
            width = 100,
            height = 60,
            onPress = function() end,
        },
    })
    inspected = host:inspect(4, 4)
    assert(inspected and inspected.testId == "inspect-chrome-button",
        "F6 used authored tree order instead of Chrome paint order")
    local inspection = host:inspectionTree()
    local baseIndex, chromeIndex
    for index, entry in ipairs(inspection.nodes) do
        if entry.testId == "inspect-base-button" then baseIndex = index end
        if entry.testId == "inspect-chrome-portal" then chromeIndex = index end
    end
    assert(baseIndex and chromeIndex and baseIndex < chromeIndex,
        "F6 outlines did not follow base-then-Chrome paint order")
    host:unmount()
end

-- Proves source-ordered modal stacking, top-only input, gesture takeover, and
-- LIFO keyboard-focus restoration without any application-owned coordinator.
local function stackedModalPlanes()
    local basePresses, lowerPresses, upperPresses = 0, 0, 0
    local lowerDismisses, upperDismisses = 0, 0
    local dragEnd

    -- Builds zero, one, or two independently authored modal portal layers.
    local function Stack(lower, upper)
        return Frog.Overlay {
            testId = "stack-root",
            width = 540,
            height = 960,
            Frog.Button {
                testId = "stack-base-button",
                width = 120,
                height = 48,
                shortcut = "b",
                onPress = function() basePresses = basePresses + 1 end,
                Frog.Text "Base",
            },
            lower and Frog.Modal {
                key = "stack-lower",
                testId = "stack-lower-modal",
                dismiss = "both",
                onDismiss = function() lowerDismisses = lowerDismisses + 1 end,
                align = "center",
                justify = "center",
                Frog.Column {
                    testId = "stack-lower-surface",
                    width = 220,
                    height = 300,
                    gap = 8,
                    Frog.Button {
                        testId = "stack-lower-button",
                        width = 180,
                        height = 48,
                        shortcut = "l",
                        onPress = function() lowerPresses = lowerPresses + 1 end,
                        Frog.Text "Lower",
                    },
                    Frog.Scroll {
                        testId = "stack-lower-scroll",
                        width = 180,
                        height = 70,
                        axis = "vertical",
                        bar = true,
                        Frog.Column {
                            Frog.Box { width = 180, height = 90 },
                            Frog.Box { width = 180, height = 90 },
                        },
                    },
                    Frog.DragSource {
                        testId = "stack-lower-drag",
                        payload = { kind = "stack-spell" },
                        preview = Frog.Box { width = 40, height = 30 },
                        onDrop = function() return true end,
                        onDragEnd = function(status, detail)
                            dragEnd = { status = status, detail = detail }
                        end,
                        Frog.Box { width = 180, height = 60 },
                    },
                },
            } or nil,
            upper and Frog.Modal {
                key = "stack-upper",
                testId = "stack-upper-modal",
                dismiss = "both",
                onDismiss = function() upperDismisses = upperDismisses + 1 end,
                align = "center",
                justify = "center",
                Frog.Box {
                    testId = "stack-upper-surface",
                    width = 180,
                    height = 120,
                    align = "center",
                    justify = "center",
                    Frog.Button {
                        testId = "stack-upper-button",
                        width = 120,
                        height = 48,
                        shortcut = "u",
                        onPress = function() upperPresses = upperPresses + 1 end,
                        Frog.Text "Upper",
                    },
                },
            } or nil,
        }
    end

    local host = support.host { width = 540, height = 960 }
    host:mount(Stack(false, false))
    host:keyDown("tab", "tab", false)
    local baseFocus = node(host, "stack-base-button").identity
    assert(host:inspectionTree().interaction.focused == baseFocus,
        "base Button did not receive initial keyboard focus")

    host:render(Stack(true, false))
    host:keyDown("tab", "tab", false)
    local lowerFocus = node(host, "stack-lower-button").identity
    assert(host:inspectionTree().interaction.focused == lowerFocus,
        "lower Modal did not isolate keyboard focus")

    local x, y = center(host, "stack-lower-drag")
    host:pointerDown(x, y, "touch", 1)
    host:pointerMove(x + 20, y, "touch")
    assert(host:inspectionTree().interaction.session.claimed == "drag",
        "lower Modal drag did not start")
    host:render(Stack(true, true))
    assert(dragEnd and dragEnd.status == "cancelled"
            and dragEnd.detail == "modal-takeover",
        "higher Modal did not safely cancel the lower drag")

    local inspection = host:inspectionTree()
    assert(#inspection.interaction.modals == 2
            and inspection.interaction.modal
                == inspection.interaction.modals[2]
            and inspection.nodes[1].testId == "stack-upper-modal",
        "F6 did not identify only the source-last Modal as active")

    local paintOrder = {}
    host:draw {
        box = function(_, painted)
            local id = painted.props.testId
            if id == "stack-lower-modal" or id == "stack-upper-modal" then
                paintOrder[#paintOrder + 1] = id
            end
        end,
    }
    assert(#paintOrder == 2
            and paintOrder[1] == "stack-lower-modal"
            and paintOrder[2] == "stack-upper-modal",
        "Modal portals did not paint once in source order")

    host:keyDown("tab", "tab", false)
    local upperFocus = node(host, "stack-upper-button").identity
    assert(host:inspectionTree().interaction.focused == upperFocus,
        "upper Modal did not take keyboard focus")
    host:keyDown("l", "l", false)
    assert(lowerPresses == 0, "lower Modal shortcut leaked through the top")
    host:keyDown("u", "u", false)
    assert(upperPresses == 1, "top Modal shortcut was not routed")
    assert(host:textInput("frog"), "stacked Modal leaked text input")

    local lowerScroll = node(host, "stack-lower-scroll")
    local scrollBefore = lowerScroll._scroll.offset
    x, y = center(host, "stack-lower-scroll")
    host:pointerMove(x, y, "mouse")
    assert(host:wheelMoved(0, -1), "stacked Modal leaked wheel input")
    assert(lowerScroll._scroll.offset == scrollBefore,
        "covered lower Modal received wheel input")

    x, y = center(host, "stack-lower-button")
    host:pointerDown(x, y, "mouse", 1)
    host:pointerUp(x, y, "mouse", 1)
    assert(lowerPresses == 0,
        "covered lower Modal received pointer input")
    host:pointerDown(5, 5, "mouse", 1)
    host:pointerUp(5, 5, "mouse", 1)
    assert(upperDismisses == 2 and lowerDismisses == 0,
        "outside pointer did not dismiss only the top Modal")
    assert(host:pointerDown(5, 5, "mouse", 2)
            and host:pointerUp(5, 5, "mouse", 2),
        "stacked Modal leaked a secondary pointer edge")

    host:keyDown("escape", "escape", false)
    assert(upperDismisses == 3 and lowerDismisses == 0,
        "Escape did not dismiss only the top Modal")
    host:render(Stack(true, false))
    assert(host:inspectionTree().interaction.focused == lowerFocus,
        "closing the top Modal did not restore lower focus")
    host:keyDown("escape", "escape", false)
    assert(lowerDismisses == 1,
        "remaining lower Modal did not receive Escape")
    host:render(Stack(false, false))
    assert(host:inspectionTree().interaction.focused == baseFocus,
        "closing the final Modal did not restore base focus")
    host:keyDown("b", "b", false)
    assert(basePresses == 1, "base shortcut did not recover after all Modals")
    host:unmount()
end

-- Keeps the active top Modal focused when covered siblings enter or leave
-- below it, while rebuilding the eventual return path back to base focus.
local function modalFocusUnderlayChanges()
    -- Builds keyed sibling portals so their identity survives source reindexing.
    local function FocusStack(showA, showB)
        return Frog.Overlay {
            width = 540,
            height = 960,
            Frog.Button {
                testId = "focus-base",
                width = 100,
                height = 48,
                onPress = function() end,
                Frog.Text "Base",
            },
            showA and Frog.Modal {
                key = "focus-a",
                testId = "focus-modal-a",
                dismiss = "none",
                Frog.Button {
                    testId = "focus-a",
                    width = 100,
                    height = 48,
                    onPress = function() end,
                    Frog.Text "A",
                },
            } or nil,
            showB and Frog.Modal {
                key = "focus-b",
                testId = "focus-modal-b",
                dismiss = "none",
                Frog.Button {
                    testId = "focus-b",
                    width = 100,
                    height = 48,
                    onPress = function() end,
                    Frog.Text "B",
                },
            } or nil,
        }
    end

    local function focused(host, testId)
        return host:inspectionTree().interaction.focused
            == node(host, testId).identity
    end

    -- Removing A from beneath focused B preserves B and retargets B's later
    -- return directly to the base layer.
    local host = support.host { width = 540, height = 960 }
    host:mount(FocusStack(false, false))
    host:keyDown("tab", "tab", false)
    assert(focused(host, "focus-base"), "focus edge missing base focus")
    host:render(FocusStack(true, false))
    host:keyDown("tab", "tab", false)
    host:render(FocusStack(true, true))
    host:keyDown("tab", "tab", false)
    assert(focused(host, "focus-b"), "focus edge missing B focus")
    host:render(FocusStack(false, true))
    assert(focused(host, "focus-b"),
        "removing a covered lower Modal cleared top focus")
    host:render(FocusStack(false, false))
    assert(focused(host, "focus-base"),
        "removed underlay left the top Modal's return chain stale")
    host:unmount()

    -- Inserting A beneath focused B also preserves B. A has no invented focus,
    -- but closing both layers still restores the original base control.
    host = support.host { width = 540, height = 960 }
    host:mount(FocusStack(false, false))
    host:keyDown("tab", "tab", false)
    host:render(FocusStack(false, true))
    host:keyDown("tab", "tab", false)
    assert(focused(host, "focus-b"), "focus insert edge missing B focus")
    host:render(FocusStack(true, true))
    assert(focused(host, "focus-b"),
        "inserting a covered lower Modal cleared top focus")
    host:render(FocusStack(true, false))
    assert(host:inspectionTree().interaction.focused == nil,
        "newly inserted covered Modal invented keyboard focus")
    host:render(FocusStack(false, false))
    assert(focused(host, "focus-base"),
        "inserted underlay broke final base-focus restoration")
    host:unmount()
end

-- Consumes every pointer edge over a noninteractive Modal child without
-- manufacturing a session, dismissing, or reaching any covered layer.
local function modalBlankAreaConsumption()
    local function run(stacked)
        local basePresses, lowerPresses = 0, 0
        local lowerDismisses, topDismisses = 0, 0
        local host = support.host { width = 540, height = 960 }
        host:mount(Frog.Overlay {
            width = 540,
            height = 960,
            Frog.Pressable {
                testId = "blank-base",
                onPress = function() basePresses = basePresses + 1 end,
                Frog.Box { width = 540, height = 960 },
            },
            stacked and Frog.Modal {
                key = "blank-lower",
                testId = "blank-lower-modal",
                dismiss = "both",
                onDismiss = function()
                    lowerDismisses = lowerDismisses + 1
                end,
                align = "center",
                justify = "center",
                Frog.Pressable {
                    testId = "blank-lower-control",
                    onPress = function() lowerPresses = lowerPresses + 1 end,
                    Frog.Box { width = 300, height = 300 },
                },
            } or nil,
            Frog.Modal {
                key = "blank-top",
                testId = "blank-top-modal",
                dismiss = "both",
                onDismiss = function() topDismisses = topDismisses + 1 end,
                align = "center",
                justify = "center",
                Frog.Box {
                    testId = "blank-top-surface",
                    width = 200,
                    height = 200,
                },
            },
        })

        local x, y = center(host, "blank-top-surface")
        assert(host:pointerDown(x, y, "mouse", 1),
            "Modal blank area leaked pointerDown")
        assert(host:inspectionTree().interaction.session == nil,
            "Modal blank area manufactured a pointer session")
        assert(host:pointerMove(x + 2, y + 2, "mouse"),
            "Modal blank area leaked no-session pointerMove")
        assert(host:pointerUp(x + 2, y + 2, "mouse", 1),
            "Modal blank area leaked no-session pointerUp")
        assert(basePresses == 0 and lowerPresses == 0
                and lowerDismisses == 0 and topDismisses == 0,
            "Modal blank pointer path reached a covered action or dismissal")
        host:unmount()
    end

    run(false)
    run(true)
end

-- Successful reconciliation emits one hover false edge. A throwing hover edge
-- instead faults its Host and is never replayed.
local function hoverEdges()
    local function run(kind)
        local edges, throw = {}, false
        local function onHover(value)
            edges[#edges + 1] = value
            if throw then error("intentional hover edge") end
        end
        local function HoverControl()
            if kind == "Button" then
                return Frog.Button {
                    testId = "hover-edge",
                    width = 100,
                    height = 60,
                    onPress = function() end,
                    onHoverChange = onHover,
                    Frog.Box { width = 100, height = 60 },
                }
            end
            return Frog.Pressable {
                testId = "hover-edge",
                width = 100,
                height = 60,
                onHoverChange = onHover,
                Frog.Box { width = 100, height = 60 },
            }
        end
        local function HoverTree(modal)
            return Frog.Overlay {
                HoverControl(),
                modal and Frog.Modal {
                    testId = "hover-modal", dismiss = "none",
                    Frog.Box { width = 100, height = 60 },
                } or nil,
            }
        end
        local host = support.host { width = 540, height = 960 }
        host:mount(HoverTree(false))
        local x, y = center(host, "hover-edge")
        host:pointerMove(x, y, "mouse")
        host:render(Frog.Box { testId = "hover-gone", width = 20, height = 20 })
        assert(#edges == 2 and edges[1] == true and edges[2] == false,
            kind .. " removal did not emit one exact hover false edge")
        host:unmount()

        edges = {}
        host = support.host { width = 540, height = 960 }
        host:mount(HoverTree(false))
        x, y = center(host, "hover-edge")
        host:pointerMove(x, y, "mouse")
        host:render(HoverTree(true))
        assert(#edges == 2 and edges[2] == false,
            kind .. " Modal takeover did not clear hover exactly once")
        host:unmount()

        edges, throw = {}, true
        host = support.host { width = 540, height = 960 }
        host:mount(HoverTree(false))
        x, y = center(host, "hover-edge")
        local ok = pcall(function() host:pointerMove(x, y, "mouse") end)
        assert(not ok and #edges == 1,
            kind .. " failed hover true edge did not run exactly once")
        expectFault(host, "FrogUI:hover", function()
            host:pointerMove(x, y, "mouse")
        end, kind .. " failed hover true edge")
        assert(#edges == 1,
            kind .. " failed hover true edge was retried")
        host:unmount()

        edges, throw = {}, false
        host = support.host { width = 540, height = 960 }
        host:mount(HoverTree(false))
        x, y = center(host, "hover-edge")
        host:pointerMove(x, y, "mouse")
        throw = true
        ok = pcall(function() host:pointerMove(300, 300, "mouse") end)
        assert(not ok and #edges == 2,
            kind .. " failed hover false edge did not run exactly once")
        expectFault(host, "FrogUI:hover", function()
            host:pointerMove(300, 300, "mouse")
        end, kind .. " failed hover false edge")
        assert(#edges == 2,
            kind .. " failed hover false edge was retried")
        host:unmount()
    end

    for _, kind in ipairs({ "Pressable", "Button" }) do run(kind) end
end

local function horizontalAndMomentum()
    local function run(parts)
        local log = {}
        local host = support.host { width = 540, height = 960 }
        host:mount(InteractionTree(log, function() return false end, true))
        local x, y = center(host, "source")
        host:pointerDown(x, y, "touch", 1)
        host:pointerMove(x - 20, y, "touch")
        assert(host:inspectionTree().interaction.session.claimed == "scroll",
            "horizontal movement did not claim horizontal Scroll")
        host:update(0.02)
        host:pointerMove(x - 45, y, "touch")
        host:pointerUp(x - 45, y, "touch", 1)
        for _, dt in ipairs(parts) do host:update(dt) end
        local offset = host:inspectionTree().interaction.scrolls[1].offset
        host:unmount()
        return offset
    end
    local whole = run({ 0.1 })
    local split = run({ 0.04, 0.06 })
    support.near(whole, split, "Scroll momentum dt partition")
end

function check.run()
    definitionContracts()
    controlledTextInput()
    pressHoldHover()
    authorityButtons()
    atomicDragLifecycle()
    inputReentryAndQuiescence()
    dragAndScroll()
    controlledSnapScroll()
    lifecycleRollbackAndModal()
    cancellationTransactions()
    modalPortalAndInput()
    chromePortalAndModalIsolation()
    stackedModalPlanes()
    modalFocusUnderlayChanges()
    modalBlankAreaConsumption()
    hoverEdges()
    horizontalAndMomentum()
end

return check
