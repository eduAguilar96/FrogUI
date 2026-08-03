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

function viewport.new(options)
    options = options or {}
    local region = options.viewport or {}
    local self = setmetatable({}, viewport)
    self.x = nonnegative(region.x, 0)
    self.y = nonnegative(region.y, 0)
    self.physicalWidth = nonnegative(region.width, options.width or 540)
    self.physicalHeight = nonnegative(region.height, options.height or 960)
    self.designWidth = nonnegative(options.designWidth, 540)
    self.designHeight = nonnegative(options.designHeight, 960)
    assert(self.physicalWidth > 0 and self.physicalHeight > 0,
        "viewport width and height must be positive")
    assert(self.designWidth > 0 and self.designHeight > 0,
        "design width and height must be positive")
    self.wideRatio = options.wideRatio or 1
    assert(finite(self.wideRatio) and self.wideRatio > 0,
        "wideRatio must be finite and positive")
    local safe = options.safe or {}
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
