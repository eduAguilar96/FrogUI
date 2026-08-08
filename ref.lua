-- Committed refs expose arranged primitive rectangles without letting a
-- candidate render publish partial geometry. Host owns their lifecycle.

local ref = {}

-- Private state keeps public handles read-only and prevents application code
-- from mutating the rectangle used by framework effects.
local states = setmetatable({}, { __mode = "k" })

-- Returns a detached rectangle so a caller cannot mutate committed state.
local function copyRect(rect)
    if not rect then return nil end
    return {
        x = rect.x,
        y = rect.y,
        width = rect.width,
        height = rect.height,
    }
end

local handleMeta = {
    __index = function(handle, key)
        local state = states[handle]
        if key == "current" then return copyRect(state and state.current) end
        return nil
    end,
    __newindex = function(_, key)
        error("FrogUI refs are read-only; cannot assign " .. tostring(key), 2)
    end,
    __metatable = "FrogUI ref",
    __tostring = function(handle)
        local state = states[handle]
        return state and ("FrogUI ref " .. state.id) or "expired FrogUI ref"
    end,
}

-- Creates one stable, public ref handle owned by a Host hook slot.
function ref.new(owner, id, key)
    local handle = setmetatable({}, handleMeta)
    states[handle] = {
        owner = owner,
        id = id,
        key = key,
        current = nil,
    }
    return handle
end

-- Reports whether a value is a live FrogUI ref handle.
function ref.isRef(value)
    return type(value) == "table" and states[value] ~= nil
end

-- Rejects handles created by a different Host instance.
function ref.belongsTo(handle, owner)
    local state = states[handle]
    return state ~= nil and state.owner == owner
end

-- Returns development metadata without exposing mutable private state.
function ref.inspect(handle)
    local state = assert(states[handle], "invalid FrogUI ref")
    return {
        id = state.id,
        key = state.key,
        current = copyRect(state.current),
    }
end

-- Publishes one complete successful arrange, clearing absent attachments.
function ref.publish(previous, current, rectangles)
    for handle in pairs(previous or {}) do
        if not current[handle] then states[handle].current = nil end
    end
    for handle in pairs(current or {}) do
        states[handle].current = copyRect(rectangles[handle])
    end
end

return ref
