-- Adversarial public-contract checks for mounted resources and frame callbacks.
-- The stories use generic counters so framework behavior stays domain-neutral.

local Frog = require("frogui")
local support = require("tests.support")

local check = {}

local Observed = Frog.event("ProcessCheck.Observed", function(event)
    assert(type(event.value) == "string",
        "Observed value must be a string")
end)

-- Requires a callback to fail with one actionable diagnostic fragment.
local function rejects(label, callback, fragment)
    local ok, err = pcall(callback)
    assert(not ok, label .. " unexpectedly succeeded")
    assert(tostring(err):find(fragment, 1, true),
        label .. " rejected for the wrong reason: " .. tostring(err))
end

-- Returns the inspection record for one visible test id.
local function inspectionEntry(host, testId)
    for _, entry in ipairs(host:inspectionTree().nodes) do
        if entry.testId == testId then return entry end
    end
    error("missing inspection entry " .. testId, 0)
end

local Added = Frog.action("ProcessCheck.Added", function(action)
    assert(type(action.amount) == "number", "Added amount must be numeric")
end)

local basicCreates = 0
local basicCleanups = 0
local basicRenders = 0
local basicResource
local frameOrder = {}

-- Owns one retained resource and two frame subscriptions that publish actions.
local BasicProcess = Frog.actor("ProcessCheckBasic", {
    initial = { total = 0 },
    actions = {
        [Added] = function(state, action)
            return { total = state.total + action.amount }
        end,
    },
    render = function(props, state, send)
        basicRenders = basicRenders + 1
        local process = Frog.useResource(function()
            basicCreates = basicCreates + 1
            local value = { elapsed = 0, serial = basicCreates }
            return value, function()
                basicCleanups = basicCleanups + 1
            end
        end)
        basicResource = process
        Frog.useFrame(function(dt)
            frameOrder[#frameOrder + 1] = "first"
            process.elapsed = process.elapsed + dt * props.multiplier
            send(Added { amount = 1 })
        end)
        Frog.useFrame(function()
            frameOrder[#frameOrder + 1] = "second"
            send(Added { amount = 1 })
        end)
        return Frog.Box {
            testId = "process-basic",
            width = 160,
            height = 60,
            Frog.Text("Total " .. state.total),
        }
    end,
})

-- Finds the process metadata attached to the BasicProcess visible root.
local function basicMetadata(host)
    local entry = inspectionEntry(host, "process-basic")
    for _, owner in ipairs(entry.processes or {}) do
        if owner.owner == "ProcessCheckBasic" then return owner end
    end
    error("F6 omitted ProcessCheckBasic lifecycle metadata", 0)
end

-- Proves stable ownership, callback replacement, batching, F6, and cleanup.
local function basicLifecycle(reducedMotion)
    basicCreates, basicCleanups, basicRenders = 0, 0, 0
    basicResource, frameOrder = nil, {}
    local host = support.host {
        width = 540,
        height = 960,
        reducedMotion = reducedMotion == true,
    }
    host:mount(BasicProcess { multiplier = 1 })
    local retained = assert(basicResource, "useResource returned no value")
    assert(basicCreates == 1 and basicRenders == 1,
        "mount did not create and render exactly once")

    local metadata = basicMetadata(host)
    assert(#metadata.hooks == 3,
        "F6 omitted resource or frame subscriptions")
    assert(metadata.hooks[1].kind == "useResource"
            and metadata.hooks[1].mounted,
        "F6 did not report the mounted resource")
    assert(metadata.hooks[2].kind == "useFrame"
            and metadata.hooks[3].kind == "useFrame",
        "F6 did not report both frame callbacks")
    local resourceId = metadata.hooks[1].id
    local firstFrameId = metadata.hooks[2].id

    host:update(0.25)
    support.near(retained.elapsed, 0.25,
        "frame callback resource elapsed")
    assert(table.concat(frameOrder, ",") == "first,second",
        "frame callbacks did not run in source order")
    assert(basicRenders == 2,
        "two frame publications did not batch into one render")
    assert(assert(support.findText(host:tree(), "Total 2")),
        "batched frame actions did not update actor state")

    host:render(BasicProcess { multiplier = 4 })
    assert(basicResource == retained and basicCreates == 1,
        "ordinary rerender replaced the mounted resource")
    metadata = basicMetadata(host)
    assert(metadata.hooks[1].id == resourceId
            and metadata.hooks[2].id == firstFrameId,
        "ordinary rerender replaced lifecycle identities")
    frameOrder = {}
    host:update(0.25)
    support.near(retained.elapsed, 1.25,
        "rerendered frame callback did not observe new props")
    assert(table.concat(frameOrder, ",") == "first,second",
        "rerender duplicated a frame subscription")

    host:resize(960, 540)
    assert(basicResource == retained and basicCreates == 1,
        "resize replaced the mounted resource")
    metadata = basicMetadata(host)
    assert(metadata.hooks[1].id == resourceId
            and metadata.hooks[2].id == firstFrameId,
        "resize replaced lifecycle identities")

    host:unmount()
    assert(basicCleanups == 1,
        "Host unmount did not clean the resource exactly once")
end

local candidateCreates = 0
local candidateCleanups = 0

-- Creates a resource in a subtree that may belong to a failed candidate.
local CandidateResource = Frog.component("ProcessCheckCandidateResource",
    function()
        local process = Frog.useResource(function()
            candidateCreates = candidateCreates + 1
            return { serial = candidateCreates }, function()
                candidateCleanups = candidateCleanups + 1
            end
        end)
        return Frog.Box {
            testId = "candidate-resource",
            width = 40,
            height = 30,
            Frog.Text(tostring(process.serial)),
        }
    end)

-- Throws after a sibling has already created its candidate resource.
local CandidateFailure = Frog.component("ProcessCheckCandidateFailure",
    function()
        error("intentional candidate failure")
    end)

-- Adds or removes the candidate resource without changing the root owner.
local CandidateRoot = Frog.component("ProcessCheckCandidateRoot", function(props)
    return Frog.Column {
        testId = "candidate-root",
        props.show and CandidateResource {} or nil,
        props.fail and CandidateFailure {} or nil,
    }
end)

-- Proves a failed candidate cleans only its unpublished resource.
local function candidateAtomicity()
    candidateCreates, candidateCleanups = 0, 0
    local host = support.host { width = 120, height = 100 }
    host:mount(CandidateRoot {})
    rejects("candidate resource failure", function()
        host:render(CandidateRoot { show = true, fail = true })
    end, "intentional candidate failure")
    assert(candidateCreates == 1 and candidateCleanups == 1,
        "failed candidate did not dispose its unpublished resource")
    assert(not support.find(host:tree(), "candidate-resource"),
        "failed candidate replaced the committed tree")

    host:render(CandidateRoot { show = true })
    local entry = inspectionEntry(host, "candidate-resource")
    local metadata = assert(entry.processes and entry.processes[1],
        "candidate resource omitted process metadata")
    assert(metadata.hooks[1].mounted,
        "successful candidate did not publish its mounted resource")
    assert(candidateCreates == 2 and candidateCleanups == 1,
        "candidate cleanup touched the later committed resource")
    host:unmount()
    assert(candidateCleanups == 2,
        "committed candidate resource did not clean on unmount")
end

-- Proves cleanup failure while rejecting a candidate is terminal: its
-- externally owned lifetime has already crossed a non-retryable boundary.
local function candidateCleanupFailureIsTerminal()
    local cleanupCalls = 0
    local FailingResource = Frog.component(
        "ProcessCheckFailingCandidateResource", function()
            Frog.useResource(function()
                return {}, function()
                    cleanupCalls = cleanupCalls + 1
                    error("intentional candidate cleanup failure")
                end
            end)
            return Frog.Box { width = 20, height = 20 }
        end)
    local FailingRoot = Frog.component(
        "ProcessCheckFailingCandidateRoot", function(props)
            return Frog.Column {
                props.fail and FailingResource {} or nil,
                props.fail and CandidateFailure {} or nil,
            }
        end)
    local host = support.host { width = 80, height = 60 }
    host:mount(FailingRoot {})
    rejects("candidate cleanup failure", function()
        host:render(FailingRoot { fail = true })
    end, "intentional candidate cleanup failure")
    assert(cleanupCalls == 1 and host:inspectionTree().fault,
        "candidate cleanup failure did not terminally fault its Host")
    rejects("faulted candidate cleanup Host mutation", function()
        host:render(FailingRoot {})
    end, "FrogUI Host faulted")
    assert(cleanupCalls == 1,
        "fault rejection retried failed candidate resource cleanup")
    host:unmount()
end

local outerCreates = 0
local outerCleanups = {}
local outerCurrent

-- Mounts one keyed resource so navigation-like replacement creates a lifetime.
local OuterResource = Frog.component("ProcessCheckOuterResource", function(props)
    local process = Frog.useResource(function()
        outerCreates = outerCreates + 1
        local value = { name = props.name, serial = outerCreates }
        return value, function()
            outerCleanups[value.serial] = (outerCleanups[value.serial] or 0) + 1
        end
    end)
    outerCurrent = process
    return Frog.Box {
        testId = "outer-resource",
        width = 80,
        height = 30,
        Frog.Text(process.name),
    }
end)

-- Gives an input callback a way to replace one keyed resource lifetime.
local OuterRoot = Frog.component("ProcessCheckOuterRoot", function(props)
    return Frog.Column {
        OuterResource { key = props.name, name = props.name },
        Frog.Button {
            testId = "outer-fail",
            width = 80,
            height = 30,
            shortcut = "f",
            onPress = props.onFail,
            Frog.Text "Fail",
        },
    }
end)

-- Proves a callback failure faults after its nested resource commit.
local function outerCallbackFault()
    outerCreates, outerCleanups, outerCurrent = 0, {}, nil
    local host = support.host { width = 140, height = 100 }
    local onFail
    onFail = function()
        host:render(OuterRoot { name = "new", onFail = onFail })
        assert(outerCurrent.name == "new",
            "nested render did not publish its candidate resource")
        error("intentional outer process failure")
    end
    host:mount(OuterRoot { name = "old", onFail = onFail })
    rejects("outer process fault", function()
        host:keyDown("f", "f", false)
    end, "intentional outer process failure")
    assert(host:inspectionTree().fault,
        "outer callback failure did not fault the Host")
    assert(assert(support.findText(host:tree(), "new"))
            and outerCurrent.name == "new",
        "faulted callback did not retain its committed resource tree")
    assert(outerCleanups[1] == 1 and outerCleanups[2] == nil,
        "faulted commit did not retire only the replaced resource")
    rejects("faulted process Host mutation", function()
        host:render(OuterRoot { name = "old", onFail = onFail })
    end, "FrogUI Host faulted")
    host:unmount()
    assert(outerCleanups[1] == 1 and outerCleanups[2] == 1,
        "faulted Host unmount did not clean each lifetime exactly once")
end

local hotCreates = 0
local hotCleanups = 0
local hotCurrent

-- Builds one hot-reloadable component render callback with the same hook shape.
local function hotRender(label)
    return function()
        local process = Frog.useResource(function()
            hotCreates = hotCreates + 1
            local value = { label = label, serial = hotCreates }
            return value, function() hotCleanups = hotCleanups + 1 end
        end)
        hotCurrent = process
        Frog.useFrame(function() end)
        return Frog.Box {
            testId = "hot-process",
            width = 80,
            height = 30,
            Frog.Text(process.label),
        }
    end
end

-- Proves a compatible owner callback replacement recreates only its resource.
local function hotReloadLifecycle()
    hotCreates, hotCleanups, hotCurrent = 0, 0, nil
    local firstRender = hotRender("first")
    local HotOwner = Frog.component("ProcessCheckHotOwner", firstRender)
    local host = support.host { width = 120, height = 80 }
    host:mount(HotOwner {})
    local first = hotCurrent
    local before = inspectionEntry(host, "hot-process").processes[1]
    HotOwner.render = hotRender("second")
    host:render(HotOwner {})
    local after = inspectionEntry(host, "hot-process").processes[1]
    assert(hotCurrent ~= first and hotCurrent.label == "second",
        "owner callback hot reload retained the old resource")
    assert(hotCreates == 2 and hotCleanups == 1,
        "hot reload did not create then clean exactly once")
    assert(after.hooks[1].id ~= before.hooks[1].id,
        "hot reload did not expose the replacement resource id")
    assert(after.hooks[2].id == before.hooks[2].id,
        "hot reload replaced the frame subscription identity")
    host:unmount()
    assert(hotCleanups == 2,
        "hot-reloaded resource did not clean on unmount")
end

local cleanupCalls = {}

-- Creates one resource whose cleanup may fail after recording its attempt.
local CleanupResource = Frog.component("ProcessCheckCleanupResource",
    function(props)
        Frog.useResource(function()
            return { name = props.name }, function()
                cleanupCalls[#cleanupCalls + 1] = props.name
                if props.fail then error("intentional cleanup failure") end
            end
        end)
        return Frog.Box { width = 20, height = 20 }
    end)

-- Removes two resources together to prove all cleanup attempts are terminal.
local CleanupRoot = Frog.component("ProcessCheckCleanupRoot", function(props)
    return Frog.Row {
        testId = "cleanup-root",
        props.show and CleanupResource {
            key = "first", name = "first", fail = true,
        } or nil,
        props.show and CleanupResource {
            key = "second", name = "second",
        } or nil,
    }
end)

-- Proves cleanup failure surfaces after commit and never blocks later cleanup.
local function cleanupFailureIsTerminal()
    cleanupCalls = {}
    local host = support.host { width = 100, height = 60 }
    host:mount(CleanupRoot { show = true })
    rejects("committed cleanup failure", function()
        host:render(CleanupRoot { show = false })
    end, "intentional cleanup failure")
    assert(table.concat(cleanupCalls, ",") == "first,second",
        "cleanup failure prevented a later resource cleanup")
    assert(#assert(support.find(host:tree(), "cleanup-root")).children == 0,
        "cleanup failure rolled back the committed removal")
    assert(host:inspectionTree().fault,
        "committed cleanup failure did not fault the Host")
    rejects("faulted cleanup Host mutation", function()
        host:render(CleanupRoot { show = false })
    end, "FrogUI Host faulted")
    assert(#cleanupCalls == 2,
        "fault rejection replayed a disposed resource cleanup")
    host:unmount()
    assert(#cleanupCalls == 2,
        "faulted Host unmount replayed a disposed resource cleanup")
end

local FailedFrame = Frog.action("ProcessCheck.FailedFrame")
local frameFailureResource
local frameFailureCleanups = 0

-- Emits one action and then fails after advancing its retained process.
local FrameFailureOwner = Frog.actor("ProcessCheckFrameFailure", {
    initial = "ready",
    actions = { [FailedFrame] = function() return "changed" end },
    render = function(props, state, send)
        local process = Frog.useResource(function()
            return { calls = 0 }, function()
                frameFailureCleanups = frameFailureCleanups + 1
            end
        end)
        frameFailureResource = process
        Frog.useFrame(function()
            process.calls = process.calls + 1
            send(FailedFrame {})
            if props.fail then error("intentional frame failure") end
        end)
        return Frog.Box {
            testId = "frame-failure",
            width = 90,
            height = 30,
            Frog.Text(state),
        }
    end,
})

-- Proves a failed frame faults without claiming to rewind process internals.
local function frameFailureFault()
    frameFailureCleanups = 0
    local host = support.host { width = 120, height = 80 }
    host:mount(FrameFailureOwner { fail = true })
    local retained = frameFailureResource
    rejects("frame callback failure", function()
        host:update(0.1)
    end, "intentional frame failure")
    assert(assert(support.findText(host:tree(), "ready")),
        "failed frame callback published its queued action")
    assert(retained.calls == 1,
        "FrogUI pretended it could roll back arbitrary resource internals")
    assert(host:inspectionTree().fault,
        "failed frame callback did not fault the Host")
    rejects("faulted frame Host render", function()
        host:render(FrameFailureOwner { fail = false })
    end, "FrogUI Host faulted")
    rejects("faulted frame Host update", function()
        host:update(0.1)
    end, "FrogUI Host faulted")
    assert(frameFailureResource == retained and frameFailureCleanups == 0,
        "faulting replaced or prematurely cleaned the mounted resource")
    host:unmount()
    assert(frameFailureCleanups == 1,
        "faulted frame resource did not clean exactly once on unmount")
end

local partitionResource

-- Accumulates the exact dt values delivered by the Host without UI messages.
local PartitionOwner = Frog.component("ProcessCheckPartitionOwner", function()
    local process = Frog.useResource(function()
        return { elapsed = 0, calls = 0 }, function() end
    end)
    partitionResource = process
    Frog.useFrame(function(dt)
        process.elapsed = process.elapsed + dt
        process.calls = process.calls + 1
    end)
    return Frog.Box { width = 20, height = 20 }
end)

-- Proves dt partitioning and reduced motion do not alter frame delivery.
local function frameClockContract()
    local function run(parts, reducedMotion)
        local host = support.host {
            width = 40,
            height = 40,
            reducedMotion = reducedMotion,
        }
        host:mount(PartitionOwner {})
        local retained = partitionResource
        for _, dt in ipairs(parts) do host:update(dt) end
        local elapsed, calls = retained.elapsed, retained.calls
        host:unmount()
        return elapsed, calls
    end

    local whole, wholeCalls = run({ 0.3 }, false)
    local partitioned, partitionCalls = run({ 0.1, 0.2 }, false)
    local reduced, reducedCalls = run({ 0.1, 0.2 }, true)
    support.near(whole, 0.3, "whole frame dt")
    support.near(partitioned, whole, "partitioned frame dt")
    support.near(reduced, whole, "reduced-motion frame dt")
    assert(wholeCalls == 1 and partitionCalls == 2 and reducedCalls == 2,
        "Host did not deliver exactly one callback per update")
end

-- Mounts one ordered listener whose callback is replaced by normal rerenders.
local EventOwner = Frog.component("ProcessCheckEventOwner", function(props)
    Frog.useEvent(Observed, function(event)
        props.log[#props.log + 1] = props.label .. ":" .. event.value
        event.value = "mutated delivery"
    end)
    return Frog.Box {
        testId = "event-owner-" .. props.label,
        width = 20,
        height = 20,
    }
end)

-- Keeps a lifecycle listener mounted even when its owner has no visible leaf.
local HiddenEventOwner = Frog.component(
    "ProcessCheckHiddenEventOwner", function(props)
        Frog.useEvent(Observed, function(event)
            props.log[#props.log + 1] = "hidden:" .. event.value
        end)
        return nil
    end)

-- Throws after both candidate listeners have rendered but before publication.
local EventCandidateFailure = Frog.component(
    "ProcessCheckEventCandidateFailure", function()
        error("intentional event-listener candidate failure")
    end)

-- Keeps two listeners in readable tree order around an optional failure.
local EventRoot = Frog.component("ProcessCheckEventRoot", function(props)
    return Frog.Row {
        EventOwner { key = "first", label = props.first,
            log = props.log },
        EventOwner { key = "second", label = "second",
            log = props.log },
        HiddenEventOwner { log = props.log },
        props.fail and EventCandidateFailure {} or nil,
    }
end)

-- Proves ordered detached delivery, callback replacement, candidate atomicity,
-- F6 provenance, and exact listener removal on route replacement.
local function eventListenerLifecycle()
    local log = {}
    local host = support.host { width = 100, height = 60 }
    host:mount(EventRoot { first = "old", log = log })
    local metadata = inspectionEntry(host, "event-owner-old").processes[1]
    assert(metadata.hooks[1].kind == "useEvent"
            and metadata.hooks[1].event == "ProcessCheck.Observed",
        "F6 omitted the mounted typed-event subscription")

    Frog.emit(Observed { value = "one" })
    assert(table.concat(log, ",") == "old:one,second:one,hidden:one",
        "useEvent delivery was unordered or shared a mutable payload")

    host:render(EventRoot { first = "new", log = log })
    Frog.emit(Observed { value = "two" })
    assert(table.concat(log, ",")
            == "old:one,second:one,hidden:one,new:two,second:two,hidden:two",
        "rerender duplicated a listener or retained its stale callback")

    rejects("event-listener candidate failure", function()
        host:render(EventRoot { first = "failed", log = log, fail = true })
    end, "intentional event-listener candidate failure")
    Frog.emit(Observed { value = "three" })
    assert(table.concat(log, ",")
            == "old:one,second:one,hidden:one,new:two,second:two,hidden:two,"
                .. "new:three,second:three,hidden:three",
        "failed candidate replaced the committed event listeners")

    host:render(Frog.Box { testId = "event-route-replacement",
        width = 20, height = 20 })
    local before = #log
    Frog.emit(Observed { value = "after" })
    assert(#log == before,
        "route replacement retained an unmounted event listener")
    host:unmount()
end

-- Proves malformed process hooks and direct frame reconciliation fail loudly.
local function validationContracts()
    rejects("useResource outside render", function()
        Frog.useResource(function() return {}, function() end end)
    end, "may only run while a component, actor, or view renders")
    rejects("useFrame outside render", function()
        Frog.useFrame(function() end)
    end, "may only run while a component, actor, or view renders")
    rejects("useEvent outside render", function()
        Frog.useEvent(Observed, function() end)
    end, "may only run while a component, actor, or view renders")

    local BadCreate = Frog.component("ProcessCheckBadCreate", function()
        Frog.useResource("not a function")
        return Frog.Box {}
    end)
    rejects("invalid create", function()
        support.host { width = 40, height = 40 }:mount(BadCreate {})
    end, "expects a create function")

    local MissingCleanup = Frog.component("ProcessCheckMissingCleanup",
        function()
            Frog.useResource(function() return {} end)
            return Frog.Box {}
        end)
    rejects("missing cleanup", function()
        support.host { width = 40, height = 40 }:mount(MissingCleanup {})
    end, "must return resource, cleanup")

    local BadFrame = Frog.component("ProcessCheckBadFrame", function()
        Frog.useFrame(false)
        return Frog.Box {}
    end)
    rejects("invalid frame", function()
        support.host { width = 40, height = 40 }:mount(BadFrame {})
    end, "expects a function")

    local BadEvent = Frog.component("ProcessCheckBadEvent", function()
        Frog.useEvent(Added, function() end)
        return Frog.Box {}
    end)
    rejects("invalid event token", function()
        support.host { width = 40, height = 40 }:mount(BadEvent {})
    end, "expects a Frog.event token")

    local BadEventCallback = Frog.component(
        "ProcessCheckBadEventCallback", function()
            Frog.useEvent(Observed, false)
            return Frog.Box {}
        end)
    rejects("invalid event callback", function()
        support.host { width = 40, height = 40 }:mount(BadEventCallback {})
    end, "expects a callback function")

    local ConditionalKind = Frog.component("ProcessCheckConditionalKind",
        function(props)
            if props.frame then Frog.useFrame(function() end)
            else
                Frog.useResource(function()
                    return {}, function() end
                end)
            end
            return Frog.Box {}
        end)
    local host = support.host { width = 40, height = 40 }
    host:mount(ConditionalKind {})
    rejects("process hook kind replacement", function()
        host:render(ConditionalKind { frame = true })
    end, "changed hook 1 from useResource to useFrame")
    host:unmount()

    local DirectRender
    DirectRender = Frog.component("ProcessCheckDirectRender", function()
        Frog.useFrame(function() host:render(DirectRender {}) end)
        return Frog.Box {}
    end)
    host = support.host { width = 40, height = 40 }
    host:mount(DirectRender {})
    rejects("direct render from frame", function()
        host:update(0.1)
    end, "direct render is forbidden")
    host:unmount()
end

function check.run()
    basicLifecycle(false)
    basicLifecycle(true)
    candidateAtomicity()
    candidateCleanupFailureIsTerminal()
    outerCallbackFault()
    hotReloadLifecycle()
    cleanupFailureIsTerminal()
    frameFailureFault()
    frameClockContract()
    eventListenerLifecycle()
    validationContracts()
end

return check
