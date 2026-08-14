-- Focused contract for FrogUI's ordinary actor-local semantic scheduler.
-- It proves explicit ownership, full layout, retained Hooks, views, portals,
-- event batches, rollback, and separate semantic/allocation measurements.

local Frog = require("frogui")
local support = require("tests.support")

local check = {}

local SchedulerLifecycleProbe = Frog.component(
    "ActorLocalCheckSchedulerLifecycleProbe", function()
        return Frog.Box { width = 10, height = 10 }
    end)

local Grow = Frog.action("ActorLocalCheck.Grow")
local localCounts = {}
local dynamicRef
local resourceCreates, resourceCleanups, frameCalls = 0, 0, 0

local function counted(name)
    localCounts[name] = (localCounts[name] or 0) + 1
end

local DynamicLeaf = Frog.component("ActorLocalCheckDynamicLeaf",
    function(props)
        counted("dynamicLeaf")
        return Frog.Box {
            testId = "actor-local-dynamic-leaf",
            ref = props.anchor,
            width = "100%",
            height = 20,
        }
    end)

local NestedLeaf = Frog.component("ActorLocalCheckNestedLeaf", function()
    counted("nestedLeaf")
    return Frog.Box {
        testId = "actor-local-nested-leaf",
        width = 10,
        height = 10,
    }
end)

local NestedActor = Frog.actor("ActorLocalCheckNestedActor", {
    initial = 0,
    actions = {},
    render = function()
        counted("nestedActor")
        return NestedLeaf {}
    end,
})

local DynamicActor = Frog.actor("ActorLocalCheckDynamicActor", {
    initial = { width = 30 },
    actions = {
        [Grow] = function(state)
            return { width = state.width + 50 }
        end,
    },
    render = function(_, state)
        counted("dynamicActor")
        local anchor = Frog.useRef()
        dynamicRef = anchor
        return Frog.Column {
            testId = "actor-local-dynamic",
            width = state.width,
            height = 40,
            gap = 2,
            DynamicLeaf { anchor = anchor },
            NestedActor { key = "nested" },
        }
    end,
})
local DynamicAddress = DynamicActor:address("actor-local-dynamic")

local StaticLeaf = Frog.component("ActorLocalCheckStaticLeaf", function()
    counted("staticLeaf")
    return Frog.Box {
        testId = "actor-local-static-leaf",
        width = 20,
        height = 20,
    }
end)

local StaticActor = Frog.actor("ActorLocalCheckStaticActor", {
    initial = 0,
    actions = {},
    render = function()
        counted("staticActor")
        Frog.useResource(function()
            resourceCreates = resourceCreates + 1
            return {}, function()
                resourceCleanups = resourceCleanups + 1
            end
        end)
        Frog.useFrame(function() frameCalls = frameCalls + 1 end)
        return StaticLeaf {}
    end,
})

local LocalRoot = Frog.component("ActorLocalCheckRoot", function()
    counted("root")
    return Frog.Row {
        testId = "actor-local-root",
        width = 220,
        height = 80,
        gap = 5,
        align = "start",
        DynamicActor {
            key = "dynamic",
            address = DynamicAddress,
        },
        StaticActor { key = "static" },
    }
end)

local function localHost(width, height)
    local host = support.host {
        width = width or 220,
        height = height or 120,
        diagnostics = true,
    }
    return host
end

-- Proves one changed parent actor refreshes its whole local component/actor
-- subtree while a sibling actor, resource, frame, and component remain intact.
local function localSiblingLayoutAndHooks()
    localCounts = {}
    dynamicRef = nil
    resourceCreates, resourceCleanups, frameCalls = 0, 0, 0
    local host = localHost()
    host:mount(LocalRoot {})
    local firstRef = assert(dynamicRef, "actor-local mount omitted its ref")
    local staticBefore = assert(support.find(host:tree(),
        "actor-local-static-leaf")).layout.x
    assert(resourceCreates == 1 and resourceCleanups == 0,
        "actor-local mount created the wrong resource lifetime")

    Frog.send(DynamicAddress, Grow {})
    local report = host:_readActorLocal()
    assert(report.last.full == false and report.last.dirtyActors == 1,
        "typed action did not select one local actor boundary")
    assert(report.last.renderedOwners == 4
            and report.last.reusedOwners == 3,
        "actor-local candidate rendered or retained the wrong owners")
    assert(localCounts.root == 1
            and localCounts.dynamicActor == 2
            and localCounts.dynamicLeaf == 2
            and localCounts.nestedActor == 2
            and localCounts.nestedLeaf == 2
            and localCounts.staticActor == 1
            and localCounts.staticLeaf == 1,
        "changed actor did not preserve the expected semantic boundary")

    local dynamic = assert(support.find(host:tree(),
        "actor-local-dynamic"))
    local staticAfter = assert(support.find(host:tree(),
        "actor-local-static-leaf")).layout.x
    support.near(dynamic.layout.width, 80, "actor-local changed width")
    support.near(staticAfter - staticBefore, 50,
        "actor-local sibling reflow")
    assert(dynamicRef == firstRef and firstRef.current,
        "actor-local render replaced its retained ref")
    support.near(firstRef.current.width, 80,
        "actor-local ref did not publish fresh layout")
    assert(resourceCreates == 1 and resourceCleanups == 0,
        "untouched actor recreated or disposed its resource")

    host:update(1 / 60)
    assert(frameCalls == 1,
        "untouched actor lost its retained frame subscription")

    host:resize(400, 200)
    report = host:_readActorLocal()
    assert(report.last.full == true
            and report.last.renderedOwners == 7
            and report.last.reusedOwners == 0,
        "resize did not take the conservative full-render fallback")
    assert(dynamicRef == firstRef and resourceCreates == 1,
        "full resize fallback replaced retained Hooks")

    host:refreshTheme(host.theme, host.assets, LocalRoot {})
    report = host:_readActorLocal()
    assert(report.last.full == true
            and report.last.renderedOwners == 7
            and report.last.reusedOwners == 0,
        "theme/hot-reload path did not take the full-render fallback")
    assert(dynamicRef == firstRef and resourceCreates == 1,
        "theme/hot-reload fallback replaced retained Hooks")

    host:unmount()
    assert(firstRef.current == nil and resourceCleanups == 1,
        "actor-local unmount did not clear Hooks exactly once")
    assert(host:_readActorLocal().liveOwners == 0,
        "successful unmount retained actor-local descriptions")
end

local ObserveBump = Frog.action("ActorLocalCheck.ObserveBump")
local observedRenders, viewRenders = 0, 0

local ObservedActor = Frog.actor("ActorLocalCheckObservedActor", {
    initial = 0,
    actions = {
        [ObserveBump] = function(state) return state + 1 end,
    },
    render = function(_, state)
        observedRenders = observedRenders + 1
        return Frog.Text {
            testId = "actor-local-observed",
            tostring(state),
        }
    end,
})
local ObservedAddress = ObservedActor:address("actor-local-observed")
local ObservedView = ObservedActor:view("ActorLocalCheckObservedView",
    function(_, state, _, status)
        viewRenders = viewRenders + 1
        return Frog.Text {
            testId = "actor-local-view",
            status.mounted and tostring(state) or "missing",
        }
    end)

local ObservedRoot = Frog.component("ActorLocalCheckObservedRoot", function()
    return Frog.Column {
        ObservedActor { address = ObservedAddress },
        ObservedView { target = ObservedAddress },
    }
end)

local ToggleObservedMount = Frog.action("ActorLocalCheck.ToggleObservedMount")
local ObservedMountOwner = Frog.actor("ActorLocalCheckObservedMountOwner", {
    initial = true,
    actions = {
        [ToggleObservedMount] = function(state) return not state end,
    },
    render = function(_, mounted)
        return Frog.Column {
            mounted and ObservedActor { address = ObservedAddress } or nil,
        }
    end,
})
local ObservedMountAddress =
    ObservedMountOwner:address("actor-local-observed-mount")
local ObservedMountRoot = Frog.component("ActorLocalCheckObservedMountRoot",
    function()
        return Frog.Column {
            ObservedMountOwner { address = ObservedMountAddress },
            ObservedView { target = ObservedAddress },
        }
    end)

-- Proves an addressed view follows the changed actor automatically without
-- turning the containing root component into a manual dependency owner.
local function addressedViewFollowsActor()
    observedRenders, viewRenders = 0, 0
    local host = localHost()
    host:mount(ObservedRoot {})
    Frog.send(ObservedAddress, ObserveBump {})
    local report = host:_readActorLocal()
    assert(report.last.dirtyActors == 1
            and report.last.renderedOwners == 2
            and report.last.reusedOwners == 1,
        "addressed view did not join its changed actor boundary")
    assert(observedRenders == 2 and viewRenders == 2,
        "addressed actor/view callback cadence is wrong")
    assert(assert(support.find(host:tree(), "actor-local-view")).props.text
            == "1", "addressed view retained stale actor state")
    host:unmount()

    observedRenders, viewRenders = 0, 0
    host = localHost()
    host:mount(ObservedMountRoot {})
    Frog.send(ObservedMountAddress, ToggleObservedMount {})
    assert(assert(support.find(host:tree(), "actor-local-view")).props.text
            == "missing",
        "addressed view retained a removed target")
    report = host:_readActorLocal()
    assert(report.last.renderedOwners == 2
            and report.last.reusedOwners == 1,
        "target removal did not refresh only its owner and addressed view")
    Frog.send(ObservedMountAddress, ToggleObservedMount {})
    assert(assert(support.find(host:tree(), "actor-local-view")).props.text
            == "0", "addressed view did not observe a remounted target")
    report = host:_readActorLocal()
    assert(report.last.renderedOwners == 3
            and report.last.reusedOwners == 1,
        "target remount did not refresh its exact semantic owners")
    host:unmount()
end

local Broadcast = Frog.event("ActorLocalCheck.Broadcast")
local broadcastRenders = { a = 0, b = 0 }

local BroadcastActor = Frog.actor("ActorLocalCheckBroadcastActor", {
    initial = 0,
    actions = {},
    reactions = {
        Frog.on(Broadcast) {
            transition = function(state) return state + 1 end,
        },
    },
    render = function(props, state)
        broadcastRenders[props.id] = broadcastRenders[props.id] + 1
        return Frog.Text {
            testId = "actor-local-broadcast-" .. props.id,
            tostring(state),
        }
    end,
})
local BroadcastA = BroadcastActor:address("actor-local-broadcast-a")
local BroadcastB = BroadcastActor:address("actor-local-broadcast-b")
local BroadcastRoot = Frog.component("ActorLocalCheckBroadcastRoot", function()
    return Frog.Column {
        BroadcastActor { key = "a", id = "a", address = BroadcastA },
        BroadcastActor { key = "b", id = "b", address = BroadcastB },
    }
end)

local NestedBroadcast = Frog.event("ActorLocalCheck.NestedBroadcast")
local nestedBroadcastRenders = { parent = 0, child = 0 }

local NestedBroadcastChild = Frog.actor(
    "ActorLocalCheckNestedBroadcastChild", {
        initial = 0,
        actions = {},
        reactions = {
            Frog.on(NestedBroadcast) {
                transition = function(state) return state + 1 end,
            },
        },
        render = function(_, state)
            nestedBroadcastRenders.child = nestedBroadcastRenders.child + 1
            return Frog.Text { tostring(state) }
        end,
    })

local NestedBroadcastParent = Frog.actor(
    "ActorLocalCheckNestedBroadcastParent", {
        initial = 0,
        actions = {},
        reactions = {
            Frog.on(NestedBroadcast) {
                transition = function(state) return state + 1 end,
            },
        },
        render = function(_, state)
            nestedBroadcastRenders.parent = nestedBroadcastRenders.parent + 1
            return Frog.Column {
                Frog.Text { tostring(state) },
                NestedBroadcastChild {},
            }
        end,
    })

local NestedBroadcastRoot = Frog.component(
    "ActorLocalCheckNestedBroadcastRoot", function()
        return NestedBroadcastParent {}
    end)

-- Proves one breadth-first event can select several exact actor boundaries and
-- still reconcile only once after the complete delivery queue drains.
local function eventSelectsSeveralActors()
    broadcastRenders = { a = 0, b = 0 }
    local host = localHost()
    host:mount(BroadcastRoot {})
    Frog.emit(Broadcast {})
    local report = host:_readActorLocal()
    assert(report.last.dirtyActors == 2
            and report.last.renderedOwners == 2
            and report.last.reusedOwners == 1,
        "broadcast did not select two exact actor boundaries")
    assert(broadcastRenders.a == 2 and broadcastRenders.b == 2,
        "broadcast actor callbacks did not run exactly once")
    local trace = host:messageTrace()
    assert(#trace == 1 and trace[1].reconciled,
        "broadcast actor-local work did not commit once at queue tail")
    host:unmount()

    nestedBroadcastRenders = { parent = 0, child = 0 }
    host = localHost()
    host:mount(NestedBroadcastRoot {})
    Frog.emit(NestedBroadcast {})
    report = host:_readActorLocal()
    assert(report.last.dirtyActors == 2
            and report.last.renderedOwners == 2
            and report.last.reusedOwners == 1,
        "nested dirty actors did not collapse to one parent traversal")
    assert(nestedBroadcastRenders.parent == 2
            and nestedBroadcastRenders.child == 2,
        "nested dirty actor rendered more than once in one event batch")
    host:unmount()
end

local ToggleModal = Frog.action("ActorLocalCheck.ToggleModal")
local ModalActor = Frog.actor("ActorLocalCheckModalActor", {
    initial = false,
    actions = {
        [ToggleModal] = function(state) return not state end,
    },
    render = function(_, open)
        if not open then return nil end
        return Frog.Modal {
            testId = "actor-local-modal",
            dismiss = "none",
            Frog.Box { width = 80, height = 50 },
        }
    end,
})
local ModalAddress = ModalActor:address("actor-local-modal")
local PortalRoot = Frog.component("ActorLocalCheckPortalRoot", function()
    return Frog.Overlay {
        width = 220,
        height = 120,
        ModalActor { address = ModalAddress },
        Frog.Chrome {
            testId = "actor-local-chrome",
            Frog.Box { width = 20, height = 20 },
        },
    }
end)

-- Proves topology changes inside one actor still rebuild global Modal/Chrome
-- plane ownership from the complete fresh primitive tree.
local function portalOrderRemainsGlobal()
    local host = localHost()
    host:mount(PortalRoot {})
    assert(#host._modals == 0 and host._chrome,
        "portal proof did not mount its baseline Chrome")
    Frog.send(ModalAddress, ToggleModal {})
    assert(#host._modals == 1 and host._modal and host._chrome,
        "actor-local open lost Modal/Chrome ownership")
    assert(host._modal.identity
            == assert(support.find(host:tree(), "actor-local-modal")).identity,
        "actor-local Modal plane points at stale geometry")
    Frog.send(ModalAddress, ToggleModal {})
    assert(#host._modals == 0 and host._modal == nil and host._chrome,
        "actor-local close left stale Modal ownership")
    host:unmount()
end

local Break = Frog.action("ActorLocalCheck.Break")
local failedCreates, failedCleanups = 0, 0

local FailingResource = Frog.component("ActorLocalCheckFailingResource",
    function()
        Frog.useResource(function()
            failedCreates = failedCreates + 1
            return {}, function() failedCleanups = failedCleanups + 1 end
        end)
        return Frog.Box { width = "invalid-width", height = 10 }
    end)

local FragileActor = Frog.actor("ActorLocalCheckFragileActor", {
    initial = false,
    actions = {
        [Break] = function() return true end,
    },
    render = function(_, broken)
        if broken then return FailingResource {} end
        return Frog.Box {
            testId = "actor-local-last-good",
            width = 20,
            height = 20,
        }
    end,
})
local FragileAddress = FragileActor:address("actor-local-fragile")

-- Proves rejected local candidates preserve the last committed tree/cache and
-- clean only the resource created by the failed owner subtree.
local function rejectedCandidateIsAtomic()
    failedCreates, failedCleanups = 0, 0
    local host = localHost()
    local tree = support.mount(host, FragileActor { address = FragileAddress })
    local lastGood = assert(support.find(tree, "actor-local-last-good"))
    local sent, failure = pcall(Frog.send, FragileAddress, Break {})
    assert(not sent and tostring(failure):find("width must be", 1, true),
        "actor-local invalid candidate did not fail loudly")
    assert(host:tree() == tree
            and support.find(host:tree(), "actor-local-last-good") == lastGood,
        "actor-local failure replaced the last committed tree")
    local report = host:_readActorLocal()
    assert(report.totals.candidates == 1
            and report.totals.localCandidates == 0
            and report.last.full == true,
        "failed actor-local candidate published its semantic cache")
    assert(failedCreates == 1 and failedCleanups == 1,
        "failed actor-local candidate leaked its new resource")
    assert(rawget(host, "_actorLocalDirtyActors") == nil,
        "failed actor-local candidate leaked its dirty batch")
    host:unmount()
end

local MeasureBump = Frog.action("ActorLocalCheck.MeasureBump")
local measureRenders = 0

local MeasureLeaf = Frog.component("ActorLocalCheckMeasureLeaf",
    function(props)
        measureRenders = measureRenders + 1
        return Frog.Box {
            width = props.width,
            height = 4,
        }
    end)

local MeasureStatic = Frog.component("ActorLocalCheckMeasureStatic",
    function()
        measureRenders = measureRenders + 1
        local column = { width = 40, height = 320 }
        for index = 1, 80 do
            column[#column + 1] = MeasureLeaf {
                key = index,
                width = 20 + index % 3,
            }
        end
        return Frog.Column(column)
    end)

local MeasureActor = Frog.actor("ActorLocalCheckMeasureActor", {
    initial = 0,
    actions = {
        [MeasureBump] = function(state) return state + 1 end,
    },
    render = function(_, state)
        measureRenders = measureRenders + 1
        return Frog.Box { width = 20 + state % 2, height = 20 }
    end,
})
local MeasureAddress = MeasureActor:address("actor-local-measure")

local MeasureRoot = Frog.component("ActorLocalCheckMeasureRoot", function()
    measureRenders = measureRenders + 1
    return Frog.Row {
        width = 220,
        height = 360,
        MeasureActor { address = MeasureAddress },
        MeasureStatic {},
    }
end)

local function allocatedDuring(callback)
    collectgarbage("collect")
    collectgarbage("stop")
    local before = collectgarbage("count")
    local ok, failure = pcall(callback)
    local allocated = collectgarbage("count") - before
    collectgarbage("restart")
    if not ok then error(failure, 0) end
    return allocated
end

local function measureCandidate(localEnabled, iterations)
    measureRenders = 0
    local host = support.host {
        width = 220,
        height = 400,
        diagnostics = true,
    }
    if not localEnabled then host:_useCompleteSemanticRenders() end
    host:mount(MeasureRoot {})
    measureRenders = 0
    local allocated = allocatedDuring(function()
        for _ = 1, iterations do
            Frog.send(MeasureAddress, MeasureBump {})
        end
    end)
    local renders = measureRenders
    host:unmount()
    collectgarbage("collect")
    return allocated / iterations, renders / iterations
end

-- Measures semantic callbacks and allocation independently on the same large
-- generic tree. The synthetic comparison is a feasibility proof, not application-specific work
-- acceptance evidence or a production performance threshold.
local function semanticAndAllocationMeasurement()
    local iterations = 8
    local fullKB, fullRenders = measureCandidate(false, iterations)
    local localKB, localRenders = measureCandidate(true, iterations)
    assert(fullRenders == 83 and localRenders == 1,
        "actor-local semantic measurement has the wrong callback cadence")
    assert(localKB < fullKB,
        "actor-local scheduler did not reduce synthetic allocation")
    check.lastMeasurement = {
        iterations = iterations,
        fullKBPerUpdate = fullKB,
        localKBPerUpdate = localKB,
        fullRendersPerUpdate = fullRenders,
        localRendersPerUpdate = localRenders,
        allocationReduction = 1 - localKB / fullKB,
    }
    print(("FrogUI actor-local synthetic: callbacks %.0f -> %.0f, "
        .. "allocation %.3f -> %.3f KB/update (%.2f%% saved)")
        :format(fullRenders, localRenders, fullKB, localKB,
            check.lastMeasurement.allocationReduction * 100))
end

local function ordinaryHostOwnsScheduler()
    local host = support.host { width = 80, height = 80, diagnostics = true }
    assert(rawget(host, "_actorLocal") and host._actorLocalEnabled,
        "ordinary FrogUI Host omitted actor-local scheduling")
    host:mount(SchedulerLifecycleProbe {})
    assert(host:_readActorLocal().liveOwners == 1,
        "ordinary mount did not retain its semantic owner")
    host:unmount()
    assert(rawget(host, "_actorLocal") and host._actorLocalEnabled
            and host:_readActorLocal().liveOwners == 0,
        "ordinary unmount did not reset reusable actor-local scheduling")
    host:mount(SchedulerLifecycleProbe {})
    assert(host:_readActorLocal().liveOwners == 1,
        "same Host did not reuse actor-local scheduling after remount")
    host:unmount()
end

function check.run()
    ordinaryHostOwnsScheduler()
    localSiblingLayoutAndHooks()
    addressedViewFollowsActor()
    eventSelectsSeveralActors()
    portalOrderRemainsGlobal()
    rejectedCandidateIsAtomic()
    semanticAndAllocationMeasurement()
    return true
end

return check
