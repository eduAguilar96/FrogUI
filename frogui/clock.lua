-- Provides deterministic clocks for motion, feedback, and later animation
-- playback. A clock moves only when its owner explicitly advances it.

local clock = {}

local Clock = {}
Clock.__index = Clock

local function finite(value)
    return type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

-- Advances this clock without consulting wall time or LÖVE globals.
function Clock:advance(dt)
    assert(finite(dt) and dt >= 0,
        "Frog clock advance expects a finite non-negative dt")
    self._time = self._time + dt
    return self._time
end

-- Returns the exact time currently owned by this clock.
function Clock:now()
    return self._time
end

-- Moves this clock to a deterministic point, including backwards for replay.
function Clock:reset(time)
    time = time or 0
    assert(finite(time) and time >= 0,
        "Frog clock reset expects a finite non-negative time")
    self._time = time
    return self._time
end

-- Creates an independent clock. Hosts own a raw clock; callers may pass
-- explicit playback and feedback clocks to recipes later.
function clock.new(time)
    local self = setmetatable({ __frogClock = true, _time = 0 }, Clock)
    self:reset(time)
    return self
end

function clock.isClock(value)
    return type(value) == "table" and value.__frogClock == true
        and getmetatable(value) == Clock
end

return clock
