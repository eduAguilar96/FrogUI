-- Focused contract for FrogUI's private render-replay feasibility census. The
-- observer always executes callbacks and publishes evidence only with a valid
-- candidate tree; it never changes the committed presentation.

local Frog = require("frogui")
local support = require("tests.support")

local check = {}

local renders = 0

local Stable = Frog.component("RenderReplayCensusCheckStable", function(props)
    renders = renders + 1
    return Frog.Text { tostring(props.value) }
end)

local Failing = Frog.component("RenderReplayCensusCheckFailing", function()
    error("intentional replay-census candidate failure")
end)

local InvalidPrimitive = Frog.component(
    "RenderReplayCensusCheckInvalidPrimitive", function()
        return Frog.Box { width = "invalid-width", height = 10 }
    end)

local CandidateRoot = Frog.component(
    "RenderReplayCensusCheckCandidateRoot", function(props)
        return Frog.Column {
            Stable { key = "stable", value = props.value },
            props.fail and Failing { key = "failure" } or nil,
            props.invalid and InvalidPrimitive { key = "invalid" } or nil,
        }
    end)

local ActorRoot = Frog.actor("RenderReplayCensusCheckActorRoot", {
    initial = 1,
    render = function(_, state)
        return Stable { value = state }
    end,
})

local ViewportProbe = Frog.component(
    "RenderReplayCensusCheckViewportProbe", function(props)
        local viewport = Frog.useViewport()
        if props.failWide and viewport.wide then
            error("intentional replay-census resize failure")
        end
        return Frog.Text { viewport.wide and "wide" or "portrait" }
    end)

local HookProbe = Frog.component("RenderReplayCensusCheckHookProbe",
    function()
        Frog.useRef()
        return Frog.Box { width = 10, height = 10 }
    end)

local DataProbe = Frog.component("RenderReplayCensusCheckDataProbe",
    function(props)
        return Frog.Text { tostring(props.data.value or props.data.name) }
    end)

local InlineCallbackProbe = Frog.component(
    "RenderReplayCensusCheckInlineCallbackProbe", function()
        return Frog.Button {
            width = 20,
            height = 20,
            onPress = function() end,
        }
    end)

local function dependencyCallback() end

local DependencyChild = Frog.component(
    "RenderReplayCensusCheckDependencyChild", function()
        return Frog.Box { width = 10, height = 10 }
    end)

local DependencyRoot = Frog.component(
    "RenderReplayCensusCheckDependencyRoot", function()
        local anchor = Frog.useRef()
        local clock = Frog.useResource(function()
            return Frog.clock(), function() end
        end)
        return DependencyChild {
            anchor = anchor,
            clock = clock,
            onPress = dependencyCallback,
        }
    end)

local Record = Frog.action("RenderReplayCensusCheck.Record", function(action)
    assert(type(action.value) == "number", "record value must be numeric")
end)

local function censusHost(width, height)
    local host = support.host {
        width = width or 120,
        height = height or 180,
        diagnostics = true,
    }
    assert(host:_attachRenderReplayCensus())
    return host
end

local function plainHostHasNoCensusState()
    local host = support.host { width = 120, height = 180 }
    assert(rawget(host, "_renderReplayOracle") == nil,
        "ordinary Host retained render replay state")
    host:mount(Stable { value = 1 })
    host:render(Stable { value = 1 })
    assert(rawget(host, "_renderReplayOracle") == nil,
        "ordinary component expansion created render replay state")
    host:unmount()
end

local function exactHitsAndCandidateRollback()
    renders = 0
    local host = censusHost()
    host:mount(CandidateRoot { value = 1, fail = false })
    host:render(CandidateRoot { value = 1, fail = false })
    host:_resetRenderReplayCensusCounters()

    host:render(CandidateRoot { value = 1, fail = false })
    local report = host:_readRenderReplayCensus()
    assert(report.callbacks == report.visits and report.callbacks >= 2,
        "render replay census skipped a real component callback")
    assert(report.potentialHits >= 2,
        "verified exact component inputs did not become potential hits")
    local rendersBeforeFailure = renders

    host:_resetRenderReplayCensusCounters()
    local rendered, failure = pcall(host.render, host,
        CandidateRoot { value = 1, fail = true })
    assert(not rendered and tostring(failure):find(
            "intentional replay-census candidate failure", 1, true),
        "candidate rollback fixture did not fail")
    assert(renders > rendersBeforeFailure,
        "failed candidate did not execute the real stable callback")
    report = host:_readRenderReplayCensus()
    assert(report.visits == 0 and report.callbacks == 0,
        "failed candidate leaked replay census counters")

    host:render(CandidateRoot { value = 1, fail = false })
    report = host:_readRenderReplayCensus()
    assert(report.potentialHits >= 2,
        "failed candidate poisoned the last committed replay baseline")

    host:_resetRenderReplayCensusCounters()
    rendered, failure = pcall(host.render, host,
        CandidateRoot { value = 1, invalid = true })
    assert(not rendered and tostring(failure):find(
            "width must be", 1, true),
        "post-callback primitive validation fixture did not fail")
    report = host:_readRenderReplayCensus()
    assert(report.visits == 0 and report.semanticCallbacks == 0,
        "invalid primitive candidate leaked replay census evidence")
    host:unmount()
    assert(rawget(host, "_renderReplayOracle") == nil,
        "Host unmount retained replay census descriptions")
end

local function nonReplayableSemanticDenominator()
    local host = censusHost()
    host:mount(ActorRoot {})
    host:render(ActorRoot {})
    local report = host:_readRenderReplayCensus()
    assert(report.semanticCallbacks == report.callbacks + 2,
        "actor callbacks were omitted from the semantic denominator")
    host:unmount()
end

local function viewportDependencyAndRollback()
    local host = censusHost(120, 180)
    host:mount(ViewportProbe { failWide = true })
    host:render(ViewportProbe { failWide = true })
    host:_resetRenderReplayCensusCounters()

    local resized, failure = pcall(host.resize, host, 180, 120)
    assert(not resized and tostring(failure):find(
            "intentional replay-census resize failure", 1, true),
        "failed viewport candidate did not fail")
    local report = host:_readRenderReplayCensus()
    assert(report.visits == 0 and report.callbacks == 0,
        "failed resize leaked replay census counters")

    host:render(ViewportProbe { failWide = true })
    report = host:_readRenderReplayCensus()
    assert(report.potentialHits == 1,
        "failed resize changed the committed viewport baseline")
    host:unmount()

    host = censusHost(120, 180)
    host:mount(ViewportProbe { failWide = false })
    host:render(ViewportProbe { failWide = false })
    host:_resetRenderReplayCensusCounters()
    host:resize(180, 120)
    report = host:_readRenderReplayCensus()
    assert(report.potentialHits == 0
            and report.missReasons.viewport == 1,
        "portrait-to-wide resize was not classified as a viewport miss")
    host:unmount()
end

local function conservativeInputsAndOutputs()
    local host = censusHost()
    host:mount(HookProbe {})
    local report = host:_readRenderReplayCensus()
    assert(report.ineligibleReasons.hooks == 1,
        "positional Hook owner was replay eligible")
    host:unmount()

    host = censusHost()
    host:mount(DependencyRoot {})
    report = host:_readRenderReplayCensus()
    assert(report.dependencyShapes.Clock == 1
            and report.dependencyShapes.Ref == 1
            and report.dependencyShapes.Callback == 1,
        "FrogUI capability dependency shapes were not classified")
    assert(report.dependencyRoots["Clock\0clock"] == 1
            and report.dependencyRoots["Ref\0anchor"] == 1
            and report.dependencyRoots["Callback\0onPress"] == 1,
        "capability dependency roots were not classified")
    assert(report.hookShapes.useRef == 1
            and report.hookShapes.useResource == 1,
        "component Hook dependency shapes were not classified")
    host:unmount()

    local fakeToken = { kind = "component", name = "Mutable", value = 1 }
    host = censusHost()
    local root = DataProbe { data = fakeToken }
    host:mount(root)
    host:render(root)
    host:_resetRenderReplayCensusCounters()
    fakeToken.name = "Changed"
    host:render(root)
    report = host:_readRenderReplayCensus()
    assert(report.potentialHits == 0 and report.missReasons.input == 1,
        "token-shaped mutable application data was trusted by identity")
    host:unmount()

    local cyclic = {}
    cyclic.self = cyclic
    host = censusHost()
    host:mount(DataProbe { data = cyclic })
    report = host:_readRenderReplayCensus()
    assert(report.ineligibleReasons["input-cycle"] == 1,
        "cyclic component input did not fail closed")
    host:unmount()

    host = censusHost()
    host:mount(DataProbe { data = Frog.clock() })
    report = host:_readRenderReplayCensus()
    assert(report.ineligibleReasons["input-metatable"] == 1,
        "clock capability did not fail closed")
    host:unmount()

    host = censusHost()
    host:mount(InlineCallbackProbe {})
    host:render(InlineCallbackProbe {})
    report = host:_readRenderReplayCensus()
    assert(report.potentialHits == 0 and report.missReasons.output == 1,
        "fresh output closure was mistaken for repeatable output")
    host:unmount()

    host = censusHost()
    local record = Record { value = 3 }
    host:mount(DataProbe { data = record })
    host:render(DataProbe { data = record })
    host:_resetRenderReplayCensusCounters()
    host:render(DataProbe { data = record })
    report = host:_readRenderReplayCensus()
    assert(report.potentialHits == 1,
        "typed message record did not preserve its exact identity metadata")
    host:unmount()
end

function check.run()
    plainHostHasNoCensusState()
    exactHitsAndCandidateRollback()
    nonReplayableSemanticDenominator()
    viewportDependencyAndRollback()
    conservativeInputsAndOutputs()
    return true
end

return check
