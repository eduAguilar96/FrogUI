-- Converts physical window dimensions into FrogUI's responsive virtual
-- viewport, including fit-then-extend scaling and wide-mode detection.

local viewport = {}
viewport.__index = viewport

local function finite(value)
    return type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

local function nonnegative(value, fallback)
    if value == nil then return fallback end
    assert(finite(value) and value >= 0,
        "viewport values must be finite and non-negative")
    return value
end

local function positive(value, label)
    assert(finite(value) and value > 0,
        label .. " must be finite and positive")
    return value
end

-- Physical size belongs to the platform boundary. A caller may pass an exact
-- top-level size, an exact viewport subregion, or omit both dimensions inside
-- LÖVE and let the Host sample the current drawable once at construction.
-- Mixed/partial records are rejected so a typo cannot silently change scale.
local function physicalSize(options, region)
    local regionOwnsSize = region.width ~= nil or region.height ~= nil
    local optionsOwnsSize = options.width ~= nil or options.height ~= nil
    assert(not (regionOwnsSize and optionsOwnsSize),
        "viewport size belongs either to options.width/height or "
            .. "options.viewport.width/height, not both")
    if regionOwnsSize then
        assert(region.width ~= nil and region.height ~= nil,
            "options.viewport requires both width and height")
        return positive(region.width, "viewport width"),
            positive(region.height, "viewport height")
    end
    if optionsOwnsSize then
        assert(options.width ~= nil and options.height ~= nil,
            "FrogUI Host requires both width and height")
        return positive(options.width, "viewport width"),
            positive(options.height, "viewport height")
    end
    local graphics = love and love.graphics
    assert(graphics and type(graphics.getDimensions) == "function",
        "FrogUI Host requires physical width/height outside LÖVE")
    local width, height = graphics.getDimensions()
    return positive(width, "LÖVE drawable width"),
        positive(height, "LÖVE drawable height")
end

local function fields(record, allowed, label)
    assert(type(record) == "table" and getmetatable(record) == nil,
        label .. " must be a plain table")
    for key in pairs(record) do
        assert(allowed[key], "unknown " .. label .. " field " .. tostring(key))
    end
end

function viewport.new(options)
    assert(type(options) == "table" and getmetatable(options) == nil,
        "FrogUI viewport options must be a plain table")
    local region = options.viewport or {}
    fields(region, { x = true, y = true, width = true, height = true },
        "options.viewport")
    local self = setmetatable({}, viewport)
    self.x = nonnegative(region.x, 0)
    self.y = nonnegative(region.y, 0)
    self.physicalWidth, self.physicalHeight = physicalSize(options, region)
    assert(options.designWidth ~= nil and options.designHeight ~= nil,
        "FrogUI Host requires explicit designWidth and designHeight")
    self.designWidth = positive(options.designWidth, "designWidth")
    self.designHeight = positive(options.designHeight, "designHeight")
    self.wideRatio = options.wideRatio or 1
    assert(finite(self.wideRatio) and self.wideRatio > 0,
        "wideRatio must be finite and positive")
    local safe = options.safe or {}
    fields(safe, { left = true, right = true, top = true, bottom = true },
        "options.safe")
    self.safe = {
        left = nonnegative(safe.left, 0),
        right = nonnegative(safe.right, 0),
        top = nonnegative(safe.top, 0),
        bottom = nonnegative(safe.bottom, 0),
    }
    self:recalculate()
    return self
end

function viewport:recalculate()
    self.scale = math.min(
        self.physicalWidth / self.designWidth,
        self.physicalHeight / self.designHeight)
    self.width = self.physicalWidth / self.scale
    self.height = self.physicalHeight / self.scale
    self.wide = self.width / self.height >= self.wideRatio
end

function viewport:resize(width, height)
    assert(finite(width) and width > 0, "viewport width must be finite and positive")
    assert(finite(height) and height > 0, "viewport height must be finite and positive")
    self.physicalWidth = width
    self.physicalHeight = height
    self:recalculate()
end

function viewport:toVirtual(x, y)
    return (x - self.x) / self.scale, (y - self.y) / self.scale
end

function viewport:toPhysical(x, y)
    return self.x + x * self.scale, self.y + y * self.scale
end

function viewport:snapshot()
    return {
        width = self.width,
        height = self.height,
        wide = self.wide,
        scale = self.scale,
        safe = {
            left = self.safe.left or 0,
            right = self.safe.right or 0,
            top = self.safe.top or 0,
            bottom = self.safe.bottom or 0,
        },
    }
end

return viewport
