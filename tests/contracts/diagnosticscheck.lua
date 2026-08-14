-- Focused contract for the opt-in FrogUI Host profiler. It proves semantic
-- activity is attributed without changing the actor/component API.

local Frog = require("frogui")
local Diagnostics = require("frogui.diagnostics")
local support = require("tests.support")

local check = {}

local Advanced = Frog.action("DiagnosticsCheck.Advanced")
local Shifted = Frog.event("DiagnosticsCheck.Shifted")

local Probe = Frog.actor("DiagnosticsCheckProbe", {
    initial = 0,
    actions = {
        [Advanced] = function(state) return state + 1 end,
    },
    render = function(_, state, send)
        Frog.useFrame(function()
            send(Advanced {})
        end)
        return Frog.Box {
            testId = "diagnostics-probe",
            width = 40,
            height = 40,
            Frog.Text { tostring(state) },
        }
    end,
})

-- Exercises every B4p.6 attribution boundary without making application fixtures
-- part of the generic profiler contract.
local AttributionProbe = Frog.component(
    "DiagnosticsCheckAttributionProbe", function()
        local anchor = Frog.useRef()
        return Frog.Column {
            width = 120,
            height = 120,
            gap = 2,
            Frog.Box {
                ref = anchor,
                width = 10,
                height = 10,
            },
            Frog.Scroll {
                key = "scroll",
                width = 20,
                height = 20,
                axis = "vertical",
                Frog.Box { width = 20, height = 30 },
            },
            Frog.RadialDial {
                key = "dial",
                width = 32,
                height = 32,
                trackRadius = 8,
                value = 1,
                values = { 1, 2 },
                onChange = function() end,
                Frog.Box { key = 1, width = 6, height = 6 },
                Frog.Box { key = 2, width = 6, height = 6 },
            },
            Frog.Motion {
                key = "motion",
                width = 10,
                height = 10,
                Frog.Box { width = 10, height = 10 },
            },
            Frog.EffectLayer {
                width = 20,
                height = 20,
                Frog.Projectile {
                    key = "projectile",
                    from = { x = 1, y = 1 },
                    to = { x = 10, y = 10 },
                    duration = 1,
                },
                Frog.PopupText {
                    key = "popup",
                    text = "1",
                    at = { x = 5, y = 5 },
                    duration = 1,
                },
            },
        }
    end)

local StaticRefProbe = Frog.component("DiagnosticsCheckStaticRefProbe",
    function()
        local anchor = Frog.useRef()
        return Frog.Box {
            ref = anchor,
            testId = "diagnostics-static-ref",
            width = 20,
            height = 20,
        }
    end)

local GeometryMotionProbe = Frog.component(
    "DiagnosticsCheckGeometryMotionProbe", function(props)
        local anchor = Frog.useRef()
        return Frog.Motion {
            ref = anchor,
            testId = "diagnostics-geometry-motion",
            width = 20,
            height = 20,
            juice = { travel = { key = 1,
                recipe = Frog.withClock(props.clock, Frog.tween {
                    to = { x = 20 }, duration = 1,
                }) } },
        }
    end)

local CosmeticMotionProbe = Frog.component(
    "DiagnosticsCheckCosmeticMotionProbe", function(props)
        return Frog.Motion {
            testId = "diagnostics-cosmetic-motion",
            width = 20,
            height = 20,
            juice = { fade = { key = 1,
                recipe = Frog.withClock(props.clock, Frog.tween {
                    to = { opacity = 0.5 }, duration = 1,
                }) } },
        }
    end)

local MessageMotionProbe = Frog.component(
    "DiagnosticsCheckMessageMotionProbe", function()
        return Frog.Motion {
            testId = "diagnostics-message-motion",
            width = 20,
            height = 20,
            juice = {
                shift = Frog.tween { to = { x = 12 }, duration = 0.2 },
            },
            reactions = {
                Frog.on(Shifted) { do_ = Frog.play("shift") },
            },
        }
    end)

local comparisonCallbackCalls = 0
local function stableComparisonCallback()
    comparisonCallbackCalls = comparisonCallbackCalls + 1
end

-- Gives the candidate observer one small keyed tree whose layout, paint,
-- interaction callback, and topology can change independently.
local CandidateComparisonProbe = Frog.actor(
    "DiagnosticsCandidateComparisonProbe", {
        initial = 7,
        render = function(props)
            local children = {
                Frog.Button {
                    key = "control",
                    testId = "diagnostics-candidate-control",
                    width = 24,
                    height = 16,
                    onPress = props.onPress,
                    onHoverChange = props.onHoverChange,
                    Frog.Text { "Probe" },
                },
                Frog.Motion {
                    key = "stable",
                    width = 12,
                    height = 12,
                    juice = props.juice,
                },
            }
            if props.extra then
                children[#children + 1] = Frog.Box {
                    key = "extra", width = 8, height = 8,
                }
            end
            return Frog.Column {
                testId = "diagnostics-candidate-comparison",
                width = props.width,
                height = 80,
                background = props.background,
                unpack(children),
            }
        end,
    })

local function hasOwner(owners, name)
    for _, owner in ipairs(owners or {}) do
        if owner.name == name then return true end
    end
    return false
end

local function onlyTrace(host)
    local trace = host:diagnosticTrace()
    local row = assert(trace[#trace],
        "FrogUI diagnostic check expected one row")
    for context, transform in pairs(row.transformAttribution or {}) do
        assert(transform.calls == transform.runs + transform.skips,
            context .. " transform calls did not partition into run/skip")
        if transform.runs == 0 then
            assert(transform.nodesVisited == 0,
                context .. " skipped transforms visited nodes")
        end
    end
    return row
end

local function hasKey(map, fragment)
    for name in pairs(map or {}) do
        if name:find(fragment, 1, true) then return true end
    end
    return false
end

-- Exercises committed transform locality and arranged-ref revision gating
-- without running the graphical allocation probe.
local function transformAndRefAttribution()
    local host = support.host {
        width = 120, height = 120, diagnostics = true,
    }
    host:mount(StaticRefProbe {})
    local initialRefRevision = host._arrangedRefRevision
    assert(initialRefRevision > 0
            and host._publishedRefRevision == initialRefRevision,
        "initial ref publication did not synchronize its revision")
    host:clearDiagnostics()
    host:update(0)
    host:draw({})
    local clean = onlyTrace(host)
    local committed = assert(clean.transformAttribution.committed,
        "clean frame omitted committed transform attribution")
    local refs = assert(clean.refAttribution.committed,
        "clean frame omitted committed ref attribution")
    assert(committed.calls == 1 and committed.skips == 1
            and committed.runs == 0 and committed.nodesVisited == 0
            and committed.invalidations == 0,
        "clean committed transform did recursive work or claimed a cause")
    assert(refs.calls == 1 and refs.skips == 1
            and refs.treeVisits == 0 and refs.published == 0
            and refs.changedRectangles == 0,
        "clean committed refs did not take the revision-proven skip")

    -- Two exact Scroll invalidations collapse into one immediate transform;
    -- a following RadialDial transform remains a separate interaction call.
    host:clearDiagnostics()
    host._diagnostics:ensureFrame()
    local node = assert(support.find(host:tree(), "diagnostics-static-ref"))
    node.layout.x = node.layout.x + 3
    host:_invalidateTransform(node, "Scroll", "drag")
    host:_invalidateTransform(node, "Scroll", "drag")
    local _, scrollTransform = host:_transformTree(nil,
        "interactionTransform")
    host:_refreshCommittedRefs("interaction", scrollTransform)
    node.layout.y = node.layout.y + 2
    host:_invalidateTransform(node, "RadialDial", "settle")
    local _, radialTransform = host:_transformTree(nil,
        "interactionTransform")
    host:_refreshCommittedRefs("interaction", radialTransform)
    host:update(0)
    host:draw({})
    local interaction = onlyTrace(host)
    local interactionTransform = assert(
        interaction.transformAttribution.interaction)
    local interactionRefs = assert(interaction.refAttribution.interaction)
    local followingCommitted = assert(
        interaction.transformAttribution.committed)
    assert(interactionTransform.calls == 2
            and interactionTransform.runs == 2
            and interactionTransform.branchRuns == 0
            and interactionTransform.fullRuns == 2
            and interactionTransform.fallbackRuns == 0
            and interactionTransform.invalidations == 3
            and interactionTransform.coalescedInvalidations == 1
            and interactionTransform.dirtyRoots == 2
            and interactionTransform.families.Scroll == 2
            and interactionTransform.families.RadialDial == 1
            and next(interactionTransform.owners) == nil
            and next(interactionTransform.recipes) == nil,
        "immediate interaction transforms lost source/coalescing attribution")
    assert(interactionRefs.calls == 2
            and interactionRefs.skips == 0
            and interactionRefs.changedRectangles == 2
            and interactionRefs.interactionInvalidated == 2,
        "interaction refs lost actual changed-rectangle attribution")
    assert(followingCommitted.skips == 1
            and followingCommitted.nodesVisited == 0,
        "interaction transform was misreported as a committed run")

    host:clearDiagnostics()
    host:render(StaticRefProbe {})
    assert(host._arrangedRefRevision > initialRefRevision
            and host._publishedRefRevision == host._arrangedRefRevision,
        "candidate ref publication did not synchronize its revision")
    host:update(0)
    host:draw({})
    local rebuilt = onlyTrace(host)
    assert(rebuilt.transformAttribution.candidate.runs == 1
            and rebuilt.transformAttribution.candidate.fullRuns == 1
            and rebuilt.transformAttribution.candidate.branchRuns == 0
            and rebuilt.transformAttribution.committed.skips == 1,
        "candidate and committed transforms were not kept separate")
    node = assert(support.find(host:tree(), "diagnostics-static-ref"))
    host:_invalidateTransform(node, "interaction", "other")
    assert(host._pendingTransformAttribution,
        "diagnostic lifecycle check did not create a pending cause")
    host:unmount()
    assert(host._pendingTransformAttribution == nil,
        "unmounted Host retained diagnostic node references")
    assert(host._arrangedRefRevision == 0
            and host._publishedRefRevision == 0,
        "unmounted Host retained arranged-ref revisions")

    local clock = Frog.clock()
    host = support.host { width = 120, height = 120, diagnostics = true }
    host:mount(GeometryMotionProbe { clock = clock })
    host:clearDiagnostics()
    clock:advance(0.5)
    host:update(0)
    host:draw({})
    local moving = onlyTrace(host)
    local motionTransform = assert(moving.transformAttribution.committed)
    local motionRefs = assert(moving.refAttribution.committed)
    assert(motionTransform.runs == 1
            and motionTransform.families.Motion == 1
            and motionTransform.changingOwners == 1
            and motionTransform.activeGeometryMotions == 1
            and motionTransform.dirtyRoots == 1
            and motionTransform.branchRuns == 1
            and motionTransform.fullRuns == 0
            and motionTransform.fallbackRuns == 0
            and motionTransform.nodesVisited
                == motionTransform.branchCoverage
            and motionTransform.lcaCoverage == 0
            and motionTransform.routingTreeVisits == 0,
        "geometry Motion lost committed locality attribution")
    assert(hasKey(motionTransform.owners,
            "DiagnosticsCheckGeometryMotionProbe")
            and hasKey(motionTransform.recipes, "travel|with_clock|translate")
            and not hasKey(motionTransform.owners, "logical-root"),
        "geometry Motion metadata was unbounded or omitted semantic recipe data")
    assert(motionRefs.visualTransformChanged == 1
            and motionRefs.calls == 1 and motionRefs.skips == 1
            and motionRefs.treeVisits == 0
            and motionRefs.published == 0 and motionRefs.cleared == 0
            and motionRefs.changedRectangles == 0,
        "visual-only Motion did not preserve arranged refs by revision")
    host:unmount()

    clock = Frog.clock()
    host = support.host { width = 120, height = 120, diagnostics = true }
    host:mount(CosmeticMotionProbe { clock = clock })
    host:clearDiagnostics()
    clock:advance(0.5)
    host:update(0)
    host:draw({})
    local cosmetic = onlyTrace(host).transformAttribution.committed
    assert(cosmetic.skips == 1 and cosmetic.nodesVisited == 0
            and cosmetic.activeGeometryMotions == 0
            and cosmetic.families.Motion == nil,
        "opacity-only Motion was attributed as geometry")
    host:unmount()

    host = support.host {
        width = 120, height = 120, diagnostics = true, reducedMotion = true,
    }
    host:mount(MessageMotionProbe {})
    host:clearDiagnostics()
    Frog.emit(Shifted {})
    host:update(0)
    host:draw({})
    local messaged = onlyTrace(host).transformAttribution
    assert(messaged.message.runs == 1
            and messaged.message.branchRuns == 0
            and messaged.message.fullRuns == 1
            and messaged.message.fallbackRuns == 0
            and messaged.message.families.Motion == 1
            and messaged.message.details["Motion:event-play"] == 1
            and messaged.committed.skips == 1,
        "message-triggered Motion was folded into committed transform work")
    host:unmount()
end

-- Proves B4p.28 remains an observational, commit-scoped census. Equal resolved
-- results are reported separately from opaque callback identity, while a
-- rejected candidate never reaches the trace.
local function candidateComparisonAttribution()
    local host = support.host {
        width = 140, height = 120, diagnostics = true,
    }
    local function description(width, background, callback, extra, juice,
            onHoverChange)
        return CandidateComparisonProbe {
            width = width,
            background = background,
            onPress = callback,
            extra = extra,
            juice = juice,
            onHoverChange = onHoverChange,
        }
    end
    host:mount(description(80, { 0.1, 0.2, 0.3, 1 },
        stableComparisonCallback, false))

    host:clearDiagnostics()
    host:render(description(80, { 0.1, 0.2, 0.3, 1 },
        stableComparisonCallback, false))
    host:update(0)
    host:draw({})
    local row = onlyTrace(host)
    local comparison = assert(row.candidateComparisons[1],
        "successful FrogUI rebuild omitted its candidate comparison")
    assert(#row.candidateComparisons == 1
            and comparison.rootActor == "DiagnosticsCandidateComparisonProbe"
            and comparison.rootRevision == 7,
        "candidate comparison lost its bounded root actor/revision context")
    assert(comparison.candidateNodes == comparison.matchedNodes
            and comparison.committedNodes == comparison.matchedNodes
            and comparison.addedNodes == 0 and comparison.removedNodes == 0,
        "equal candidate comparison reported inconsistent node coverage")
    for _, category in ipairs {
            "physical", "type", "topology", "layout", "geometry", "paint",
            "interaction", "retained" } do
        assert((comparison.stable[category] or 0)
                + (comparison.changed[category] or 0)
                + (comparison.unknown[category] or 0)
                    == comparison.matchedNodes,
            "candidate comparison did not partition " .. category)
    end
    assert(comparison.stable.topology == comparison.matchedNodes
            and comparison.stable.geometry == comparison.matchedNodes
            and comparison.unknown.interaction >= 1
            and comparison.callbackUnknownObservations >= 1
            and comparison.stableTopologyBranches[1].nodes
                == comparison.candidateNodes
            and comparison.stableGeometryBranches[1].nodes
                == comparison.candidateNodes,
        "equal candidate results were not separated from callback opacity")
    assert(comparison.layoutReuseStableInputNodes == comparison.matchedNodes
            and comparison.layoutReuseExactOutputNodes
                == comparison.matchedNodes
            and comparison.layoutReuseEligibleNodes
                == comparison.candidateNodes
            and comparison.layoutReuseBranchCount == 1
            and comparison.layoutReuseBranches[1].nodes
                == comparison.candidateNodes,
        "closed stable layout inputs did not prove the exact output branch")

    local function publish(nextDescription)
        host:clearDiagnostics()
        host:render(nextDescription)
        host:update(0)
        host:draw({})
        local nextRow = onlyTrace(host)
        return assert(nextRow.candidateComparisons[1]), nextRow
    end

    comparison = publish(description(92, { 0.1, 0.2, 0.3, 1 },
        stableComparisonCallback, false))
    assert(comparison.changed.layout == 1
            and comparison.changed.paint == 0
            and comparison.changed.interaction == 0
            and comparison.changed.retained == 0
            and comparison.changed.topology == 0,
        "layout-only candidate leaked into another authored family")

    comparison = publish(description(92, { 0.4, 0.2, 0.1, 1 },
        stableComparisonCallback, false))
    assert(comparison.changed.paint == 1
            and comparison.changed.layout == 0
            and comparison.changed.interaction == 0
            and comparison.changed.retained == 0
            and comparison.changed.topology == 0
            and comparison.changed.geometry == 0,
        "paint-only candidate leaked into layout or retained observation")

    local changedCallback = function() end
    comparison = publish(description(92, { 0.4, 0.2, 0.1, 1 },
        changedCallback, false))
    assert(comparison.changed.interaction == 0
            and comparison.unknown.interaction >= 1
            and comparison.callbackUnknownObservations >= 1,
        "callback-only candidate was treated as semantic equality or change")

    local pulse = { pulse = Frog.tween {
        to = { opacity = 0.8 }, duration = 0.2,
    } }
    comparison = publish(description(92, { 0.4, 0.2, 0.1, 1 },
        changedCallback, false, pulse))
    assert(comparison.changed.retained == 1
            and comparison.changed.layout == 0
            and comparison.changed.paint == 0
            and comparison.changed.topology == 0,
        "retained-membership input leaked into another authored family")

    publish(description(92, { 0.4, 0.2, 0.1, 1 },
        changedCallback, false))
    comparison, row = publish(description(92, { 0.4, 0.2, 0.1, 1 },
        changedCallback, true))
    assert(comparison.addedNodes == 1 and comparison.removedNodes == 0
            and comparison.changed.topology == 1
            and comparison.changed.layout == 0
            and comparison.changed.paint == 0
            and comparison.changed.retained == 0,
        "topology-only candidate leaked into another authored family")
    assert(comparisonCallbackCalls == 0,
        "candidate comparison invoked an authored callback")

    local exported = host:diagnosticTrace()
    exported[1].candidateComparisons[1].stable.layout = 999
    exported[1].candidateComparisons[1].changedOwners.layout.mutated = 999
    exported[1].candidateComparisons[1].stableTopologyBranches[1].owner =
        "mutated"
    exported[1].candidateComparisons[1].layoutReuseBranches[1] = {
        owner = "mutated", logicalIdentity = "mutated", nodes = 999,
    }
    local detached = host:diagnosticTrace()[1].candidateComparisons[1]
    assert(detached.stable.layout ~= 999
            and detached.changedOwners.layout.mutated == nil
            and detached.stableTopologyBranches[1].owner ~= "mutated"
            and (detached.layoutReuseBranches[1] or {}).owner ~= "mutated",
        "candidate comparison trace exposed retained profiler storage")

    host:unmount()

    -- The candidate below completes comparison and publication work, then its
    -- removed hover edge throws from Interaction.afterCommit. A comparison may
    -- be retained only after the complete Host operation succeeds.
    local faultHost = support.host {
        width = 540, height = 960, diagnostics = true,
    }
    local function hoverFailure(hovered)
        if not hovered then error("intentional candidate commit failure") end
    end
    faultHost:mount(description(80, { 0.1, 0.2, 0.3, 1 },
        stableComparisonCallback, false, nil, hoverFailure))
    local control = assert(support.find(faultHost:tree(),
        "diagnostics-candidate-control"))
    assert(control.props.onHoverChange == hoverFailure,
        "candidate commit fixture lost its authored hover callback")
    faultHost._hoveredIdentity = control.identity
    faultHost:clearDiagnostics()
    local accepted = pcall(faultHost.render, faultHost,
        Frog.Box { width = 20, height = 20 })
    assert(not accepted, "candidate comparison commit fixture did not fail")
    faultHost:draw({})
    local faultTrace = faultHost._diagnostics:trace()
    assert(#faultTrace == 1
            and #faultTrace[1].candidateComparisons == 0,
        "failed Host commit contaminated candidate comparison evidence")
    faultHost:unmount()
end

function check.run()
    candidateComparisonAttribution()
    transformAndRefAttribution()
    local host = support.host {
        width = 120,
        height = 120,
        diagnostics = true,
    }
    host:mount(Probe {})
    host:update(1 / 60)
    assert(host:diagnostics().samples == 0,
        "FrogUI profiler exposed an unfinished update as a complete frame")
    host:draw({})

    local snapshot = host:diagnostics()
    assert(snapshot.enabled and snapshot.samples == 1,
        "FrogUI profiler did not retain one completed frame")
    assert(snapshot.counts.messages == 1
            and snapshot.counts.reconciles == 1,
        "FrogUI profiler did not attribute one semantic reconciliation")
    assert(snapshot.activityTotals.messages == 1
            and snapshot.activityTotals.actionMessages == 1
            and snapshot.activityTotals.actorTransitions == 1
            and snapshot.activityTotals.acceptedActorTransitions == 1
            and snapshot.activityTotals.changedActorTransitions == 1,
        "FrogUI profiler did not retain typed message/transition activity")
    assert(snapshot.cohorts.reconciled.samples == 1
            and snapshot.cohorts.quiet.samples == 0
            and snapshot.cohorts.reconciled.activityTotals.reconciles == 1,
        "FrogUI profiler did not separate reconciled and quiet frames")
    assert(snapshot.causes[1]
            and snapshot.causes[1].name:find(
                "DiagnosticsCheck.Advanced", 1, true),
        "FrogUI profiler omitted its typed dirty cause")
    assert(snapshot.counts.nodes >= 2
            and snapshot.counts.renderOwners >= 1,
        "FrogUI profiler omitted committed tree pressure")
    assert(snapshot.slowest and snapshot.slowest.totalMs >= 0
            and type(snapshot.slowest.phases.reconcile) == "number"
            and snapshot.slowest.causes[1]
            and snapshot.slowest.causes[1].name:find(
                "DiagnosticsCheck.Advanced", 1, true),
        "FrogUI profiler omitted its correlated slowest-frame record")
    for _, name in ipairs({ "total", "update", "frameCallbacks",
            "messageDelivery", "actionProcessing", "eventProcessing",
            "actorTransitions", "reconcile", "componentExpansion",
            "semanticRender", "semanticPreparation",
            "semanticBookkeeping", "primitiveValidation",
            "primitiveMaterialization", "primitivePostValidation",
            "scrollReconciliation", "radialReconciliation",
            "motionReconciliation", "effectReconciliation",
            "deferredResolution", "effectOwnership", "eventOrdering",
            "layout", "candidateTransform", "messageTransform", "commit",
            "runtime", "interaction", "motion", "motionUpdate",
            "committedTransform", "refs", "effects", "effectRefresh",
            "effectUpdate", "effectBounds",
            "candidateComparison", "diagnosticObserver", "external", "paint" }) do
        local phase = assert(snapshot.phases[name],
            "FrogUI profiler omitted phase " .. name)
        assert(type(phase.current) == "number" and phase.current >= 0
                and type(phase.p95) == "number" and phase.p95 >= 0
                and type(phase.max) == "number" and phase.max >= 0,
            "FrogUI profiler emitted malformed timing for " .. name)
    end

    host:render(Probe {})
    host:update(1 / 60)
    host:draw({})
    local external = host:diagnostics()
    assert(external.counts.reconciles == 2
            and external.counts.externalRenderOperations == 1,
        "FrogUI profiler omitted direct-render work before update")

    host:pointerMove(5, 5, "mouse")
    host:update(1 / 60)
    host:draw({})
    assert(host:diagnostics().counts.externalInputOperations == 1,
        "FrogUI profiler omitted public input routing before update")

    host:resize(140, 120)
    host:update(1 / 60)
    host:draw({})
    local resized = host:diagnostics()
    assert(resized.counts.reconciles == 2
            and resized.counts.externalResizeOperations == 1,
        "FrogUI profiler omitted responsive rebuild work before update")

    host:refreshTheme(host.theme, host.assets, Probe {})
    host:update(1 / 60)
    host:draw({})
    assert(host:diagnostics().counts.externalThemeRefreshOperations == 1,
        "FrogUI profiler omitted Host theme-refresh work before update")

    host:render(AttributionProbe {})
    host:update(1 / 60)
    host:draw({})
    host:update(1 / 60)
    host:draw({})
    local attributed = host:diagnostics()
    local activity = attributed.activityTotals
    assert(activity.semanticRenders >= 1
            and activity.scrollReconciliations >= 1
            and activity.radialReconciliations >= 1
            and activity.motionReconciliations >= 1
            and activity.effectReconciliations >= 1
            and activity.postResolutionPasses >= 1,
        "FrogUI profiler omitted one B4p.6 expansion boundary")
    assert(attributed.counts.descriptors >= attributed.counts.primitives
            and attributed.counts.primitives >= 1
            and attributed.counts["primitive.PopupText"] == 1
            and attributed.counts.popupTexts == 1
            and attributed.counts.identityBytes > 0
            and attributed.counts.logicalIdentityBytes > 0
            and attributed.counts.sourceAttributedDescriptors > 0,
        "FrogUI profiler omitted compact descriptor/path/source attribution")
    assert(hasOwner(attributed.topSemanticOwners,
            "component:DiagnosticsCheckAttributionProbe"),
        "FrogUI profiler omitted bounded semantic-owner attribution")
    assert(attributed.cohorts.quiet.samples >= 1
            and type(attributed.cohorts.quiet.memory.phases.motion.average)
                == "number",
        "FrogUI profiler omitted quiet runtime heap context")
    local attributedTrace = host:diagnosticTrace()
    local last = attributedTrace[#attributedTrace]
    assert(type(last.memoryStartKB) == "number"
            and type(last.memoryKB) == "number"
            and type(last.memoryDeltaKB) == "number"
            and type(last.heapDeltasKB.runtime) == "number"
            and type(last.heapDeltasKB.interaction) == "number"
            and type(last.heapDeltasKB.motion) == "number"
            and type(last.heapDeltasKB.refs) == "number"
            and type(last.heapDeltasKB.effects) == "number",
        "FrogUI diagnostic trace omitted per-frame net heap context")
    local function timing(row, name)
        return row.timings[name] or 0
    end
    local sawAttributedRebuild = false
    for _, row in ipairs(attributedTrace) do
        if (row.activity.scrollReconciliations or 0) > 0 then
            sawAttributedRebuild = true
            local expansionChildren = timing(row, "semanticRender")
                + timing(row, "semanticPreparation")
                + timing(row, "semanticBookkeeping")
                + timing(row, "primitiveValidation")
                + timing(row, "primitiveMaterialization")
                + timing(row, "primitivePostValidation")
                + timing(row, "scrollReconciliation")
                + timing(row, "radialReconciliation")
                + timing(row, "motionReconciliation")
                + timing(row, "effectReconciliation")
                + timing(row, "deferredResolution")
                + timing(row, "effectOwnership")
                + timing(row, "eventOrdering")
            assert(timing(row, "componentExpansion") + 0.001
                    >= expansionChildren,
                "FrogUI expansion children exceeded their parent frame")
            assert(timing(row, "runtime") + 0.001
                    >= timing(row, "interaction")
                        + timing(row, "motion") + timing(row, "refs")
                        + timing(row, "effects"),
                "FrogUI runtime children exceeded their parent frame")
            assert(timing(row, "motion") + 0.001
                    >= timing(row, "motionUpdate")
                        + timing(row, "committedTransform"),
                "FrogUI Motion children exceeded their parent frame")
            assert(timing(row, "effects") + 0.001
                    >= timing(row, "effectRefresh")
                        + timing(row, "effectUpdate")
                        + timing(row, "effectBounds"),
                "FrogUI effect children exceeded their parent frame")
        end
    end
    assert(sawAttributedRebuild,
        "FrogUI diagnostic invariant check missed its attributed rebuild")
    local originalOwner = attributed.topSemanticOwners[1].name
    local originalHeap = attributed.memory.phases.motion.average
    attributed.topSemanticOwners[1].name = "mutated"
    attributed.memory.phases.motion.average = 999
    attributedTrace[#attributedTrace].heapDeltasKB.motion = 999
    local detached = host:diagnostics()
    local detachedTrace = host:diagnosticTrace()
    assert(detached.topSemanticOwners[1].name == originalOwner
            and detached.memory.phases.motion.average == originalHeap
            and detachedTrace[#detachedTrace].heapDeltasKB.motion ~= 999,
        "FrogUI diagnostics exposed heap or owner profiler storage")

    host:render(Frog.Box { width = 5, height = 5 })
    host:update(1 / 60)
    host:draw({})
    assert(host:diagnostics().counts["primitive.PopupText"] == 0,
        "FrogUI profiler retained a stale primitive histogram entry")
    host:unmount()
    local unmountedOk, unmountedError = pcall(host.diagnosticTrace, host)
    assert(not unmountedOk
            and tostring(unmountedError):find("unmounted", 1, true),
        "FrogUI diagnostic trace accepted an unmounted Host")

    local quiet = support.host { width = 120, height = 120 }
    quiet:mount(Frog.Box { width = 10, height = 10 })
    quiet:update(1 / 60)
    quiet:draw({})
    assert(not quiet:diagnostics().enabled
            and quiet:diagnostics().samples == 0
            and quiet._diagnostics.current == nil
            and quiet._pendingTransformAttribution == nil,
        "ordinary FrogUI Host unexpectedly retained profile history")
    assert(quiet:setDiagnosticsEnabled(true),
        "ordinary Host could not opt into diagnostics")
    quiet:update(1 / 60)
    quiet:draw({})
    local enabledQuiet = quiet:diagnostics()
    assert(enabledQuiet.enabled and enabledQuiet.samples == 1
            and enabledQuiet.counts.nodes >= 1,
        "runtime diagnostic opt-in omitted its fresh frame or structure")
    assert(quiet:setDiagnosticsEnabled(false),
        "ordinary Host could not opt out of diagnostics")
    quiet:update(1 / 60)
    quiet:draw({})
    assert(not quiet:diagnostics().enabled
            and quiet:diagnostics().samples == 0
            and quiet._diagnostics.current == nil
            and quiet._diagnosticPrimitiveNames == nil,
        "runtime diagnostic opt-out retained observer state")
    local disabledOk, disabledError = pcall(quiet.clearDiagnostics, quiet)
    assert(not disabledOk
            and tostring(disabledError):find("diagnostics = true", 1, true),
        "FrogUI diagnostic clear accepted a disabled Host")
    quiet:unmount()

    local boundaryHost
    local boundaryRejected = false
    local toggleBoundaryRejected = false
    local BoundaryProbe = Frog.component(
        "DiagnosticsCheckBoundaryProbe", function()
            Frog.useFrame(function()
                local ok, reason = pcall(
                    boundaryHost.clearDiagnostics, boundaryHost)
                boundaryRejected = not ok
                    and tostring(reason):find("during Host update", 1, true)
                        ~= nil
                local toggleOk, toggleReason = pcall(
                    boundaryHost.setDiagnosticsEnabled,
                    boundaryHost, false)
                toggleBoundaryRejected = not toggleOk
                    and tostring(toggleReason):find(
                        "during Host update", 1, true) ~= nil
            end)
            return Frog.Box { width = 10, height = 10 }
        end)
    boundaryHost = support.host {
        width = 120,
        height = 120,
        diagnostics = true,
    }
    boundaryHost:mount(BoundaryProbe {})
    boundaryHost:update(1 / 60)
    boundaryHost:draw({})
    assert(boundaryRejected and toggleBoundaryRejected,
        "FrogUI diagnostic control accepted an active update callback")
    boundaryHost:unmount()

    local ring = Diagnostics.new { enabled = true, historyLimit = 2 }
    for marker = 1, 3 do
        ring:beginFrame()
        ring:setCount("marker", marker)
        ring:increment("pulse")
        if marker == 2 then ring:increment("reconciles") end
        ring:cause("marker:" .. marker)
        local started = ring:start()
        ring:finishUpdate(started)
        ring:finishDraw(ring:start())
    end
    local wrapped = ring:snapshot()
    assert(wrapped.samples == 2 and wrapped.counts.marker == 3,
        "wrapped FrogUI profile ring did not report its newest sample")
    assert(#wrapped.causes == 2,
        "wrapped FrogUI profile ring retained an expired cause")
    assert(wrapped.activityTotals.pulse == 2
            and wrapped.activityTotals.marker == nil
            and wrapped.cohorts.reconciled.samples == 1
            and wrapped.cohorts.quiet.samples == 1,
        "wrapped FrogUI profile mixed retained structure with frame activity")
    assert(wrapped.slowest and wrapped.slowest.totalMs >= 0,
        "wrapped FrogUI profile ring omitted its slowest retained frame")
    local trace = ring:trace()
    assert(#trace == 2 and trace[1].counts.marker == 2
            and trace[2].counts.marker == 3
            and trace[1].activity.reconciles == 1
            and trace[2].activity.reconciles == nil,
        "FrogUI diagnostic trace lost chronological frame activity")
    trace[1].counts.marker = 999
    trace[1].activity.reconciles = 999
    trace[1].timings.update = 999
    trace[1].causes[1].name = "mutated"
    local isolated = ring:trace()
    assert(isolated[1].counts.marker == 2
            and isolated[1].activity.reconciles == 1
            and isolated[1].timings.update ~= 999
            and isolated[1].causes[1].name == "marker:2",
        "FrogUI diagnostic trace exposed retained profiler storage")
    ring:clear()
    local cleared = ring:snapshot()
    assert(cleared.samples == 0 and #ring:trace() == 0
            and cleared.counts.marker == 3,
        "FrogUI diagnostic clear did not isolate a fresh measurement window")

    ring:beginFrame()
    ring:recordTransform("committed", {
        calls = 1,
        runs = 1,
        skips = 0,
        nodesVisited = 7,
        owners = {
            alpha = 5, bravo = 5, charlie = 4, delta = 3,
            echo = 2, foxtrot = 100, golf = 1,
        },
    })
    ring:finishUpdate(ring:start())
    ring:finishDraw(ring:start())
    local boundedTrace = ring:trace()
    local boundedOwners = boundedTrace[#boundedTrace]
        .transformAttribution.committed.owners
    assert(boundedOwners.foxtrot == 100
            and boundedOwners.alpha == 5 and boundedOwners.bravo == 5
            and boundedOwners.charlie == 4 and boundedOwners.delta == 3
            and boundedOwners.echo == nil and boundedOwners.golf == nil
            and boundedOwners.other == 3,
        "FrogUI transform categories were not exact deterministic top-five")
    boundedOwners.foxtrot = 999
    local detachedBoundedTrace = ring:trace()
    local detachedOwners = detachedBoundedTrace[#detachedBoundedTrace]
        .transformAttribution.committed.owners
    assert(detachedOwners.foxtrot == 100,
        "FrogUI transform category trace exposed retained profiler storage")
    return true
end

return check
