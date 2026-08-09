-- Development-only rolling profiler for one FrogUI Host. It records coarse
-- pipeline phases and structural counts without retaining component state or
-- presentation payloads. Hosts must opt in explicitly.

local diagnostics = {}
diagnostics.__index = diagnostics

local DEFAULT_HISTORY = 180
local PHASES = {
    "update", "frameCallbacks", "messageDelivery", "actionProcessing",
    "eventProcessing", "actorTransitions", "reconcile",
    "componentExpansion", "layout", "commit", "runtime", "interaction",
    "motion", "refs", "effects", "diagnosticObserver", "external", "paint",
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
        }
    end
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
    if not started or not self.current then return end
    local elapsed = math.max(0, now() - started)
    self.current.timings[name] = (self.current.timings[name] or 0) + elapsed
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
    local memory = collectgarbage("count")
    sample.memoryKB = memory
    sample.memoryDeltaKB = memory - sample.memoryStartKB
    sample.memoryStartKB = nil
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
            memoryDeltaKB = sample.memoryDeltaKB or 0,
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
