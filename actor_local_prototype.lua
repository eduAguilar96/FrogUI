-- ActorLocalPrototype is an opt-in development proof for explicit actor-local
-- semantic updates. It retains returned descriptions only across typed actor
-- changes; ordinary FrogUI Hosts never allocate or consult this cache.

local Prototype = {}
Prototype.__index = Prototype

local function copySet(source)
    if source == nil then return nil, 0 end
    local output, count = {}, 0
    for key, value in pairs(source) do
        if value then
            output[key] = true
            count = count + 1
        end
    end
    return output, count
end

local function copyReport(source)
    local output = {}
    for key, value in pairs(source or {}) do output[key] = value end
    return output
end

-- Creates one empty Host-lifetime cache and bounded scalar report.
function Prototype.new()
    return setmetatable({
        _outputs = {},
        _totals = {
            candidates = 0,
            fullCandidates = 0,
            localCandidates = 0,
            renderedOwners = 0,
            reusedOwners = 0,
        },
        _last = {},
    }, Prototype)
end

-- Starts a full candidate when dirtyActors is nil and an actor-local candidate
-- otherwise. The dirty set is copied so later message work cannot mutate it.
function Prototype:beginCandidate(dirtyActors)
    local copied, dirtyCount = copySet(dirtyActors)
    return {
        full = copied == nil,
        dirtyActors = copied or {},
        dirtyActorCount = dirtyCount,
        outputs = {},
        renderedOwners = 0,
        reusedOwners = 0,
    }
end

-- Returns whether one mounted actor was named by the current message batch.
function Prototype:isDirty(stage, logicalPath)
    return stage.full or stage.dirtyActors[logicalPath] == true
end

-- Reuses one exact committed owner description. Token, render callback, and
-- authored input descriptor identities must still name the same boundary.
function Prototype:reuse(stage, logicalPath, token, callback, descriptor)
    if stage.full then return false end
    local record = self._outputs[logicalPath]
    if not record or record.token ~= token or record.callback ~= callback
            or record.descriptor ~= descriptor then
        return false
    end
    stage.outputs[logicalPath] = record
    stage.reusedOwners = stage.reusedOwners + 1
    return true, record.rendered
end

-- Records one callback result in candidate-local storage. Nil output remains a
-- valid record because the containing record table owns the distinction.
function Prototype:record(stage, logicalPath, token, callback, descriptor,
        rendered)
    stage.outputs[logicalPath] = {
        token = token,
        callback = callback,
        descriptor = descriptor,
        rendered = rendered,
    }
    stage.renderedOwners = stage.renderedOwners + 1
end

-- Publishes a complete owner-description set only with its Host candidate.
function Prototype:commit(stage)
    self._outputs = stage.outputs
    local totals = self._totals
    totals.candidates = totals.candidates + 1
    if stage.full then
        totals.fullCandidates = totals.fullCandidates + 1
    else
        totals.localCandidates = totals.localCandidates + 1
    end
    totals.renderedOwners = totals.renderedOwners + stage.renderedOwners
    totals.reusedOwners = totals.reusedOwners + stage.reusedOwners
    self._last = {
        full = stage.full,
        dirtyActors = stage.dirtyActorCount,
        renderedOwners = stage.renderedOwners,
        reusedOwners = stage.reusedOwners,
        liveOwners = self:liveOwnerCount(),
    }
end

-- Counts retained scalar-keyed records without exposing their descriptions.
function Prototype:liveOwnerCount()
    local count = 0
    for _ in pairs(self._outputs) do count = count + 1 end
    return count
end

-- Returns detached scalar evidence for focused development checks.
function Prototype:report()
    return {
        totals = copyReport(self._totals),
        last = copyReport(self._last),
        liveOwners = self:liveOwnerCount(),
    }
end

-- Clears all retained descriptions at the end of the Host lifetime.
function Prototype:reset()
    self._outputs = {}
    self._last = {}
    self._totals = {
        candidates = 0,
        fullCandidates = 0,
        localCandidates = 0,
        renderedOwners = 0,
        reusedOwners = 0,
    }
end

return Prototype
