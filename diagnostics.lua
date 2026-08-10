-- Development-only rolling profiler for one FrogUI Host. It records coarse
-- pipeline phases and structural counts without retaining component state or
-- presentation payloads. Hosts must opt in explicitly.

local diagnostics = {}
diagnostics.__index = diagnostics

local DEFAULT_HISTORY = 180
local ATTRIBUTION_NAME_LIMIT = 5
local PHASES = {
    "update", "frameCallbacks", "messageDelivery", "actionProcessing",
    "eventProcessing", "actorTransitions", "reconcile",
    "componentExpansion", "semanticRender", "semanticPreparation",
    "semanticBookkeeping", "primitiveValidation",
    "primitiveMaterialization", "primitivePostValidation",
    "scrollReconciliation",
    "radialReconciliation", "motionReconciliation",
    "effectReconciliation", "deferredResolution", "effectOwnership",
    "eventOrdering", "layout", "candidateTransform", "messageTransform",
    "interactionTransform",
    "commit",
    "runtime", "interaction", "motion", "motionUpdate",
    "committedTransform", "refs", "effects", "effectRefresh",
    "effectUpdate", "effectBounds",
    "diagnosticObserver", "external", "paint",
}

local HEAP_PHASES = {
    "runtime", "interaction", "motion", "refs", "effects",
}

-- Uses LÖVE's monotonic wall clock when available and a portable fallback in
-- headless checks.
local function now()
    if love and love.timer and love.timer.getTime then
        return love.timer.getTime()
    end
    return os.clock()
end

local function finiteNonNegative(value, label)
    assert(type(value) == "number" and value == value
            and value >= 0 and value < math.huge,
        label .. " must be a finite non-negative number")
    return value
end

local function percentile(values, fraction)
    if #values == 0 then return 0 end
    table.sort(values)
    local index = math.max(1, math.ceil(#values * fraction))
    return values[index]
end

local function shallowCopy(source)
    local copy = {}
    for key, value in pairs(source or {}) do copy[key] = value end
    return copy
end

local function copyAttribution(source)
    local output = {}
    for context, row in pairs(source or {}) do
        local copy = {}
        for name, value in pairs(row) do
            copy[name] = type(value) == "table" and shallowCopy(value) or value
        end
        output[context] = copy
    end
    return output
end

-- Creates one disabled-by-default profiler. A fixed ring prevents the tool
-- itself from creating unbounded history during long Battle sessions.
function diagnostics.new(options)
    options = options or {}
    assert(type(options) == "table" and getmetatable(options) == nil,
        "FrogUI diagnostics options must be a plain table")
    local historyLimit = options.historyLimit or DEFAULT_HISTORY
    assert(type(historyLimit) == "number" and historyLimit >= 1
            and historyLimit % 1 == 0,
        "FrogUI diagnostics historyLimit must be a positive integer")
    return setmetatable({
        enabled = options.enabled == true,
        historyLimit = historyLimit,
        history = {},
        historyCount = 0,
        historyCursor = 0,
        current = nil,
        retainedCounts = {},
    }, diagnostics)
end

-- Begins one Host update sample. Headless callers that omit draw still commit
-- their preceding update before the next sample begins.
function diagnostics:ensureFrame()
    if not self.enabled then return end
    if not self.current then
        self.current = {
            timings = {},
            counts = shallowCopy(self.retainedCounts),
            activity = {},
            causes = {},
            memoryStartKB = collectgarbage("count"),
            heapDeltasKB = {},
            ownerRenders = {},
            transformAttribution = {},
            refAttribution = {},
        }
    end
end

local function addCategories(target, source)
    for name, count in pairs(source or {}) do
        target[name] = (target[name] or 0) + count
    end
end

-- Selects the exact largest five categories after a frame is complete. Equal
-- counts use name order, making the retained set independent of pairs() order.
local function boundedCategories(source)
    local entries = {}
    for name, count in pairs(source or {}) do
        entries[#entries + 1] = { name = name, count = count }
    end
    table.sort(entries, function(left, right)
        if left.count ~= right.count then return left.count > right.count end
        return left.name < right.name
    end)
    local output, overflow = {}, 0
    for index, entry in ipairs(entries) do
        if index <= ATTRIBUTION_NAME_LIMIT then
            output[entry.name] = entry.count
        else
            overflow = overflow + entry.count
        end
    end
    if overflow > 0 then output.other = overflow end
    return output
end

local function boundTransformCategories(rows)
    for _, row in pairs(rows or {}) do
        row.families = boundedCategories(row.families)
        row.owners = boundedCategories(row.owners)
        row.recipes = boundedCategories(row.recipes)
        row.details = boundedCategories(row.details)
        row.fallbackReasons = boundedCategories(row.fallbackReasons)
    end
end

local function addFields(target, source, fields)
    for _, name in ipairs(fields) do
        target[name] = (target[name] or 0) + (source[name] or 0)
    end
end

-- Records one transform call without retaining nodes, paths, props, or state.
-- The four contexts remain separate so an immediate interaction transform can
-- never be misreported as the later committed update call.
function diagnostics:recordTransform(context, row)
    if not self.enabled or not self.current then return end
    assert(context == "candidate" or context == "message"
            or context == "committed" or context == "interaction",
        "unknown FrogUI transform diagnostic context " .. tostring(context))
    local aggregate = self.current.transformAttribution[context]
    if not aggregate then
        aggregate = {
            families = {}, owners = {}, recipes = {}, details = {},
            fallbackReasons = {},
        }
        self.current.transformAttribution[context] = aggregate
    end
    addFields(aggregate, row, {
        "calls", "runs", "skips", "nodesVisited", "invalidations",
        "coalescedInvalidations", "changingOwners", "dirtyRoots",
        "lcaCoverage", "branchCoverage", "activeGeometryMotions",
        "branchRuns", "fullRuns", "fallbackRuns", "branchNodes",
        "fullNodes", "pendingTargets", "survivingRoots",
        "descendantsSuppressed", "routingTreeVisits", "lcaMeasured",
    })
    addCategories(aggregate.families, row.families)
    addCategories(aggregate.owners, row.owners)
    addCategories(aggregate.recipes, row.recipes)
    addCategories(aggregate.details, row.details)
    addCategories(aggregate.fallbackReasons, row.fallbackReasons)
end

-- Records one committed-ref publication. Ref comparison stays observational:
-- the Host still publishes the same complete rectangle set on every call.
function diagnostics:recordRefs(context, row)
    if not self.enabled or not self.current then return end
    assert(context == "committed" or context == "interaction",
        "unknown FrogUI ref diagnostic context " .. tostring(context))
    local aggregate = self.current.refAttribution[context]
    if not aggregate then
        aggregate = {}
        self.current.refAttribution[context] = aggregate
    end
    addFields(aggregate, row, {
        "calls", "treeVisits", "published", "cleared", "changedRectangles",
        "visualTransformChanged", "interactionInvalidated",
    })
end

-- Starts the update portion of a graphical frame. Input/reload work may have
-- opened this sample first; a previous headless update without draw commits
-- before the new one begins.
function diagnostics:beginFrame()
    if not self.enabled then return end
    if self.current and self.current.updateFinished then self:_commit() end
    self:ensureFrame()
end

-- Returns a timestamp only while profiling so disabled Hosts pay no timer-call
-- cost inside their normal runtime path.
function diagnostics:start()
    if not self.enabled or not self.current then return nil end
    return now()
end

-- Adds elapsed wall time to one named phase. Nested phases are intentional:
-- reconcile includes expansion, layout, and commit for easy top-level reading.
function diagnostics:finish(name, started)
    if not started or not self.current then return nil end
    local elapsed = math.max(0, now() - started)
    self.current.timings[name] = (self.current.timings[name] or 0) + elapsed
    return elapsed
end

-- Attributes one completed semantic render to its token name. The bounded
-- profiler keeps only count and elapsed time; props, state, and paths never
-- cross this boundary.
function diagnostics:ownerRender(name, elapsed)
    if not elapsed or not self.current then return end
    local owner = self.current.ownerRenders[name]
    if not owner then
        owner = { count = 0, seconds = 0 }
        self.current.ownerRenders[name] = owner
    end
    owner.count = owner.count + 1
    owner.seconds = owner.seconds + elapsed
end

-- Starts one diagnostic-only net-heap interval. This deliberately uses Lua's
-- current heap size, not an allocation claim: a collection may make the
-- matching delta negative.
function diagnostics:heapStart()
    if not self.enabled or not self.current then return nil end
    return collectgarbage("count")
end

-- Closes one sequential heap interval and returns the new cursor so adjacent
-- runtime phases need only one heap sample at their shared boundary.
function diagnostics:heapMark(name, startedKB)
    if not startedKB or not self.current then return nil end
    local currentKB = collectgarbage("count")
    local deltas = self.current.heapDeltasKB
    deltas[name] = (deltas[name] or 0) + currentKB - startedKB
    return currentKB
end

-- Records a nested heap interval from two already-sampled cursors. Host uses
-- this for the complete runtime total without adding another GC observation.
function diagnostics:heapRecord(name, startedKB, finishedKB)
    if not startedKB or not finishedKB or not self.current then return end
    local deltas = self.current.heapDeltasKB
    deltas[name] = (deltas[name] or 0) + finishedKB - startedKB
end

-- Increments one per-frame activity counter such as messages or reconciles.
function diagnostics:increment(name, amount)
    if not self.enabled or not self.current then return end
    amount = finiteNonNegative(amount or 1, "FrogUI diagnostic increment")
    self.current.counts[name] = (self.current.counts[name] or 0) + amount
    self.current.activity[name] = (self.current.activity[name] or 0) + amount
end

-- Publishes a retained structural count. Tree size remains useful on quiet
-- frames without forcing FrogUI to walk the committed tree every frame.
function diagnostics:setCount(name, value)
    if not self.enabled then return end
    value = finiteNonNegative(value, "FrogUI diagnostic count")
    self.retainedCounts[name] = value
    if self.current then self.current.counts[name] = value end
end

-- Records one compact reason that dirtied presentation. Names are framework or
-- typed-message identities only; payloads and actor state are never retained.
function diagnostics:cause(name)
    if not self.enabled or not self.current then return end
    assert(type(name) == "string" and name ~= "",
        "FrogUI diagnostic cause must be non-empty text")
    self.current.causes[name] = (self.current.causes[name] or 0) + 1
end

function diagnostics:finishUpdate(started)
    self:finish("update", started)
    if self.current then self.current.updateFinished = true end
end

-- Completes and commits a graphical frame after Painter returns.
function diagnostics:finishDraw(started)
    self:finish("paint", started)
    if self.current then self:_commit() end
end

function diagnostics:_commit()
    local sample = assert(self.current, "FrogUI diagnostics has no current sample")
    boundTransformCategories(sample.transformAttribution)
    local memory = collectgarbage("count")
    sample.memoryKB = memory
    sample.memoryDeltaKB = memory - sample.memoryStartKB
    sample.timings.total = (sample.timings.update or 0)
        + (sample.timings.external or 0)
        + (sample.timings.paint or 0)
    sample.updateFinished = nil
    self.historyCursor = self.historyCursor % self.historyLimit + 1
    self.history[self.historyCursor] = sample
    self.historyCount = math.min(self.historyCount + 1, self.historyLimit)
    self.current = nil
end

local function samples(self)
    local output = {}
    if self.historyCount < self.historyLimit then
        for index = 1, self.historyCount do
            output[#output + 1] = self.history[index]
        end
    else
        -- The slot after the cursor is the oldest full-ring sample; walking
        -- from there leaves the current cursor (the newest sample) last.
        for offset = 1, self.historyCount do
            local index = (self.historyCursor + offset - 1)
                % self.historyLimit + 1
            output[#output + 1] = self.history[index]
        end
    end
    return output
end

-- Clears completed and in-progress samples before an isolated measurement
-- window. Retained tree counts survive because clearing history does not
-- replace the committed tree.
function diagnostics:clear()
    if not self.enabled then return end
    self.history = {}
    self.historyCount = 0
    self.historyCursor = 0
    self.current = nil
end

local function phaseSummary(history, phaseNames)
    local phases = {}
    for _, name in ipairs(phaseNames) do
        local values, sum, maximum = {}, 0, 0
        for _, sample in ipairs(history) do
            local value = (sample.timings[name] or 0) * 1000
            values[#values + 1] = value
            sum = sum + value
            maximum = math.max(maximum, value)
        end
        phases[name] = {
            current = history[#history]
                    and (history[#history].timings[name] or 0) * 1000
                or 0,
            average = #values > 0 and sum / #values or 0,
            p95 = percentile(values, 0.95),
            max = maximum,
        }
    end
    return phases
end

-- Summarizes signed scalar samples without the milliseconds conversion used
-- by phaseSummary. Net heap movement may be negative when GC runs.
local function valueSummary(history, valueFor)
    local values, sum, minimum, maximum = {}, 0, math.huge, -math.huge
    for _, sample in ipairs(history) do
        local value = valueFor(sample) or 0
        values[#values + 1] = value
        sum = sum + value
        minimum = math.min(minimum, value)
        maximum = math.max(maximum, value)
    end
    return {
        current = history[#history] and valueFor(history[#history]) or 0,
        average = #values > 0 and sum / #values or 0,
        p95 = percentile(values, 0.95),
        min = #values > 0 and minimum or 0,
        max = #values > 0 and maximum or 0,
    }
end

local function memorySummary(history)
    local phases = {}
    for _, name in ipairs(HEAP_PHASES) do
        phases[name] = valueSummary(history, function(sample)
            return (sample.heapDeltasKB or {})[name] or 0
        end)
    end
    local heapDropFrames = 0
    for _, sample in ipairs(history) do
        if (sample.memoryDeltaKB or 0) < 0 then
            heapDropFrames = heapDropFrames + 1
        end
    end
    return {
        frameDeltaKB = valueSummary(history,
            function(sample) return sample.memoryDeltaKB or 0 end),
        phases = phases,
        heapDropFrames = heapDropFrames,
    }
end

local function ownerSummary(history)
    local totals = {}
    for _, sample in ipairs(history) do
        for name, owner in pairs(sample.ownerRenders or {}) do
            local total = totals[name]
            if not total then
                total = { name = name, count = 0, seconds = 0 }
                totals[name] = total
            end
            total.count = total.count + owner.count
            total.seconds = total.seconds + owner.seconds
        end
    end
    local owners = {}
    for _, owner in pairs(totals) do
        owners[#owners + 1] = {
            name = owner.name,
            count = owner.count,
            totalMs = owner.seconds * 1000,
            averageMs = owner.count > 0
                    and owner.seconds * 1000 / owner.count
                or 0,
        }
    end
    table.sort(owners, function(left, right)
        if left.totalMs ~= right.totalMs then return left.totalMs > right.totalMs end
        if left.count ~= right.count then return left.count > right.count end
        return left.name < right.name
    end)
    while #owners > 5 do table.remove(owners) end
    return owners
end

local function activitySummary(history)
    local totals = {}
    for _, sample in ipairs(history) do
        for name, count in pairs(sample.activity or {}) do
            totals[name] = (totals[name] or 0) + count
        end
    end
    return totals
end

local function causeSummary(history)
    local totals = {}
    for _, sample in ipairs(history) do
        for name, count in pairs(sample.causes or {}) do
            totals[name] = (totals[name] or 0) + count
        end
    end
    local causes = {}
    for name, count in pairs(totals) do
        causes[#causes + 1] = { name = name, count = count }
    end
    table.sort(causes, function(left, right)
        if left.count ~= right.count then return left.count > right.count end
        return left.name < right.name
    end)
    while #causes > 3 do table.remove(causes) end
    return causes
end

-- Summarizes a correlated frame cohort. Activity comes only from increment()
-- calls in those samples; retained tree counts never leak into these totals.
local function cohortSummary(history, phaseNames)
    return {
        samples = #history,
        phases = phaseSummary(history, phaseNames),
        memory = memorySummary(history),
        topSemanticOwners = ownerSummary(history),
        activityTotals = activitySummary(history),
        causes = causeSummary(history),
    }
end

-- Exports the bounded ring once in chronological order for developer tools
-- that need frame correlation. Unlike snapshot(), this deliberately allocates
-- one detached row per retained sample and should not be polled by an overlay.
function diagnostics:trace()
    local output = {}
    local phaseNames = { "total" }
    for _, name in ipairs(PHASES) do phaseNames[#phaseNames + 1] = name end
    for index, sample in ipairs(samples(self)) do
        local timings = {}
        for _, name in ipairs(phaseNames) do
            timings[name] = (sample.timings[name] or 0) * 1000
        end
        output[index] = {
            timings = timings,
            counts = shallowCopy(sample.counts),
            activity = shallowCopy(sample.activity),
            causes = causeSummary { sample },
            memoryStartKB = sample.memoryStartKB or 0,
            memoryKB = sample.memoryKB or 0,
            memoryDeltaKB = sample.memoryDeltaKB or 0,
            heapDeltasKB = shallowCopy(sample.heapDeltasKB),
            topSemanticOwners = ownerSummary { sample },
            transformAttribution = copyAttribution(
                sample.transformAttribution),
            refAttribution = copyAttribution(sample.refAttribution),
        }
    end
    return output
end

-- Returns a compact detached summary for overlays and checks. Times are
-- milliseconds; no actor state, props, messages, or component descriptions
-- cross this diagnostic boundary.
function diagnostics:snapshot()
    local history = samples(self)
    local latest = history[#history]
    local phaseNames = { "total" }
    for _, name in ipairs(PHASES) do phaseNames[#phaseNames + 1] = name end
    local reconciled, quiet = {}, {}
    for _, sample in ipairs(history) do
        if (sample.activity.reconciles or 0) > 0 then
            reconciled[#reconciled + 1] = sample
        else
            quiet[#quiet + 1] = sample
        end
    end
    local slowest
    for _, sample in ipairs(history) do
        local totalMs = (sample.timings.total or 0) * 1000
        if not slowest or totalMs > slowest.totalMs then
            local slowPhases = {}
            for _, name in ipairs(phaseNames) do
                slowPhases[name] = (sample.timings[name] or 0) * 1000
            end
            local slowCauses = {}
            for name, count in pairs(sample.causes or {}) do
                slowCauses[#slowCauses + 1] = { name = name, count = count }
            end
            table.sort(slowCauses, function(left, right)
                if left.count ~= right.count then
                    return left.count > right.count
                end
                return left.name < right.name
            end)
            slowest = {
                totalMs = totalMs,
                phases = slowPhases,
                counts = shallowCopy(sample.counts),
                causes = slowCauses,
                memoryDeltaKB = sample.memoryDeltaKB or 0,
            }
        end
    end
    return {
        enabled = self.enabled,
        samples = #history,
        phases = phaseSummary(history, phaseNames),
        memory = memorySummary(history),
        topSemanticOwners = ownerSummary(history),
        counts = shallowCopy(latest and latest.counts or self.retainedCounts),
        activityTotals = activitySummary(history),
        causes = causeSummary(history),
        cohorts = {
            reconciled = cohortSummary(reconciled, phaseNames),
            quiet = cohortSummary(quiet, phaseNames),
        },
        slowest = slowest,
        memoryKB = latest and latest.memoryKB or collectgarbage("count"),
        memoryDeltaKB = latest and latest.memoryDeltaKB or 0,
    }
end

return diagnostics
