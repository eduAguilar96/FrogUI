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

local function sameRect(left, right)
    if left == right then return true end
    if not left or not right then return false end
    return left.x == right.x and left.y == right.y
        and left.width == right.width and left.height == right.height
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
function ref.publish(previous, current, rectangles, observe)
    local stats = observe and { published = 0, cleared = 0, changed = 0 } or nil
    for handle in pairs(previous or {}) do
        if not current[handle] then
            if stats and states[handle].current ~= nil then
                stats.cleared = stats.cleared + 1
            end
            states[handle].current = nil
        end
    end
    for handle in pairs(current or {}) do
        local rectangle = rectangles[handle]
        if stats then stats.published = stats.published + 1 end
        if stats and not sameRect(states[handle].current, rectangle) then
            stats.changed = stats.changed + 1
        end
        states[handle].current = copyRect(rectangle)
    end
    return stats
end

return ref
