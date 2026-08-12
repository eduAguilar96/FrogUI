-- ActorLocal is FrogUI's Host-owned semantic scheduler. It retains committed
-- component/actor descriptions across typed actor changes so unchanged owners
-- skip their callbacks while every primitive and layout pass still rebuilds.

local ActorLocal = {}
ActorLocal.__index = ActorLocal

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

-- Creates one empty Host-lifetime semantic output cache.
function ActorLocal.new()
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
    }, ActorLocal)
end

-- Starts a full candidate when dirtyActors is nil and an actor-local candidate
-- otherwise. The dirty set is copied so later messages cannot mutate it.
function ActorLocal:beginCandidate(dirtyActors)
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
function ActorLocal:isDirty(stage, logicalPath)
    return stage.full or stage.dirtyActors[logicalPath] == true
end

-- Reuses one exact committed owner description when its identity is stable.
function ActorLocal:reuse(stage, logicalPath, token, callback, descriptor)
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

-- Records one callback result in candidate-local storage. Nil remains valid
-- because the containing record owns the distinction from a missing owner.
function ActorLocal:record(stage, logicalPath, token, callback, descriptor,
        rendered)
    stage.outputs[logicalPath] = {
        token = token,
        callback = callback,
        descriptor = descriptor,
        rendered = rendered,
    }
    stage.renderedOwners = stage.renderedOwners + 1
end

-- Publishes a complete semantic-output set only with its Host candidate.
function ActorLocal:commit(stage)
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
function ActorLocal:liveOwnerCount()
    local count = 0
    for _ in pairs(self._outputs) do count = count + 1 end
    return count
end

-- Returns detached scalar evidence for focused development checks.
function ActorLocal:report()
    return {
        totals = copyReport(self._totals),
        last = copyReport(self._last),
        liveOwners = self:liveOwnerCount(),
    }
end

-- Clears all retained descriptions and counters between mount lifetimes.
function ActorLocal:reset()
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

return ActorLocal
