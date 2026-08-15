-- Proves FrogUI motion as one deterministic vertical slice: declarations,
-- clocks, retained identity, paint/input transforms, feedback, candidate
-- rollback, and terminal runtime faults.

local Frog = require("frogui")
local Motion = require("frogui.motion")
local support = require("tests.support")

local check = {}

local Impact = Frog.event("MotionCheck.Impact", function(payload)
    assert(type(payload.id) == "string", "MotionCheck.Impact.id is required")
end)

local Break = Frog.action("MotionCheck.Break")
local Ordered = Frog.event("MotionCheck.Ordered")
local BrokenActor = Frog.actor("MotionCheckBrokenActor", {
    initial = "ready",
    actions = { [Break] = { ready = "broken" } },
    render = function(_, state)
        assert(state ~= "broken", "intentional motion runtime render failure")
        return Frog.Box { testId = "fault-actor", width = 1, height = 1 }
    end,
})
BrokenActor.App = BrokenActor:address("MotionCheckBrokenActor.App")

local OrderedActor = Frog.actor("MotionCheckOrderedActor", {
    initial = "waiting",
    actions = {},
    reactions = {
        Frog.on(Ordered) { transition = Frog.go("received") },
    },
    render = function()
        return Frog.Box { width = 1, height = 1 }
    end,
})

local ResizeProbe = Frog.component("MotionCheckResizeProbe", function(props)
    local viewport = Frog.useViewport()
    assert(not viewport.wide, "intentional motion resize render failure")
    return Frog.Box {
        testId = "resize-runtime", width = 20, height = 20,
        juice = { appear = { key = 1, recipe = Frog.withClock(props.clock,
            Frog.tween { to = { x = 20 }, duration = 1 }) } },
    }
end)

-- Returns a named impact target used across event, clock, and fault checks.
local function ImpactTarget(options)
    options = options or {}
    return Frog.Box {
        key = options.key,
        testId = options.testId or "impact-target",
        width = 40,
        height = 20,
        juice = {
            impact = Frog.withClock(options.clock or Frog.clock(), Frog.parallel {
                Frog.tween { to = { x = 20 }, duration = 1 },
                Frog.shake { y = 4, rotation = 0.02,
                    duration = 0.5, frequency = 8 },
                Frog.sequence {
                    Frog.sound { cue = "impact" },
                    Frog.delay(0.2),
                    Frog.haptic { cue = "light" },
                },
            }),
        },
        reactions = {
            Frog.on(Impact) {
                match = { id = options.id or "target" },
                do_ = Frog.play("impact"),
            },
        },
    }
end

local function expectError(callback, fragment)
    local ok, err = pcall(callback)
    assert(not ok and tostring(err):find(fragment, 1, true),
        "expected error containing " .. fragment .. ", got " .. tostring(err))
end

-- Proves a runtime failure faults one Host and blocks authored work until the
-- caller unmounts it; inspection remains available for the original cause.
local function expectFault(host, origin, retry, label)
    local fault = host:inspectionTree().fault
    assert(fault and fault.origin:find(origin, 1, true),
        label .. " did not record its terminal Host fault")
    local ok, reason = pcall(retry)
    assert(not ok and tostring(reason):find("FrogUI Host faulted", 1, true),
        label .. " allowed work after its terminal Host fault")
end

local function constructorAndClockContracts()
    local clock = Frog.clock(2)
    support.near(clock:now(), 2, "clock initial time")
    support.near(clock:advance(0.25), 2.25, "clock advance")
    support.near(clock:reset(0.5), 0.5, "clock reset")
    expectError(function() clock:advance(-1) end, "non-negative")
    expectError(function() Frog.shake { x = "six" } end, "x must be finite")
    expectError(function() Frog.shake { scale = 0.1, damping = 0 } end,
        "damping must be a finite positive")
    expectError(function()
        Frog.pulse { to = { x = 4 }, duration = 0.2, exponent = 0 }
    end, "exponent must be a finite positive")
    expectError(function() Frog.loop(Frog.delay(1), 10001) end, "at most 10000")
    expectError(function()
        support.host { feedback = { vibration = function() end } }
    end, "unknown FrogUI feedback service")
    expectError(function() support.host { reducedMotion = "yes" } end,
        "reducedMotion must be a boolean")
    local nestedClock = Frog.clock()
    local host = support.host { width = 540, height = 960 }
    expectError(function()
        host:mount(Frog.Box { juice = { invalid = Frog.sequence {
            Frog.withClock(nestedClock, Frog.delay(1)),
        } } })
    end, "must wrap the entire named juice recipe")
    local zeroHost = support.host { width = 540, height = 960 }
    expectError(function()
        zeroHost:mount(Frog.Box { juice = {
            invalid = Frog.loop(Frog.sound { cue = "instant" }),
        } })
    end, "cannot repeat a zero-duration recipe")
    local springHost = support.host { width = 540, height = 960 }
    expectError(function()
        springHost:mount(Frog.Motion {
            scale = { target = 2, spring = { frequency = 10, dampping = 1 } },
        })
    end, "unknown field dampping")
    local typoHost = support.host { width = 540, height = 960 }
    expectError(function()
        typoHost:mount(Frog.Box {
            juice = { impact = Frog.shake { x = 1 } },
            reactions = { Frog.on(Impact) { do_ = Frog.play("impcat") } },
        })
    end, "plays undeclared juice recipe impcat")

    local ActorDo = Frog.actor("MotionCheckActorDo", {
        initial = "ready",
        actions = {},
        reactions = {
            Frog.on(Impact) { do_ = Frog.play("impact") },
        },
        render = function() return Frog.Box {} end,
    })
    local actorHost = support.host { width = 540, height = 960 }
    expectError(function() actorHost:mount(ActorDo {}) end,
        "Frog.play belongs to element reactions")
    expectError(function()
        support.host { width = 540, height = 960 }:mount(Frog.Box {
            juice = { bad = { key = 1, recipe = Frog.delay(1),
                onComplete = "later" } },
        })
    end, "onComplete must be a function")
    expectError(function()
        support.host { width = 540, height = 960 }:mount(Frog.Box {
            juice = { bad = { key = 1,
                recipe = Frog.loop(Frog.delay(1)),
                onComplete = function() end } },
        })
    end, "cannot complete an infinite recipe")

    local authoredTarget = { x = 12 }
    local immutable = Frog.tween {
        to = authoredTarget, duration = 0.4, ease = "out_quad",
    }
    authoredTarget.x = 99
    assert(immutable.kind == "tween" and immutable.duration == 0.4
            and immutable.to.x == 12,
        "recipe constructor retained its mutable input table")
    local authoredSequence = { immutable, Frog.delay(0.1) }
    local immutableSequence = Frog.sequence(authoredSequence)
    authoredSequence[1] = Frog.delay(9)
    assert(immutableSequence.recipes[1] == immutable,
        "recipe composition retained its mutable input array")

    -- Named pulse/flash are ordinary compositions, not framework-only tags.
    local pulse = Frog.sequence {
        Frog.spring { to = { scale = 1.08 }, frequency = 12, damping = 0.8 },
        Frog.tween { to = { scale = 1 }, duration = 0.1, ease = "out_quad" },
    }
    local flash = Frog.sequence {
        Frog.tween { to = { tint = { 1, 0.5, 0.5, 1 } }, duration = 0.05 },
        Frog.tween { to = { tint = { 1, 1, 1, 1 } }, duration = 0.1 },
    }
    assert(pulse.kind == "sequence" and flash.kind == "sequence",
        "pulse/flash did not remain readable named compositions")
end

-- Proves Pulse is one continuous symmetric out-and-back recipe whose terminal
-- pose is exactly its starting pose, including under reduced motion.
local function pulseContract()
    local clock = Frog.clock()
    local host = support.host { width = 540, height = 960 }
    host:mount(Frog.Motion {
        testId = "pulse",
        width = 20,
        height = 20,
        juice = { recoil = { key = 1, recipe = Frog.withClock(clock,
            Frog.pulse {
                to = { x = 40, scaleX = 0.7, scaleY = 1.2 },
                duration = 0.4,
                exponent = 0.65,
            }) } },
        Frog.Box { width = 20, height = 20 },
    })
    local node = assert(support.find(host:tree(), "pulse"))
    local quarterAmount = math.sin(math.pi * 0.25) ^ 0.65
    clock:advance(0.1)
    host:update(0)
    support.near(node.presentation.x, 40 * quarterAmount,
        "pulse first quarter")
    clock:advance(0.1)
    host:update(0)
    support.near(node.presentation.x, 40, "pulse midpoint")
    support.near(node.presentation.scaleX, 0.7, "pulse midpoint scaleX")
    clock:advance(0.1)
    host:update(0)
    support.near(node.presentation.x, 40 * quarterAmount,
        "pulse mirrored third quarter")
    clock:advance(0.1)
    host:update(0)
    support.near(node.presentation.x, 0, "pulse terminal x")
    support.near(node.presentation.scaleX, 1, "pulse terminal scaleX")
    support.near(node.presentation.scaleY, 1, "pulse terminal scaleY")
    assert(next(node._motion.active) == nil,
        "pulse retained a finished Motion runner")
    host:unmount()

    local reduced = support.host {
        width = 540, height = 960, reducedMotion = true,
    }
    reduced:mount(Frog.Motion {
        testId = "reduced-pulse",
        width = 20,
        height = 20,
        juice = { recoil = Frog.pulse {
            to = { x = 40 }, duration = 0.4,
        } },
        Frog.Box { width = 20, height = 20 },
    })
    node = assert(support.find(reduced:tree(), "reduced-pulse"))
    support.near(node.presentation.x, 0, "reduced pulse terminal x")
    assert(next(node._motion.active) == nil,
        "reduced pulse retained a Motion runner")
    reduced:unmount()
end

-- Proves recipe completion is terminal, exactly once, and shares keyed motion
-- cancellation semantics without becoming a render-time side effect.
local function completionLifecycle()
    local completions = 0
    local key = 1
    local function Tree()
        return Frog.Box {
            testId = "completion-target",
            juice = { recover = { key = key,
                recipe = Frog.delay(0.2),
                onComplete = function() completions = completions + 1 end } },
        }
    end
    local host = support.host { width = 540, height = 960 }
    host:mount(Tree())
    host:update(0.1)
    host:render(Tree())
    assert(completions == 0, "completion ran before its recipe settled")
    host:update(0.1)
    host:update(1)
    assert(completions == 1, "completion was not delivered exactly once")
    key = 2
    host:render(Tree())
    key = 3
    host:render(Tree())
    host:update(0.21)
    assert(completions == 2,
        "replaced keyed completion was not cancelled: " .. completions)
    host:unmount()

    local firstCompletions, staleCompletions = 0, 0
    local secondKey = 1
    local deliveryHost
    local function DeliveryTree()
        return Frog.Column {
            Frog.Box { key = "first", juice = { finish = { key = 1,
                recipe = Frog.delay(0.1),
                onComplete = function()
                    firstCompletions = firstCompletions + 1
                    secondKey = 2
                    deliveryHost:render(DeliveryTree())
                end } } },
            Frog.Box { key = "second", juice = { finish = { key = secondKey,
                recipe = Frog.delay(0.1),
                onComplete = function()
                    staleCompletions = staleCompletions + 1
                end } } },
        }
    end
    deliveryHost = support.host { width = 540, height = 960 }
    deliveryHost:mount(DeliveryTree())
    deliveryHost:update(0.1)
    assert(firstCompletions == 1 and staleCompletions == 0,
        "an earlier completion did not cancel a later stale generation")
    deliveryHost:update(0.1)
    assert(staleCompletions == 1,
        "the replacement completion did not run exactly once")
    deliveryHost:unmount()

    local reducedCompletions = 0
    local reduced = support.host {
        width = 540, height = 960, reducedMotion = true,
    }
    reduced:mount(Frog.Box { juice = { recover = { key = 1,
        recipe = Frog.delay(5),
        onComplete = function()
            reducedCompletions = reducedCompletions + 1
        end,
    } } })
    assert(reducedCompletions == 0,
        "reduced-motion completion ran during mount/render")
    reduced:update(0)
    reduced:update(0)
    assert(reducedCompletions == 1,
        "reduced-motion completion did not run once on the next update")
    reduced:unmount()

    local failedCompletions, failedCleanups = 0, 0
    local FailedCompletionOwner = Frog.component(
            "MotionCheckFailedCompletionOwner", function()
        Frog.useResource(function()
            return {}, function() failedCleanups = failedCleanups + 1 end
        end)
        return Frog.Box { juice = { finish = { key = 1,
            recipe = Frog.delay(0.1),
            onComplete = function()
                failedCompletions = failedCompletions + 1
                error("intentional completion failure")
            end,
        } } }
    end)
    local failed = support.host { width = 540, height = 960 }
    failed:mount(FailedCompletionOwner {})
    expectError(function() failed:update(0.1) end,
        "intentional completion failure")
    expectFault(failed, "juice:", function() failed:update(1) end,
        "failed Motion completion")
    assert(failedCompletions == 1,
        "failed terminal completion was retried")
    failed:unmount()
    assert(failedCleanups == 1,
        "faulted Motion Host did not clean its resource exactly once")
end

local function runPartition(parts)
    local clock = Frog.clock()
    local host = support.host { width = 540, height = 960 }
    host:mount(ImpactTarget { clock = clock })
    Frog.emit(Impact { id = "target" })
    for _, dt in ipairs(parts) do
        clock:advance(dt)
        host:update(0)
    end
    local node = assert(support.find(host:tree(), "impact-target"))
    local snapshot = host:inspectionTree()
    local entry
    for _, candidate in ipairs(snapshot.nodes) do
        if candidate.testId == "impact-target" then entry = candidate break end
    end
    local result = {
        x = entry.motion.current.x,
        y = entry.motion.current.y,
        rotation = entry.motion.current.rotation,
        boundsX = entry.bounds.x,
        active = #entry.motion.active,
        restX = node.layout.x,
    }
    host:unmount()
    return result
end

local function deterministicClockAndNoRerender()
    local one = runPartition { 0.5 }
    local split = runPartition { 0.1, 0.15, 0.25 }
    support.near(one.x, split.x, "dt-partition x")
    support.near(one.y, split.y, "dt-partition y")
    support.near(one.rotation, split.rotation, "dt-partition rotation")
    support.near(one.boundsX, split.boundsX, "dt-partition bounds")
    assert(one.x > 9.9 and one.x < 10.1 and one.boundsX > one.restX,
        "explicit clock did not drive transform without layout movement")

    local dampedClock = Frog.clock()
    local damped = support.host { width = 540, height = 960 }
    damped:mount(Frog.Motion {
        testId = "damped-shake",
        width = 20,
        height = 20,
        juice = { pulse = { key = 1, recipe = Frog.withClock(dampedClock,
            Frog.shake {
                x = 3,
                rotation = 0.07,
                scale = 0.10,
                duration = 0.5,
                frequency = 10,
                damping = 7,
                coherent = true,
            }) } },
        Frog.Box { width = 20, height = 20 },
    })
    local peakTime = 1 / 40
    dampedClock:advance(peakTime)
    damped:update(0)
    local dampedNode = assert(support.find(damped:tree(), "damped-shake"))
    local envelope = math.exp(-7 * peakTime)
    support.near(dampedNode.presentation.x, 3 * envelope,
        "exponentially damped shake translation")
    support.near(dampedNode.presentation.rotation, 0.07 * envelope,
        "coherent damped shake rotation")
    support.near(dampedNode.presentation.scale, 1 + 0.10 * envelope,
        "exponentially damped shake scale")
    damped:unmount()

    local renders = 0
    -- Counts component renders while raw-clock updates animate its child.
    local RenderCounter = Frog.component("MotionCheckRenderCounter", function()
        renders = renders + 1
        return Frog.Motion {
            testId = "counter-motion",
            x = { target = renders == 1 and 0 or 10, spring = "snappy" },
            Frog.Box { width = 20, height = 20 },
        }
    end)
    local host = support.host { width = 540, height = 960 }
    host:mount(RenderCounter {})
    host:render(RenderCounter {})
    host:update(0.1)
    host:update(0.1)
    assert(renders == 2, "Host clock updates rerendered application components")
    host:unmount()
end

-- Proves clean frames are O(1) at the transform boundary, while a dirty frame
-- updates the retained matrix/bounds storage used by paint, input, refs, and
-- F6. The revision is an internal check seam, not an application API.
local function cachedCommittedTransforms()
    local host = support.host { width = 540, height = 960 }
    host:mount(Frog.Box {
        testId = "cache-root", width = 100, height = 100,
        Frog.Box { testId = "cache-child", width = 20, height = 20 },
    })
    local root = assert(support.find(host:tree(), "cache-root"))
    local child = assert(support.find(host:tree(), "cache-child"))
    assert(root.presentation == child.presentation
            and root.presentation.x == 0
            and root.presentation.y == 0
            and root.presentation.rotation == 0
            and root.presentation.scale == 1
            and root.presentation.opacity == 1,
        "static primitives did not share the canonical presentation defaults")
    assert(root._localTransform == child._localTransform
            and root._worldTransform == child._worldTransform
            and root._inverseWorldTransform == child._inverseWorldTransform
            and root._visualBounds == nil
            and child._visualBounds == nil
            and root._visualContentBounds == nil
            and child._visualContentBounds == nil,
        "static primitives did not alias identity geometry")
    local rootRevision = root._motionTransformRevision
    local world, inverse = child._worldTransform, child._inverseWorldTransform
    local bounds, contentBounds = child._visualBounds,
        child._visualContentBounds

    local cleanRan, cleanStats = Motion.transformTree(root)
    assert(not cleanRan and cleanStats == nil,
        "ordinary clean transform allocated diagnostic attribution")

    host:update(0)
    assert(root._motionTransformRevision == rootRevision,
        "clean Host update recursively recomputed committed transforms")
    assert(child._worldTransform == world
            and child._inverseWorldTransform == inverse
            and child._visualBounds == bounds
            and child._visualContentBounds == contentBounds,
        "clean Host update replaced retained transform storage")
    assert(root._motionParent == nil and child._motionParent == nil,
        "transform cache introduced parent backlinks into the render tree")

    child.layout.x = child.layout.x + 10
    Motion.invalidate(host:tree())
    host:update(0)
    assert(root._motionTransformRevision == rootRevision + 1,
        "explicit geometry invalidation did not refresh the committed tree")
    assert(child._worldTransform == world
            and child._inverseWorldTransform == inverse
            and child._visualBounds == bounds
            and child._visualContentBounds == contentBounds,
        "dirty transform refresh did not update storage in place")
    support.near((child._visualBounds or child.layout).x, child.layout.x,
        "dirty transform refresh visual x")
    host:unmount()

    local cosmeticClock = Frog.clock()
    host = support.host { width = 540, height = 960 }
    host:mount(Frog.Box {
        testId = "cache-cosmetic", width = 20, height = 20,
        juice = { cosmetic = { key = 1,
            recipe = Frog.withClock(cosmeticClock, Frog.parallel {
                Frog.delay(1),
                Frog.tween { to = { opacity = 0.5 }, duration = 1 },
                Frog.tween {
                    to = { tint = { 0.5, 1, 1, 1 } }, duration = 1,
                },
                Frog.sequence {
                    Frog.delay(0.2),
                    Frog.sound { cue = "cosmetic-only" },
                },
            }) } },
    })
    local cosmetic = assert(support.find(host:tree(), "cache-cosmetic"))
    local cosmeticRevision = host:tree()._motionTransformRevision
    cosmeticClock:advance(0.5)
    host:update(0)
    assert(cosmetic.presentation.opacity < 1
            and cosmetic.presentation.tint[1] < 1,
        "cosmetic-only Motion did not update its paint presentation")
    assert(host:tree()._motionTransformRevision == cosmeticRevision,
        "opacity/tint/delay Motion needlessly recomputed geometry")
    host:unmount()

    local clock = Frog.clock()
    host = support.host { width = 540, height = 960 }
    host:mount(Frog.Column {
        width = 100, height = 100,
        Frog.Motion {
            testId = "cache-motion", width = 20, height = 20,
            juice = { travel = { key = 1,
                recipe = Frog.withClock(clock, Frog.tween {
                    to = { x = 40 }, duration = 1,
                }) } },
            Frog.Box { width = 10, height = 10 },
        },
        Frog.Box { width = 10, height = 10 },
        Frog.Box { width = 10, height = 10 },
    })
    local moving = assert(support.find(host:tree(), "cache-motion"))
    local movingChild = moving.children[1]
    local staticRoot = host:tree()
    local staticLeft, staticRight = staticRoot.children[2],
        staticRoot.children[3]
    assert(staticRoot.presentation == staticLeft.presentation
            and staticLeft.presentation == staticRight.presentation
            and moving.presentation ~= staticRoot.presentation,
        "Motion did not detach mutable presentation from static defaults")
    assert(staticRoot._localTransform == staticLeft._localTransform
            and staticLeft._localTransform == staticRight._localTransform
            and moving._localTransform ~= staticRoot._localTransform
            and moving._worldTransform ~= staticRoot._worldTransform
            and moving._inverseWorldTransform
                ~= staticRoot._inverseWorldTransform
            and movingChild._localTransform == staticRoot._localTransform
            and movingChild._worldTransform == moving._worldTransform
            and movingChild._inverseWorldTransform
                == moving._inverseWorldTransform,
        "static/Motion transform aliases crossed their ownership boundary")
    local movingRevision = host:tree()._motionTransformRevision
    local movingToken = host:tree()._motionTreeToken
    local work = host._transformWork
    local roots, boundary = work.roots, work.boundary
    host:update(0)
    assert(host:tree()._motionTransformRevision == movingRevision,
        "stationary explicit clock dirtied an unchanged transform")
    clock:advance(0.5)
    host:update(0)
    assert(host:tree()._motionTransformRevision == movingRevision + 1
            and moving._visualBounds.x > moving.layout.x,
        "active Motion did not invalidate its changed transform")
    assert(staticRoot.presentation.x == 0
            and staticRoot.presentation.opacity == 1,
        "Motion mutation leaked into shared static presentation defaults")
    assert(movingChild._worldTransform == moving._worldTransform
            and movingChild._inverseWorldTransform
                == moving._inverseWorldTransform,
        "Motion update detached its static descendant transform aliases")
    assert(host:tree()._motionTreeToken == movingToken
            and host._transformWork == work
            and host._transformWork.roots == roots
            and host._transformWork.boundary == boundary,
        "ordinary Motion did not reuse the exact branch router")
    assert(host._pendingTransformAttribution == nil
            and host._diagnostics.current == nil
            and not host._transformWork.active
            and next(host._transformWork.nodes) == nil,
        "ordinary geometry Motion retained diagnostic or node attribution")
    host:unmount()

    host = support.host { width = 100, height = 100 }
    host:mount(Frog.Column {
        testId = "alias-singular-root", width = 100, height = 100,
        Frog.Motion {
            testId = "alias-singular-motion", width = 20, height = 20,
            scale = 0,
            Frog.Box {
                testId = "alias-singular-child", width = 10, height = 10,
            },
        },
        Frog.Chrome {
            testId = "alias-portal", Frog.Box {
                testId = "alias-portal-child", width = 10, height = 10,
            },
        },
    })
    local singularRoot = assert(support.find(host:tree(),
        "alias-singular-root"))
    local singularMotion = assert(support.find(host:tree(),
        "alias-singular-motion"))
    local singularChild = assert(support.find(host:tree(),
        "alias-singular-child"))
    local portal = assert(support.find(host:tree(), "alias-portal"))
    local portalChild = assert(support.find(host:tree(),
        "alias-portal-child"))
    assert(singularMotion._inverseWorldTransform == nil
            and singularChild._inverseWorldTransform == nil
            and singularChild._worldTransform
                == singularMotion._worldTransform,
        "static descendant did not inherit a singular Motion boundary")
    assert(portal._localTransform == singularRoot._localTransform
            and portal._worldTransform == singularRoot._worldTransform
            and portal._inverseWorldTransform
                == singularRoot._inverseWorldTransform
            and portalChild._worldTransform == portal._worldTransform,
        "Chrome portal did not restart static aliases at identity")
    host:unmount()
end

-- Proves B4p.7 locality math without changing the full-tree transform policy.
-- These are diagnostic observations over the existing recursion, not a dirty
-- subtree execution path.
local function transformLocalityAttribution()
    local host = support.host { width = 540, height = 960 }
    host:mount(Frog.Column {
        testId = "locality-root", width = 100, height = 100,
        Frog.Column {
            testId = "locality-left", width = 40, height = 40,
            Frog.Box { testId = "locality-leaf", width = 10, height = 10 },
        },
        Frog.Column {
            testId = "locality-right", width = 40, height = 40,
            Frog.Box { testId = "locality-portal", width = 10, height = 10,
                Frog.Box {
                    testId = "locality-portal-leaf", width = 5, height = 5,
                },
            },
        },
    })
    local root = assert(support.find(host:tree(), "locality-root"))
    local left = assert(support.find(host:tree(), "locality-left"))
    local leaf = assert(support.find(host:tree(), "locality-leaf"))
    local right = assert(support.find(host:tree(), "locality-right"))
    local portal = assert(support.find(host:tree(), "locality-portal"))
    local portalLeaf = assert(support.find(host:tree(),
        "locality-portal-leaf"))

    local ran, skipped = Motion.transformTree(root, { [leaf] = true })
    assert(not ran and skipped.nodesVisited == 0,
        "clean transform attribution visited nodes")

    Motion.invalidate(root)
    local _, ancestor = Motion.transformTree(root, {
        [left] = true,
        [leaf] = true,
    })
    assert(ancestor.dirtyRoots == 1
            and ancestor.branchCoverage == 2
            and ancestor.lcaCoverage == 2,
        "ancestor locality did not subsume its dirty descendant")

    Motion.invalidate(root)
    local _, siblings = Motion.transformTree(root, {
        [leaf] = true,
        [right] = true,
    })
    assert(siblings.dirtyRoots == 2
            and siblings.branchCoverage < siblings.lcaCoverage
            and siblings.lcaCoverage <= siblings.nodesVisited,
        "sibling locality did not report union and LCA coverage")

    -- A portal begins a new transform plane. Cross-plane LCA coverage is the
    -- sum of each plane's local LCA rather than the broad authored root.
    portal._portal = true
    Motion.invalidate(root)
    local _, crossPlane = Motion.transformTree(root, {
        [leaf] = true,
        [portalLeaf] = true,
    })
    assert(crossPlane.dirtyRoots == 2
            and crossPlane.lcaCoverage == crossPlane.branchCoverage
            and crossPlane.lcaCoverage < crossPlane.nodesVisited,
        "portal locality crossed transform-plane ancestry")
    host:unmount()
end

local function geometrySnapshot(node)
    local function values(matrix)
        if not matrix then return false end
        return { matrix.a, matrix.b, matrix.c, matrix.d, matrix.tx, matrix.ty }
    end
    local function bounds(value, x, y, width, height)
        return value and { value.x, value.y, value.width, value.height }
            or { x, y, width, height }
    end
    return {
        localMatrix = values(node._localTransform),
        world = values(node._worldTransform),
        inverse = values(node._inverseWorldTransform),
        bounds = bounds(node._visualBounds,
            node.layout.x, node.layout.y, node.layout.width, node.layout.height),
        content = bounds(node._visualContentBounds,
            node.layout.contentX, node.layout.contentY,
            node.layout.contentWidth, node.layout.contentHeight),
    }
end

local function assertGeometrySnapshot(node, expected, label)
    local actual = geometrySnapshot(node)
    for _, field in ipairs {
            "localMatrix", "world", "inverse", "bounds", "content",
        } do
        assert(actual[field] ~= false and expected[field] ~= false,
            label .. " unexpectedly lost " .. field)
        for index, value in ipairs(expected[field]) do
            support.near(actual[field][index], value,
                label .. " " .. field .. " " .. index)
        end
    end
end

local function inspectionEntry(host, testId)
    for _, entry in ipairs(host:inspectionTree().nodes) do
        if entry.testId == testId then return entry end
    end
    error("missing Motion inspection entry " .. testId, 0)
end

-- Proves exact ancestor suppression, sibling/portal separation, retained table
-- identity, and full-versus-branch geometry/input/F6 equivalence.
local function exactDirtyBranchExecution()
    local host = support.host {
        width = 540, height = 960, diagnostics = true, inspectorActive = true,
    }
    host:mount(Frog.Column {
        testId = "branch-root", width = 140, height = 120,
        Frog.Column {
            testId = "branch-left", width = 50, height = 50,
            juice = { idle = Frog.delay(1) },
            Frog.Box {
                testId = "branch-leaf", width = 20, height = 20,
                juice = { idle = Frog.delay(1) },
            },
        },
        Frog.Column {
            testId = "branch-right", width = 50, height = 50,
            Frog.Box {
                testId = "branch-portal", width = 30, height = 30,
                Frog.Box {
                    testId = "branch-portal-leaf", width = 12, height = 12,
                    juice = { idle = Frog.delay(1) },
                },
            },
        },
    })
    local root = assert(support.find(host:tree(), "branch-root"))
    local left = assert(support.find(root, "branch-left"))
    local leaf = assert(support.find(root, "branch-leaf"))
    local portal = assert(support.find(root, "branch-portal"))
    local portalLeaf = assert(support.find(root, "branch-portal-leaf"))
    portal._portal = true
    Motion.invalidate(root)
    Motion.transformTree(root, nil, {
        generation = host._generation, scratch = {},
    })

    left.presentation.x = 7
    leaf.presentation.rotation = 0.12
    portalLeaf.presentation.scale = 1.25
    host._diagnostics:ensureFrame()
    host:_invalidateTransform(left, "Motion", "frame-sample")
    host:_invalidateTransform(leaf, "Motion", "frame-sample")
    host:_invalidateTransform(portalLeaf, "Motion", "frame-sample")
    local _, row = host:_transformTree(nil, "committedTransform")
    assert(row.branchRuns == 1 and row.fullRuns == 0
            and row.fallbackRuns == 0 and row.pendingTargets == 3
            and row.survivingRoots == 2
            and row.descendantsSuppressed == 1
            and row.branchNodes == 3 and row.routingTreeVisits == 0,
        "exact branch plan crossed ancestry or portal planes")
    assert(not host._transformWork.active
            and next(host._transformWork.nodes) == nil,
        "successful branch retained its consumed node batch")

    local leafSnapshot = geometrySnapshot(leaf)
    local portalSnapshot = geometrySnapshot(portalLeaf)
    local storage = {
        leaf._localTransform, leaf._worldTransform,
        leaf._inverseWorldTransform, leaf._visualBounds,
        leaf._visualContentBounds,
    }
    local leafInspection = inspectionEntry(host, "branch-leaf").bounds
    local hitX = leaf._visualBounds.x + leaf._visualBounds.width / 2
    local hitY = leaf._visualBounds.y + leaf._visualBounds.height / 2
    local branchHit = host:inspect(hitX, hitY)

    Motion.invalidate(root)
    Motion.transformTree(root, nil, {
        generation = host._generation, scratch = {},
    })
    assertGeometrySnapshot(leaf, leafSnapshot, "branch/full leaf")
    assertGeometrySnapshot(portalLeaf, portalSnapshot,
        "branch/full portal leaf")
    assert(leaf._localTransform == storage[1]
            and leaf._worldTransform == storage[2]
            and leaf._inverseWorldTransform == storage[3]
            and leaf._visualBounds == storage[4]
            and leaf._visualContentBounds == storage[5],
        "branch/full refresh replaced retained geometry storage")
    local fullInspection = inspectionEntry(host, "branch-leaf").bounds
    support.near(fullInspection.x, leafInspection.x, "branch/full F6 x")
    support.near(fullInspection.y, leafInspection.y, "branch/full F6 y")
    local fullHit = host:inspect(hitX, hitY)
    assert((branchHit and branchHit.testId) == (fullHit and fullHit.testId),
        "branch/full transforms disagreed on topmost inspection hit")

    -- An ancestor-only branch must refresh every descendant Motion boundary.
    -- The descendant can then become the next frame's exact branch root
    -- without inheriting the ancestor transform that preceded that move.
    local leafInstance = leaf._motion
    local previousBoundary = leafInstance._branchParentTx
    left.presentation.x = 19
    host._diagnostics:ensureFrame()
    host:_invalidateTransform(left, "Motion", "frame-sample")
    local _, ancestorRow = host:_transformTree(nil, "committedTransform")
    assert(ancestorRow.branchRuns == 1 and ancestorRow.branchNodes == 2
            and leaf._motion == leafInstance
            and leafInstance._branchParentTx ~= previousBoundary,
        "ancestor branch did not refresh its descendant Motion boundary")

    leaf.presentation.rotation = leaf.presentation.rotation + 0.08
    host._diagnostics:ensureFrame()
    host:_invalidateTransform(leaf, "Motion", "frame-sample")
    local _, descendantRow = host:_transformTree(nil, "committedTransform")
    assert(descendantRow.branchRuns == 1
            and descendantRow.branchNodes == 1,
        "refreshed descendant did not remain an exact branch root")
    local chainedSnapshot = geometrySnapshot(leaf)
    Motion.invalidate(root)
    Motion.transformTree(root, nil, {
        generation = host._generation, scratch = {},
    })
    assertGeometrySnapshot(leaf, chainedSnapshot,
        "ancestor/descendant branch chain")
    host:unmount()
end

-- Proves every conservative context/fallback and candidate lifecycle clears or
-- preserves the one ordinary pending batch at the exact authority boundary.
local function branchFallbackAndLifecycle()
    local function Description(id)
        return Frog.Row {
            testId = id or "fallback-root", width = 120, height = 40,
            juice = { idle = Frog.delay(1) },
            Frog.Box {
                testId = "fallback-left", width = 30, height = 30,
                juice = { idle = Frog.delay(1) },
            },
            Frog.Box {
                testId = "fallback-right", width = 30, height = 30,
                juice = { idle = Frog.delay(1) },
            },
            Frog.Box { testId = "fallback-plain", width = 1, height = 1 },
        }
    end
    local host = support.host { width = 540, height = 960, diagnostics = true }
    host:mount(Description())
    local root = assert(support.find(host:tree(), "fallback-root"))
    local left = assert(support.find(root, "fallback-left"))
    local right = assert(support.find(root, "fallback-right"))
    local plain = assert(support.find(root, "fallback-plain"))
    expectError(function()
        host:_invalidateTransform(plain, "Motion", "frame-sample")
    end, "mounted Motion owner")
    assert(not host._transformWork.active
            and plain._motionTreeToken == nil
            and plain._motionPlane == nil
            and plain._motionPreorderStart == nil
            and plain._motionParentA == nil,
        "plain node accepted Motion routing or retained branch metadata")

    local function begin()
        host._diagnostics:ensureFrame()
        left.presentation.x = left.presentation.x + 1
        host:_invalidateTransform(left, "Motion", "frame-sample")
    end
    local function expectFull(reason, phase)
        local _, row = host:_transformTree(nil,
            phase or "committedTransform")
        assert(row.fullRuns == 1 and row.branchRuns == 0,
            reason .. " did not retain the full transform")
        if phase == nil then
            assert(row.fallbackRuns == 1
                    and row.fallbackReasons[reason] == 1,
                reason .. " did not report its bounded fallback")
        end
        assert(not host._transformWork.active,
            reason .. " retained a consumed transform batch")
        return row
    end

    begin()
    host:_invalidateTransform(left, "Scroll", "momentum")
    expectFull("non-motion-or-mixed")

    begin()
    host._transformWork.generation = -1
    expectFull("stale-generation")

    begin()
    host:_invalidateTransform(right, "Motion", "frame-sample")
    left._motion._branchTreeToken = -1
    local detached = expectFull("detached")
    assert(detached.pendingTargets == 2,
        "multi-target fallback reported partial pending work")

    begin()
    host._transformWork.treeToken = -1
    expectFull("structural-token")

    begin()
    left._motion._branchParentA = nil
    expectFull("missing-metadata")

    host._diagnostics:ensureFrame()
    host:_invalidateTransform(left, "Motion", "frame-sample")
    host:_invalidateTransform(right, "Motion", "frame-sample")
    left._motion._branchPreorderEnd = right._motion._branchPreorderStart
    right._motion._branchPreorderEnd =
        right._motion._branchPreorderStart + 1
    expectFull("ambiguous-overlap")

    host._diagnostics:ensureFrame()
    host:_invalidateTransform(root, "Motion", "frame-sample")
    expectFull("coverage-limit")

    begin()
    expectFull("message context", "messageTransform")

    begin()
    local committedInstance = left._motion
    local committedToken = committedInstance._branchTreeToken
    local committedStart = committedInstance._branchPreorderStart
    local committedBoundary = committedInstance._branchParentTx
    expectError(function()
        host:render(Frog.Modal {
            dismiss = "none",
            Frog.Modal {
                dismiss = "none",
                Frog.Box {
                    width = 10, height = 10,
                    juice = { idle = Frog.delay(1) },
                },
            },
        })
    end, "root portals cannot be nested")
    assert(left._motion == committedInstance
            and committedInstance._branchTreeToken == committedToken
            and committedInstance._branchPreorderStart == committedStart
            and committedInstance._branchParentTx == committedBoundary,
        "failed post-transform candidate mutated committed Motion metadata")
    assert(host._transformWork.active
            and host._transformWork.nodes[left._motion],
        "failed candidate consumed the committed transform batch")
    local _, preserved = host:_transformTree(nil, "committedTransform")
    assert(preserved.branchRuns == 1,
        "failed candidate did not preserve a branch-eligible batch")

    begin()
    host:render(Description("replacement-root"))
    assert(not host._transformWork.active
            and next(host._transformWork.nodes) == nil,
        "successful candidate retained the replaced tree's node batch")
    local replacement = assert(support.find(host:tree(), "fallback-left"))
    assert(replacement._motion ~= committedInstance
            and replacement._motion._branchTreeToken
                == host:tree()._motionTreeToken,
        "successful candidate reused stale committed Motion metadata")
    host:_invalidateTransform(replacement, "Motion", "frame-sample")
    host:unmount()
    assert(not host._transformWork.active
            and next(host._transformWork.nodes) == nil,
        "unmount retained ordinary transform nodes")

    local many = {
        testId = "root-limit-root", width = 520, height = 2,
        gap = 1,
    }
    for index = 1, 260 do
        many[#many + 1] = Frog.Box {
            width = 1, height = 1, juice = { idle = Frog.delay(1) },
        }
    end
    host = support.host { width = 540, height = 960, diagnostics = true }
    host:mount(Frog.Row(many))
    root = assert(support.find(host:tree(), "root-limit-root"))
    host._diagnostics:ensureFrame()
    for index = 1, 129 do
        host:_invalidateTransform(root.children[index],
            "Motion", "frame-sample")
    end
    local _, limited = host:_transformTree(nil, "committedTransform")
    assert(limited.fullRuns == 1 and limited.fallbackRuns == 1
            and limited.fallbackReasons["root-limit"] == 1,
        "branch root safety limit did not force a full transform")
    host._diagnostics:ensureFrame()
    for index = 1, 257 do
        host:_invalidateTransform(root.children[index],
            "Motion", "frame-sample")
    end
    local _, targetLimited = host:_transformTree(nil, "committedTransform")
    assert(targetLimited.fullRuns == 1 and targetLimited.fallbackRuns == 1
            and targetLimited.fallbackReasons["target-limit"] == 1
            and targetLimited.pendingTargets == 0,
        "pending Motion target cap did not bound its ordinary node set")
    host:unmount()

    host = support.host { width = 540, height = 960 }
    host:mount(Description("bare-root"))
    root = assert(support.find(host:tree(), "bare-root"))
    left = assert(support.find(root, "fallback-left"))
    local token = root._motionTreeToken
    left.presentation.x = 3
    Motion.invalidate(root)
    host:update(0)
    assert(root._motionTreeToken ~= token,
        "bare Motion.invalidate unexpectedly entered the branch path")
    host:unmount()
end

local function keyedEntranceUsesMotionBase()
    local clock = Frog.clock()
    local entranceKey = 1
    local opacity, scale = 0, 0.8
    -- Builds an entrance whose declarative Motion props are its initial base.
    local function Entrance()
        return Frog.Motion {
            testId = "keyed-entrance",
            width = 20, height = 20,
            opacity = opacity,
            scale = scale,
            juice = { appear = { key = entranceKey,
                recipe = Frog.withClock(clock, Frog.tween {
                    to = { opacity = 1, scale = 1 }, duration = 1,
                    ease = "linear",
                }) } },
        }
    end
    local host = support.host { width = 540, height = 960 }
    host:mount(Entrance())
    local node = assert(support.find(host:tree(), "keyed-entrance"))
    support.near(node.presentation.opacity, 0,
        "first-mount keyed opacity ignored its Motion base")
    support.near(node.presentation.scale, 0.8,
        "first-mount keyed scale ignored its Motion base")
    clock:advance(0.5)
    host:update(0)
    node = assert(support.find(host:tree(), "keyed-entrance"))
    support.near(node.presentation.opacity, 0.5,
        "keyed opacity entrance midpoint")
    support.near(node.presentation.scale, 0.9,
        "keyed scale entrance midpoint")

    opacity, scale, entranceKey = 0.2, 0.7, 2
    host:render(Entrance())
    node = assert(support.find(host:tree(), "keyed-entrance"))
    support.near(node.presentation.opacity, 0.5,
        "simultaneous target/key change abandoned current opacity")
    support.near(node.presentation.scale, 0.9,
        "simultaneous target/key change abandoned current scale")
    host:unmount()
end

-- Proves fixed Motion wrappers stay ordinary candidate presentation while
-- dynamic declarations enter and leave the retained runtime exactly once.
local function staticMotionLifecycle()
    local clock = Frog.clock()
    local mode = "static"
    local function Description()
        if mode == "dynamic" then
            return Frog.Motion {
                testId = "static-lifecycle", width = 20, height = 20,
                x = 15,
                juice = { travel = { key = 1,
                    recipe = Frog.withClock(clock, Frog.tween {
                        to = { x = 25 }, duration = 1,
                    }) } },
            }
        end
        return Frog.Motion {
            testId = "static-lifecycle", width = 20, height = 20,
            x = 7,
        }
    end

    local host = support.host { width = 540, height = 960 }
    host:mount(Description())
    local node = assert(support.find(host:tree(), "static-lifecycle"))
    assert(node._motion == nil and next(host._motions) == nil,
        "fixed Motion manufactured a retained animation process")
    support.near(node.presentation.x, 7, "fixed Motion presentation")

    expectError(function()
        host:render(Frog.Motion {
            testId = "static-lifecycle", width = 20, height = 20,
            scale = -1,
        })
    end, "scale target must be non-negative")
    expectError(function()
        host:render(Frog.Motion {
            testId = "static-lifecycle", width = 20, height = 20,
            scaleX = -1,
        })
    end, "scaleX target must be non-negative")
    expectError(function()
        host:render(Frog.Motion {
            testId = "static-lifecycle", width = 20, height = 20,
            pivot = { x = 0.5 },
        })
    end, "pivot needs normalized x and y")
    expectError(function()
        Frog.tween { to = { scaleY = -1 }, duration = 1 }
    end, "scaleY must be finite and non-negative")
    node = assert(support.find(host:tree(), "static-lifecycle"))
    support.near(node.presentation.x, 7,
        "failed fixed candidate replaced committed presentation")

    mode = "dynamic"
    host:render(Description())
    node = assert(support.find(host:tree(), "static-lifecycle"))
    assert(node._motion and next(host._motions) ~= nil,
        "dynamic Motion did not mount its retained process")
    support.near(node.presentation.x, 15,
        "static-to-dynamic Motion lost its authored entrance base")
    clock:advance(0.5)
    host:update(0)
    support.near(assert(support.find(host:tree(),
        "static-lifecycle")).presentation.x, 20,
        "static-to-dynamic Motion did not advance")

    mode = "static"
    host:render(Description())
    node = assert(support.find(host:tree(), "static-lifecycle"))
    assert(node._motion == nil and next(host._motions) == nil,
        "dynamic-to-static Motion retained an idle process")
    support.near(node.presentation.x, 7,
        "dynamic-to-static Motion lost fixed presentation")
    clock:advance(1)
    host:update(0)
    support.near(assert(support.find(host:tree(),
        "static-lifecycle")).presentation.x, 7,
        "retired Motion process changed fixed presentation")

    host:resize(960, 540)
    node = assert(support.find(host:tree(), "static-lifecycle"))
    assert(node._motion == nil and next(host._motions) == nil,
        "resize promoted a fixed Motion into retained state")
    support.near(node.presentation.x, 7,
        "fixed Motion changed across resize")
    host:unmount()
end

local function transformedPaintInputAndInspector()
    local presses, observed = 0
    local painter = {}
    function painter:text(node, _, style)
        if node.props.testId == "motion-text" then observed = style end
    end
    local host = support.host { width = 540, height = 960, painter = painter }
    host:mount(Frog.Motion {
        testId = "motion-root",
        x = 80,
        scale = 1.5,
        opacity = 0.5,
        tint = { 0.5, 1, 1, 1 },
        Frog.Button {
            testId = "motion-button",
            width = 80,
            height = 40,
            onPress = function() presses = presses + 1 end,
            Frog.Text { testId = "motion-text", color = { 1, 1, 1, 1 }, "Move" },
        },
    })
    local motionRoot = assert(support.find(host:tree(), "motion-root"))
    assert(motionRoot.presentation and motionRoot.presentation.tint,
        "Motion tint target was not committed")
    support.near(motionRoot.presentation.tint[1], 0.5, "Motion tint target")
    host:draw()
    assert(observed, "custom painter did not receive transformed descendant")
    support.near(observed.color[1], 0.5, "ancestor tint through Motion")
    support.near(observed.color[4], 0.5, "numeric Motion opacity exactly once")

    local entry
    for _, candidate in ipairs(host:inspectionTree().nodes) do
        if candidate.testId == "motion-button" then entry = candidate break end
    end
    entry = assert(entry, "inspector omitted transformed button")
    assert(entry.bounds.x ~= entry.restBounds.x
            and entry.bounds.width > entry.restBounds.width,
        "F6 did not expose rest and transformed bounds")
    local x = entry.bounds.x + entry.bounds.width / 2
    local y = entry.bounds.y + entry.bounds.height / 2
    assert(host:pointerDown(x, y, "mouse", 1),
        "transformed paint bounds were not hittable")
    host:pointerUp(x, y, "mouse", 1)
    assert(presses == 1, "transformed Button did not activate")
    host:unmount()
end

-- Proves independent axis scale and a feet pivot use one affine transform for
-- default/custom paint, input, and F6 while refs retain arranged rest geometry.
local function asymmetricScaleAndPivot()
    local presses, observed, motionRef = 0
    local painter = {}
    function painter:box(node, style)
        if node.props.testId == "asymmetric-button" then observed = style end
    end
    local AsymmetricFigure = Frog.component(
        "MotionCheckAsymmetricFigure", function()
            local handle = Frog.useRef()
            motionRef = handle
            return Frog.Motion {
                testId = "asymmetric-motion",
                ref = handle,
                width = 80,
                height = 40,
                x = 12,
                y = -6,
                scale = 1.2,
                scaleX = 1.5,
                scaleY = 0.5,
                pivot = { x = 0.5, y = 1 },
                Frog.Button {
                    testId = "asymmetric-button",
                    width = 80,
                    height = 40,
                    onPress = function() presses = presses + 1 end,
                    Frog.Text {
                        testId = "asymmetric-label",
                        "Figure",
                    },
                },
            }
        end)

    local host = support.host {
        width = 540,
        height = 960,
        painter = painter,
    }
    host:mount(AsymmetricFigure {})
    host:draw()
    local node = assert(support.find(host:tree(), "asymmetric-motion"))
    local world = assert(node._worldTransform,
        "asymmetric Motion did not publish a world transform")
    support.near(world.a, 1.8, "composed horizontal scale")
    support.near(world.b, 0, "unrotated horizontal skew")
    support.near(world.c, 0, "unrotated vertical skew")
    support.near(world.d, 0.6, "composed vertical scale")

    local pivotX = node.layout.x + node.layout.width * 0.5
    local pivotY = node.layout.y + node.layout.height
    local paintedPivotX = world.a * pivotX + world.c * pivotY + world.tx
    local paintedPivotY = world.b * pivotX + world.d * pivotY + world.ty
    support.near(paintedPivotX, pivotX + 12, "translated feet pivot x")
    support.near(paintedPivotY, pivotY - 6, "translated feet pivot y")
    support.near(node._visualBounds.width, 144,
        "asymmetric visual width")
    support.near(node._visualBounds.height, 24,
        "asymmetric visual height")

    observed = assert(observed,
        "custom painter omitted asymmetric transformed descendant")
    support.near(observed.transform.world.a, world.a,
        "custom paint horizontal transform")
    support.near(observed.transform.world.d, world.d,
        "custom paint vertical transform")

    local refRect = assert(motionRef.current,
        "asymmetric Motion ref did not publish")
    support.near(refRect.x, node.layout.x, "asymmetric rest ref x")
    support.near(refRect.y, node.layout.y, "asymmetric rest ref y")
    support.near(refRect.width, node.layout.width,
        "asymmetric rest ref width")
    support.near(refRect.height, node.layout.height,
        "asymmetric rest ref height")
    assert(refRect.width ~= node._visualBounds.width
            and refRect.height ~= node._visualBounds.height,
        "Motion ref stopped representing stable arranged geometry")

    local inspected
    for _, candidate in ipairs(host:inspectionTree().nodes) do
        if candidate.testId == "asymmetric-button" then
            inspected = candidate
            break
        end
    end
    inspected = assert(inspected,
        "F6 omitted asymmetric transformed Button")
    support.near(inspected.bounds.width, node._visualBounds.width,
        "F6 asymmetric width")
    support.near(inspected.bounds.height, node._visualBounds.height,
        "F6 asymmetric height")
    local hitX = inspected.bounds.x + inspected.bounds.width / 2
    local hitY = inspected.bounds.y + inspected.bounds.height / 2
    assert(host:pointerDown(hitX, hitY, "mouse", 1),
        "asymmetric transformed Button was not hittable")
    host:pointerUp(hitX, hitY, "mouse", 1)
    assert(presses == 1,
        "asymmetric transformed Button did not activate exactly once")
    host:unmount()

    local canvas = love.graphics.newCanvas(540, 960, { dpiscale = 1 })
    love.graphics.push("all")
    love.graphics.setCanvas { canvas, stencil = true }
    love.graphics.origin()
    love.graphics.clear(0, 0, 0, 0)
    host = support.host { width = 540, height = 960 }
    host:mount(Frog.Motion {
        width = 40,
        height = 40,
        x = 80,
        y = 40,
        scaleX = 2,
        scaleY = 0.5,
        pivot = { x = 0.5, y = 1 },
        Frog.Box {
            testId = "asymmetric-default-box",
            width = 40,
            height = 40,
            background = { 1, 1, 1, 1 },
        },
    })
    local paintedNode = assert(support.find(host:tree(),
        "asymmetric-default-box"))
    local paintedBounds = assert(paintedNode._visualBounds)
    host:draw()
    love.graphics.pop()
    local pixels = canvas:newImageData()
    local centerX = math.floor(paintedBounds.x + paintedBounds.width / 2)
    local centerY = math.floor(paintedBounds.y + paintedBounds.height / 2)
    local outsideY = math.max(0, math.floor(paintedBounds.y - 3))
    local outsideX = math.min(539,
        math.floor(paintedBounds.x + paintedBounds.width + 3))
    local _, _, _, painted = pixels:getPixel(centerX, centerY)
    local _, _, _, above = pixels:getPixel(centerX, outsideY)
    local _, _, _, beyond = pixels:getPixel(outsideX, centerY)
    assert(painted > 0.9 and above < 0.01 and beyond < 0.01,
        ("default paint disagreed with asymmetric feet-pivot geometry"
            .. " (inside=%.3f above=%.3f beyond=%.3f"
            .. " bounds=%.1f,%.1f %.1fx%.1f)")
            :format(painted, above, beyond,
                paintedBounds.x, paintedBounds.y,
                paintedBounds.width, paintedBounds.height))
    host:unmount()

    local clock = Frog.clock()
    host = support.host { width = 540, height = 960 }
    host:mount(Frog.Motion {
        testId = "asymmetric-animated",
        width = 40,
        height = 80,
        pivot = { x = 0.5, y = 1 },
        juice = { squash = { key = 1,
            recipe = Frog.withClock(clock, Frog.tween {
                to = { scaleX = 0.5, scaleY = 1.5 },
                duration = 1,
            }) } },
        Frog.Box { width = 40, height = 80 },
    })
    clock:advance(0.5)
    host:update(0)
    node = assert(support.find(host:tree(), "asymmetric-animated"))
    support.near(node.presentation.scaleX, 0.75,
        "animated horizontal scale midpoint")
    support.near(node.presentation.scaleY, 1.25,
        "animated vertical scale midpoint")
    pivotX = node.layout.x + node.layout.width * 0.5
    pivotY = node.layout.y + node.layout.height
    world = node._worldTransform
    support.near(world.a * pivotX + world.c * pivotY + world.tx,
        pivotX, "animated feet pivot x")
    support.near(world.b * pivotX + world.d * pivotY + world.ty,
        pivotY, "animated feet pivot y")
    host:unmount()

    host = support.host {
        width = 540,
        height = 960,
        reducedMotion = true,
    }
    host:mount(Frog.Motion {
        testId = "asymmetric-reduced",
        width = 20,
        height = 40,
        pivot = { x = 0.5, y = 1 },
        juice = { squash = { key = 1, recipe = Frog.tween {
            to = { scaleX = 0.5, scaleY = 1.5 },
            duration = 1,
        } } },
    })
    node = assert(support.find(host:tree(), "asymmetric-reduced"))
    support.near(node.presentation.scaleX, 0.5,
        "reduced-motion horizontal scale")
    support.near(node.presentation.scaleY, 1.5,
        "reduced-motion vertical scale")
    assert(next(node._motion.active) == nil,
        "reduced asymmetric Motion retained a runner")
    host:unmount()
end

local function ordinaryPaintAndTargetRemoval()
    local boxStyle, imageStyle
    local painter = {}
    function painter:box(node, style)
        if node.props.testId == "ordinary-opacity" then boxStyle = style end
    end
    function painter:image(node, _, style)
        if node.props.testId == "ordinary-tint" then imageStyle = style end
    end
    local host = support.host {
        width = 540, height = 960, painter = painter,
        assets = { icon = support.generatedImage(2, 2) },
    }
    host:mount(Frog.Column {
        Frog.Box {
            testId = "ordinary-opacity", opacity = 0.5,
            juice = { drift = Frog.tween { to = { x = 10 }, duration = 1 } },
        },
        Frog.Image {
            testId = "ordinary-tint", source = "icon",
            width = 20, height = 20, tint = { 0.5, 1, 1, 1 },
            juice = { drift = Frog.tween { to = { x = 10 }, duration = 1 } },
        },
    })
    host:draw()
    support.near(boxStyle.opacity, 0.5,
        "ordinary opacity with juice applied exactly once")
    support.near(imageStyle.tint[1], 0.5,
        "ordinary Image tint with juice applied exactly once")
    host:unmount()

    local clock = Frog.clock()
    local includeTargets = true
    -- Rebuilds one Motion while its unrelated keyed tween remains active.
    local function TargetTree()
        local props = {
            testId = "target-removal", width = 20, height = 20,
            juice = { drift = { key = 1, recipe = Frog.withClock(clock,
                Frog.tween { to = { x = 20 }, duration = 1 }) } },
        }
        if includeTargets then
            props.scale = 2
            props.tint = { 0.5, 0.5, 1, 1 }
        end
        return Frog.Motion(props)
    end
    host = support.host { width = 540, height = 960 }
    host:mount(TargetTree())
    clock:advance(0.5)
    host:update(0)
    includeTargets = false
    host:render(TargetTree())
    local entry
    for _, candidate in ipairs(host:inspectionTree().nodes) do
        if candidate.testId == "target-removal" then entry = candidate break end
    end
    support.near(entry.motion.current.x, 10,
        "unrelated recipe survived Motion target removal")
    support.near(entry.motion.current.scale, 1,
        "removed scale target restored neutral value")
    assert(entry.motion.current.tint == nil,
        "removed tint target did not restore neutral nil")
    clock:advance(0.25)
    host:update(0)
    entry = host:inspectionTree().nodes[1]
    support.near(entry.motion.current.x, 15,
        "unrelated recipe stopped after target removal")
    host:unmount()
end

local function retainedIdentityCompatibility()
    local clock = Frog.clock()
    local vertical, reverse = false, false
    -- Swaps only parent flow and keyed order; each Motion remains compatible.
    local function ResponsiveTree()
        local Flow = vertical and Frog.Column or Frog.Row
        local items = reverse and { "b", "a" } or { "a", "b" }
        return Flow {
            Frog.each(items, function(id)
                return Frog.Motion {
                    key = id,
                    testId = "retained-" .. id,
                    width = 20, height = 20,
                    juice = { appear = { key = 1,
                        recipe = Frog.withClock(clock,
                            Frog.tween { to = { x = 20 }, duration = 1 }) } },
                }
            end),
        }
    end
    local host = support.host { width = 540, height = 960 }
    host:mount(ResponsiveTree())
    clock:advance(0.5)
    host:update(0)
    vertical, reverse = true, true
    host:render(ResponsiveTree())
    local retained = assert(support.find(host:tree(), "retained-a"))
    support.near(retained.presentation.x, 10,
        "Row/Column reorder remounted keyed Motion")

    local kind = "Box"
    local kindKey = 1
    -- Reuses one keyed logical slot while deliberately changing primitive kind.
    local function KindTree()
        local Primitive = kind == "Box" and Frog.Box or Frog.Overlay
        return Primitive {
            key = "kind", testId = "kind-runtime", width = 20, height = 20,
            juice = { appear = { key = kindKey,
                recipe = Frog.withClock(clock,
                    Frog.tween { to = { x = 20 }, duration = 1 }) } },
        }
    end
    host:render(KindTree())
    clock:advance(0.25)
    host:update(0)
    kind = "Overlay"
    host:render(KindTree())
    support.near(assert(support.find(host:tree(), "kind-runtime")).presentation.x, 0,
        "incompatible primitive kind retained old runtime")
    clock:advance(0.25)
    host:update(0)
    support.near(assert(support.find(host:tree(), "kind-runtime")).presentation.x, 5,
        "incompatible primitive kind did not start a fresh runtime")
    host:unmount()

    local remounted = support.host { width = 540, height = 960 }
    remounted:mount(KindTree())
    support.near(assert(support.find(remounted:tree(), "kind-runtime")).presentation.x,
        0, "unmount/remount retained stale runtime")
    remounted:unmount()
end

local function exactTransformedClip()
    local canvas = love.graphics.newCanvas(540, 960, { dpiscale = 1 })
    local previous = love.graphics.getCanvas()
    love.graphics.setCanvas { canvas, stencil = true }
    love.graphics.clear(0, 0, 0, 0)
    local presses = 0
    local host = support.host { width = 540, height = 960 }
    host:mount(Frog.Motion {
        width = 100, height = 100,
        x = 200, y = 200, rotation = math.pi / 4,
        Frog.Box {
            width = 100, height = 100, padding = 10, clip = true,
            Frog.Box {
                width = 100, height = 100, offset = { x = 70 }, clip = true,
                Frog.Button {
                    testId = "rotated-clipped-button",
                    width = 100, height = 100,
                    background = { 1, 1, 1, 1 },
                    onPress = function() presses = presses + 1 end,
                },
            },
        },
    })
    host:draw()
    love.graphics.setCanvas(previous)
    local pixels = canvas:newImageData()
    local _, _, _, leaked = pixels:getPixel(305, 255)
    local _, _, _, visible = pixels:getPixel(275, 275)
    local count, minX, maxX, minY, maxY = 0
    for y = 170, 330 do
        for x = 170, 330 do
            local _, _, _, alpha = pixels:getPixel(x, y)
            if alpha > 0.5 then
                count = count + 1
                minX, maxX = math.min(minX or x, x), math.max(maxX or x, x)
                minY, maxY = math.min(minY or y, y), math.max(maxY or y, y)
            end
        end
    end
    assert(leaked < 0.01,
        "rotated nested clip leaked through its transformed AABB: "
            .. tostring(leaked))
    assert(visible > 0.9,
        "rotated nested clip removed content inside both clip shapes: "
            .. tostring(visible) .. ", count=" .. tostring(count)
            .. ", bounds=" .. table.concat({ minX or -1, minY or -1,
                maxX or -1, maxY or -1 }, ","))
    assert(not host:pointerDown(305, 255, "mouse", 1),
        "rotated nested clip leaked Button input outside the clip")
    host:pointerUp(305, 255, "mouse", 1)
    assert(host:pointerDown(275, 275, "mouse", 1),
        "rotated nested clip rejected Button input inside the clip")
    host:pointerUp(275, 275, "mouse", 1)
    assert(presses == 1, "rotated clipped Button did not activate exactly once")
    host:setInspectorVisible(true)
    local inside = assert(host:inspect(275, 275),
        "F6 could not inspect inside the rotated nested clip")
    assert(inside.testId == "rotated-clipped-button",
        "F6 did not select the transformed clipped Button")
    local outside = host:inspect(305, 255)
    assert(not outside or outside.testId ~= "rotated-clipped-button",
        "F6 leaked through the transformed nested clip")
    host:setInspectorVisible(false)
    host:unmount()
end

local function keyedRetentionAndFeedback()
    local cues = {}
    local replayKey = 1
    local clock = Frog.clock()
    -- Rebuilds the same keyed element; only replayKey may restart its recipe.
    local function KeyedTree()
        return Frog.Box {
            key = "stable",
            testId = "keyed-motion",
            width = 20,
            height = 20,
            juice = {
                appear = {
                    key = replayKey,
                    recipe = Frog.withClock(clock, Frog.sequence {
                        Frog.tween { to = { x = 20 }, duration = 1 },
                        Frog.sound { cue = "done" },
                    }),
                },
            },
        }
    end
    local host = support.host { width = 540, height = 960,
        feedback = { sound = function(cue) cues[#cues + 1] = cue end } }
    host:mount(KeyedTree())
    local mountedMeta = host:inspectionTree().nodes[1].motion
    assert(mountedMeta.declared[1].name == "appear"
            and mountedMeta.declared[1].clock == "explicit"
            and mountedMeta.declared[1].key == 1
            and mountedMeta.reactionCount == 0
            and mountedMeta.reducedMotion == false,
        "F6 omitted declared recipe clock/key/reaction metadata")
    assert(mountedMeta.activeDetails[1].name == "appear"
            and mountedMeta.activeDetails[1].elapsed == 0
            and mountedMeta.activeDetails[1].duration == 1
            and mountedMeta.activeDetails[1].progress == 0,
        "F6 omitted active recipe timing metadata")
    clock:advance(0.5)
    host:update(0)
    local before = host:inspectionTree().nodes[1].motion.current.x
    host:render(KeyedTree())
    clock:advance(0.25)
    host:update(0)
    local same = host:inspectionTree().nodes[1].motion.current.x
    support.near(before, 10, "keyed midpoint")
    support.near(same, 15, "same-key rerender retained elapsed recipe")
    replayKey = 2
    host:render(KeyedTree())
    clock:advance(0.25)
    host:update(0)
    local restarted = host:inspectionTree().nodes[1].motion.current.x
    support.near(restarted, 16.25, "changed key restarted from current value")
    replayKey = nil
    host:render(KeyedTree())
    replayKey = 2
    host:render(KeyedTree())
    clock:advance(0.25)
    host:update(0)
    support.near(host:inspectionTree().nodes[1].motion.current.x, 17.1875,
        "nil key did not disarm the prior replay key")
    assert(#cues == 0, "keyed tween feedback fired before sequence completion")
    host:unmount()
end

local function deterministicFeedbackAndSpring()
    local cues = {}
    local host = support.host { width = 540, height = 960,
        feedback = { sound = function(cue) cues[#cues + 1] = cue end } }
    host:mount(Frog.Box {
        juice = {
            zeta = { key = 1, recipe = Frog.sound { cue = "zeta" } },
            alpha = { key = 1, recipe = Frog.sound { cue = "alpha" } },
        },
    })
    assert(cues[1] == "alpha" and cues[2] == "zeta",
        "keyed recipe feedback followed unordered map traversal")
    host:unmount()

    cues = {}
    local sequenceClock = Frog.clock()
    host = support.host { width = 540, height = 960,
        feedback = { sound = function(cue) cues[#cues + 1] = cue end } }
    host:mount(Frog.Box { juice = { timing = { key = 1,
        recipe = Frog.withClock(sequenceClock, Frog.sequence {
            Frog.sound { cue = "sequence-start" },
            Frog.delay(0.2),
            Frog.sound { cue = "sequence-later" },
        }) } } })
    assert(cues[1] == "sequence-start" and cues[2] == nil,
        "sequence did not emit its zero-time feedback exactly once")
    sequenceClock:advance(0.19)
    host:update(0)
    assert(cues[2] == nil, "sequence emitted delayed feedback too early")
    sequenceClock:advance(0.01)
    host:update(0)
    assert(cues[2] == "sequence-later" and cues[3] == nil,
        "sequence cursor delayed or duplicated feedback")
    host:unmount()

    cues = {}
    local clock = Frog.clock()
    host = support.host { width = 540, height = 960,
        feedback = { sound = function(cue) cues[#cues + 1] = cue end } }
    local function Delayed(id)
        return Frog.Box {
            key = id,
            juice = { cue = { key = 1, recipe = Frog.withClock(clock,
                Frog.sequence { Frog.delay(0.1), Frog.sound { cue = id } }) } },
        }
    end
    host:mount(Frog.Column { Delayed("first"), Delayed("second") })
    clock:advance(0.1)
    host:update(0)
    assert(cues[1] == "first" and cues[2] == "second",
        "motion updates did not follow committed tree order")
    host:unmount()

    local function SpringRun(parts)
        local springClock, springCues = Frog.clock(), {}
        local springHost = support.host { width = 540, height = 960,
            feedback = { sound = function(cue)
                springCues[#springCues + 1] = cue
            end } }
        springHost:mount(Frog.Box {
            testId = "spring-runtime",
            juice = { settle = { key = 1, recipe = Frog.withClock(springClock,
                Frog.sequence {
                    Frog.spring { to = { x = 20 }, frequency = 10, damping = 1 },
                    Frog.sound { cue = "settled" },
                }) } },
        })
        for _, dt in ipairs(parts) do
            springClock:advance(dt)
            springHost:update(0)
        end
        local x = assert(support.find(springHost:tree(), "spring-runtime")).presentation.x
        springHost:unmount()
        return x, springCues
    end
    local wholeX, wholeCues = SpringRun { 0.7 }
    local splitX, splitCues = SpringRun { 0.2, 0.15, 0.35 }
    support.near(wholeX, 20, "spring exact completion")
    support.near(splitX, wholeX, "spring dt partition")
    assert(wholeCues[1] == "settled" and splitCues[1] == "settled",
        "sequenced spring completion did not fire exactly once")

    local jumpClock = Frog.clock()
    local jumpHost = support.host { width = 540, height = 960 }
    jumpHost:mount(Frog.Box { juice = { ticking = { key = 1,
        recipe = Frog.withClock(jumpClock, Frog.loop(Frog.sequence {
            Frog.delay(0.001), Frog.sound { cue = "tick" },
        })) } } })
    jumpClock:advance(2)
    expectError(function() jumpHost:update(0) end,
        "crossed more than 1024 cycles")
    expectFault(jumpHost, "Host:update", function() jumpHost:update(0) end,
        "failed Motion update")
    jumpHost:unmount()
end

local function unifiedEventPreorder()
    local function Listener(id)
        return Frog.Box {
            key = id,
            juice = { pulse = Frog.shake { x = 1 } },
            reactions = { Frog.on(Ordered) { do_ = Frog.play("pulse") } },
        }
    end
    local host = support.host { width = 540, height = 960 }
    host:mount(Frog.Column {
        Listener("element-1"),
        OrderedActor { key = "actor-1" },
        Listener("element-2"),
        OrderedActor { key = "actor-2" },
    })
    Frog.emit(Ordered {})
    local trace = host:messageTrace()
    local delivered = trace[#trace]
    local recipients = delivered.recipients
    assert(#recipients == 4
            and recipients[1]:sub(1, 6) == "juice:"
            and recipients[2]:sub(1, 6) ~= "juice:"
            and recipients[3]:sub(1, 6) == "juice:"
            and recipients[4]:sub(1, 6) ~= "juice:",
        "event recipients did not follow unified committed-tree preorder")
    for _, transition in ipairs(delivered.transitions) do
        assert(type(transition.changed) == "boolean",
            "Motion event trace omitted boolean changed status")
    end
    host:unmount()
end

local function activeCandidateAtomicity()
    local clock = Frog.clock()
    local host = support.host { width = 540, height = 960 }
    local function ActiveTree()
        return Frog.Box {
            testId = "active-candidate",
            juice = { appear = { key = 1, recipe = Frog.withClock(clock,
                Frog.tween { to = { x = 20 }, duration = 1 }) } },
        }
    end
    host:mount(ActiveTree())
    clock:advance(0.5)
    host:update(0)
    expectError(function()
        host:render(Frog.Box { juice = {
            broken = Frog.loop(Frog.sound { cue = "zero" }),
        } })
    end, "cannot repeat a zero-duration recipe")
    support.near(assert(support.find(host:tree(), "active-candidate")).presentation.x,
        10, "failed render replaced active motion tree")
    clock:advance(0.25)
    host:update(0)
    support.near(assert(support.find(host:tree(), "active-candidate")).presentation.x,
        15, "active recipe did not survive failed render")
    host:unmount()

    clock = Frog.clock()
    host = support.host { width = 540, height = 960 }
    host:mount(ResizeProbe { clock = clock })
    clock:advance(0.5)
    host:update(0)
    expectError(function() host:resize(960, 540) end,
        "intentional motion resize render failure")
    assert(not host:viewport().wide,
        "failed resize did not restore the prior viewport")
    clock:advance(0.25)
    host:update(0)
    support.near(assert(support.find(host:tree(), "resize-runtime")).presentation.x,
        15, "active recipe did not survive failed resize")
    host:unmount()
end

local function runtimeFaultAndReducedMotion()
    local cues = {}
    local faultCleanups = 0
    local RuntimeFaultOwner = Frog.component(
            "MotionCheckRuntimeFaultOwner", function()
        Frog.useResource(function()
            return {}, function() faultCleanups = faultCleanups + 1 end
        end)
        return Frog.Column {
            BrokenActor { address = BrokenActor.App },
            ImpactTarget { id = "fault" },
            Frog.Button {
                testId = "fault-button",
                width = 80, height = 30,
                onPress = function()
                    Frog.emit(Impact { id = "fault" })
                    Frog.send(BrokenActor.App, Break {})
                end,
                Frog.Text "Break",
            },
        }
    end)
    local host = support.host { width = 540, height = 960,
        feedback = {
            sound = function(cue) cues[#cues + 1] = "sound:" .. cue end,
            haptic = function(cue) cues[#cues + 1] = "haptic:" .. cue end,
        },
    }
    host:mount(RuntimeFaultOwner {})
    local button = assert(support.find(host:tree(), "fault-button"))
    local x, y = support.center(button)
    host:pointerDown(x, y, "mouse", 1)
    expectError(function() host:pointerUp(x, y, "mouse", 1) end,
        "intentional motion runtime render failure")
    assert(#cues == 0, "runtime fault leaked staged sound/haptic")
    expectFault(host, "Button:", function()
        host:pointerUp(x, y, "mouse", 1)
    end, "failed Motion callback")
    host:unmount()
    assert(faultCleanups == 1,
        "faulted Motion callback did not clean its resource exactly once")

    local reduced = support.host { width = 540, height = 960,
        reducedMotion = true,
        feedback = {
            sound = function(cue) cues[#cues + 1] = "sound:" .. cue end,
            haptic = function(cue) cues[#cues + 1] = "haptic:" .. cue end,
        },
    }
    reduced:mount(Frog.Box {
        testId = "reduced",
        width = 20, height = 20,
        juice = { appear = { key = 1, recipe = Frog.sequence {
            Frog.sound { cue = "start" },
            Frog.delay(1),
            Frog.tween { to = { x = 30 }, duration = 1 },
            Frog.haptic { cue = "finish" },
        } } },
    })
    local entry = reduced:inspectionTree().nodes[1]
    support.near(entry.motion.current.x, 30, "reduced motion settled transform")
    assert(#entry.motion.active == 0,
        "reduced motion retained an active recipe")
    assert(cues[#cues - 1] == "sound:start" and cues[#cues] == "haptic:finish",
        "reduced motion did not preserve ordered feedback leaves")
    reduced:unmount()
end

function check.run()
    constructorAndClockContracts()
    pulseContract()
    deterministicClockAndNoRerender()
    cachedCommittedTransforms()
    transformLocalityAttribution()
    exactDirtyBranchExecution()
    branchFallbackAndLifecycle()
    keyedEntranceUsesMotionBase()
    staticMotionLifecycle()
    transformedPaintInputAndInspector()
    asymmetricScaleAndPivot()
    ordinaryPaintAndTargetRemoval()
    retainedIdentityCompatibility()
    exactTransformedClip()
    keyedRetentionAndFeedback()
    deterministicFeedbackAndSpring()
    unifiedEventPreorder()
    activeCandidateAtomicity()
    runtimeFaultAndReducedMotion()
    completionLifecycle()
end

return check
