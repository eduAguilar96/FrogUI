-- Actor state follows actor type+key through reorder/resize and dies on
-- unmount. Runtime failures fault the Host; candidate-build failures do not.

local Frog = require("frogui")
local support = require("tests.support")

local check = {}

local Bump = Frog.action("IdentityCounter.Bump")
local Explode = Frog.action("IdentityCounter.Explode")
-- Owns keyed scalar state used to prove reorder-safe actor identity.
local Counter = Frog.actor("IdentityCounter", {
    initial = 0,
    actions = {
        [Bump] = function(state) return state + 1 end,
        [Explode] = function() error("intentional reducer failure") end,
    },
    render = function(props, state)
        return Frog.Text {
            testId = "counter-" .. props.id,
            props.id .. ":" .. state,
        }
    end,
})
local CounterA = Counter:address("identity-a")
local CounterB = Counter:address("identity-b")

local Break = Frog.action("Fragile.Break")
-- Refuses one reconciled state so the test can prove runtime fault semantics.
local Fragile = Frog.actor("Fragile", {
    initial = "sound",
    actions = { [Break] = { sound = "broken" } },
    render = function(_, state)
        assert(state ~= "broken", "intentional actor render failure")
        return Frog.Text { testId = "fragile-state", state }
    end,
})
local FragileAddress = Fragile:address("fragile")

local retainedSend, latestSend
local RetainedBump = Frog.action("RetainedActor.Bump")
-- Exposes a render-created sender so reconciliation and mount lifetimes can
-- be distinguished without using an address.
local RetainedActor = Frog.actor("RetainedActor", {
    initial = 0,
    actions = { [RetainedBump] = function(state) return state + 1 end },
    render = function(_, state, send)
        latestSend = function() send(RetainedBump {}) end
        retainedSend = retainedSend or latestSend
        return Frog.Text { testId = "retained-state", tostring(state) }
    end,
})

local disposed = {}
local DisposeBump = Frog.action("DisposableActor.Bump")
-- Records its final state so actor lifecycle cleanup can be verified directly.
local DisposableActor = Frog.actor("DisposableActor", {
    initial = 0,
    actions = {
        [DisposeBump] = function(state) return state + 1 end,
    },
    unmount = function(props, state)
        disposed[#disposed + 1] = { id = props.id, state = state }
        if props.failCleanup then error("intentional unmount failure") end
    end,
    render = function(props, state)
        return Frog.Text {
            testId = "disposable-" .. props.id,
            props.id .. ":" .. state,
        }
    end,
})
local DisposableAddress = DisposableActor:address("disposable")

local function press(host, testId)
    local button = assert(support.find(host:tree(), testId), testId)
    local x, y = support.center(button)
    local scale = host:viewport().scale
    x, y = x * scale, y * scale
    assert(host:pointerDown(x, y, "mouse", 1), testId .. " pointer down")
    assert(host:pointerUp(x, y, "mouse", 1), testId .. " pointer up")
end

local function expectFailure(label, callback, pattern)
    local ok, err = pcall(callback)
    assert(not ok, label .. " unexpectedly succeeded")
    assert(tostring(err):find(pattern, 1, true),
        label .. " failed unclearly: " .. tostring(err))
end

local function nodeText(host, testId)
    return assert(support.find(host:tree(), testId), testId).props.text
end

function check.run()
    local showRetained = true
    local host
    local Reorder = Frog.action("IdentityStory.Reorder")
    -- Reorders counter instances while retaining their keyed actor state.
    local Root
    Root = Frog.actor("IdentityStory", {
        initial = false,
        actions = {
            [Reorder] = function(reversed) return not reversed end,
        },
        render = function(_, reversed)
        local items = reversed and {
            { id = "b", address = CounterB },
            { id = "a", address = CounterA },
        } or {
            { id = "a", address = CounterA },
            { id = "b", address = CounterB },
        }
        return Frog.Column {
            Frog.Row {
                gap = 4,
                Frog.Button {
                    testId = "bump-a-reorder",
                    onPress = function()
                        Frog.send(CounterA, Bump {})
                        Frog.send(Root.App, Reorder {})
                    end,
                    Frog.Text "Bump A + reorder",
                },
                Frog.Button {
                    testId = "bump-a",
                    onPress = function() Frog.send(CounterA, Bump {}) end,
                    Frog.Text "Bump A",
                },
                Frog.Button {
                    testId = "explode-a",
                    onPress = function() Frog.send(CounterA, Explode {}) end,
                    Frog.Text "Explode",
                },
                Frog.Button {
                    testId = "break-render",
                    onPress = function() Frog.send(FragileAddress, Break {}) end,
                    Frog.Text "Break render",
                },
            },
            Frog.Row {
                gap = 4,
                Frog.each(items, function(item)
                    return Counter {
                        key = item.id,
                        address = item.address,
                        id = item.id,
                    }
                end),
            },
            Fragile { address = FragileAddress },
            showRetained and RetainedActor { key = "retained" } or nil,
        }
        end,
    })
    Root.App = Root:address("identity-story")

    host = support.host { width = 540, height = 960 }
    host:mount(Root { address = Root.App })
    assert(nodeText(host, "counter-a") == "a:0"
            and nodeText(host, "counter-b") == "b:0",
        "keyed actors did not start from independent state")
    press(host, "bump-a-reorder")
    assert(nodeText(host, "counter-a") == "a:1"
            and nodeText(host, "counter-b") == "b:0",
        "keyed actor state followed its old index during reorder")
    retainedSend()
    assert(nodeText(host, "retained-state") == "1",
        "retained actor send did not survive unrelated reconciliation")
    local counters = support.collect(host:tree(), function(node)
        return node.testId == "counter-a" or node.testId == "counter-b"
            or node.props and (node.props.testId == "counter-a"
                or node.props.testId == "counter-b")
    end)
    assert(counters[1].props.testId == "counter-b"
            and counters[2].props.testId == "counter-a",
        "actor children did not visibly reorder")

    host:resize(960, 540)
    assert(nodeText(host, "counter-a") == "a:1",
        "resize reset keyed actor state")

    expectFailure("failed address discovery render", function()
        host:render(Frog.Column {
            Counter { key = "x", address = CounterA, id = "x" },
            Counter { key = "y", address = CounterA, id = "y" },
        })
    end, "duplicate")
    assert(nodeText(host, "counter-a") == "a:1",
        "failed address discovery replaced the committed tree")
    press(host, "bump-a")
    assert(nodeText(host, "counter-a") == "a:2",
        "failed address discovery corrupted the committed registry")

    local sameHostStale = latestSend
    showRetained = false
    host:render(Root { address = Root.App })
    showRetained = true
    host:render(Root { address = Root.App })
    assert(latestSend ~= sameHostStale
            and nodeText(host, "retained-state") == "0",
        "same-path actor remount reused its removed lifetime")
    latestSend()
    assert(nodeText(host, "retained-state") == "1",
        "fresh same-Host actor sender was rejected")

    local staleUnmountedSend = latestSend
    host:unmount()
    host:mount(Root { address = Root.App })
    assert(nodeText(host, "counter-a") == "a:0",
        "actor state survived unmount/remount")
    latestSend()
    assert(nodeText(host, "retained-state") == "1",
        "fresh remounted actor sender was rejected")
    expectFailure("stale actor mount sender", staleUnmountedSend,
        "unmounted actor")
    assert(nodeText(host, "retained-state") == "1"
            and host:inspectionTree().fault,
        "stale sender reached the remounted actor or left its Host mutable")
    host:unmount()

    showRetained = true
    local reducerFault = support.host { width = 540, height = 960 }
    reducerFault:mount(Root { address = Root.App })
    expectFailure("throwing actor reducer", function()
        press(reducerFault, "explode-a")
    end, "intentional reducer failure")
    assert(reducerFault:inspectionTree().fault,
        "throwing reducer did not fault the Host")
    expectFailure("faulted reducer Host mutation", function()
        reducerFault:resize(960, 540)
    end, "Host faulted")
    reducerFault:unmount()

    local renderFault = support.host { width = 540, height = 960 }
    renderFault:mount(Root { address = Root.App })
    expectFailure("failed actor reconciliation", function()
        press(renderFault, "break-render")
    end, "intentional actor render failure")
    assert(nodeText(renderFault, "fragile-state") == "sound"
            and renderFault:inspectionTree().fault,
        "failed reconciliation changed the committed tree or stayed mutable")
    expectFailure("faulted reconciliation Host mutation", function()
        renderFault:render(Root { address = Root.App })
    end, "Host faulted")
    renderFault:unmount()

    showRetained = true
    local senderFault = support.host { width = 540, height = 960 }
    senderFault:mount(Root { address = Root.App })
    local removedSend = latestSend
    showRetained = false
    senderFault:render(Root { address = Root.App })
    expectFailure("removed actor sender", removedSend, "unmounted actor")
    assert(senderFault:inspectionTree().fault,
        "removed actor sender failure did not fault its Host")
    senderFault:unmount()
    showRetained = true

    expectFailure("invalid actor unmount", function()
        Frog.actor("InvalidUnmountActor", {
            initial = "ready", actions = {}, unmount = true,
            render = function() return Frog.Box {} end,
        })
    end, "unmount must be a function")

    disposed = {}
    local lifecycle = support.host { width = 540, height = 960 }
    lifecycle:mount(DisposableActor {
        key = "one", address = DisposableAddress, id = "one",
    })
    Frog.send(DisposableAddress, DisposeBump {})
    lifecycle:render(DisposableActor {
        key = "one", address = DisposableAddress, id = "one",
    })
    lifecycle:resize(960, 540)
    assert(#disposed == 0,
        "retained actor cleaned up during rerender or resize")
    expectFailure("failed lifecycle candidate", function()
        lifecycle:render(Frog.Column {
            DisposableActor {
                key = "one", address = DisposableAddress, id = "one",
            },
            DisposableActor {
                key = "two", address = DisposableAddress, id = "two",
            },
        })
    end, "duplicate")
    assert(#disposed == 0,
        "failed candidate cleaned up the committed actor")
    lifecycle:render(Frog.Box { width = 1, height = 1 })
    assert(#disposed == 1 and disposed[1].id == "one"
            and disposed[1].state == 1,
        "removed actor did not clean up once with its final props/state")
    lifecycle:render(DisposableActor {
        key = "one", address = DisposableAddress, id = "remounted",
    })
    lifecycle:unmount()
    assert(#disposed == 2 and disposed[2].id == "remounted"
            and disposed[2].state == 0,
        "Host unmount did not clean up the fresh actor exactly once")

    disposed = {}
    local failing = support.host { width = 540, height = 960 }
    failing:mount(Frog.Column {
        DisposableActor { key = "fail", id = "fail", failCleanup = true },
        DisposableActor { key = "safe", id = "safe" },
    })
    expectFailure("terminal actor cleanup", function()
        failing:render(Frog.Box {
            testId = "cleanup-committed", width = 1, height = 1,
        })
    end, "intentional unmount failure")
    assert(#disposed == 2 and disposed[1].id == "fail"
            and disposed[2].id == "safe"
            and support.find(failing:tree(), "cleanup-committed"),
        "cleanup failure skipped a sibling or rolled back committed removal")
    assert(failing:inspectionTree().fault,
        "committed actor cleanup failure did not fault the Host")
    failing:unmount()
end

return check
