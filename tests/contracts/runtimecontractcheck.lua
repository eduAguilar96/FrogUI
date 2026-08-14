-- Adversarial M2 runtime checks that do not belong to any visual story.

local Frog = require("frogui")
local support = require("tests.support")

local check = {}

local function expectFailure(label, callback, pattern)
    local ok, err = pcall(callback)
    assert(not ok, label .. " unexpectedly succeeded")
    assert(tostring(err):find(pattern, 1, true),
        label .. " failed unclearly: " .. tostring(err))
end

local function press(host, testId)
    local button = assert(support.find(host:tree(), testId), testId)
    local x, y = support.center(button)
    local scale = host:viewport().scale
    assert(host:pointerDown(x * scale, y * scale, "mouse", 1),
        testId .. " pointer down")
    assert(host:pointerUp(x * scale, y * scale, "mouse", 1),
        testId .. " pointer up")
end

local function definitionFailures()
    local Change = Frog.action("Contract.Change")
    expectFailure("direct Frog.go action handler", function()
        Frog.actor("BadDirectGo", {
            initial = "a",
            actions = { [Change] = Frog.go("b") },
            render = function() return nil end,
        })
    end, "not direct Frog.go")
    expectFailure("non-scalar action-map key", function()
        Frog.actor("BadMapKey", {
            initial = "a",
            actions = { [Change] = { [{}] = "b" } },
            render = function() return nil end,
        })
    end, "keys must be scalar")
    expectFailure("table action-map value", function()
        Frog.actor("BadMapValue", {
            initial = "a",
            actions = { [Change] = { a = { nested = true } } },
            render = function() return nil end,
        })
    end, "values must be scalar")
    expectFailure("table initial with scalar map", function()
        Frog.actor("BadTableMap", {
            initial = { mode = "a" },
            actions = { [Change] = { a = "b" } },
            render = function() return nil end,
        })
    end, "uses table state")

    local CycleEvent = Frog.event("contract.cycle")
    local cycle = {}
    cycle.self = cycle
    expectFailure("cyclic reaction match", function()
        Frog.on(CycleEvent) { match = cycle, transition = Frog.go("done") }
    end, "may not contain cycles")

    -- Returns invalid initial state so mount-time validation must reject it.
    local BadInitial = Frog.actor("BadInitial", {
        initial = function() return function() end end,
        actions = {},
        render = function() return nil end,
    })
    local initialHost = support.host { width = 540, height = 960 }
    expectFailure("invalid initial state return", function()
        initialHost:mount(Frog.Box { BadInitial {} })
    end, "initial state")
end

local function messageOwnershipAndFaults()
    local Captured = Frog.event("contract.captured", function(event)
        assert(type(event.value) == "string", "value must be a string")
        assert(type(event.kind) == "string", "kind must be a string")
    end)
    local MutateMessage = Frog.event("contract.mutate-message")
    local MutateProps = Frog.event("contract.mutate-props")
    local Loop = Frog.event("contract.loop")
    local Plain = Frog.event("contract.plain")
    local EmitBoundPlain = Frog.event("contract.emit-bound-plain")
    local Invalid = Frog.action("Contract.InvalidReturn")

    local receiverRenders = 0
    local observedCanonicalMessage = false
    -- Exercises action validation, reducer returns, reactions, and render count.
    local Receiver = Frog.actor("ContractReceiver", {
        initial = function() return { value = "initial", count = 0 } end,
        actions = {
            [Invalid] = function() return function() end end,
        },
        reactions = {
            Frog.on(Captured) {
                match = { kind = Frog.oneOf({ "kept", "also-kept" }) },
                transition = function(state, event)
                    return { value = event.value, count = state.count + 1 }
                end,
            },
            Frog.on(MutateMessage) {
                transition = function(state, event)
                    event.changed = true
                    return state
                end,
            },
            Frog.on(MutateProps) {
                transition = function(state, _, props)
                    props.config.value = "changed"
                    return state
                end,
            },
        },
        render = function(_, state)
            receiverRenders = receiverRenders + 1
            return Frog.Text {
                testId = "contract-value",
                state.value .. ":" .. state.count,
            }
        end,
    })
    local ReceiverAddress = Receiver:address("contract-receiver")
    -- Runs after Receiver and proves one reducer cannot corrupt the canonical
    -- event record delivered to a later broadcast recipient.
    local MessageObserver = Frog.actor("ContractMessageObserver", {
        initial = "waiting",
        actions = {},
        reactions = {
            Frog.on(MutateMessage) {
                transition = function(state, event)
                    assert(event.changed == nil,
                        "earlier reducer corrupted canonical broadcast data")
                    observedCanonicalMessage = true
                    return state
                end,
            },
        },
        render = function() return nil end,
    })
    -- Re-emits its event indefinitely so the runtime loop limit can stop it.
    local LoopActor = Frog.actor("ContractLoop", {
        initial = "idle",
        actions = {},
        reactions = {
            Frog.on(Loop) {
                transition = Frog.go("idle", { emit = Loop {} }),
            },
        },
        render = function() return nil end,
    })
    local LoopAddress = LoopActor:address("contract-loop")
    -- Resolves a prop binding before the same plain-message snapshot boundary
    -- used by direct Frog.send/Frog.emit delivery.
    local BindingProbe = Frog.actor("ContractBindingProbe", {
        initial = "idle",
        actions = {},
        reactions = {
            Frog.on(EmitBoundPlain) {
                transition = Frog.go("done", {
                    emit = Plain { value = Frog.prop("boundValue") },
                }),
            },
        },
        render = function() return nil end,
    })
    local config = { value = "clean" }
    local host = support.host {
        width = 540,
        height = 960,
        messageTraceLimit = 3,
        messageLoopLimit = 3,
    }
    host:mount(Frog.Column {
        Frog.Button {
            testId = "snapshot-message",
            onPress = function()
                local fact = Captured { value = "before", kind = "kept" }
                Frog.emit(fact)
                fact.value = "after"
            end,
            Frog.Text "Snapshot",
        },
        Frog.Button {
            testId = "batch-messages",
            onPress = function()
                Frog.emit(Captured { value = "batch-one", kind = "kept" })
                Frog.emit(Captured { value = "batch-two", kind = "also-kept" })
            end,
            Frog.Text "Batch",
        },
        Frog.Button {
            testId = "invalid-return",
            onPress = function() Frog.send(ReceiverAddress, Invalid {}) end,
            Frog.Text "Invalid",
        },
        Receiver { address = ReceiverAddress, config = config },
        MessageObserver {},
        LoopActor { address = LoopAddress },
    })

    for _, case in ipairs({
        { "message function", function() end, "plain data" },
        { "message nonfinite", 0 / 0, "non-finite" },
        { "message metatable", setmetatable({}, {}), "plain data" },
        { "message unsupported key", { [{}] = true }, "keys must be scalar" },
    }) do
        expectFailure(case[1], function()
            Frog.emit(Plain { value = case[2] })
        end, case[3])
    end
    local payloadCycle = {}
    payloadCycle.self = payloadCycle
    expectFailure("message cycle", function()
        Frog.emit(Plain { value = payloadCycle })
    end, "acyclic")
    Frog.emit(Captured { value = "ignored", kind = "other" })
    assert(assert(support.find(host:tree(), "contract-value")).props.text
            == "initial:0", "Frog.oneOf accepted an unlisted value")
    press(host, "snapshot-message")
    assert(assert(support.find(host:tree(), "contract-value")).props.text
            == "before:1", "delivery observed a record mutation after enqueue")
    local beforeBatchRenders = receiverRenders
    press(host, "batch-messages")
    assert(assert(support.find(host:tree(), "contract-value")).props.text
            == "batch-two:3" and receiverRenders == beforeBatchRenders + 1,
        "one callback message batch did not reconcile exactly once")

    local trace = host:messageTrace()
    local delivered = trace[#trace]
    assert(delivered.token == "contract.captured"
            and type(delivered.token) == "string",
        "trace token is not the exact public string shape")
    assert(delivered.source and delivered.source.token
            and delivered.source.token.path and delivered.source.origin
            and delivered.source.origin.path,
        "trace omitted token or callback source")

    Frog.emit(MutateMessage {})
    Frog.emit(MutateProps {})
    assert(observedCanonicalMessage,
        "later recipient did not receive the canonical broadcast record")
    assert(config.value == "changed",
        "runtime unexpectedly added recursive props purity policing")

    Frog.emit(Captured { value = "two", kind = "also-kept" })
    Frog.emit(Captured { value = "three", kind = "kept" })
    Frog.emit(Captured { value = "four", kind = "kept" })
    local capped = host:messageTrace()
    assert(#capped == 3 and capped[1].sequence + 1 == capped[2].sequence
            and capped[2].sequence + 1 == capped[3].sequence,
        "message trace did not retain an ordered bounded tail")
    expectFailure("bounded message loop", function()
        Frog.emit(Loop {})
    end, "loop exceeded")
    local fault = host:inspectionTree().fault
    assert(fault and fault.message:find("loop exceeded", 1, true),
        "message-loop failure did not fault the Host")
    expectFailure("faulted Host message rejection", function()
        Frog.emit(Captured { value = "after-fault", kind = "kept" })
    end, "Host faulted")
    host:unmount()

    local invalidHost = support.host { width = 540, height = 960 }
    invalidHost:mount(Frog.Column {
        Frog.Button {
            testId = "invalid-return",
            onPress = function() Frog.send(ReceiverAddress, Invalid {}) end,
            Frog.Text "Invalid",
        },
        Receiver { address = ReceiverAddress, config = {} },
    })
    expectFailure("invalid reducer state return", function()
        press(invalidHost, "invalid-return")
    end, "transition result")
    assert(invalidHost:inspectionTree().fault,
        "invalid reducer return did not fault the Host")
    expectFailure("faulted Host render rejection", function()
        invalidHost:render(Frog.Box { width = 1, height = 1 })
    end, "Host faulted")
    invalidHost:unmount()

    local bindingHost = support.host { width = 540, height = 960 }
    bindingHost:mount(Frog.Box {
        BindingProbe { boundValue = function() end },
    })
    expectFailure("resolved binding plain data", function()
        Frog.emit(EmitBoundPlain {})
    end, "plain")
    assert(bindingHost:inspectionTree().fault,
        "emitted-message reconciliation failure did not fault the Host")
    bindingHost:unmount()
end

local function actorTypeChange()
    local Increment = Frog.action("TypeA.Increment")
    -- Owns state before the same keyed position changes to another actor type.
    local TypeA = Frog.actor("ContractTypeA", {
        initial = 0,
        actions = { [Increment] = function(state) return state + 1 end },
        render = function(_, state)
            return Frog.Text { testId = "typed-state", "A:" .. state }
        end,
    })
    local AddressA = TypeA:address("contract-type-a")
    -- Replaces TypeA to prove actor identity includes the definition token.
    local TypeB = Frog.actor("ContractTypeB", {
        initial = "fresh",
        actions = {},
        render = function(_, state)
            return Frog.Text { testId = "typed-state", "B:" .. state }
        end,
    })
    local AddressB = TypeB:address("contract-type-b")
    local useB = false
    -- Selects the actor type mounted at one stable keyed position.
    local Root = Frog.component("ContractTypeRoot", function()
        return Frog.Column {
            Frog.Button {
                testId = "increment-a",
                onPress = function() Frog.send(AddressA, Increment {}) end,
                Frog.Text "Increment",
            },
            useB and TypeB { key = "same", address = AddressB }
                or TypeA { key = "same", address = AddressA },
        }
    end)
    local host = support.host { width = 540, height = 960 }
    host:mount(Root {})
    press(host, "increment-a")
    assert(assert(support.find(host:tree(), "typed-state")).props.text == "A:1")
    useB = true
    host:render(Root {})
    assert(assert(support.find(host:tree(), "typed-state")).props.text == "B:fresh",
        "actor state survived a same-key actor type change")
    useB = false
    host:render(Root {})
    assert(assert(support.find(host:tree(), "typed-state")).props.text == "A:0",
        "unmounted actor state revived after a type change")
    host:unmount()
end

local function responsiveActorContinuity()
    local Toggle = Frog.action("Responsive.Toggle")
    local Reveal = Frog.event("responsive.reveal")
    -- Owns scalar state that must survive a responsive recomposition.
    local Scalar = Frog.actor("ResponsiveScalar", {
        initial = "closed",
        actions = { [Toggle] = { closed = "open", open = "closed" } },
        render = function(_, state)
            if state == "closed" then return nil end
            return Frog.Text { testId = "responsive-scalar", state }
        end,
    })
    local ScalarAddress = Scalar:address("responsive-scalar")
    -- Owns table state that must survive the same responsive recomposition.
    local TableActor = Frog.actor("ResponsiveTable", {
        initial = function() return { visible = false, count = 0 } end,
        actions = {},
        reactions = {
            Frog.on(Reveal) {
                transition = function(state)
                    return { visible = true, count = state.count + 1 }
                end,
            },
        },
        render = function(_, state)
            if not state.visible then return nil end
            return Frog.Text {
                testId = "responsive-table",
                "count:" .. state.count,
            }
        end,
    })
    local TableAddress = TableActor:address("responsive-table")
    -- Switches container primitives while preserving both nested actor owners.
    local Root = Frog.component("ResponsiveActorRoot", function()
        local viewport = Frog.useViewport()
        local Flow = viewport.wide and Frog.Row or Frog.Column
        return Flow {
            testId = "responsive-shell",
            Frog.Button {
                testId = "responsive-toggle",
                onPress = function() Frog.send(ScalarAddress, Toggle {}) end,
                Frog.Text "Toggle",
            },
            Scalar { address = ScalarAddress },
            TableActor { address = TableAddress },
        }
    end)
    local host = support.host { width = 390, height = 844 }
    host:mount(Root {})
    assert(assert(support.find(host:tree(), "responsive-shell")).type == "Column",
        "responsive proof did not start in portrait composition")
    press(host, "responsive-toggle")
    Frog.emit(Reveal {})
    assert(support.find(host:tree(), "responsive-scalar")
            and assert(support.find(host:tree(), "responsive-table")).props.text
                == "count:1",
        "responsive actors did not accept state before resize")

    host:resize(960, 540)
    assert(assert(support.find(host:tree(), "responsive-shell")).type == "Row",
        "responsive proof did not switch to wide composition")
    assert(support.find(host:tree(), "responsive-scalar")
            and assert(support.find(host:tree(), "responsive-table")).props.text
                == "count:1",
        "Row/Column switch remounted responsive actor state")
    local actors = {}
    for _, actor in ipairs(host:inspectionTree().actors) do
        actors[actor.name] = actor.state
    end
    assert(actors.ResponsiveScalar == "open"
            and actors.ResponsiveTable.count == 1,
        "logical actor registry lost state across responsive layout primitives")
    host:unmount()
end

local function componentAncestryReset()
    local Bump = Frog.action("Wrapped.Bump")
    -- Owns state whose component-ancestry change must intentionally reset it.
    local Owner = Frog.actor("WrappedOwner", {
        initial = 0,
        actions = { [Bump] = function(state) return state + 1 end },
        render = function(_, state, send)
            return Frog.Button {
                testId = "wrapped-owner",
                onPress = function() send(Bump {}) end,
                Frog.Text("wrapped:" .. state),
            }
        end,
    })
    -- Supplies the first semantic component ancestor around Owner.
    local WrapperA = Frog.component("WrapperA", function()
        return Owner { key = "owner" }
    end)
    -- Supplies a different semantic ancestor to force Owner identity reset.
    local WrapperB = Frog.component("WrapperB", function()
        return Owner { key = "owner" }
    end)
    local useB = false
    -- Selects which wrapper owns the otherwise identical nested actor.
    local Root = Frog.component("WrappedRoot", function()
        local Wrapper = useB and WrapperB or WrapperA
        return Frog.Box { Wrapper { key = "wrapper" } }
    end)
    local host = support.host { width = 540, height = 960 }
    host:mount(Root {})
    press(host, "wrapped-owner")
    assert(assert(support.find(host:tree(), "wrapped-owner")).children[1]
            .props.text == "wrapped:1")
    useB = true
    host:render(Root {})
    assert(assert(support.find(host:tree(), "wrapped-owner")).children[1]
            .props.text == "wrapped:0",
        "actor state survived a semantic component-ancestry change")
    host:unmount()
end

local function semanticNameUniqueness()
    -- Claims a semantic component name for the duplicate-name contract.
    local SameA = Frog.component("ContractSameName", function()
        return Frog.Text { testId = "same-name", "A" }
    end)
    -- Independently claims SameA's name so a live collision can be rejected.
    local SameB = Frog.component("ContractSameName", function()
        return Frog.Text { testId = "same-name", "B" }
    end)
    local host = support.host { width = 540, height = 960 }
    host:mount(SameA {})
    expectFailure("same-name component switch", function()
        host:render(SameB {})
    end, "semantic token name collision")
    assert(assert(support.find(host:tree(), "same-name")).props.text == "A",
        "same-name component failure replaced the committed tree")
    host:render(Frog.Box {})
    host:render(SameB {})
    assert(assert(support.find(host:tree(), "same-name")).props.text == "B",
        "semantic token name was not released after a committed unmount")
    host:unmount()

    -- Claims the first duplicate actor token name.
    local ActorA = Frog.actor("ContractDuplicateActor", {
        initial = "a", actions = {}, render = function() return nil end,
    })
    -- Claims the second duplicate actor token name for collision validation.
    local ActorB = Frog.actor("ContractDuplicateActor", {
        initial = "b", actions = {}, render = function() return nil end,
    })
    local actorHost = support.host { width = 540, height = 960 }
    expectFailure("same-name actor tokens", function()
        actorHost:mount(Frog.Column { ActorA {}, ActorB {} })
    end, "semantic token name collision")

    -- Owns the address used to test duplicate connected-view names.
    local Owner = Frog.actor("ContractViewOwner", {
        initial = "ready", actions = {}, render = function() return nil end,
    })
    local Address = Owner:address("contract-view-owner")
    -- First connected view claims the semantic name under test.
    local ViewA = Owner:view("ContractDuplicateView", function() return nil end)
    -- Second connected view deliberately collides with ViewA's live name.
    local ViewB = Owner:view("ContractDuplicateView", function() return nil end)
    local viewHost = support.host { width = 540, height = 960 }
    expectFailure("same-name view tokens", function()
        viewHost:mount(Frog.Column {
            ViewA { target = Address },
            ViewB { target = Address },
            Owner { address = Address },
        })
    end, "semantic token name collision")
end

function check.run()
    definitionFailures()
    messageOwnershipAndFaults()
    actorTypeChange()
    responsiveActorContinuity()
    componentAncestryReset()
    semanticNameUniqueness()
end

return check
