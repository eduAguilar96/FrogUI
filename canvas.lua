-- Records a small validated shape vocabulary for the bounded Canvas leaf.
-- Application callbacks never receive LÖVE graphics or mutable recorder state.

local canvas = {}

-- This is the single authority for Canvas work and geometry ceilings. Geometry
-- may extend beyond a leaf for clipped effects, but only within a leaf-relative
-- envelope and an absolute backstop that keeps GPU inputs finite and modest.
local LIMITS = {
    commandCount = 1024,
    transformDepth = 32,
    relativeExtent = 8,
    minimumExtent = 64,
    absoluteExtent = 16384,
    lineWidth = 256,
    transformScale = 64,
    combinedScale = 64,
    rotation = math.pi * 1024,
    curveSegments = 48,
}

local STATES = setmetatable({}, { __mode = "k" })
local METHODS = {}
local PAINTER_MT = {
    __index = METHODS,
    __newindex = function()
        error("FrogUI Canvas painter is read-only", 2)
    end,
    __metatable = "FrogUICanvasPainter",
}

local function pack(...)
    return { n = select("#", ...), ... }
end

local function returnsNothing(results, first, label)
    for index = first, results.n do
        assert(results[index] == nil, label .. " must not return a value")
    end
end

local function finite(value)
    return type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

local function plain(value, label)
    assert(type(value) == "table" and getmetatable(value) == nil,
        label .. " must be a plain table")
end

local function number(value, label, minimum)
    assert(finite(value), label .. " must be a finite number")
    if minimum ~= nil then
        assert(value >= minimum,
            label .. " must be at least " .. tostring(minimum))
    end
    return value
end

local function defaulted(value, fallback)
    if value == nil then return fallback end
    return value
end

local function fields(value, allowed, label)
    plain(value, label)
    for key in pairs(value) do
        assert(allowed[key], label .. " has unknown field " .. tostring(key))
    end
end

local function detached(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, child in pairs(value) do copy[detached(key)] = detached(child) end
    return copy
end

local function hypot(x, y)
    local largest = math.max(math.abs(x), math.abs(y))
    if largest == 0 then return 0 end
    local smaller = math.min(math.abs(x), math.abs(y)) / largest
    return largest * math.sqrt(1 + smaller * smaller)
end

local RECT_FIELDS = {
    x = true, y = true, width = true, height = true,
    radius = true, color = true, lineWidth = true,
}
local CIRCLE_FIELDS = {
    x = true, y = true, radius = true, color = true, lineWidth = true,
}
local ELLIPSE_FIELDS = {
    x = true, y = true, radiusX = true, radiusY = true, color = true,
}
local TRANSFORM_FIELDS = {
    x = true, y = true, rotation = true, scale = true,
}

local function stateFor(self)
    local state = STATES[self]
    assert(state and state.open,
        "FrogUI Canvas painter is no longer active")
    assert(not state.suspended,
        "FrogUI Canvas painter must use the scoped painter passed to withTransform")
    return state
end

local function newPainter(state)
    local painter = setmetatable({}, PAINTER_MT)
    state.open = true
    STATES[painter] = state
    return painter
end

local function assertReach(state, localReach, label)
    assert(finite(localReach) and localReach <= state.envelope,
        label .. " exceeds the Canvas geometry ceiling")
    local reach = state.reach + state.scale * localReach
    assert(finite(reach) and reach <= state.envelope,
        label .. " exceeds the Canvas geometry ceiling")
end

local function append(state, command)
    state.budget.count = state.budget.count + 1
    assert(state.budget.count <= LIMITS.commandCount,
        "FrogUI Canvas exceeded its per-leaf command budget")
    state.commands[#state.commands + 1] = command
end

local function color(state, value, label)
    assert(value ~= nil, label .. " requires color")
    if type(value) == "string" then
        assert(value ~= "", label .. " color token must be non-empty")
    else
        plain(value, label .. " color")
        local named = value.r ~= nil or value.g ~= nil
            or value.b ~= nil or value.a ~= nil
        local allowed = named and { r = true, g = true, b = true, a = true }
            or { [1] = true, [2] = true, [3] = true, [4] = true }
        local required = named and { "r", "g", "b" } or { 1, 2, 3 }
        for key in pairs(value) do
            assert(allowed[key], label .. " color has unknown channel "
                .. tostring(key))
        end
        for _, key in ipairs(required) do
            assert(value[key] ~= nil, label .. " color is missing channel "
                .. tostring(key))
        end
        for key, channel in pairs(value) do
            assert(finite(channel) and channel >= 0 and channel <= 1,
                label .. " color channel " .. tostring(key)
                    .. " must be between 0 and 1")
        end
    end
    return detached(state.resolveColor(value))
end

local function lineWidth(value, label, state)
    local width = number(defaulted(value, 1), label .. " lineWidth", 0)
    assert(width > 0, label .. " lineWidth must be positive")
    assert(width <= math.min(LIMITS.lineWidth, state.envelope),
        label .. " lineWidth exceeds the Canvas geometry ceiling")
    return width
end

local function rectangle(self, kind, value, stroke)
    local state = stateFor(self)
    fields(value, RECT_FIELDS, "Canvas " .. kind)
    local label = "Canvas " .. kind
    local command = {
        kind = kind,
        x = number(value.x, label .. " x"),
        y = number(value.y, label .. " y"),
        width = number(value.width, label .. " width", 0),
        height = number(value.height, label .. " height", 0),
        radius = number(defaulted(value.radius, 0), label .. " radius", 0),
        _segments = LIMITS.curveSegments,
        color = color(state, value.color, label),
    }
    assert(command.radius <= math.min(command.width, command.height) / 2,
        label .. " radius exceeds half its smallest dimension")
    local strokeRadius = 0
    if stroke then
        command.lineWidth = lineWidth(value.lineWidth, label, state)
        strokeRadius = command.lineWidth / 2
    else
        assert(value.lineWidth == nil, label .. " does not accept lineWidth")
    end
    local farX = math.max(math.abs(command.x),
        math.abs(command.x + command.width))
    local farY = math.max(math.abs(command.y),
        math.abs(command.y + command.height))
    assertReach(state, hypot(farX, farY) + strokeRadius, label)
    append(state, command)
end

local function circle(self, kind, value, stroke)
    local state = stateFor(self)
    fields(value, CIRCLE_FIELDS, "Canvas " .. kind)
    local label = "Canvas " .. kind
    local command = {
        kind = kind,
        x = number(value.x, label .. " x"),
        y = number(value.y, label .. " y"),
        radius = number(value.radius, label .. " radius", 0),
        _segments = LIMITS.curveSegments,
        color = color(state, value.color, label),
    }
    local strokeRadius = 0
    if stroke then
        command.lineWidth = lineWidth(value.lineWidth, label, state)
        strokeRadius = command.lineWidth / 2
    else
        assert(value.lineWidth == nil, label .. " does not accept lineWidth")
    end
    assertReach(state, hypot(command.x, command.y)
        + command.radius + strokeRadius, label)
    append(state, command)
end

--- Records one filled rounded rectangle in Canvas-local logical pixels.
function METHODS:fillRect(value)
    rectangle(self, "fillRect", value, false)
end

--- Records one outlined rounded rectangle in Canvas-local logical pixels.
function METHODS:strokeRect(value)
    rectangle(self, "strokeRect", value, true)
end

--- Records one filled circle in Canvas-local logical pixels.
function METHODS:fillCircle(value)
    circle(self, "fillCircle", value, false)
end

--- Records one outlined circle in Canvas-local logical pixels.
function METHODS:strokeCircle(value)
    circle(self, "strokeCircle", value, true)
end

--- Records one filled ellipse in Canvas-local logical pixels.
function METHODS:fillEllipse(value)
    local state = stateFor(self)
    fields(value, ELLIPSE_FIELDS, "Canvas fillEllipse")
    local command = {
        kind = "fillEllipse",
        x = number(value.x, "Canvas fillEllipse x"),
        y = number(value.y, "Canvas fillEllipse y"),
        radiusX = number(value.radiusX, "Canvas fillEllipse radiusX", 0),
        radiusY = number(value.radiusY, "Canvas fillEllipse radiusY", 0),
        _segments = LIMITS.curveSegments,
        color = color(state, value.color, "Canvas fillEllipse"),
    }
    assertReach(state, hypot(command.x, command.y)
        + math.max(command.radiusX, command.radiusY), "Canvas fillEllipse")
    append(state, command)
end

--- Records a nested translate/rotate/uniform-scale group.
function METHODS:withTransform(value, callback)
    local state = stateFor(self)
    fields(value, TRANSFORM_FIELDS, "Canvas transform")
    assert(type(callback) == "function",
        "Canvas withTransform needs a callback")
    local depth = state.depth + 1
    assert(depth <= LIMITS.transformDepth,
        "FrogUI Canvas exceeded its transform-depth budget")
    local scale = value.scale == nil and 1
        or number(value.scale, "Canvas transform scale", 0)
    assert(scale <= LIMITS.transformScale,
        "Canvas transform scale exceeds the Canvas geometry ceiling")
    local combinedScale = state.scale * scale
    assert(finite(combinedScale) and combinedScale <= LIMITS.combinedScale,
        "Canvas transform scale product exceeds the Canvas geometry ceiling")
    local x = number(defaulted(value.x, 0), "Canvas transform x")
    local y = number(defaulted(value.y, 0), "Canvas transform y")
    local rotation = number(defaulted(value.rotation, 0),
        "Canvas transform rotation")
    assert(math.abs(rotation) <= LIMITS.rotation,
        "Canvas transform rotation exceeds the Canvas geometry ceiling")
    local localTranslation = hypot(x, y)
    assert(finite(localTranslation) and localTranslation <= state.envelope,
        "Canvas transform translation exceeds the Canvas geometry ceiling")
    local translatedReach = state.reach + state.scale * localTranslation
    assert(finite(translatedReach) and translatedReach <= state.envelope,
        "Canvas transform translation exceeds the Canvas geometry ceiling")

    state.budget.maxDepth = math.max(state.budget.maxDepth, depth)
    local command = {
        kind = "transform",
        x = x,
        y = y,
        rotation = rotation,
        scale = scale,
        commands = {},
    }
    append(state, command)
    state.suspended = true
    local childState = {
        commands = command.commands,
        budget = state.budget,
        resolveColor = state.resolveColor,
        depth = depth,
        envelope = state.envelope,
        scale = combinedScale,
        reach = translatedReach,
    }
    local child = newPainter(childState)
    local results = pack(pcall(callback, child))
    childState.open = false
    state.suspended = false
    if not results[1] then error(results[2], 0) end
    returnsNothing(results, 2, "Canvas withTransform callback")
end

-- Runs one application callback into detached commands and failure metadata.
function canvas.record(draw, width, height, resolveColor)
    local rect = {
        x = 0,
        y = 0,
        width = width,
        height = height,
    }
    local commands = {}
    local budget = { count = 0, maxDepth = 0 }
    local rootState
    local results = pack(xpcall(function()
        rect.width = number(rect.width, "Canvas arranged width", 0)
        rect.height = number(rect.height, "Canvas arranged height", 0)
        assert(rect.width <= LIMITS.absoluteExtent
                and rect.height <= LIMITS.absoluteExtent,
            "Canvas arranged bounds exceed the Canvas geometry ceiling")
        local leafExtent = math.max(rect.width, rect.height)
        local envelope = math.min(LIMITS.absoluteExtent,
            math.max(LIMITS.minimumExtent,
                leafExtent * LIMITS.relativeExtent))
        rootState = {
            commands = commands,
            budget = budget,
            resolveColor = resolveColor,
            depth = 0,
            envelope = envelope,
            scale = 1,
            reach = 0,
        }
        local recorder = newPainter(rootState)
        local returned = pack(draw(recorder, detached(rect)))
        returnsNothing(returned, 1, "Canvas draw callback")
    end, debug.traceback))
    if rootState then rootState.open = false end
    local ok, reason = results[1], results[2]
    return ok and commands or {}, {
        status = ok and "ready" or "failed",
        commandCount = ok and budget.count or 0,
        transformDepth = ok and budget.maxDepth or 0,
        clipped = true,
        localBounds = rect,
        error = ok and nil or tostring(reason),
    }
end

-- Returns commands that a custom Host painter may inspect but never mutate.
function canvas.detached(commands)
    return detached(commands)
end

return canvas
