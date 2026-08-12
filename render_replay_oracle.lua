-- RenderReplayOracle is an opt-in diagnostic census for exact component
-- render-description replay. It observes every callback but never skips one.

local Message = require("src.frogui.message")
local Element = require("src.frogui.element")
local Clock = require("src.frogui.clock")
local Ref = require("src.frogui.ref")

local Oracle = {}
Oracle.__index = Oracle

local MAX_TABLES = 512
local MAX_DEPTH = 32
local MAX_VALUES = 4096
local MAX_STRING_BYTES = 128 * 1024
local MAX_OWNER_STATS = 128
local TOP_OWNER_COUNT = 8

local function finite(value)
    return type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

-- Returns whether a metatable-bearing FrogUI definition is immutable identity.
local function tokenIdentity(value)
    return Element.isToken(value) or Message.isDefinitionToken(value)
end

-- Names only capabilities FrogUI itself can identify without invoking an
-- authored metamethod. Everything else remains an explicit opaque shape.
local function capabilityShape(value)
    if Ref.isRef(value) then return "Ref" end
    if rawget(value, "__frogClock") == true and Clock.isClock(value) then
        return "Clock"
    end
    if rawget(value, "__frogAddress") == true
            and Message.isAddress(value) then
        return "Address"
    end
    return "OpaqueMetatable"
end

local function scalarIdentity(value)
    local kind = type(value)
    if kind == "nil" or kind == "boolean" or kind == "string"
            or kind == "function" then
        return true
    end
    return kind == "number" and finite(value)
end

local function fail(state, reason)
    state.reason = state.reason or reason
end

-- Copies one bounded value graph while retaining only immutable token/function
-- identities. Shared aliases survive; cycles and mutable capabilities fail.
local function captureValue(value, state, depth, asKey)
    state.values = state.values + 1
    if state.values > MAX_VALUES then
        fail(state, "value-budget")
        return nil
    end
    if type(value) == "string" then
        state.stringBytes = state.stringBytes + #value
        if state.stringBytes > MAX_STRING_BYTES then
            fail(state, "string-budget")
            return nil
        end
    end
    if asKey then
        local kind = type(value)
        if kind == "string" or kind == "boolean"
                or kind == "number" and finite(value) then
            return value
        end
        fail(state, "unsupported-key")
        return nil
    end
    if scalarIdentity(value) then return value end
    local kind = type(value)
    if kind ~= "table" then
        fail(state, kind == "number" and "non-finite" or "capability")
        return nil
    end
    if tokenIdentity(value) then return value end
    if getmetatable(value) ~= nil then
        fail(state, "metatable")
        return nil
    end
    if depth > MAX_DEPTH then
        fail(state, "depth-budget")
        return nil
    end
    if state.active[value] then
        fail(state, "cycle")
        return nil
    end
    if state.seen[value] then return state.seen[value] end
    state.tables = state.tables + 1
    if state.tables > MAX_TABLES then
        fail(state, "table-budget")
        return nil
    end

    local copy = {}
    state.seen[value] = copy
    state.active[value] = true
    local messageToken = Message.token(value)
    if messageToken then state.messageTokens[copy] = messageToken end
    for key, nested in pairs(value) do
        local copiedKey = captureValue(key, state, depth + 1, true)
        if state.reason then break end
        local copiedValue = captureValue(nested, state, depth + 1, false)
        if state.reason then break end
        copy[copiedKey] = copiedValue
    end
    state.active[value] = nil
    return copy
end

-- Captures one exact comparison baseline without retaining caller-owned tables.
local function capture(value)
    local state = {
        seen = {}, active = {}, messageTokens = {}, tables = 0,
        values = 0, stringBytes = 0,
    }
    local root = captureValue(value, state, 1, false)
    if state.reason then return nil, state.reason end
    return { root = root, messageTokens = state.messageTokens }
end

local function sameValue(snapshot, value, state, depth)
    state.values = state.values + 1
    if state.values > MAX_VALUES then return false end
    if type(value) == "string" then
        state.stringBytes = state.stringBytes + #value
        if state.stringBytes > MAX_STRING_BYTES then return false end
    end
    if scalarIdentity(snapshot) or tokenIdentity(snapshot) then
        return snapshot == value
    end
    if type(snapshot) ~= "table" or type(value) ~= "table" then return false end
    if depth > MAX_DEPTH or getmetatable(value) ~= nil then return false end
    local snapshotToken = state.messageTokens[snapshot]
    if snapshotToken ~= Message.token(value) then return false end
    local paired = state.forward[snapshot]
    if paired then return paired == value end
    if state.reverse[value] then return false end
    state.tables = state.tables + 1
    if state.tables > MAX_TABLES then return false end
    state.forward[snapshot] = value
    state.reverse[value] = snapshot
    for key, nested in pairs(snapshot) do
        if not sameValue(nested, rawget(value, key), state, depth + 1) then
            return false
        end
    end
    for key in pairs(value) do
        if rawget(snapshot, key) == nil then return false end
    end
    return true
end

-- Compares a current graph against one detached exact baseline.
local function same(baseline, value)
    if not baseline then return false end
    return sameValue(baseline.root, value, {
        messageTokens = baseline.messageTokens,
        forward = {}, reverse = {}, tables = 0,
        values = 0, stringBytes = 0,
    }, 1)
end

local function rootLabel(key)
    local kind = type(key)
    if kind == "string" then return key end
    if kind == "number" or kind == "boolean" then
        return "[" .. kind .. ":" .. tostring(key) .. "]"
    end
    return "[unsupported-key]"
end

local function dependencyKey(shape, root)
    return shape .. "\0" .. root
end

local function recordDependency(state, shape, root)
    root = root or "(root)"
    state.shapes[shape] = true
    state.roots[dependencyKey(shape, root)] = true
end

-- Finds component-input dependency shapes without retaining their values.
-- This walk is diagnostic-only, bounded, and never invokes callbacks or
-- metamethods. Shared tables are visited once per component input graph.
local function scanDependencyValue(value, state, depth, root)
    state.values = state.values + 1
    if state.values > MAX_VALUES then
        recordDependency(state, "ValueBudget", root)
        return
    end
    local kind = type(value)
    if kind == "function" then
        recordDependency(state, "Callback", root)
        return
    end
    if kind == "userdata" or kind == "thread" then
        recordDependency(state,
            kind == "userdata" and "Userdata" or "Thread", root)
        return
    end
    if kind ~= "table" or tokenIdentity(value) then return end
    if getmetatable(value) ~= nil then
        recordDependency(state, capabilityShape(value), root)
        return
    end
    if depth > MAX_DEPTH then
        recordDependency(state, "DepthBudget", root)
        return
    end
    if state.seen[value] then return end
    state.seen[value] = true
    state.tables = state.tables + 1
    if state.tables > MAX_TABLES then
        recordDependency(state, "TableBudget", root)
        return
    end
    for key, nested in pairs(value) do
        local nestedRoot = depth == 1 and rootLabel(key) or root
        scanDependencyValue(nested, state, depth + 1, nestedRoot)
        if state.values > MAX_VALUES or state.tables > MAX_TABLES then break end
    end
end

local function scanDependencies(props)
    local state = {
        shapes = {}, roots = {}, seen = {},
        values = 0, tables = 0,
    }
    scanDependencyValue(props, state, 1, nil)
    return state
end

local function emptyTotals()
    return {
        visits = 0,
        eligible = 0,
        potentialHits = 0,
        callbacks = 0,
        semanticCallbacks = 0,
    }
end

local function increment(map, key, amount)
    map[key] = (map[key] or 0) + (amount or 1)
end

-- Counts every successful semantic callback, including actors and addressed
-- views that a component-only replay policy could never skip.
function Oracle:afterSemanticCallback(stage)
    increment(stage.totals, "semanticCallbacks")
end

local function ownerTotals(stage, logicalPath)
    local owner = stage.owners[logicalPath]
    if owner then return owner end
    if stage.ownerCount >= MAX_OWNER_STATS then
        logicalPath = "(overflow)"
        owner = stage.owners[logicalPath]
        if owner then return owner end
    else
        stage.ownerCount = stage.ownerCount + 1
    end
    owner = emptyTotals()
    owner.logicalPath = logicalPath
    stage.owners[logicalPath] = owner
    stage.ownerOrder[#stage.ownerOrder + 1] = logicalPath
    return owner
end

local function addVisit(stage, logicalPath, field)
    increment(stage.totals, field)
    increment(ownerTotals(stage, logicalPath), field)
end

local function markIneligible(stage, logicalPath, reason)
    increment(stage.reasons, reason)
end

-- Creates one committed census with no effect on Host rendering.
function Oracle.new()
    return setmetatable({
        _records = {},
        _totals = emptyTotals(),
        _reasons = {},
        _missReasons = {},
        _dependencyShapes = {},
        _dependencyRoots = {},
        _dependencyOwners = {},
        _hookShapes = {},
        _hookOwners = {},
        _owners = {},
        _ownerCount = 0,
    }, Oracle)
end

-- Begins one candidate-local census transaction.
function Oracle:beginCandidate(viewport)
    local viewportSnapshot, reason = capture(viewport)
    assert(viewportSnapshot,
        "RenderReplayOracle rejected Host viewport: " .. tostring(reason))
    return {
        records = {},
        totals = emptyTotals(),
        reasons = {},
        missReasons = {},
        dependencyShapes = {},
        dependencyRoots = {},
        dependencyOwners = {},
        hookShapes = {},
        hookOwners = {},
        owners = {},
        ownerOrder = {},
        ownerCount = 0,
        viewport = viewportSnapshot,
    }
end

-- Observes exact input before the component callback executes.
function Oracle:beforeComponent(stage, logicalPath, token, callback, props)
    assert(not stage.records[logicalPath],
        "duplicate RenderReplayOracle owner " .. logicalPath)
    addVisit(stage, logicalPath, "visits")
    local input, inputReason = capture(props)
    local dependencies = scanDependencies(props)
    local previous = self._records[logicalPath]
    local missReason
    local exactPreviousInput = false
    if input then
        if not previous then
            missReason = "cold"
        elseif not previous.eligible then
            missReason = "previous-ineligible"
        elseif previous.token ~= token or previous.callback ~= callback then
            missReason = "callback"
        elseif not same(previous.input, props) then
            missReason = "input"
        elseif previous.usesViewport
                and not same(previous.viewport, stage.viewport.root) then
            missReason = "viewport"
        else
            exactPreviousInput = true
            if not previous.verified then missReason = "warming" end
        end
    end
    return {
        logicalPath = logicalPath,
        token = token,
        callback = callback,
        input = input,
        inputReason = inputReason,
        dependencies = dependencies,
        previous = previous,
        exactPreviousInput = exactPreviousInput,
        missReason = missReason,
        predicted = exactPreviousInput and previous.verified,
    }
end

-- Verifies hooks, viewport use, and exact output after the callback still ran.
function Oracle:afterComponent(stage, visit, owner, rendered)
    local logicalPath = visit.logicalPath
    addVisit(stage, logicalPath, "callbacks")
    for shape in pairs(visit.dependencies.shapes) do
        increment(stage.dependencyShapes, shape)
        increment(stage.dependencyOwners,
            dependencyKey(shape, visit.token.name))
    end
    for key in pairs(visit.dependencies.roots) do
        increment(stage.dependencyRoots, key)
    end
    local hookKinds = {}
    for _, hook in ipairs(owner.hooks or {}) do
        hookKinds[hook.kind] = true
    end
    for kind in pairs(hookKinds) do
        increment(stage.hookShapes, kind)
        increment(stage.hookOwners,
            dependencyKey(kind, visit.token.name))
    end
    if owner.usesViewport then
        increment(stage.dependencyShapes, "Viewport")
        increment(stage.dependencyRoots,
            dependencyKey("Viewport", "Frog.useViewport"))
        increment(stage.dependencyOwners,
            dependencyKey("Viewport", visit.token.name))
    end
    local reason
    if #(owner.hooks or {}) > 0 then
        reason = "hooks"
    elseif not visit.input then
        reason = "input-" .. tostring(visit.inputReason)
    end
    local output, outputReason
    if not reason then
        output, outputReason = capture(rendered)
        if not output then reason = "output-" .. tostring(outputReason) end
    end
    if reason then
        markIneligible(stage, logicalPath, reason)
        stage.records[logicalPath] = {
            eligible = false,
            reason = reason,
            token = visit.token,
            callback = visit.callback,
        }
        return
    end

    addVisit(stage, logicalPath, "eligible")
    local previous = visit.previous
    local usesViewport = owner.usesViewport == true
    local exactPrevious = visit.exactPreviousInput
        and previous.usesViewport == usesViewport
    local exactOutput = exactPrevious and same(previous.output, rendered)
    local verified = exactPrevious and exactOutput or false
    -- Hindsight feasibility only: the callback ran and its exact output still
    -- verified the record that matched before execution.
    if visit.predicted and verified then
        addVisit(stage, logicalPath, "potentialHits")
    elseif visit.exactPreviousInput
            and previous.usesViewport ~= usesViewport then
        increment(stage.missReasons, "viewport-dependency")
    elseif visit.exactPreviousInput and not exactOutput then
        increment(stage.missReasons, "output")
    elseif visit.missReason then
        increment(stage.missReasons, visit.missReason)
    end
    stage.records[logicalPath] = {
        eligible = true,
        verified = verified,
        token = visit.token,
        callback = visit.callback,
        input = visit.input,
        usesViewport = usesViewport,
        viewport = usesViewport and stage.viewport or nil,
        output = output,
    }
end

local function mergeTotals(target, source)
    for key, value in pairs(source) do
        if type(value) == "number" then increment(target, key, value) end
    end
end

local function copyMap(source)
    local output = {}
    for key, value in pairs(source) do output[key] = value end
    return output
end

-- Prepares a complete next state while the candidate can still fail safely.
function Oracle:prepareCommit(stage)
    local totals = copyMap(self._totals)
    local reasons = copyMap(self._reasons)
    local missReasons = copyMap(self._missReasons)
    local dependencyShapes = copyMap(self._dependencyShapes)
    local dependencyRoots = copyMap(self._dependencyRoots)
    local dependencyOwners = copyMap(self._dependencyOwners)
    local hookShapes = copyMap(self._hookShapes)
    local hookOwners = copyMap(self._hookOwners)
    local owners = {}
    for logicalPath, source in pairs(self._owners) do
        owners[logicalPath] = copyMap(source)
    end
    local ownerCount = self._ownerCount
    mergeTotals(totals, stage.totals)
    mergeTotals(reasons, stage.reasons)
    mergeTotals(missReasons, stage.missReasons)
    mergeTotals(dependencyShapes, stage.dependencyShapes)
    mergeTotals(dependencyRoots, stage.dependencyRoots)
    mergeTotals(dependencyOwners, stage.dependencyOwners)
    mergeTotals(hookShapes, stage.hookShapes)
    mergeTotals(hookOwners, stage.hookOwners)
    for _, logicalPath in ipairs(stage.ownerOrder) do
        local source = stage.owners[logicalPath]
        local target = owners[logicalPath]
        if not target then
            if ownerCount >= MAX_OWNER_STATS then
                logicalPath = "(overflow)"
                target = owners[logicalPath]
            else
                ownerCount = ownerCount + 1
            end
            if not target then
                target = emptyTotals()
                target.logicalPath = logicalPath
                owners[logicalPath] = target
            end
        end
        mergeTotals(target, source)
    end
    stage.commitState = {
        records = stage.records,
        totals = totals,
        reasons = reasons,
        missReasons = missReasons,
        dependencyShapes = dependencyShapes,
        dependencyRoots = dependencyRoots,
        dependencyOwners = dependencyOwners,
        hookShapes = hookShapes,
        hookOwners = hookOwners,
        owners = owners,
        ownerCount = ownerCount,
    }
end

-- Publishes one prevalidated census state with assignment-only commit work.
function Oracle:commit(stage)
    local state = stage.commitState
    self._records = state.records
    self._totals = state.totals
    self._reasons = state.reasons
    self._missReasons = state.missReasons
    self._dependencyShapes = state.dependencyShapes
    self._dependencyRoots = state.dependencyRoots
    self._dependencyOwners = state.dependencyOwners
    self._hookShapes = state.hookShapes
    self._hookOwners = state.hookOwners
    self._owners = state.owners
    self._ownerCount = state.ownerCount
end

-- Clears measurement totals while preserving warm verification records.
function Oracle:clearCounters()
    self._totals = emptyTotals()
    self._reasons = {}
    self._missReasons = {}
    self._dependencyShapes = {}
    self._dependencyRoots = {}
    self._dependencyOwners = {}
    self._hookShapes = {}
    self._hookOwners = {}
    self._owners = {}
    self._ownerCount = 0
end

-- Clears records and totals when the owning Host unmounts.
function Oracle:reset()
    self._records = {}
    self:clearCounters()
end

-- Returns bounded detached census evidence for one-shot development tools.
function Oracle:report()
    local owners = {}
    for _, source in pairs(self._owners) do
        owners[#owners + 1] = {
            logicalPath = source.logicalPath,
            visits = source.visits,
            eligible = source.eligible,
            potentialHits = source.potentialHits,
            callbacks = source.callbacks,
        }
    end
    table.sort(owners, function(left, right)
        if left.potentialHits ~= right.potentialHits then
            return left.potentialHits > right.potentialHits
        end
        if left.eligible ~= right.eligible then
            return left.eligible > right.eligible
        end
        if left.visits ~= right.visits then return left.visits > right.visits end
        return left.logicalPath < right.logicalPath
    end)
    while #owners > TOP_OWNER_COUNT do table.remove(owners) end
    local liveRecords = 0
    for _ in pairs(self._records) do liveRecords = liveRecords + 1 end
    return {
        visits = self._totals.visits,
        eligible = self._totals.eligible,
        potentialHits = self._totals.potentialHits,
        callbacks = self._totals.callbacks,
        semanticCallbacks = self._totals.semanticCallbacks,
        ineligibleReasons = copyMap(self._reasons),
        missReasons = copyMap(self._missReasons),
        dependencyShapes = copyMap(self._dependencyShapes),
        dependencyRoots = copyMap(self._dependencyRoots),
        dependencyOwners = copyMap(self._dependencyOwners),
        hookShapes = copyMap(self._hookShapes),
        hookOwners = copyMap(self._hookOwners),
        topOwners = owners,
        liveRecords = liveRecords,
    }
end

return Oracle
