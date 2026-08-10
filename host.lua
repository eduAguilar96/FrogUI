-- Owns FrogUI's one mounted tree: component expansion, actor reconciliation,
-- input routing, inspection, resource lookup, and committed rendering.

local Layout = require("src.frogui.layout")
local Painter = require("src.frogui.painter")
local Viewport = require("src.frogui.viewport")
local Element = require("src.frogui.element")
local Message = require("src.frogui.message")
local Clock = require("src.frogui.clock")
local Motion = require("src.frogui.motion")
local Effect = require("src.frogui.effects.runtime")
local Shader = require("src.frogui.shader")
local Interaction = require("src.frogui.interaction")
local Ref = require("src.frogui.ref")
local Diagnostics = require("src.frogui.diagnostics")

local host = {}
host.__index = host

local activeHost = nil
local renderingHost = nil

local PRIMITIVES = {
    Box = true, Row = true, Column = true, Overlay = true,
    EffectLayer = true, PopupText = true, Projectile = true, Flipbook = true,
    Text = true, Image = true, SpriteSheet = true,
    TiledImage = true, ShaderImage = true,
    Icon = true, Canvas = true, Button = true, Motion = true,
    Pressable = true, HorizontalSwipe = true, RadialDial = true,
    Scroll = true, Modal = true, Chrome = true,
    DragSource = true, DropTarget = true,
}

local DEFAULT_FONT_SIZES = {
    title = 28,
    heading = 22,
    body = 18,
    caption = 13,
    impact = 34,
}

local COMMON_PROPS = {
    key = true, width = true, height = true, grow = true,
    opacity = true, offset = true, testId = true,
    juice = true, reactions = true, ref = true,
}
local CONTAINER_PROPS = {
    padding = true, background = true, border = true, borderWidth = true,
    radius = true, clip = true, overflow = true,
    gap = true, align = true, justify = true, wrap = true,
}
local TYPE_PROPS = {
    Box = {
        padding = true, background = true, border = true, borderWidth = true,
        radius = true, clip = true, overflow = true,
        align = true, justify = true,
    },
    Row = CONTAINER_PROPS,
    Column = CONTAINER_PROPS,
    Overlay = {
        padding = true, background = true, border = true, borderWidth = true,
        radius = true, clip = true, overflow = true,
        align = true, justify = true,
    },
    EffectLayer = {
        padding = true, clip = true, overflow = true,
    },
    PopupText = {
        text = true, at = true, variant = true,
        duration = true, distance = true,
        role = true, fontScale = true,
        color = true, wrap = true, maxLines = true,
        align = true, fitDown = true,
        outlineWidth = true, outlineColor = true,
        shadowOffset = true, shadowColor = true,
        shine = true, shineSplit = true,
        x = true, y = true, scale = true,
    },
    Projectile = {
        from = true, to = true, fromOffset = true, toOffset = true,
        duration = true, clock = true, feedbackClock = true,
        onComplete = true, color = true, radius = true, coreRatio = true,
        trailDuration = true, trailAlpha = true,
        frames = true, fps = true, anchor = true, rotate = true, tint = true,
    },
    Flipbook = {
        frames = true, at = true, atOffset = true, fps = true, clock = true,
        contactAt = true, onContact = true, onComplete = true,
        rotation = true, mirror = true, anchor = true, tint = true,
    },
    TiledImage = {
        source = true, tileWidth = true, tileHeight = true,
        phase = true, velocity = true, clock = true,
        repeatAxis = true, filter = true, tint = true,
    },
    ShaderImage = {
        shader = true, uniforms = true, fallback = true, blend = true,
    },
    Canvas = { draw = true },
    Text = {
        text = true, role = true, fontScale = true,
        color = true, wrap = true, maxLines = true,
        align = true, fitDown = true,
        outlineWidth = true, outlineColor = true,
    },
    Image = {
        source = true, sourceRect = true, fit = true, tint = true,
        mirror = true,
    },
    SpriteSheet = {
        source = true, frameCount = true, fps = true, clock = true,
        fit = true, mirror = true, filter = true, tint = true,
    },
    Icon = {
        source = true, sourceRect = true, fit = true, tint = true,
        mirror = true, outline = true,
    },
    Button = {
        padding = true, background = true, border = true, borderWidth = true,
        hoverBackground = true, hoverBorder = true,
        pressedBackground = true, pressedBorder = true,
        focusedBackground = true, focusedBorder = true,
        selectedBackground = true, selectedBorder = true,
        radius = true,
        onPress = true, onLongPress = true, onHoverChange = true,
        onCommit = true, onResult = true,
        sound = true, rejectSound = true, hoverSound = true,
        disabled = true, selected = true, shortcut = true,
        align = true, justify = true,
    },
    Motion = {
        x = true, y = true, rotation = true, scale = true,
        opacity = true, tint = true,
    },
    Pressable = {
        onPress = true, onLongPress = true, onHoverChange = true,
        sound = true, hoverSound = true,
    },
    HorizontalSwipe = { onSwipe = true, onPress = true },
    RadialDial = {
        value = true, values = true, onChange = true, disabled = true,
        trackRadius = true, sound = true, spinSound = true,
        background = true, border = true, borderWidth = true,
        focusedBorder = true,
    },
    Scroll = {
        axis = true, bar = true, scrollPosition = true,
        snapInterval = true, onScrollEnd = true,
    },
    Modal = {
        dismiss = true, onDismiss = true,
        dismissSound = true,
        allowChrome = true,
        padding = true, background = true,
        align = true, justify = true,
    },
    Chrome = {
        padding = true, background = true,
        align = true, justify = true,
    },
    DragSource = {
        payload = true, preview = true, onDrop = true,
        onDragStart = true, onDragEnd = true,
        grabSound = true, dropSound = true, rejectSound = true,
    },
    DropTarget = { accepts = true, address = true },
}

local function shallowCopy(input)
    local output = {}
    for key, value in pairs(input or {}) do output[key] = value end
    return output
end

local function deepCopy(value, seen)
    if type(value) ~= "table" then return value end
    if Message.isAddress(value) or value.__frogMessageToken
            or value.__frogBinding or value.__frogTransition
            or Clock.isClock(value) or Ref.isRef(value) then
        return value
    end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local output = {}
    seen[value] = output
    local valueMeta = getmetatable(value)
    if valueMeta then setmetatable(output, valueMeta) end
    for key, nested in pairs(value) do
        output[deepCopy(key, seen)] = deepCopy(nested, seen)
    end
    return output
end

local function actorLabel(instance)
    if instance.address then return instance.address.name end
    return instance.identity
end

-- Preserves the primary failure while still surfacing a later cleanup failure.
local function appendFailure(primary, label, secondary)
    if not secondary then return primary end
    if not primary then return label .. ": " .. tostring(secondary) end
    return tostring(primary) .. "\n" .. label .. ": " .. tostring(secondary)
end

local function stateAllowed(state, from)
    if from == nil then return true end
    if type(from) ~= "table" then return state == from end
    for _, accepted in ipairs(from) do if state == accepted then return true end end
    return false
end

local function validState(value)
    local kind = type(value)
    if kind == "number" then
        return value == value and value > -math.huge and value < math.huge
    end
    if kind == "table" then
        return not value.__frogTransition and not value.__frogMessageToken
            and not value.__frogAddress and not value.__frogDescriptor
            and getmetatable(value) == nil
    end
    return kind == "string" or kind == "boolean"
end

local function validateState(value, label)
    assert(validState(value),
        label .. " must be a scalar or table state (received " .. type(value) .. ")")
    return value
end

local function validateActorState(token, value, label)
    validateState(value, label)
    if type(value) == "table" then
        for action, handler in pairs(token.definition.actions) do
            assert(type(handler) == "function",
                token.name .. " uses table state, so action " .. action.name
                    .. " must use a reducer rather than a scalar map")
        end
    end
    return value
end

local function validatePrimitive(name, children)
    assert(PRIMITIVES[name], "unknown FrogUI primitive " .. tostring(name))
    if name == "Box" or name == "Button" or name == "Motion" then
        assert(#children <= 1, "Frog." .. name .. " accepts at most one child")
    elseif name == "Pressable" or name == "HorizontalSwipe"
            or name == "Scroll" or name == "Modal"
            or name == "Chrome"
            or name == "DragSource" or name == "DropTarget" then
        assert(#children == 1, "Frog." .. name .. " accepts exactly one child")
    elseif name == "ShaderImage" then
        assert(#children == 1, "Frog.ShaderImage accepts exactly one child")
    elseif name == "Text" or name == "PopupText"
            or name == "Projectile" or name == "Flipbook"
            or name == "Image" or name == "SpriteSheet"
            or name == "TiledImage"
            or name == "Icon" or name == "Canvas" then
        assert(#children == 0, "Frog." .. name .. " does not accept children")
    end
end

local function finite(value)
    return type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

local function method(value, name)
    if type(value) ~= "table" and type(value) ~= "userdata" then return nil end
    local ok, member = pcall(function() return value[name] end)
    return ok and type(member) == "function" and member or nil
end

local function assetObject(value)
    return method(value, "getWidth") and method(value, "getHeight")
end

local function validateColorTable(value, label)
    assert(type(value) == "table", label .. " must be a color table")
    local named = value.r ~= nil or value.g ~= nil or value.b ~= nil or value.a ~= nil
    local allowed = named and { r = true, g = true, b = true, a = true }
        or { [1] = true, [2] = true, [3] = true, [4] = true }
    local required = named and { "r", "g", "b" } or { 1, 2, 3 }
    for key in pairs(value) do
        assert(allowed[key], label .. " has an unknown color channel")
    end
    for _, key in ipairs(required) do
        assert(value[key] ~= nil, label .. " is missing a color channel")
    end
    for key, channel in pairs(value) do
        assert(finite(channel) and channel >= 0 and channel <= 1,
            label .. " channel " .. tostring(key) .. " must be between 0 and 1")
    end
end

local function validateTheme(theme)
    if theme.fontFile ~= nil then
        assert(type(theme.fontFile) == "string" and theme.fontFile ~= "",
            "theme.fontFile must be a non-empty asset path")
    end
    for token, color in pairs(theme.colors or {}) do
        assert(type(token) == "string", "theme color tokens must be strings")
        validateColorTable(color, "theme color " .. token)
    end
    assert(theme.shaders == nil or (type(theme.shaders) == "table"
            and getmetatable(theme.shaders) == nil),
        "theme.shaders must be a plain semantic-source table")
    for token, source in pairs(theme.shaders or {}) do
        assert(type(token) == "string" and token ~= "",
            "theme shader tokens must be non-empty strings")
        assert(type(source) == "string" and source ~= "",
            "theme shader " .. token .. " must be non-empty source text")
    end
    local button = ((theme.controls or {}).button or {})
    local colorKeys = {
        background = true, hover = true, pressed = true, focused = true,
        selected = true, disabled = true, border = true,
        focusedBorder = true,
    }
    for key, value in pairs(button) do
        assert(colorKeys[key] or key == "radius",
            "unknown theme.controls.button field " .. tostring(key))
        if key == "radius" then
            assert(finite(value) and value >= 0,
                "theme.controls.button radius must be finite and non-negative")
        elseif type(value) == "string" then
            assert((theme.colors or {})[value] or Painter.defaults[value],
                "unknown FrogUI color token " .. value)
        else
            validateColorTable(value, "theme.controls.button " .. key)
        end
    end
    local soundKeys = {
        activate = true, hover = true, reject = true, dismiss = true,
        dragGrab = true, dragDrop = true,
        dialSpin = true, dialCommit = true,
    }
    assert(theme.sounds == nil or (type(theme.sounds) == "table"
            and getmetatable(theme.sounds) == nil),
        "theme.sounds must be a plain semantic-cue table")
    for key, cue in pairs(theme.sounds or {}) do
        assert(soundKeys[key],
            "unknown theme.sounds field " .. tostring(key))
        assert(type(cue) == "string" and cue ~= "",
            "theme.sounds." .. key .. " must be a non-empty cue id")
    end
end

-- Validates an optional semantic cue override; false explicitly disables it.
local function validateSound(value, label)
    assert(value == nil or value == false
            or (type(value) == "string" and value ~= ""),
        label .. " must be a non-empty cue id or false")
end

-- Resolves one component override against the application theme defaults.
local function soundCue(self, override, defaultKey)
    if override == false then return nil end
    return override or (self.theme.sounds or {})[defaultKey]
end

local function validateSize(value, label)
    if value == nil then return end
    if type(value) == "string" then
        local amount = value:match("^([%d%.]+)%%$")
        assert(amount and tonumber(amount) and tonumber(amount) >= 0,
            label .. " must be a non-negative number or percentage")
        return
    end
    assert(finite(value), label .. " must be finite and non-negative")
    assert(value >= 0, label .. " must be non-negative")
end

-- Validates one semantic token or direct LÖVE image object.
local function validateAssetSource(self, source, label)
    assert(source ~= nil, label .. " source token is required")
    if type(source) == "string" then
        local declared = self.assets[source]
        assert(declared ~= nil,
            "unknown FrogUI asset token " .. tostring(source))
        assert(type(declared) == "string" or assetObject(declared),
            "malformed FrogUI asset " .. tostring(source))
    else
        assert(assetObject(source), "malformed direct FrogUI asset")
    end
end

local function validateNumber(value, label, low, high)
    if value == nil then return end
    assert(finite(value), label .. " must be finite")
    if low == 0 then assert(value >= 0, label .. " must be non-negative")
    elseif low ~= nil then assert(value >= low, label .. " is below its minimum") end
    if high ~= nil then assert(value <= high, label .. " is above its maximum") end
end

local function validatePadding(value)
    if value == nil then return end
    if type(value) == "number" then
        validateNumber(value, "padding", 0)
        return
    end
    assert(type(value) == "table", "padding must be a number or side table")
    local allowed = { left = true, right = true, top = true, bottom = true }
    for side, amount in pairs(value) do
        assert(allowed[side], "unknown padding side " .. tostring(side))
        validateNumber(amount, "padding " .. side, 0)
    end
end

local function validateOffset(value)
    if value == nil then return end
    assert(type(value) == "table" and getmetatable(value) == nil,
        "offset must be a plain { x, y } table")
    for axis, amount in pairs(value) do
        assert(axis == "x" or axis == "y",
            "unknown offset axis " .. tostring(axis))
        validateNumber(amount, "offset " .. axis)
    end
end

-- Validates one effect endpoint as either a live Host ref or a layer point.
local function validateEffectAnchor(self, value, label)
    if Ref.isRef(value) then
        assert(Ref.belongsTo(value, self), label .. " belongs to a different Host")
        return
    end
    assert(type(value) == "table" and getmetatable(value) == nil,
        label .. " must be a FrogUI ref or plain { x, y } point")
    for axis, amount in pairs(value) do
        assert(axis == "x" or axis == "y",
            label .. " has unknown field " .. tostring(axis))
        validateNumber(amount, label .. "." .. axis)
    end
    assert(finite(value.x) and finite(value.y),
        label .. ".x/.y must be finite numbers")
end

-- Validates an optional point-like value without requiring both axes.
local function validateOptionalPoint(value, label)
    if value == nil then return end
    assert(type(value) == "table" and getmetatable(value) == nil,
        label .. " must be a plain { x?, y? } offset")
    for axis, amount in pairs(value) do
        assert(axis == "x" or axis == "y",
            label .. " has unknown field " .. tostring(axis))
        validateNumber(amount, label .. "." .. axis)
    end
end

-- Validates one scalar/vector/clock shader uniform value.
local function validateShaderUniform(value, label)
    if finite(value) or type(value) == "boolean" or Clock.isClock(value) then
        return
    end
    assert(type(value) == "table" and getmetatable(value) == nil,
        label .. " must be a number, boolean, Frog.clock, or numeric vector")
    local count = 0
    for key, amount in pairs(value) do
        assert(type(key) == "number" and key >= 1 and key % 1 == 0,
            label .. " must be a dense numeric vector")
        assert(finite(amount), label .. " vector values must be finite")
        count = math.max(count, key)
    end
    assert(count >= 2 and count <= 4,
        label .. " vector must contain two through four numbers")
    for index = 1, count do
        assert(value[index] ~= nil, label .. " must be a dense numeric vector")
    end
end

-- Validates a dense frame catalog while allowing absent assets at draw time.
local function validateEffectFrames(self, value, label, required)
    if value == nil then
        assert(not required, label .. " is required")
        return
    end
    assert(type(value) == "table" and getmetatable(value) == nil,
        label .. " must be a plain dense asset-token array")
    local count = 0
    for key in pairs(value) do
        assert(type(key) == "number" and key >= 1 and key % 1 == 0,
            label .. " must be a plain dense asset-token array")
        count = math.max(count, key)
    end
    if required then assert(count > 0, label .. " must not be empty") end
    for index = 1, count do
        local source = value[index]
        assert(source ~= nil, label .. " must be dense")
        if type(source) == "string" then
            local declared = self.assets[source]
            assert(declared ~= nil,
                "unknown FrogUI asset token " .. tostring(source))
            assert(type(declared) == "string" or assetObject(declared),
                "malformed FrogUI asset " .. tostring(source))
        else
            assert(assetObject(source), label .. " has malformed direct asset")
        end
    end
end

-- Validates a normalized image pivot used by animated projectile skins.
local function validateEffectPivot(value, label)
    if value == nil then return end
    assert(type(value) == "table" and getmetatable(value) == nil,
        label .. " must be a plain { x, y } point")
    for axis, amount in pairs(value) do
        assert(axis == "x" or axis == "y",
            label .. " has unknown field " .. tostring(axis))
        validateNumber(amount, label .. "." .. axis, 0, 1)
    end
    assert(value.x ~= nil and value.y ~= nil,
        label .. " needs normalized x and y")
end

local function oneOf(value, accepted, label)
    if value == nil then return end
    for _, candidate in ipairs(accepted) do if value == candidate then return end end
    error(label .. " has unsupported value " .. tostring(value), 0)
end

local function validatePrimitiveProps(self, name, props)
    local allowed = TYPE_PROPS[name] or {}
    for key in pairs(props) do
        assert(COMMON_PROPS[key] or allowed[key],
            "unknown prop " .. tostring(key) .. " on " .. name)
    end
    if props.ref ~= nil then
        assert(Ref.isRef(props.ref),
            name .. " ref must come from Frog.useRef/useKeyedRefs")
        assert(Ref.belongsTo(props.ref, self),
            name .. " ref belongs to a different Host")
    end
    validateSize(props.width, name .. " width")
    validateSize(props.height, name .. " height")
    validateNumber(props.grow, name .. " grow", 0)
    validateOffset(props.offset)
    validatePadding(props.padding)
    validateNumber(props.borderWidth, name .. " borderWidth", 0)
    validateNumber(props.radius, name .. " radius", 0)
    if name ~= "Motion" and name ~= "PopupText" then
        validateNumber(props.opacity, name .. " opacity", 0, 1)
    end
    if props.juice ~= nil then
        assert(type(props.juice) == "table" and getmetatable(props.juice) == nil,
            name .. " juice must be a plain named recipe table")
    end
    if props.reactions ~= nil then
        assert(type(props.reactions) == "table" and getmetatable(props.reactions) == nil,
            name .. " reactions must be a plain dense array")
        local count = 0
        for key in pairs(props.reactions) do
            assert(type(key) == "number" and key >= 1 and key % 1 == 0,
                name .. " reactions must be a dense array")
            count = math.max(count, key)
        end
        for index = 1, count do
            local reaction = props.reactions[index]
            assert(Message.isReaction(reaction),
                name .. " reaction " .. index .. " must come from Frog.on")
            assert(reaction.transition == nil and reaction.do_ ~= nil,
                name .. " element reactions may only use do_ = Frog.play(name)")
        end
    end
    assert(props.clip == nil or type(props.clip) == "boolean",
        name .. " clip must be a boolean")
    oneOf(props.overflow, { "clip", "visible" }, name .. " overflow")

    for _, colorProp in ipairs({
        "background", "border", "color", "tint", "outlineColor",
        "shadowColor",
        "hoverBackground", "hoverBorder",
        "pressedBackground", "pressedBorder",
        "focusedBackground", "focusedBorder",
        "selectedBackground", "selectedBorder",
    }) do
        local color = props[colorProp]
        if name == "Motion" and colorProp == "tint" then color = nil end
        if type(color) == "string" then
            assert((self.theme.colors or {})[color] or Painter.defaults[color],
                "unknown FrogUI color token " .. color)
        elseif color ~= nil then
            validateColorTable(color, colorProp .. " color")
        end
    end

    if name == "Row" or name == "Column" then
        validateNumber(props.gap, name .. " gap", 0)
        oneOf(props.align, { "start", "center", "end", "stretch" }, name .. " align")
        oneOf(props.justify,
            { "start", "center", "end", "space-between" }, name .. " justify")
        assert(props.wrap == nil or type(props.wrap) == "boolean",
            name .. " wrap must be a boolean")
        assert(not props.wrap or name == "Row", "wrap is currently supported on Row only")
    elseif name == "Box" or name == "Overlay" or name == "Button" then
        oneOf(props.align, { "start", "center", "end", "stretch" }, name .. " align")
        oneOf(props.justify,
            { "start", "center", "end", "stretch" }, name .. " justify")
    end
    if name == "Button" then
        assert(props.onPress == nil or type(props.onPress) == "function",
            "Button onPress must be a function")
        assert(props.onLongPress == nil or type(props.onLongPress) == "function",
            "Button onLongPress must be a function")
        assert(props.onHoverChange == nil or type(props.onHoverChange) == "function",
            "Button onHoverChange must be a function")
        assert(props.onCommit == nil or type(props.onCommit) == "function",
            "Button onCommit must be a function")
        assert(props.onResult == nil or type(props.onResult) == "function",
            "Button onResult must be a function")
        assert(not props.onCommit or (not props.onPress and props.onResult),
            "Button onCommit requires onResult and cannot use onPress")
        assert(not props.onCommit or not props.onLongPress,
            "Button onCommit cannot also use onLongPress")
        assert(not props.onResult or props.onCommit,
            "Button onResult requires onCommit")
        assert(props.disabled == nil or type(props.disabled) == "boolean",
            "Button disabled must be a boolean")
        assert(props.selected == nil or type(props.selected) == "boolean",
            "Button selected must be a boolean")
        validateSound(props.sound, "Button sound")
        validateSound(props.rejectSound, "Button rejectSound")
        validateSound(props.hoverSound, "Button hoverSound")
        assert(props.shortcut == nil or type(props.shortcut) == "string"
            or type(props.shortcut) == "table",
            "Button shortcut must be a string or array")
        if type(props.shortcut) == "table" then
            local count = 0
            for key in pairs(props.shortcut) do
                assert(type(key) == "number" and key % 1 == 0 and key > 0,
                    "Button shortcut must be a dense array")
                count = math.max(count, key)
            end
            for index = 1, count do
                local key = props.shortcut[index]
                assert(type(key) == "string",
                    "Button shortcut item " .. index .. " must be a string")
            end
        end
    elseif name == "Image" or name == "Icon" then
        validateAssetSource(self, props.source, name)
        assert(props.fit == nil or props.fit == "contain" or props.fit == "cover"
            or props.fit == "stretch",
            name .. " fit must be contain, cover, or stretch")
        local rect = props.sourceRect
        if rect ~= nil then
            assert(type(rect) == "table" and getmetatable(rect) == nil,
                name .. " sourceRect must be a plain pixel rectangle")
            for key in pairs(rect) do
                assert(key == "x" or key == "y"
                        or key == "width" or key == "height",
                    name .. " sourceRect has unknown field " .. tostring(key))
            end
            validateNumber(rect.x, name .. " sourceRect x", 0)
            validateNumber(rect.y, name .. " sourceRect y", 0)
            validateNumber(rect.width, name .. " sourceRect width")
            validateNumber(rect.height, name .. " sourceRect height")
            assert(rect.x ~= nil and rect.y ~= nil,
                name .. " sourceRect needs x and y")
            assert(rect.width and rect.width > 0
                    and rect.height and rect.height > 0,
                name .. " sourceRect width and height must be positive")
            local asset = self:_asset(props.source)
            if asset then
                assert(rect.x + rect.width <= asset:getWidth()
                        and rect.y + rect.height <= asset:getHeight(),
                    name .. " sourceRect must stay inside its source asset")
            end
        end
        assert(props.mirror == nil or type(props.mirror) == "boolean",
            name .. " mirror must be a boolean")
        if name == "Icon" then
            local outline = props.outline
            if outline ~= nil then
                assert(type(outline) == "table" and getmetatable(outline) == nil,
                    "Icon outline must be a plain { width, color } table")
                for key in pairs(outline) do
                    assert(key == "width" or key == "color",
                        "unknown Icon outline field " .. tostring(key))
                end
                validateNumber(outline.width, "Icon outline width", 0)
                local color = outline.color
                if type(color) == "string" then
                    assert((self.theme.colors or {})[color] or Painter.defaults[color],
                        "unknown FrogUI color token " .. color)
                elseif color ~= nil then
                    validateColorTable(color, "Icon outline color")
                end
            end
        end
    elseif name == "Canvas" then
        assert(type(props.draw) == "function",
            "Canvas draw must be a function")
        assert(props.width ~= nil and props.height ~= nil,
            "Canvas requires explicit width and height")
    elseif name == "Text" or name == "PopupText" then
        assert(type(props.text or "") == "string", "Text text must be a string")
        assert(props.role == nil or type(props.role) == "string", "Text role must be a string")
        validateNumber(props.fontScale, "Text fontScale")
        assert(props.fontScale == nil or props.fontScale > 0,
            "Text fontScale must be positive")
        assert(props.wrap == nil or type(props.wrap) == "boolean", "Text wrap must be a boolean")
        assert(props.fitDown == nil or type(props.fitDown) == "boolean",
            "Text fitDown must be a boolean")
        if props.maxLines ~= nil then
            assert(finite(props.maxLines) and props.maxLines >= 1
                and props.maxLines % 1 == 0, "Text maxLines must be a positive integer")
        end
        validateNumber(props.outlineWidth, "Text outlineWidth", 0)
        if name == "PopupText" then
            validateNumber(props.shadowOffset, "PopupText shadowOffset", 0)
            validateNumber(props.shine, "PopupText shine", 0, 1)
            validateNumber(props.shineSplit, "PopupText shineSplit", 0, 1)
        end
        oneOf(props.align, { "left", "center", "right", "start", "end" },
            "Text align")
        if name == "PopupText" then
            assert(type(props.at) == "table" and getmetatable(props.at) == nil,
                "PopupText at must be a plain { x, y } point")
            for field, value in pairs(props.at) do
                assert(field == "x" or field == "y",
                    "PopupText at has unknown field " .. tostring(field))
                validateNumber(value, "PopupText at." .. field)
            end
            assert(finite(props.at.x) and finite(props.at.y),
                "PopupText at.x/at.y must be finite numbers")
            oneOf(props.variant, { "float", "impact", "notice" },
                "PopupText variant")
            validateNumber(props.duration, "PopupText duration", 0)
            validateNumber(props.distance, "PopupText distance", 0)
        end
    elseif name == "Projectile" then
        assert(props.ref == nil and props.offset == nil and props.grow == nil
                and props.juice == nil and props.reactions == nil,
            "Projectile position/lifecycle belongs to its effect props")
        assert(type(props.key) == "string" or type(props.key) == "number",
            "Projectile requires a stable string/number key")
        validateEffectAnchor(self, props.from, "Projectile from")
        validateEffectAnchor(self, props.to, "Projectile to")
        assert(props.width == nil or finite(props.width) and props.width > 0,
            "Projectile width must be a positive number")
        assert(props.height == nil or finite(props.height) and props.height > 0,
            "Projectile height must be a positive number")
        validateOptionalPoint(props.fromOffset, "Projectile fromOffset")
        validateOptionalPoint(props.toOffset, "Projectile toOffset")
        validateNumber(props.duration, "Projectile duration")
        assert(props.duration and props.duration > 0,
            "Projectile duration must be positive")
        assert(props.clock == nil or Clock.isClock(props.clock),
            "Projectile clock must come from Frog.clock")
        assert(props.feedbackClock == nil or Clock.isClock(props.feedbackClock),
            "Projectile feedbackClock must come from Frog.clock")
        assert(props.onComplete == nil or type(props.onComplete) == "function",
            "Projectile onComplete must be a function")
        validateNumber(props.radius, "Projectile radius")
        assert(props.radius == nil or props.radius > 0,
            "Projectile radius must be positive")
        validateNumber(props.coreRatio, "Projectile coreRatio", 0, 1)
        validateNumber(props.trailDuration, "Projectile trailDuration", 0)
        validateNumber(props.trailAlpha, "Projectile trailAlpha", 0, 1)
        validateEffectFrames(self, props.frames, "Projectile frames", false)
        validateNumber(props.fps, "Projectile fps")
        assert(props.fps == nil or props.fps > 0,
            "Projectile fps must be positive")
        validateEffectPivot(props.anchor, "Projectile anchor")
        assert(props.rotate == nil or type(props.rotate) == "boolean",
            "Projectile rotate must be a boolean")
    elseif name == "Flipbook" then
        assert(props.ref == nil and props.offset == nil and props.grow == nil
                and props.juice == nil and props.reactions == nil,
            "Flipbook position/lifecycle belongs to its effect props")
        assert(type(props.key) == "string" or type(props.key) == "number",
            "Flipbook requires a stable string/number key")
        validateEffectFrames(self, props.frames, "Flipbook frames", true)
        validateEffectAnchor(self, props.at, "Flipbook at")
        assert(props.width == nil or finite(props.width) and props.width > 0,
            "Flipbook width must be a positive number")
        assert(props.height == nil or finite(props.height) and props.height > 0,
            "Flipbook height must be a positive number")
        validateOptionalPoint(props.atOffset, "Flipbook atOffset")
        validateNumber(props.fps, "Flipbook fps")
        assert(props.fps == nil or props.fps > 0,
            "Flipbook fps must be positive")
        assert(props.clock == nil or Clock.isClock(props.clock),
            "Flipbook clock must come from Frog.clock")
        validateNumber(props.contactAt, "Flipbook contactAt", 0, 1)
        assert(props.onContact == nil or type(props.onContact) == "function",
            "Flipbook onContact must be a function")
        assert(props.onComplete == nil or type(props.onComplete) == "function",
            "Flipbook onComplete must be a function")
        validateNumber(props.rotation, "Flipbook rotation")
        assert(props.mirror == nil or type(props.mirror) == "boolean",
            "Flipbook mirror must be a boolean")
        validateEffectPivot(props.anchor, "Flipbook anchor")
    elseif name == "SpriteSheet" then
        validateAssetSource(self, props.source, name)
        assert(finite(props.frameCount) and props.frameCount > 0
                and props.frameCount % 1 == 0,
            "SpriteSheet frameCount must be a positive integer")
        validateNumber(props.fps, "SpriteSheet fps")
        assert(props.fps and props.fps > 0,
            "SpriteSheet fps must be positive")
        assert(Clock.isClock(props.clock),
            "SpriteSheet clock must come from Frog.clock")
        oneOf(props.fit, { "contain", "cover", "stretch" },
            "SpriteSheet fit")
        assert(props.mirror == nil or type(props.mirror) == "boolean",
            "SpriteSheet mirror must be a boolean")
        oneOf(props.filter, { "nearest", "linear" },
            "SpriteSheet filter")
        local asset = self:_asset(props.source)
        if asset then
            assert(asset:getWidth() % props.frameCount == 0,
                "SpriteSheet source width must divide exactly by frameCount")
        end
    elseif name == "TiledImage" then
        validateAssetSource(self, props.source, name)
        validateNumber(props.tileWidth, "TiledImage tileWidth", 1)
        validateNumber(props.tileHeight, "TiledImage tileHeight", 1)
        validateOptionalPoint(props.phase, "TiledImage phase")
        validateOptionalPoint(props.velocity, "TiledImage velocity")
        assert(props.clock == nil or Clock.isClock(props.clock),
            "TiledImage clock must come from Frog.clock")
        assert(props.velocity == nil or props.clock ~= nil,
            "TiledImage velocity requires an explicit Frog.clock")
        oneOf(props.repeatAxis, { "x", "y", "both", "none" },
            "TiledImage repeatAxis")
        oneOf(props.filter, { "nearest", "linear" }, "TiledImage filter")
    elseif name == "ShaderImage" then
        assert(type(props.shader) == "string" and props.shader ~= "",
            "ShaderImage shader must be a non-empty semantic token")
        assert((self.theme.shaders or {})[props.shader] ~= nil,
            "unknown FrogUI shader token " .. tostring(props.shader))
        assert(props.uniforms == nil or (type(props.uniforms) == "table"
                and getmetatable(props.uniforms) == nil),
            "ShaderImage uniforms must be a plain name-to-value table")
        for uniform, value in pairs(props.uniforms or {}) do
            assert(type(uniform) == "string" and uniform ~= "",
                "ShaderImage uniform names must be non-empty strings")
            validateShaderUniform(value, "ShaderImage uniform " .. uniform)
        end
        oneOf(props.fallback, { "plain", "hidden" },
            "ShaderImage fallback")
        oneOf(props.blend, { "alpha", "add" }, "ShaderImage blend")
    elseif name == "Motion" then
        assert(props.reactions == nil or #props.reactions == 0 or props.juice ~= nil,
            "Frog.Motion reactions require named juice recipes")
    elseif name == "Pressable" then
        assert(props.onPress == nil or type(props.onPress) == "function",
            "Pressable onPress must be a function")
        assert(props.onLongPress == nil or type(props.onLongPress) == "function",
            "Pressable onLongPress must be a function")
        assert(props.onHoverChange == nil or type(props.onHoverChange) == "function",
            "Pressable onHoverChange must be a function")
        assert(props.onPress or props.onLongPress or props.onHoverChange,
            "Pressable requires a press, long-press, or hover callback")
        validateSound(props.sound, "Pressable sound")
        validateSound(props.hoverSound, "Pressable hoverSound")
    elseif name == "HorizontalSwipe" then
        assert(type(props.onSwipe) == "function",
            "HorizontalSwipe onSwipe must be a function")
        assert(props.onPress == nil or type(props.onPress) == "function",
            "HorizontalSwipe onPress must be a function")
    elseif name == "RadialDial" then
        assert(type(props.values) == "table" and getmetatable(props.values) == nil,
            "RadialDial values must be a plain dense numeric array")
        local count, maximum, seen = 0, 0, {}
        for key in pairs(props.values) do
            assert(type(key) == "number" and key >= 1 and key % 1 == 0,
                "RadialDial values must be a plain dense numeric array")
            count, maximum = count + 1, math.max(maximum, key)
        end
        assert(count == maximum and count >= 2,
            "RadialDial values must contain at least two dense entries")
        local selected = false
        for index = 1, maximum do
            local value = props.values[index]
            assert(finite(value),
                "RadialDial value " .. index .. " must be a finite number")
            assert(not seen[value], "RadialDial values must be unique")
            seen[value] = true
            if value == props.value then selected = true end
        end
        assert(finite(props.value) and selected,
            "RadialDial value must be a finite member of values")
        assert(type(props.onChange) == "function",
            "RadialDial onChange must be a function")
        assert(props.disabled == nil or type(props.disabled) == "boolean",
            "RadialDial disabled must be a boolean")
        validateNumber(props.trackRadius, "RadialDial trackRadius")
        assert(props.trackRadius == nil or props.trackRadius > 0,
            "RadialDial trackRadius must be positive")
        validateSound(props.sound, "RadialDial sound")
        validateSound(props.spinSound, "RadialDial spinSound")
    elseif name == "Scroll" then
        oneOf(props.axis, { "vertical", "horizontal" }, "Scroll axis")
        assert(props.axis ~= nil, "Scroll axis is required")
        assert(props.bar == nil or type(props.bar) == "boolean",
            "Scroll bar must be a boolean")
        validateNumber(props.scrollPosition, "Scroll scrollPosition", 0)
        validateNumber(props.snapInterval, "Scroll snapInterval")
        assert(props.snapInterval == nil or props.snapInterval > 0,
            "Scroll snapInterval must be positive")
        assert(props.onScrollEnd == nil or type(props.onScrollEnd) == "function",
            "Scroll onScrollEnd must be a function")
    elseif name == "Modal" then
        assert(props.offset == nil,
            "Modal is a root portal and does not accept offset")
        oneOf(props.dismiss, { "back", "outside", "both", "none" },
            "Modal dismiss")
        assert(props.onDismiss == nil or type(props.onDismiss) == "function",
            "Modal onDismiss must be a function")
        assert((props.dismiss or "back") == "none" or props.onDismiss,
            "dismissible Modal requires onDismiss")
        validateSound(props.dismissSound, "Modal dismissSound")
        oneOf(props.align, { "start", "center", "end", "stretch" },
            "Modal align")
        oneOf(props.justify, { "start", "center", "end", "stretch" },
            "Modal justify")
        assert(props.allowChrome == nil or type(props.allowChrome) == "boolean",
            "Modal allowChrome must be a boolean")
    elseif name == "Chrome" then
        assert(props.offset == nil,
            "Chrome is a root portal and does not accept offset")
        oneOf(props.align, { "start", "center", "end", "stretch" },
            "Chrome align")
        oneOf(props.justify, { "start", "center", "end", "stretch" },
            "Chrome justify")
    elseif name == "DragSource" then
        local payload = Interaction.snapshotPlain(props.payload,
            "DragSource payload")
        assert(type(payload) == "table" and type(payload.kind) == "string"
                and payload.kind ~= "",
            "DragSource payload requires a non-empty string kind")
        assert(Element.isDescriptor(props.preview),
            "DragSource preview must be a FrogUI description")
        assert(type(props.onDrop) == "function",
            "DragSource onDrop must be a function")
        assert(props.onDragStart == nil or type(props.onDragStart) == "function",
            "DragSource onDragStart must be a function")
        assert(props.onDragEnd == nil or type(props.onDragEnd) == "function",
            "DragSource onDragEnd must be a function")
        validateSound(props.grabSound, "DragSource grabSound")
        validateSound(props.dropSound, "DragSource dropSound")
        validateSound(props.rejectSound, "DragSource rejectSound")
    elseif name == "DropTarget" then
        assert(type(props.accepts) == "string" and props.accepts ~= "",
            "DropTarget accepts must be a non-empty string")
        Interaction.snapshotPlain(props.address, "DropTarget address")
        assert(type(props.address) == "table",
            "DropTarget address must be a plain table")
        assert(type(props.key) == "string" or type(props.key) == "number",
            "DropTarget requires a stable string/number key")
    end
end

local function childPath(parentPath, descriptor, index)
    local token = descriptor.token
    local prefix = parentPath .. "/" .. token.kind .. ":" .. token.name .. ":"
    local key = descriptor.key
    if key ~= nil then return prefix .. "key:" .. type(key) .. ":" .. tostring(key) end
    return prefix .. "index:" .. tostring(index)
end

-- Stateful identity follows semantic component/actor ancestry and stable
-- child slots. Layout primitives are deliberately absent: the documented
-- `wide and Frog.Row or Frog.Column` composition must not remount actors.
local function logicalChildPath(parentPath, descriptor, index)
    local token = descriptor.token
    local segment = token.kind == "primitive" and "slot"
        or token.kind .. ":" .. token.name
    local prefix = parentPath .. "/" .. segment .. ":"
    local key = descriptor.key
    if key ~= nil then return prefix .. "key:" .. type(key) .. ":" .. tostring(key) end
    return prefix .. "index:" .. tostring(index)
end

local function logicalOutputPath(parentPath, descriptor)
    if descriptor.token.kind == "primitive" then return parentPath end
    return logicalChildPath(parentPath .. "/output", descriptor, 1)
end

local function inside(node, x, y)
    local localX, localY = Motion.localPoint(node, x, y)
    if node.type == "RadialDial" then
        local centerX = node.x + node.width / 2
        local centerY = node.y + node.height / 2
        local dx, dy = localX - centerX, localY - centerY
        local radius = math.min(node.width, node.height) / 2
        return dx * dx + dy * dy <= radius * radius
    end
    return localX >= node.x and localY >= node.y
        and localX <= node.x + node.width and localY <= node.y + node.height
end

-- Describes a RadialDial's stable transformed circle for F6. Its ornamental
-- bounce deliberately does not change layout, hit ownership, or inspection.
local function inspectionCircle(node)
    local centerX = node.x + node.width / 2
    local centerY = node.y + node.height / 2
    local radius = math.min(node.width, node.height) / 2
    local world = node._worldTransform
    if not world then
        return { center = { x = centerX, y = centerY }, radius = radius }
    end
    local transformedX = world.a * centerX + world.c * centerY + world.tx
    local transformedY = world.b * centerX + world.d * centerY + world.ty
    local edgeX = world.a * (centerX + radius)
        + world.c * centerY + world.tx
    local edgeY = world.b * (centerX + radius)
        + world.d * centerY + world.ty
    return {
        center = { x = transformedX, y = transformedY },
        radius = math.sqrt((edgeX - transformedX) ^ 2
            + (edgeY - transformedY) ^ 2),
    }
end

local function nodeEntry(node, depth, visibleBounds)
    local entry = {
        type = node.type,
        key = node.key,
        identity = node.identity,
        logicalIdentity = node.logicalIdentity,
        owner = node.owner,
        source = node.source,
        depth = depth,
        testId = node.props.testId,
        bounds = deepCopy(visibleBounds or node._visualBounds
            or { x = node.x, y = node.y, width = node.width, height = node.height }),
        restBounds = { x = node.x, y = node.y, width = node.width, height = node.height },
    }
    if node._motion then
        local inspected = Motion.inspect(node._motion)
        entry.motion = {
            current = deepCopy(node.presentation),
            active = inspected.active,
            activeDetails = inspected.activeDetails,
            declared = inspected.declared,
            reactionCount = inspected.reactionCount,
            reducedMotion = inspected.reducedMotion,
        }
    end
    if node.type == "EffectLayer" then
        entry.effectLayer = { count = #node.children, input = "transparent" }
    elseif node.type == "PopupText" then
        entry.effect = {
            variant = node.props.variant,
            at = deepCopy(node.props.at),
            duration = node.props.duration,
            distance = node.props.distance,
            treatment = {
                role = node.props.role,
                outlineWidth = node.props.outlineWidth or 0,
                shadowOffset = node.props.shadowOffset or 0,
                shine = node.props.shine or 0,
                shineSplit = node.props.shineSplit,
            },
        }
    elseif node.type == "Projectile" or node.type == "Flipbook" then
        entry.effect = Effect.inspect(node._effect)
    elseif node.type == "TiledImage" then
        entry.tiledImage = deepCopy(node._tileGeometry or {
            repeatAxis = node.props.repeatAxis or "both",
            filter = node.props.filter or "linear",
            clock = node.props.clock and "explicit" or "none",
        })
    elseif node.type == "SpriteSheet" then
        entry.spriteSheet = deepCopy(node._spriteSheetGeometry or {
            status = "pending",
            frame = math.floor(node.props.clock:now() * node.props.fps)
                % node.props.frameCount + 1,
            frameCount = node.props.frameCount,
            fps = node.props.fps,
            time = node.props.clock:now(),
            clock = "explicit",
            fit = node.props.fit or "contain",
            filter = node.props.filter or "nearest",
            mirror = node.props.mirror == true,
        })
    elseif node.type == "ShaderImage" then
        entry.shaderImage = deepCopy(node._shaderInspection or {
            token = node.props.shader,
            status = "pending",
            fallback = node.props.fallback or "plain",
            blend = node.props.blend or "alpha",
        })
    elseif node.type == "Canvas" then
        entry.canvas = deepCopy(node._canvasInspection or {
            status = "pending",
            commandCount = 0,
            transformDepth = 0,
            clipped = true,
            localBounds = {
                x = 0, y = 0, width = node.width, height = node.height,
            },
            arrangedBounds = {
                x = node.x, y = node.y, width = node.width, height = node.height,
            },
        })
    elseif node.type == "HorizontalSwipe" then
        entry.gesture = {
            kind = "horizontal-swipe",
            input = "pointer",
            ownership = "candidate-before-claim",
        }
    elseif node.type == "RadialDial" then
        local visual = Interaction.radialPresentation(node)
        local circle = inspectionCircle(node)
        entry.inspectionShape = {
            type = "circle",
            center = deepCopy(circle.center),
            radius = circle.radius,
        }
        entry.radialDial = {
            value = node._radialDial.value,
            values = deepCopy(node._radialDial.values),
            index = node._radialDial.index,
            angle = node._radialDial.angle,
            targetAngle = node._radialDial.targetAngle,
            previewAngle = node._radialDial.previewAngle,
            visualAngle = visual.angle,
            trackRadius = node._radialDial.trackRadius,
            settling = math.abs(node._radialDial.targetAngle
                - node._radialDial.angle) > 0.0001,
            bounce = node._radialDial.bounce,
            paintScale = visual.scale,
            ornamentalPaintOverflow = visual.scale ~= 1,
            center = deepCopy(circle.center),
            radius = circle.radius,
            deadZoneRadius = circle.radius
                * Interaction.radialDialPolicy().deadZoneRatio,
            reducedMotion = node._radialDial.reducedMotion == true,
            disabled = node.props.disabled == true,
            keyboard = {
                "focused Button",
                "source-ordered Button shortcut",
                "focused dial fallback",
            },
        }
    end
    if node._scroll then
        entry.scroll = {
            axis = node._scroll.axis,
            offset = node._scroll.offset,
            extent = node._scroll.extent,
            velocity = node._scroll.velocity,
        }
    end
    if node._ref then entry.ref = Ref.inspect(node._ref) end
    if node._processOwners then
        entry.processes = deepCopy(node._processOwners)
    end
    if node.actor then entry.actor = deepCopy(node.actor) end
    if node.view then entry.view = deepCopy(node.view) end
    return entry
end

local function intersection(left, right)
    if not left then return right and deepCopy(right) or nil end
    if not right then return deepCopy(left) end
    local x = math.max(left.x, right.x)
    local y = math.max(left.y, right.y)
    local farX = math.min(left.x + left.width, right.x + right.width)
    local farY = math.min(left.y + left.height, right.y + right.height)
    if farX <= x or farY <= y then return nil end
    return { x = x, y = y, width = farX - x, height = farY - y }
end

local function flatten(node, depth, output, inheritedClip, portalRoot)
    if node._portal and node ~= portalRoot then return end
    local bounds = node._visualBounds
        or { x = node.x, y = node.y, width = node.width, height = node.height }
    local visible = intersection(bounds, inheritedClip)
    if not visible then return end
    output[#output + 1] = nodeEntry(node, depth, visible)
    local childClip = inheritedClip
    if node.type == "Scroll" or node.props.clip
            or node.props.overflow == "clip" then
        childClip = intersection(childClip, node._visualContentBounds
            or { x = node.contentX, y = node.contentY,
                width = node.contentWidth, height = node.contentHeight })
        if not childClip then return end
    end
    for _, child in ipairs(node.children) do
        flatten(child, depth + 1, output, childClip, portalRoot)
    end
end

local function deepest(node, x, y, predicate, portalRoot)
    if node._portal and node ~= portalRoot then return nil end
    local contained = inside(node, x, y)
    if node.type == "Scroll" or node.props.clip
            or node.props.overflow == "clip" then
        if not contained then return nil end
        local localX, localY = Motion.localPoint(node, x, y)
        if localX < node.contentX or localY < node.contentY
                or localX > node.contentX + node.contentWidth
                or localY > node.contentY + node.contentHeight then
            return predicate(node) and node or nil
        end
    end
    for index = #node.children, 1, -1 do
        local found = deepest(node.children[index], x, y, predicate, portalRoot)
        if found then return found end
    end
    if contained and predicate(node) then return node end
    return nil
end

-- Distinguishes a painted or input-owning inspection hit from a transparent
-- layout wrapper. Top-plane concrete hits preserve z-order; transparent
-- wrappers may fall through so the developer can reach visible content below.
local function concreteInspectionHit(node)
    if node.type == "Text" or node.type == "PopupText"
            or node.type == "Projectile" or node.type == "Flipbook"
            or node.type == "Image" or node.type == "SpriteSheet"
            or node.type == "TiledImage"
            or node.type == "Icon" or node.type == "Canvas"
            or node.type == "Button" or node.type == "Pressable"
            or node.type == "HorizontalSwipe"
            or node.type == "RadialDial"
            or node.type == "Scroll" or node.type == "DragSource"
            or node.type == "DropTarget" then
        return true
    end
    return node.props.background ~= nil or node.props.border ~= nil
end

local function findIdentity(node, identity)
    if not node then return nil end
    if node.identity == identity then return node end
    for _, child in ipairs(node.children) do
        local found = findIdentity(child, identity)
        if found then return found end
    end
    return nil
end

-- Collects exact arranged rectangles from the one currently committed tree.
local function collectCommittedRefRectangles(node, rectangles, stats)
    if not node then return end
    if stats then stats.treeVisits = stats.treeVisits + 1 end
    if node._ref then
        rectangles[node._ref] = {
            x = node.x,
            y = node.y,
            width = node.width,
            height = node.height,
        }
    end
    for _, child in ipairs(node.children or {}) do
        collectCommittedRefRectangles(child, rectangles, stats)
    end
end

local function collectFocusables(node, output, spent)
    if (node.type == "Button" and not node.props.disabled
            and not spent[node.identity]) then
        output[#output + 1] = node
    elseif node.type == "RadialDial" and not node.props.disabled then
        output[#output + 1] = node
    end
    for _, child in ipairs(node.children) do
        collectFocusables(child, output, spent)
    end
end

-- Saves and restores keyboard focus once per source-ordered modal layer.
local function reconcileModalFocus(self, oldModals, oldFocusedIdentity)
    oldModals = oldModals or {}
    local newModals = self._modals or {}
    local oldFrames = self._modalFocusStack or {}
    local baseFocus = oldFocusedIdentity
    if #oldModals > 0 then
        baseFocus = oldFrames[1] and oldFrames[1].returnFocus or nil
    end

    -- A covered layer's last focus is stored by the frame immediately above
    -- it. Preserve that knowledge by semantic portal identity even when a
    -- sibling Modal is inserted or removed below the still-active top plane.
    local layerFocus = {}
    for index, modal in ipairs(oldModals) do
        local above = oldFrames[index + 1]
        layerFocus[modal.identity] = above and above.returnFocus
            or (index == #oldModals and oldFocusedIdentity or nil)
    end

    local frames = {}
    for index, modal in ipairs(newModals) do
        local lowerFocus = baseFocus
        if index > 1 then
            lowerFocus = layerFocus[newModals[index - 1].identity]
        end
        frames[index] = {
            identity = modal.identity,
            returnFocus = lowerFocus,
        }
    end

    self._modalFocusStack = frames
    local top = newModals[#newModals]
    local focus = baseFocus
    if top then
        focus = layerFocus[top.identity]
        if not focus and top.props.allowChrome == true
                and self._chrome and oldFocusedIdentity
                and findIdentity(self._chrome, oldFocusedIdentity) then
            focus = oldFocusedIdentity
        end
    end
    self._focusedIdentity = focus and Interaction.findActiveIdentity(self, focus)
        and focus or nil
end

local function assertPresentationAllowed(self, operation)
    assert(not self._authorityCallbackActive,
        (self._authorityLabel or "authority callback") .. " may not " .. operation
            .. " presentation; return the domain result")
    assert(not self._drawing,
        "Host drawing phase may not " .. operation .. " presentation")
end

-- Releases every strong Motion-target reference held by the reusable committed
-- transform batch. Candidate construction never calls this: a failed
-- candidate must leave the previous committed batch intact.
local function clearTransformTargets(work)
    for target in pairs(work.nodes) do work.nodes[target] = nil end
    work.nodeCount = 0
end

local function clearTransformWork(self)
    local work = self._transformWork
    if not work then return end
    clearTransformTargets(work)
    for index = #work.roots, 1, -1 do work.roots[index] = nil end
    work.active = false
    work.generation = 0
    work.treeToken = nil
    work.requiresFull = false
    work.fullReason = nil
    local options = self._transformOptions
    if options then options.branch = nil end
end

-- Runtime failures are terminal for this Host. FrogUI deliberately does not
-- clone and rewind arbitrary actor/process/input state; callers must unmount
-- and create a fresh Host after the original error has been surfaced.
local function faultHost(self, origin, reason)
    if not self._fault then
        self._fault = {
            origin = origin or self._currentOrigin or "runtime",
            message = tostring(reason),
        }
    end
    clearTransformWork(self)
    self._pendingTransformAttribution = nil
    return self._fault.message
end

local function assertOperational(self, operation)
    if not self._fault then return end
    error(("FrogUI Host faulted during %s: %s; cannot %s; unmount and recreate it")
        :format(tostring(self._fault.origin), tostring(self._fault.message), operation), 0)
end

-- Frame subscribers publish typed messages; they never re-enter structural
-- Host lifecycle methods before the shared frame batch has finished.
local function assertFramePublication(self, operation)
    assert(not self._frameCallbacksActive,
        "useFrame callbacks publish with Frog.send/Frog.emit; direct "
            .. operation .. " is forbidden")
end

local function assertInputBoundary(self)
    assert(self._callbackDepth == 0,
        "platform input may not re-enter an active FrogUI callback")
end

function host.new(options)
    options = options or {}
    local self = setmetatable({}, host)
    self.theme = options.theme or {}
    validateTheme(self.theme)
    self.assets = options.assets or {}
    assert(options.reducedMotion == nil or type(options.reducedMotion) == "boolean",
        "reducedMotion must be a boolean")
    self.reducedMotion = options.reducedMotion == true
    self.feedback = options.feedback or {}
    assert(type(self.feedback) == "table" and getmetatable(self.feedback) == nil,
        "feedback must be a plain { sound?, haptic? } table")
    for name, callback in pairs(self.feedback) do
        assert(name == "sound" or name == "haptic",
            "unknown FrogUI feedback service " .. tostring(name))
        assert(type(callback) == "function",
            "feedback." .. name .. " must be a function")
    end
    self._customPainter = options.painter
    assert(options.diagnostics == nil or type(options.diagnostics) == "boolean",
        "diagnostics must be a boolean")
    self._diagnostics = Diagnostics.new {
        enabled = options.diagnostics == true,
    }
    self._diagnosticPrimitiveNames = options.diagnostics == true and {} or nil
    local viewportOptions = shallowCopy(options)
    if viewportOptions.wideRatio == nil and self.theme.breakpoints then
        viewportOptions.wideRatio = self.theme.breakpoints.wideRatio
    end
    self._viewport = Viewport.new(viewportOptions)
    self._fontCache = {}
    self._assetCache = {}
    Shader.clear(self)
    self._captures = {}
    self._inspectorVisible = options.inspectorActive == true
    self._lastInputText = nil
    self._generation = 0
    self._fault = nil
    self._actors = {}
    self._addresses = {}
    self._semanticTokens = {}
    self._hookOwners = {}
    self._resources = {}
    self._frames = {}
    self._nextResourceId = 0
    self._nextFrameId = 0
    self._refs = {}
    self._nextRefId = 0
    self._messageQueue = {}
    self._messageTrace = {}
    self._messageSequence = 0
    self._spentAuthorities = {}
    self._messageTraceLimit = options.messageTraceLimit or 80
    self._messageLoopLimit = options.messageLoopLimit or 256
    assert(type(self._messageTraceLimit) == "number"
            and self._messageTraceLimit >= 1 and self._messageTraceLimit % 1 == 0,
        "messageTraceLimit must be a positive integer")
    assert(type(self._messageLoopLimit) == "number"
            and self._messageLoopLimit >= 1 and self._messageLoopLimit % 1 == 0,
        "messageLoopLimit must be a positive integer")
    self._callbackDepth = 0
    self._rawClock = Clock.new()
    self._motions = {}
    self._effects = {}
    self._scrolls = {}
    self._radials = {}
    self._interactionSession = nil
    self._modals = {}
    self._modal = nil
    self._chrome = nil
    self._modalFocusStack = {}
    self._pointerX, self._pointerY = 0, 0
    self._motionStartSequence = 0
    self._transformWork = {
        active = false,
        generation = 0,
        treeToken = nil,
        requiresFull = false,
        fullReason = nil,
        nodeCount = 0,
        nodes = {},
        roots = {},
        boundary = {},
    }
    self._transformOptions = {
        branch = nil,
        generation = 0,
        scratch = {},
    }
    self._pendingTransformAttribution = nil
    self._feedbackQueue = {}
    self._pendingActorUnmounts = {}
    self._pendingActorUnmountLifetimes = {}
    self._pendingResourceDisposals = {}
    self._pendingResourceLifetimes = {}
    return self
end

function host:_nextMotionOrder()
    self._motionStartSequence = self._motionStartSequence + 1
    return self._motionStartSequence
end

function host:_stageFeedback(kind, cue)
    self._feedbackQueue[#self._feedbackQueue + 1] = { kind = kind, cue = cue }
end

function host:_trimFeedback(count)
    while #self._feedbackQueue > count do table.remove(self._feedbackQueue) end
end

function host:_commitFeedback()
    local queued = self._feedbackQueue
    self._feedbackQueue = {}
    for _, entry in ipairs(queued) do
        local callback = self.feedback[entry.kind]
        if callback then callback(entry.cue) end
    end
end

function host.currentViewport()
    assert(renderingHost, "Frog.useViewport() may only run while a component renders")
    return renderingHost._viewport:snapshot()
end

-- Captures the application call site so reordered positional hooks fail at the
-- owning component instead of silently receiving another hook's identity.
local function hookSource()
    if not debug or not debug.getinfo then return nil end
    for level = 2, 14 do
        local info = debug.getinfo(level, "Sl")
        if not info then break end
        local path = info.short_src or info.source
        if path and not path:find("src/frogui/", 1, true) then
            return { path = path, line = info.currentline }
        end
    end
    return nil
end

-- Formats one hook call site for direct, actionable diagnostics.
local function hookSourceLabel(source)
    if not source then return "unknown source" end
    return (source.path or "?") .. ":" .. tostring(source.line or "?")
end

-- Consumes the next positional slot and validates its committed kind/site.
function host:_consumeHook(kind, source)
    local session = assert(self._renderHook,
        "Frog." .. kind .. " may only run while a component, actor, or view renders")
    session.index = session.index + 1
    local previous = session.previous and session.previous.hooks[session.index]
    if session.previous then
        assert(previous,
            session.label .. " changed its hook count; FrogUI hooks are positional"
                .. " and unconditional")
        assert(previous.kind == kind,
            session.label .. " changed hook " .. session.index .. " from "
                .. previous.kind .. " to " .. kind)
        if not session.refreshSources and previous.source and source then
            assert(previous.source.path == source.path
                    and previous.source.line == source.line,
                session.label .. " reordered hook " .. session.index .. " from "
                    .. hookSourceLabel(previous.source) .. " to "
                    .. hookSourceLabel(source))
        end
    end
    return session, previous
end

-- Allocates a stable read-only handle for one newly mounted hook/key.
function host:_newRef(key)
    self._nextRefId = self._nextRefId + 1
    return Ref.new(self, "ref-" .. tostring(self._nextRefId), key)
end

-- Publishes render-hook ownership, process subscriptions, and arranged refs as
-- one successful Host commit. Removed resources are staged until the current
-- callback batch finishes so every committed cleanup is attempted once.
function host:_publishRenderHooks(context)
    local previousRefs = self._refs
    self:_stageResourceDisposals(self._resources, context.resources)
    self._hookOwners = context.hookOwners
    self._resources = context.resources
    self._frames = context.frames
    self._refs = context.refs
    Ref.publish(previousRefs, self._refs, context.refRectangles)
end

-- Republishes geometry after retained layout mutates the committed tree, such
-- as Scroll drag, snap, wheel, momentum, or focus reveal.
function host:_refreshCommittedRefs(context, transformRow)
    local rectangles = {}
    local profiling = self._diagnostics.enabled
    local collection = profiling and { treeVisits = 0 } or nil
    collectCommittedRefRectangles(self._tree, rectangles, collection)
    local publication = Ref.publish(self._refs, self._refs, rectangles, profiling)
    if not profiling then return end
    context = context or "interaction"
    local families = transformRow and transformRow.families or {}
    local visualChanged = transformRow and transformRow.runs > 0
        and (families.Motion or 0) > 0
    local interactionInvalidated = transformRow and transformRow.runs > 0
        and ((families.Scroll or 0) + (families.RadialDial or 0)
            + (families.interaction or 0)) > 0
    self._diagnostics:recordRefs(context, {
        calls = 1,
        treeVisits = collection.treeVisits,
        published = publication.published,
        cleared = publication.cleared,
        changedRectangles = publication.changed,
        visualTransformChanged = visualChanged and 1 or 0,
        interactionInvalidated = interactionInvalidated and 1 or 0,
    })
    self._diagnostics:increment(context .. "RefPublications")
    self._diagnostics:increment(context .. "RefTreeVisits",
        collection.treeVisits)
    self._diagnostics:increment(context .. "ChangedRefRectangles",
        publication.changed)
end

-- Implements the public positional single-ref hook.
function host.useRef()
    assert(renderingHost,
        "Frog.useRef() may only run while a component, actor, or view renders")
    local source = hookSource()
    local session, previous = renderingHost:_consumeHook("useRef", source)
    local handle = previous and previous.handle or renderingHost:_newRef(nil)
    session.hooks[session.index] = {
        kind = "useRef",
        source = source,
        handle = handle,
    }
    session.context.refs[handle] = true
    return handle
end

-- Validates and copies the dense scalar key list accepted by keyed refs.
local function keyedRefKeys(keys)
    assert(type(keys) == "table" and getmetatable(keys) == nil,
        "Frog.useKeyedRefs(keys) expects a plain dense array")
    local indexes = {}
    for index in pairs(keys) do
        assert(type(index) == "number" and index >= 1 and index % 1 == 0,
            "Frog.useKeyedRefs(keys) expects a plain dense array")
        indexes[#indexes + 1] = index
    end
    table.sort(indexes)
    local copied, seen = {}, {}
    for expected, index in ipairs(indexes) do
        assert(index == expected,
            "Frog.useKeyedRefs(keys) expects a plain dense array")
        local key = keys[index]
        local kind = type(key)
        assert(kind == "string" or kind == "number" or kind == "boolean",
            "Frog.useKeyedRefs key " .. index .. " must be a scalar")
        if kind == "number" then
            assert(finite(key),
                "Frog.useKeyedRefs key " .. index .. " must be finite")
        end
        assert(not seen[key],
            "Frog.useKeyedRefs has duplicate key " .. tostring(key))
        seen[key] = true
        copied[index] = key
    end
    return copied
end

-- Implements the public keyed-ref hook while returning an ordinary readable
-- key-to-handle table. Only handles for retained keys preserve identity.
function host.useKeyedRefs(keys)
    assert(renderingHost,
        "Frog.useKeyedRefs(keys) may only run while a component, actor, or view renders")
    local copied = keyedRefKeys(keys)
    local source = hookSource()
    local session, previous = renderingHost:_consumeHook(
        "useKeyedRefs", source)
    local previousHandles = previous and previous.handles or {}
    local handles, public = {}, {}
    for _, key in ipairs(copied) do
        local handle = previousHandles[key] or renderingHost:_newRef(key)
        handles[key] = handle
        public[key] = handle
        session.context.refs[handle] = true
    end
    session.hooks[session.index] = {
        kind = "useKeyedRefs",
        source = source,
        handles = handles,
    }
    return public
end

-- Creates one resource owned by the current semantic render lifetime. Ordinary
-- rerenders and resizes retain it; replacing the owner's render callback during
-- hot reload creates a fresh resource and disposes the old one after commit.
function host.useResource(create)
    assert(renderingHost,
        "Frog.useResource(create) may only run while a component, actor, or view renders")
    assert(type(create) == "function",
        "Frog.useResource(create) expects a create function")
    local source = hookSource()
    local session, previous = renderingHost:_consumeHook(
        "useResource", source)
    local instance = previous and not session.refreshSources
        and previous.instance or nil
    if not instance then
        local value, cleanup = create()
        assert(value ~= nil,
            "Frog.useResource(create) must return a non-nil resource")
        assert(type(cleanup) == "function",
            "Frog.useResource(create) must return resource, cleanup")
        renderingHost._nextResourceId = renderingHost._nextResourceId + 1
        instance = {
            id = "resource-" .. tostring(renderingHost._nextResourceId),
            lifetime = {},
            value = value,
            cleanup = cleanup,
            source = source,
            owner = session.label,
            disposed = false,
        }
        session.context.createdResources[
            #session.context.createdResources + 1] = instance
    end
    session.context.resources[#session.context.resources + 1] = instance
    session.hooks[session.index] = {
        kind = "useResource",
        source = source,
        instance = instance,
    }
    return instance.value
end

-- Registers one callback for every Host update. The current committed callback
-- replaces the previous closure without duplicating the subscription.
function host.useFrame(callback)
    assert(renderingHost,
        "Frog.useFrame(callback) may only run while a component, actor, or view renders")
    assert(type(callback) == "function",
        "Frog.useFrame(callback) expects a function")
    local source = hookSource()
    local session, previous = renderingHost:_consumeHook("useFrame", source)
    local id = previous and previous.id
    if not id then
        renderingHost._nextFrameId = renderingHost._nextFrameId + 1
        id = "frame-" .. tostring(renderingHost._nextFrameId)
    end
    local frame = {
        id = id,
        callback = callback,
        source = source,
        owner = session.label,
    }
    session.context.frames[#session.context.frames + 1] = frame
    session.hooks[session.index] = {
        kind = "useFrame",
        source = source,
        id = id,
        frame = frame,
    }
end

-- Attaches development-only process metadata to the visible root returned by
-- one semantic owner. Nested semantic wrappers accumulate readable entries.
local function annotateProcesses(node, ownerRecord, label, logicalPath)
    if not node or not ownerRecord then return end
    local hooks = {}
    for _, hook in ipairs(ownerRecord.hooks or {}) do
        if hook.kind == "useResource" then
            hooks[#hooks + 1] = {
                kind = hook.kind,
                id = hook.instance.id,
                mounted = not hook.instance.disposed,
            }
        elseif hook.kind == "useFrame" then
            hooks[#hooks + 1] = {
                kind = hook.kind,
                id = hook.id,
            }
        end
    end
    if #hooks == 0 then return end
    node._processOwners = node._processOwners or {}
    table.insert(node._processOwners, 1, {
        owner = label,
        logicalPath = logicalPath,
        hooks = hooks,
    })
end

function host:mount(root)
    assert(Element.isDescriptor(root), "Host:mount expects a FrogUI element/component")
    assert(not self._mounted, "Host is already mounted")
    assertOperational(self, "mount")
    assert(activeHost == nil,
        "FrogUI permits only one mounted Host")
    local feedbackMark = #self._feedbackQueue
    local motionSequence = self._motionStartSequence
    local refSequence = self._nextRefId
    local resourceSequence = self._nextResourceId
    local frameSequence = self._nextFrameId
    local ok, candidate, context = pcall(self._build, self, root)
    if not ok then
        self:_trimFeedback(feedbackMark)
        self._motionStartSequence = motionSequence
        self._nextRefId = refSequence
        self._nextResourceId = resourceSequence
        self._nextFrameId = frameSequence
        error(candidate, 0)
    end
    activeHost = self
    self._mounted = true
    self._rootDescriptor = root
    self._tree = candidate
    clearTransformWork(self)
    self._pendingTransformAttribution = nil
    self._actors = context.actors
    self._addresses = context.addresses
    self._semanticTokens = context.semanticTokens
    self._motions = context.motions
    self._effects = context.effects
    self._scrolls = context.scrolls
    self._radials = context.radials
    self._modals = context.modals
    self._modal = context.modal
    self._chrome = context.chrome
    reconcileModalFocus(self, {}, nil)
    self._generation = self._generation + 1
    self:_publishRenderHooks(context)
    self:_commitFeedback()
    return candidate
end

function host:_withRender(label, callback, ...)
    local previous = renderingHost
    renderingHost = self
    local results = { pcall(callback, ...) }
    renderingHost = previous
    if not results[1] then error(label .. " render failed: " .. tostring(results[2]), 0) end
    table.remove(results, 1)
    return unpack(results)
end

-- Reconciles one semantic render owner's positional hooks. Owners are keyed by
-- logical component/actor/view identity, independent of primitive layout.
function host:_withOwnerRender(label, token, logicalPath, context, callback, ...)
    assert(not self._renderHook,
        "FrogUI render owners may not render another owner synchronously")
    assert(not context.hookOwners[logicalPath],
        "duplicate FrogUI render-owner identity " .. logicalPath)
    local profiler = context.diagnostics
    local previous = self._hookOwners[logicalPath]
    assert(not previous or previous.token == token,
        label .. " replaced a retained hook owner with a different token")
    local session = {
        label = label,
        token = token,
        logicalPath = logicalPath,
        context = context,
        previous = previous,
        refreshSources = previous and previous.renderCallback ~= callback or false,
        hooks = {},
        index = 0,
    }
    self._renderHook = session
    local results, renderElapsed
    if profiler then
        local function observedCallback(...)
            local renderStarted = profiler:start()
            local observed = { pcall(callback, ...) }
            renderElapsed = profiler:finish("semanticRender", renderStarted)
            if not observed[1] then error(observed[2], 0) end
            table.remove(observed, 1)
            return unpack(observed)
        end
        results = {
            pcall(self._withRender, self, label, observedCallback, ...),
        }
    else
        -- Preserve the ordinary render path exactly when diagnostics are off.
        results = { pcall(self._withRender, self, label, callback, ...) }
    end
    self._renderHook = nil
    if not results[1] then error(results[2], 0) end
    if previous then
        assert(session.index == #previous.hooks,
            label .. " changed its hook count from " .. #previous.hooks
                .. " to " .. session.index .. "; FrogUI hooks are positional"
                .. " and unconditional")
    end
    context.hookOwners[logicalPath] = {
        token = token,
        renderCallback = callback,
        hooks = session.hooks,
    }
    if profiler then
        profiler:increment("semanticRenders")
        profiler:ownerRender(token.kind .. ":" .. label, renderElapsed)
    end
    table.remove(results, 1)
    return unpack(results)
end

function host:_initialState(token, props)
    local initial = token.definition.initial
    if type(initial) == "function" then
        initial = self:_withRender(token.name .. " initial", initial, props)
    end
    validateActorState(token, initial, token.name .. " initial state")
    return deepCopy(initial)
end

function host:_accepts(instance, action)
    local handler = instance.token.definition.actions[action]
    if handler == nil then return false end
    if type(handler) == "function" then return true end
    local transition = handler[instance.state]
    if transition == nil then return false end
    if Message.isTransition(transition) then
        return stateAllowed(instance.state, transition.from)
    end
    return true
end

function host:_actorSend(instance)
    local target = { identity = instance.identity, token = instance.token,
        lifetime = instance.lifetime }
    return function(record)
        return self:_enqueueAction(target, record,
            "actor:" .. actorLabel(instance))
    end
end

function host:_addressSend(address)
    return function(record)
        return self:_enqueueAction(address, record, "view:" .. address.name)
    end
end

function host:_registerActor(descriptor, owner, path, descendantPath, context,
        logicalPath)
    local profiler = context.diagnostics
    local bookkeepingStarted = profiler and profiler:start() or nil
    assert((context.previewDepth or 0) == 0,
        "DragSource preview must be stateless presentation")
    local token = descriptor.token
    assert(not context.actors[logicalPath],
        "duplicate mounted actor identity " .. logicalPath)
    if profiler then
        profiler:finish("semanticBookkeeping", bookkeepingStarted)
    end
    local preparationStarted = profiler and profiler:start() or nil
    local props = shallowCopy(descriptor.props)
    props.children = descriptor.children
    local old = self._actors[logicalPath]
    local retainedState
    if old and old.token == token then
        retainedState = old.state
    else
        retainedState = self:_initialState(token, props)
    end
    if profiler then
        profiler:finish("semanticPreparation", preparationStarted)
    end
    bookkeepingStarted = profiler and profiler:start() or nil
    local instance = {
        token = token,
        identity = logicalPath,
        props = props,
        state = retainedState,
        order = context.nextOrder,
        source = token.source or descriptor.source,
        mountSource = descriptor.source,
        -- Reconciliations replace candidate instance tables, but a callback
        -- retained by drag/animation still belongs to this exact mount.
        lifetime = old and old.token == token and old.lifetime or {},
    }
    context.nextOrder = context.nextOrder + 1
    local address = props.address
    if address ~= nil then
        assert(Message.isAddress(address), token.name .. " address prop must come from Actor:address")
        assert(address.actor == token,
            token.name .. " cannot mount an address owned by " .. address.actor.name)
        assert(not context.addresses[address], "duplicate mounted actor address " .. address.name)
        assert(not context.addressNames[address.name],
            "duplicate mounted actor address name " .. address.name)
        instance.address = address
        context.addresses[address] = instance
        context.addressNames[address.name] = instance
    end
    local reactions = token.definition.reactions or {}
    for index, reaction in ipairs(reactions) do
        assert(Message.isReaction(reaction),
            token.name .. " reaction " .. index .. " must come from Frog.on")
        assert(reaction.do_ == nil,
            token.name .. " actor reaction " .. index
                .. " cannot use do_; Frog.play belongs to element reactions")
    end
    instance.reactions = reactions
    context.actors[logicalPath] = instance
    if profiler then
        profiler:finish("semanticBookkeeping", bookkeepingStarted)
    end

    -- Render receives one detached state snapshot. Mutating it is ignored;
    -- semantic state changes belong to an action/reaction return value.
    preparationStarted = profiler and profiler:start() or nil
    local stateForRender = deepCopy(instance.state)
    local actorSend = self:_actorSend(instance)
    if profiler then
        profiler:finish("semanticPreparation", preparationStarted)
    end
    local rendered = self:_withOwnerRender(token.name, token, logicalPath,
        context, token.definition.render, props, stateForRender,
        actorSend)
    bookkeepingStarted = profiler and profiler:start() or nil
    if rendered == nil or rendered == false then
        if profiler then
            profiler:finish("semanticBookkeeping", bookkeepingStarted)
        end
        return nil
    end
    assert(Element.isDescriptor(rendered), token.name .. " must return one FrogUI element or nil")
    local outputPath = childPath(path .. "/output", rendered, 1)
    if profiler then
        profiler:finish("semanticBookkeeping", bookkeepingStarted)
    end
    local resolved = self:_resolve(rendered, token.name, outputPath, path, context,
        logicalOutputPath(logicalPath, rendered))
    if resolved then
        bookkeepingStarted = profiler and profiler:start() or nil
        annotateProcesses(resolved, context.hookOwners[logicalPath],
            token.name, logicalPath)
        resolved._actorInstances = resolved._actorInstances or {}
        table.insert(resolved._actorInstances, 1, instance)
        if descriptor.key ~= nil then resolved.key = descriptor.key end
        if profiler then
            profiler:finish("semanticBookkeeping", bookkeepingStarted)
        end
        preparationStarted = profiler and profiler:start() or nil
        local inspectedState = deepCopy(instance.state)
        if profiler then
            profiler:finish("semanticPreparation", preparationStarted)
        end
        bookkeepingStarted = profiler and profiler:start() or nil
        resolved.actor = {
            name = token.name,
            state = inspectedState,
            address = address and address.name or nil,
            reactions = #reactions,
        }
        if profiler then
            profiler:finish("semanticBookkeeping", bookkeepingStarted)
        end
    end
    return resolved
end

function host:_resolveView(descriptor, owner, path, descendantPath, context,
        logicalPath)
    local profiler = context.diagnostics
    local bookkeepingStarted = profiler and profiler:start() or nil
    assert((context.previewDepth or 0) == 0,
        "DragSource preview cannot mount an actor view")
    local token = descriptor.token
    if profiler then
        profiler:finish("semanticBookkeeping", bookkeepingStarted)
    end
    local preparationStarted = profiler and profiler:start() or nil
    local props = shallowCopy(descriptor.props)
    props.children = descriptor.children
    if profiler then
        profiler:finish("semanticPreparation", preparationStarted)
    end
    bookkeepingStarted = profiler and profiler:start() or nil
    local address = props.target
    assert(Message.isAddress(address), token.name .. " target prop must come from Actor:address")
    assert(address.actor == token.actor,
        token.name .. " target belongs to " .. address.actor.name
            .. ", expected " .. token.actor.name)
    local instance = context.addresses[address]
    local status = { mounted = instance ~= nil }
    function status:accepts(action)
        assert(type(action) == "table" and action.__frogMessageToken
                and action.messageKind == "action",
            "status:accepts expects a Frog.action token")
        if not instance then return false end
        return instance.token == token.actor and self._host:_accepts(instance, action)
    end
    status._host = self
    if profiler then
        profiler:finish("semanticBookkeeping", bookkeepingStarted)
    end
    -- Views observe the same detached render snapshot as their actor owner.
    preparationStarted = profiler and profiler:start() or nil
    local stateForRender = instance and deepCopy(instance.state) or nil
    local addressSend = self:_addressSend(address)
    if profiler then
        profiler:finish("semanticPreparation", preparationStarted)
    end
    local rendered = self:_withOwnerRender(token.name, token, logicalPath,
        context, token.render, props, stateForRender,
        addressSend, status)
    bookkeepingStarted = profiler and profiler:start() or nil
    if rendered == nil or rendered == false then
        if profiler then
            profiler:finish("semanticBookkeeping", bookkeepingStarted)
        end
        return nil
    end
    assert(Element.isDescriptor(rendered), token.name .. " must return one FrogUI element or nil")
    local outputPath = childPath(path .. "/output", rendered, 1)
    if profiler then
        profiler:finish("semanticBookkeeping", bookkeepingStarted)
    end
    local resolved = self:_resolve(rendered, token.name, outputPath,
        descendantPath or path, context, logicalOutputPath(logicalPath, rendered))
    if resolved then
        bookkeepingStarted = profiler and profiler:start() or nil
        annotateProcesses(resolved, context.hookOwners[logicalPath],
            token.name, logicalPath)
        if descriptor.key ~= nil then resolved.key = descriptor.key end
        resolved.view = {
            name = token.name,
            target = address.name,
            mounted = instance ~= nil,
        }
        if profiler then
            profiler:finish("semanticBookkeeping", bookkeepingStarted)
        end
    end
    return resolved
end

function host:_resolve(descriptor, owner, path, descendantPath, context,
        logicalPath)
    local token = descriptor.token
    local profiler = context.diagnostics
    if profiler then
        context.descriptorTotal = context.descriptorTotal + 1
        context.identityBytes = context.identityBytes + #path
        context.logicalIdentityBytes = context.logicalIdentityBytes + #logicalPath
        if descriptor.source then
            context.sourceCapturedDescriptors =
                context.sourceCapturedDescriptors + 1
        end
    end
    local semanticStarted = token.kind ~= "primitive" and profiler
        and profiler:start() or nil
    if token.kind ~= "primitive" then
        assert(descriptor.props.ref == nil,
            token.name .. " is a semantic " .. token.kind
                .. "; ref attaches only to an exact FrogUI primitive"
                .. " (forward a named anchor prop explicitly)")
    end
    if token.kind == "component" or token.kind == "actor" or token.kind == "view" then
        local semanticName = token.kind .. ":" .. token.name
        local candidate = context.semanticTokens[semanticName]
        assert(candidate == nil or candidate == token,
            "FrogUI semantic token name collision for " .. semanticName
                .. "; distinct tokens must have distinct Host-scoped names")
        local committed = self._semanticTokens[semanticName]
        assert(committed == nil or committed == token,
            "FrogUI semantic token name collision for " .. semanticName
                .. " against the committed tree")
        context.semanticTokens[semanticName] = token
    end
    if semanticStarted then
        profiler:finish("semanticBookkeeping", semanticStarted)
    end
    if token.kind == "component" then
        local preparationStarted = profiler and profiler:start() or nil
        local props = shallowCopy(descriptor.props)
        props.children = descriptor.children
        if profiler then
            profiler:finish("semanticPreparation", preparationStarted)
        end
        local rendered = self:_withOwnerRender(token.name, token, logicalPath,
            context, token.render, props)
        local bookkeepingStarted = profiler and profiler:start() or nil
        if rendered == nil or rendered == false then
            if profiler then
                profiler:finish("semanticBookkeeping", bookkeepingStarted)
            end
            return nil
        end
        assert(Element.isDescriptor(rendered),
            token.name .. " must return one FrogUI element or nil")
        local outputPath = childPath(path .. "/output", rendered, 1)
        if profiler then
            profiler:finish("semanticBookkeeping", bookkeepingStarted)
        end
        local resolved = self:_resolve(rendered, token.name, outputPath, path,
            context, logicalOutputPath(logicalPath, rendered))
        bookkeepingStarted = profiler and profiler:start() or nil
        if resolved then
            annotateProcesses(resolved, context.hookOwners[logicalPath],
                token.name, logicalPath)
            if descriptor.key ~= nil then resolved.key = descriptor.key end
        end
        if profiler then
            profiler:finish("semanticBookkeeping", bookkeepingStarted)
        end
        return resolved
    elseif token.kind == "actor" then
        return self:_registerActor(descriptor, owner, path, descendantPath,
            context, logicalPath)
    elseif token.kind == "view" then
        if not context.addresses[descriptor.props.target] then
            return {
                __frogDeferredView = true,
                descriptor = descriptor,
                owner = owner,
                path = path,
                descendantPath = descendantPath,
                logicalPath = logicalPath,
            }
        end
        return self:_resolveView(descriptor, owner, path, descendantPath,
            context, logicalPath)
    end

    local primitiveStarted = profiler and profiler:start() or nil
    validatePrimitive(token.name, descriptor.children)
    validatePrimitiveProps(self, token.name, descriptor.props)
    if (context.previewDepth or 0) > 0 then
        assert(descriptor.props.ref == nil,
            "DragSource preview cannot attach committed refs")
        assert(token.name ~= "Pressable" and token.name ~= "HorizontalSwipe"
                and token.name ~= "RadialDial"
                and token.name ~= "Scroll"
                and token.name ~= "Modal" and token.name ~= "Chrome"
                and token.name ~= "DragSource"
                and token.name ~= "DropTarget" and token.name ~= "Button",
            "DragSource preview must be static presentation")
        assert(token.name ~= "Motion" and descriptor.props.juice == nil
                and descriptor.props.reactions == nil,
            "DragSource preview cannot own Motion or event reactions")
    end
    if profiler then
        profiler:finish("primitiveValidation", primitiveStarted)
    end
    local materializationStarted = profiler and profiler:start() or nil
    local node = {
        type = token.name,
        key = descriptor.key,
        identity = path,
        logicalIdentity = logicalPath,
        owner = owner or token.name,
        source = descriptor.source,
        props = shallowCopy(descriptor.props),
        children = {},
    }
    if profiler then
        context.primitiveTotal = context.primitiveTotal + 1
        context.primitiveHistogram[token.name] =
            (context.primitiveHistogram[token.name] or 0) + 1
    end
    local attachedRef = descriptor.props.ref
    if attachedRef then
        assert(context.refs[attachedRef],
            token.name .. " ref is not live in the current render tree")
        assert(not context.refAttachments[attachedRef],
            "FrogUI ref " .. Ref.inspect(attachedRef).id
                .. " is attached to more than one primitive")
        context.refAttachments[attachedRef] = node
        node._ref = attachedRef
    end
    if profiler then
        profiler:finish("primitiveMaterialization", materializationStarted)
    end
    if token.name == "Scroll" then
        local started = profiler and profiler:start() or nil
        local instance = Interaction.reconcileScroll(
            self._scrolls[logicalPath], node, node.props, logicalPath)
        context.scrolls[logicalPath] = instance
        if profiler then
            profiler:increment("scrollReconciliations")
            profiler:finish("scrollReconciliation", started)
        end
    end
    if token.name == "RadialDial" then
        local started = profiler and profiler:start() or nil
        local instance = Interaction.reconcileRadialDial(
            self._radials[logicalPath], node, node.props, logicalPath,
            self.reducedMotion)
        context.radials[logicalPath] = instance
        if profiler then
            profiler:increment("radialReconciliations")
            profiler:finish("radialReconciliation", started)
        end
    end
    if token.name == "Motion" or descriptor.props.juice
            or descriptor.props.reactions then
        local started = profiler and profiler:start() or nil
        local instance = Motion.reconcile(self._motions[logicalPath], node,
            node.props, logicalPath, context.nextReceiverOrder, self)
        context.nextReceiverOrder = context.nextReceiverOrder + 1
        context.motions[logicalPath] = instance
        if profiler then
            profiler:increment("motionReconciliations")
            profiler:finish("motionReconciliation", started)
        end
    end
    if token.name == "Projectile" or token.name == "Flipbook" then
        local started = profiler and profiler:start() or nil
        local instance = Effect.reconcile(self._effects[logicalPath], node,
            logicalPath, context.nextEffectOrder, self)
        context.nextEffectOrder = context.nextEffectOrder + 1
        context.effects[logicalPath] = instance
        if profiler then
            profiler:increment("effectReconciliations")
            profiler:finish("effectReconciliation", started)
        end
    end
    local childrenPath = descendantPath or path
    for index, child in ipairs(descriptor.children) do
        local resolved = self:_resolve(child, owner,
            childPath(childrenPath, child, index), nil, context,
            logicalChildPath(logicalPath, child, index))
        if resolved then node.children[#node.children + 1] = resolved end
    end
    local validationStarted = profiler and profiler:start() or nil
    if token.name == "EffectLayer" then
        for _, child in ipairs(node.children) do
            assert(child.type == "PopupText" or child.type == "Projectile"
                    or child.type == "Flipbook" or child.type == "Canvas",
                "Frog.EffectLayer accepts only PopupText, Projectile,"
                    .. " Flipbook, or bounded Canvas children")
        end
    end
    if token.name == "ShaderImage" then
        local child = node.children[1]
        assert(child.type == "Image" or child.type == "TiledImage"
                or child.type == "Box" and #child.children == 0,
            "Frog.ShaderImage child must resolve to Image, TiledImage,"
                .. " or an empty Box")
    end
    if token.name == "RadialDial" then
        local interactive = {
            Button = true, Pressable = true, HorizontalSwipe = true,
            RadialDial = true, Scroll = true, Modal = true, Chrome = true,
            DragSource = true, DropTarget = true,
        }
        local function checkStatic(child)
            assert(not interactive[child.type] and child._ref == nil
                    and child.type ~= "Motion"
                    and child.type ~= "EffectLayer"
                    and child.type ~= "PopupText"
                    and child.type ~= "Projectile"
                    and child.type ~= "Flipbook"
                    and child._motion == nil,
                "Frog.RadialDial child must be static presentation")
            for _, nested in ipairs(child.children or {}) do checkStatic(nested) end
        end
        assert(#node.children == #node._radialDial.values,
            "Frog.RadialDial needs exactly one child per value")
        local keys = {}
        for index, child in ipairs(node.children) do
            assert(child.key ~= nil,
                "Frog.RadialDial child " .. index .. " needs a stable key")
            assert(not keys[child.key],
                "Frog.RadialDial children need unique stable keys")
            assert(child.props.offset == nil,
                "Frog.RadialDial option children do not accept offset")
            keys[child.key] = true
            checkStatic(child)
        end
    end
    if profiler then
        profiler:finish("primitivePostValidation", validationStarted)
    end
    if token.name == "DragSource" then
        context.previewDepth = (context.previewDepth or 0) + 1
        local preview = descriptor.props.preview
        node._dragPreview = self:_resolve(preview, owner,
            childPath(path .. "/preview", preview, 1), nil, context,
            logicalChildPath(logicalPath .. "/preview", preview, 1))
        context.previewDepth = context.previewDepth - 1
        assert(node._dragPreview, "DragSource preview returned nil")
    end
    return node
end

function host:_resolveDeferred(node, context)
    local profiler = context.diagnostics
    local started = profiler and profiler:start() or nil
    if not node then
        if profiler then profiler:finish("deferredResolution", started) end
        return nil
    end
    if node.__frogDeferredView then
        if profiler then profiler:finish("deferredResolution", started) end
        return self:_resolveView(node.descriptor, node.owner, node.path,
            node.descendantPath, context, node.logicalPath)
    end
    local children = {}
    if profiler then profiler:finish("deferredResolution", started) end
    for _, child in ipairs(node.children or {}) do
        local resolved = self:_resolveDeferred(child, context)
        started = profiler and profiler:start() or nil
        if resolved then children[#children + 1] = resolved end
        if profiler then profiler:finish("deferredResolution", started) end
    end
    started = profiler and profiler:start() or nil
    node.children = children
    if profiler then profiler:finish("deferredResolution", started) end
    return node
end

-- Rejects detached effect leaves so every point has one coordinate owner.
-- EffectLayer child validation already prevents interactive descendants.
local function validateEffectOwnership(node, insideLayer)
    if node.type == "PopupText" or node.type == "Projectile"
            or node.type == "Flipbook" then
        assert(insideLayer,
            "Frog." .. node.type .. " must be a direct Frog.EffectLayer child")
    elseif node.type == "EffectLayer" then
        assert(not insideLayer, "Frog.EffectLayer cannot be nested")
        insideLayer = true
    end
    for _, child in ipairs(node.children or {}) do
        validateEffectOwnership(child, insideLayer)
    end
end

-- Marks the few branches that need Canvas preflight so ordinary trees do not
-- allocate paint styles merely to discover that no draw callback exists.
local function annotateCanvasBranches(node)
    local contains = node.type == "Canvas"
    for _, child in ipairs(node.children or {}) do
        contains = annotateCanvasBranches(child) or contains
    end
    if node._dragPreview then
        contains = annotateCanvasBranches(node._dragPreview) or contains
    end
    node._containsCanvas = contains
    return contains
end

local function assignEventOrder(node, nextOrder)
    for _, instance in ipairs(node._actorInstances or {}) do
        instance.eventOrder = nextOrder
        nextOrder = nextOrder + 1
    end
    if node._motion then
        node._motion.eventOrder = nextOrder
        nextOrder = nextOrder + 1
    end
    for _, child in ipairs(node.children or {}) do
        nextOrder = assignEventOrder(child, nextOrder)
    end
    return nextOrder
end

local TRANSFORM_FAMILIES = {
    Motion = true,
    Scroll = true,
    RadialDial = true,
    interaction = true,
}

local TRANSFORM_TARGET_LIMIT = 256

local TRANSFORM_DETAILS = {
    Motion = { ["event-play"] = true, ["frame-sample"] = true },
    Scroll = {
        drag = true, snap = true, momentum = true, wheel = true, focus = true,
    },
    RadialDial = {
        drag = true, settle = true, ["controlled-refresh"] = true,
    },
    interaction = { other = true },
}

local TRANSFORM_CONTEXTS = {
    candidateTransform = "candidate",
    messageTransform = "message",
    committedTransform = "committed",
    interactionTransform = "interaction",
}

-- Keeps semantic diagnostic labels readable and bounded. Logical identities,
-- source paths, binding keys, and message payloads never enter this channel.
local function transformLabel(value)
    value = tostring(value or "unknown")
    value = value:gsub("[^%w_:%.$%-]", "?")
    if #value > 64 then value = value:sub(1, 61) .. "..." end
    return value
end

local function incrementMap(map, name, amount)
    map[name] = (map[name] or 0) + (amount or 1)
end

-- Marks committed geometry stale and records one bounded single-use routing
-- batch on every Host. Only Motion retains exact instances in ordinary runtime;
-- diagnostic category maps remain opt-in observations.
function host:_invalidateTransform(node, family, detail, recipes)
    if not TRANSFORM_FAMILIES[family] then
        error("unknown FrogUI transform invalidation family "
            .. tostring(family), 0)
    end
    if not TRANSFORM_DETAILS[family][detail] then
        error("unknown FrogUI " .. family .. " transform detail "
            .. tostring(detail), 0)
    end
    assert(node, "FrogUI transform invalidation requires its changed node")
    local motionInstance
    if family == "Motion" then
        motionInstance = node._motion
        assert(motionInstance and motionInstance.node == node,
            "FrogUI Motion invalidation requires its mounted Motion owner")
    end
    Motion.invalidate(self._tree)
    local work = self._transformWork
    if not work.active then
        work.active = true
        work.generation = self._generation
        work.treeToken = self._tree and self._tree._motionTreeToken or nil
        work.requiresFull = false
        work.fullReason = nil
        clearTransformTargets(work)
    elseif work.generation ~= self._generation
            or work.treeToken
                ~= (self._tree and self._tree._motionTreeToken or nil) then
        work.requiresFull = true
        work.fullReason = "structural-token"
        clearTransformTargets(work)
    end
    if family == "Motion" then
        if not work.requiresFull and not work.nodes[motionInstance] then
            if work.nodeCount >= TRANSFORM_TARGET_LIMIT then
                work.requiresFull = true
                work.fullReason = "target-limit"
                clearTransformTargets(work)
            else
                work.nodes[motionInstance] = true
                work.nodeCount = work.nodeCount + 1
            end
        end
    else
        work.requiresFull = true
        work.fullReason = "non-motion-or-mixed"
        clearTransformTargets(work)
    end
    if not self._diagnostics.enabled then return end
    local batch = self._pendingTransformAttribution
    if not batch then
        batch = {
            invalidations = 0,
            nodes = {},
            changingOwners = {},
            families = {},
            details = {},
            owners = {},
            recipes = {},
        }
        self._pendingTransformAttribution = batch
    end
    batch.invalidations = batch.invalidations + 1
    batch.nodes[node] = true
    incrementMap(batch.families, family)
    incrementMap(batch.details, family .. ":" .. detail)
    if family == "Motion" then
        batch.changingOwners[node] = true
        local owner = transformLabel(node.owner or node.type)
        incrementMap(batch.owners, owner)
        for _, recipe in ipairs(recipes or {}) do
            if recipe then
                local name = transformLabel(recipe.name)
                local kind = transformLabel(recipe.kind)
                local geometry = transformLabel(recipe.geometry)
                incrementMap(batch.recipes,
                    name .. "|" .. kind .. "|" .. geometry)
            end
        end
    end
end

local function mapCount(values)
    local count = 0
    for _ in pairs(values or {}) do count = count + 1 end
    return count
end

-- Applies transformed geometry and consumes one exact committed cause batch.
-- Only the committed Motion-only context offers the branch plan; every other
-- context remains a full authoritative transform.
function host:_transformTree(root, phase, activeMotion)
    root = root or self._tree
    local context = phase and TRANSFORM_CONTEXTS[phase] or nil
    if phase and not context then
        error("unknown FrogUI transform phase " .. tostring(phase), 0)
    end
    local committed = root == self._tree
    local work = committed and self._transformWork or nil
    local activeWork = work and work.active and work or nil
    local options = self._transformOptions
    options.generation = committed and self._generation
        or self._generation + 1
    options.branch = context == "committed" and activeWork or nil
    local profiling = self._diagnostics.enabled and phase ~= nil
    local batch = profiling and committed
        and self._pendingTransformAttribution or nil
    local targets
    if profiling then
        targets = context == "candidate" and { [root] = true }
            or batch and batch.nodes or {}
    end
    local started = profiling and self._diagnostics:start() or nil
    local ran, stats = Motion.transformTree(root, targets, options)
    options.branch = nil
    if profiling then self._diagnostics:finish(phase, started) end
    if committed and activeWork and not ran then
        error("FrogUI dirty transform batch was not consumed", 0)
    end
    if not profiling then
        if committed and ran then clearTransformWork(self) end
        return ran, nil
    end
    local invalidations = batch and batch.invalidations or 0
    local row = {
        calls = 1,
        runs = ran and 1 or 0,
        skips = ran and 0 or 1,
        nodesVisited = stats.nodesVisited or 0,
        invalidations = invalidations,
        coalescedInvalidations = ran and math.max(0, invalidations - 1) or 0,
        changingOwners = batch and mapCount(batch.changingOwners) or 0,
        dirtyRoots = stats.dirtyRoots or 0,
        lcaCoverage = stats.lcaCoverage or 0,
        branchCoverage = stats.branchCoverage or 0,
        branchRuns = stats.branchRuns or 0,
        fullRuns = stats.fullRuns or 0,
        fallbackRuns = stats.fallbackRuns or 0,
        branchNodes = stats.branchNodes or 0,
        fullNodes = stats.fullNodes or 0,
        pendingTargets = stats.pendingTargets or 0,
        survivingRoots = stats.survivingRoots or 0,
        descendantsSuppressed = stats.descendantsSuppressed or 0,
        routingTreeVisits = stats.routingTreeVisits or 0,
        lcaMeasured = stats.lcaMeasured or 0,
        activeGeometryMotions = activeMotion
            and activeMotion.activeGeometryMotions or 0,
        families = batch and batch.families or {},
        owners = batch and batch.owners or {},
        recipes = batch and batch.recipes or {},
        fallbackReasons = stats.fallbackReason
            and { [stats.fallbackReason] = 1 } or {},
        details = context == "candidate" and { ["candidate-layout"] = 1 }
            or batch and batch.details or {},
    }
    if ran then
        assert(row.nodesVisited > 0,
            "FrogUI transform run visited no nodes")
        if context ~= "candidate" then
            assert(invalidations > 0 and next(row.families) ~= nil,
                "FrogUI " .. context .. " transform ran without a cause")
            assert(row.dirtyRoots > 0,
                "FrogUI transform cause did not belong to the committed tree")
        end
        assert(row.branchRuns + row.fullRuns == 1,
            "FrogUI transform run did not choose exactly one route")
        if row.lcaMeasured == 1 then
            assert(row.branchCoverage <= row.lcaCoverage
                    and row.lcaCoverage <= row.nodesVisited,
                "FrogUI transform locality coverage is inconsistent")
        else
            assert(row.branchRuns == 1 and row.lcaCoverage == 0
                    and row.branchCoverage == row.nodesVisited,
                "FrogUI branch transform reported synthetic LCA coverage")
        end
        if committed then
            clearTransformWork(self)
            self._pendingTransformAttribution = nil
        end
    else
        assert(row.nodesVisited == 0,
            "FrogUI skipped transform performed recursive work")
        assert(invalidations == 0,
            "FrogUI skipped transform retained an unconsumed cause")
    end
    self._diagnostics:recordTransform(context, row)
    self._diagnostics:increment(context .. "TransformCalls")
    self._diagnostics:increment(context
        .. (ran and "TransformRuns" or "TransformSkips"))
    return ran, row
end

-- Publishes structural pressure only while the development profiler is active.
-- This extra walk never runs in an ordinary production Host.
local function publishDiagnosticStructure(self, root, context)
    if not self._diagnostics.enabled then return end
    local nodes = 0
    local function visit(node)
        nodes = nodes + 1
        if node._dragPreview then visit(node._dragPreview) end
        for _, child in ipairs(node.children or {}) do visit(child) end
    end
    visit(root)
    local function count(entries)
        local total = 0
        for _ in pairs(entries or {}) do total = total + 1 end
        return total
    end
    self._diagnostics:setCount("nodes", nodes)
    self._diagnostics:setCount("renderOwners", count(context.hookOwners))
    self._diagnostics:setCount("actors", count(context.actors))
    self._diagnostics:setCount("motions", count(context.motions))
    self._diagnostics:setCount("effects", count(context.effects))
    self._diagnostics:setCount("refs", count(context.refs))
    self._diagnostics:setCount("descriptors", context.descriptorTotal)
    self._diagnostics:setCount("primitives", context.primitiveTotal)
    self._diagnostics:setCount("identityBytes", context.identityBytes)
    self._diagnostics:setCount("logicalIdentityBytes",
        context.logicalIdentityBytes)
    -- Descriptor source capture happens in Element construction, before Host
    -- can time it without adding global instrumentation. This retained count
    -- is a pressure proxy, not a duration measurement.
    self._diagnostics:setCount("sourceCapturedDescriptors",
        context.sourceCapturedDescriptors)
    self._diagnostics:setCount("popupTexts",
        context.primitiveHistogram.PopupText or 0)
    self._diagnostics:setCount("canvases",
        context.primitiveHistogram.Canvas or 0)
    local previousPrimitiveNames = self._diagnosticPrimitiveNames or {}
    for name in pairs(previousPrimitiveNames) do
        if context.primitiveHistogram[name] == nil then
            self._diagnostics:setCount("primitive." .. name, 0)
        end
    end
    local primitiveNames = {}
    for name, total in pairs(context.primitiveHistogram) do
        self._diagnostics:setCount("primitive." .. name, total)
        primitiveNames[name] = true
    end
    self._diagnosticPrimitiveNames = primitiveNames
end

function host:_build(root)
    local feedbackMark = #self._feedbackQueue
    local context = {
        actors = {},
        addresses = {},
        addressNames = {},
        semanticTokens = {},
        hookOwners = {},
        resources = {},
        createdResources = {},
        frames = {},
        refs = {},
        refAttachments = {},
        refRectangles = {},
        nextOrder = 1,
        motions = {},
        effects = {},
        scrolls = {},
        radials = {},
        previewDepth = 0,
        nextReceiverOrder = 1,
        nextEffectOrder = 1,
    }
    if self._diagnostics.enabled then
        context.diagnostics = self._diagnostics
        context.descriptorTotal = 0
        context.primitiveTotal = 0
        context.primitiveHistogram = {}
        context.identityBytes = 0
        context.logicalIdentityBytes = 0
        context.sourceCapturedDescriptors = 0
    end
    local function buildCandidate()
        local expansionStarted = self._diagnostics:start()
        local rootPath = childPath("root", root, 1)
        local rootLogicalPath = logicalChildPath("logical-root", root, 1)
        local candidate = self:_resolve(root, nil, rootPath, nil, context,
            rootLogicalPath)
        candidate = self:_resolveDeferred(candidate, context)
        assert(candidate, "Host root component returned nil")
        local ownershipStarted = self._diagnostics:start()
        validateEffectOwnership(candidate, false)
        self._diagnostics:finish("effectOwnership", ownershipStarted)
        local orderingStarted = self._diagnostics:start()
        local nextEventOrder = assignEventOrder(candidate, 1)
        local hiddenActors = {}
        for _, instance in pairs(context.actors) do
            hiddenActors[#hiddenActors + 1] = instance
        end
        table.sort(hiddenActors,
            function(left, right) return left.order < right.order end)
        for _, instance in ipairs(hiddenActors) do
            if not instance.eventOrder then
                instance.eventOrder = nextEventOrder
                nextEventOrder = nextEventOrder + 1
            end
        end
        if context.diagnostics then
            context.diagnostics:increment("postResolutionPasses")
            context.diagnostics:finish("eventOrdering", orderingStarted)
        end
        self._diagnostics:finish("componentExpansion", expansionStarted)
        local layoutStarted = self._diagnostics:start()
        candidate = Layout.run(candidate,
            self._viewport.width, self._viewport.height, self)
        self._diagnostics:finish("layout", layoutStarted)
        annotateCanvasBranches(candidate)
        for handle, node in pairs(context.refAttachments) do
            context.refRectangles[handle] = {
                x = node.x,
                y = node.y,
                width = node.width,
                height = node.height,
            }
        end
        Effect.arrangeAll(context.effects, context.refRectangles, self)
        self:_transformTree(candidate, "candidateTransform")
        Effect.updateBounds(context.effects, self)
        context.modals, context.chrome = Interaction.planesFromTree(candidate)
        context.modal = context.modals[#context.modals]
        if self._diagnostics.enabled then
            local observerStarted = self._diagnostics:start()
            publishDiagnosticStructure(self, candidate, context)
            self._diagnostics:finish("diagnosticObserver", observerStarted)
        end
        return candidate
    end
    local ok, candidate = pcall(buildCandidate)
    if not ok then
        self:_trimFeedback(feedbackMark)
        local cleanupError = self:_disposeResources(
            context.createdResources, "Candidate resource rollback")
        if cleanupError then
            faultHost(self, "Candidate resource rollback", cleanupError)
        end
        error(appendFailure(candidate,
            "candidate resource rollback failed", cleanupError), 0)
    end
    return candidate, context
end

function host:render(root)
    assert(self._mounted and activeHost == self, "Host is not mounted")
    assertOperational(self, "render")
    assertPresentationAllowed(self, "render")
    assertFramePublication(self, "render")
    self._diagnostics:ensureFrame()
    local externalStarted = not self._diagnosticUpdateActive
            and self._callbackDepth == 0
            and (self._diagnosticExternalDepth or 0) == 0
        and self._diagnostics:start() or nil
    if externalStarted then
        self._diagnostics:increment("externalRenderOperations")
        self._diagnostics:cause("render")
    end
    local reconcileStarted = self._diagnostics:start()
    self._diagnostics:increment("reconciles")
    local requested = root or self._rootDescriptor
    assert(Element.isDescriptor(requested), "Host:render expects a FrogUI element/component")
    local ok, candidate, context = pcall(self._build, self, requested)
    if not ok then
        self._diagnostics:finish("reconcile", reconcileStarted)
        self._diagnostics:finish("external", externalStarted)
        error(candidate, 0)
    end
    local previous = {
        actors = self._actors,
        modals = self._modals or {},
        modalIdentity = self._modal and self._modal.identity or nil,
        tree = self._tree,
        modal = self._modal,
        chrome = self._chrome,
        focusedIdentity = self._focusedIdentity,
        hoveredIdentity = self._hoveredIdentity,
    }
    local published = false
    local function commit()
        self._rootDescriptor = requested
        self._tree = candidate
        clearTransformWork(self)
        self._pendingTransformAttribution = nil
        self._actors = context.actors
        self._addresses = context.addresses
        self._semanticTokens = context.semanticTokens
        self._motions = context.motions
        self._effects = context.effects
        self._scrolls = context.scrolls
        self._radials = context.radials
        self._modals = context.modals
        self._modal = context.modal
        self._chrome = context.chrome
        self._generation = self._generation + 1
        for identity in pairs(self._spentAuthorities) do
            if not findIdentity(self._tree, identity) then
                self._spentAuthorities[identity] = nil
            end
        end
        reconcileModalFocus(self, previous.modals, previous.focusedIdentity)
        if self._selectedIdentity
                and not Interaction.findActiveIdentity(self,
                    self._selectedIdentity) then
            self._selectedIdentity = nil
        end
        self:_publishRenderHooks(context)
        published = true
        self:_stageActorUnmounts(previous.actors, context.actors)
        Interaction.afterCommit(self, previous)
    end
    local committed, commitError
    local commitStarted = self._diagnostics:start()
    if self._callbackDepth == 0 then
        committed, commitError = pcall(self._runCallback, self, commit,
            "Host:render")
    else
        committed, commitError = pcall(commit)
    end
    self._diagnostics:finish("commit", commitStarted)
    if not committed then
        local cleanupError
        if not published then
            cleanupError = self:_disposeResources(
                context.createdResources, "Unpublished candidate cleanup")
        end
        faultHost(self, "Host:render commit", commitError)
        self._diagnostics:finish("reconcile", reconcileStarted)
        self._diagnostics:finish("external", externalStarted)
        error(appendFailure(commitError,
            "unpublished candidate cleanup failed", cleanupError), 0)
    end
    self._diagnostics:finish("reconcile", reconcileStarted)
    self._diagnostics:finish("external", externalStarted)
    return candidate
end

-- Measures one complete public Host operation that happens outside update and
-- draw. Nested callbacks and rebuilds remain attributed to their own phases,
-- while this outer boundary captures routing work such as hit testing.
local function runExternal(self, kind, operation, ...)
    assert(type(kind) == "string" and kind ~= "",
        "external diagnostic operation needs a kind")
    if not self._diagnostics.enabled then
        return operation(self, ...)
    end
    self._diagnostics:ensureFrame()
    local depth = self._diagnosticExternalDepth or 0
    local outer = not self._diagnosticUpdateActive and depth == 0
    local started = outer
        and self._diagnostics:start() or nil
    if outer then
        self._diagnostics:increment("external" .. kind .. "Operations")
        if kind == "ThemeRefresh" then
            self._diagnostics:cause("theme-refresh")
        end
    end
    self._diagnosticExternalDepth = depth + 1
    local results = { pcall(operation, self, ...) }
    self._diagnosticExternalDepth = depth
    self._diagnostics:finish("external", started)
    if not results[1] then error(results[2], 0) end
    table.remove(results, 1)
    return unpack(results)
end

-- Dev presentation reload keeps mounted actors/processes, but drops font and
-- asset caches before rebuilding the committed tree. Component modules
-- reload separately by preserving their token-table identity.
function host:_refreshTheme(theme, assets, root)
    assert(self._mounted and activeHost == self, "Host is not mounted")
    assertOperational(self, "refresh theme")
    assertPresentationAllowed(self, "refresh")
    assertFramePublication(self, "theme refresh")
    assert(type(theme) == "table", "Host:refreshTheme needs a theme table")
    assert(type(assets) == "table", "Host:refreshTheme needs an asset table")
    validateTheme(theme)
    local previousTheme, previousAssets = self.theme, self.assets
    local previousGeneration = self._generation
    local previousFonts, previousAssetCache = self._fontCache, self._assetCache
    local previousShaderCache, previousShaderFailures =
        self._shaderCache, self._shaderFailures
    self.theme = theme
    self.assets = assets
    self._fontCache = {}
    self._assetCache = {}
    Shader.clear(self)
    local ok, result = pcall(self.render, self, root)
    if not ok then
        -- A rejected candidate never published and may safely retain the last
        -- good theme. A terminal commit fault retains its published tree, so
        -- it must also retain the theme and caches that built that tree.
        if self._generation == previousGeneration then
            self.theme, self.assets = previousTheme, previousAssets
            self._fontCache, self._assetCache = previousFonts, previousAssetCache
            self._shaderCache, self._shaderFailures =
                previousShaderCache, previousShaderFailures
        end
        error(result, 0)
    end
    return result
end

function host:refreshTheme(theme, assets, root)
    return runExternal(self, "ThemeRefresh", host._refreshTheme,
        theme, assets, root)
end

function host:tree()
    return self._tree
end

function host:viewport()
    return self._viewport:snapshot()
end

function host:_appendTrace(entry)
    self._messageSequence = self._messageSequence + 1
    entry.sequence = self._messageSequence
    self._messageTrace[#self._messageTrace + 1] = entry
    while #self._messageTrace > self._messageTraceLimit do
        table.remove(self._messageTrace, 1)
    end
    return #self._messageTrace
end

function host:_enqueue(entry)
    assert(self._mounted and activeHost == self, "FrogUI has no mounted Host")
    assertOperational(self, "enqueue a message")
    assert(not self._drawing,
        "Host drawing phase may not enqueue FrogUI messages")
    assert(renderingHost == nil,
        "FrogUI messages may not be sent or emitted during render")
    assert(not self._authorityCallbackActive,
        (self._authorityLabel or "authority callback")
            .. " must return its domain result; use its result callback"
            .. " for UI messages")
    assert(not self._dispatching,
        "FrogUI reducers/reactions may emit only through Frog.go")
    self._messageQueue[#self._messageQueue + 1] = entry
end

-- Runs one irreversible domain callback without opening a UI transaction.
-- Input owns terminalization; UI follow-up belongs to a result callback.
function host:_runAuthorityCallback(label, callback, ...)
    assert(type(callback) == "function", label .. " must be a function")
    assertOperational(self, "run " .. label)
    assert(not self._authorityCallbackActive,
        "nested authority callbacks are forbidden")
    local previousDepth = self._callbackDepth
    assert(previousDepth == 0,
        label .. " authority requires the root input boundary")
    local previousOrigin = self._currentOrigin
    local previousSource = self._currentOriginSource
    self._callbackDepth = previousDepth + 1
    self._authorityCallbackActive = true
    self._authorityLabel = label
    self._currentOrigin = label
    local args = { ... }
    local results = { pcall(function()
        local ok, detail = callback(unpack(args))
        assert(type(ok) == "boolean", label .. " must return ok, detail")
        return ok, Message.snapshotPlain(detail, label .. " detail")
    end) }
    self._authorityCallbackActive = nil
    self._authorityLabel = nil
    self._callbackDepth = previousDepth
    self._currentOrigin = previousOrigin
    self._currentOriginSource = previousSource
    if not results[1] then
        faultHost(self, label, results[2])
        error(results[2], 0)
    end
    table.remove(results, 1)
    return unpack(results)
end

-- Preserves the existing source-owned drop boundary name and diagnostics.
function host:_runDropCallback(callback, ...)
    return self:_runAuthorityCallback("DragSource onDrop", callback, ...)
end

function host:_enqueueAction(target, record, origin)
    record = Message.snapshot(record, "action")
    local function enqueue()
        self:_enqueue({
            kind = "action",
            target = target,
            record = record,
            origin = origin or self._currentOrigin or "Frog.send",
            originSource = self._currentOriginSource,
        })
    end
    if self._callbackDepth == 0 then
        return self:_runCallback(enqueue, origin or "Frog.send")
    end
    enqueue()
end

function host:_enqueueEvent(record, origin)
    record = Message.snapshot(record, "event")
    local function enqueue()
        self:_enqueue({
            kind = "event",
            record = record,
            origin = origin or self._currentOrigin or "Frog.emit",
            originSource = self._currentOriginSource,
        })
    end
    if self._callbackDepth == 0 then
        return self:_runCallback(enqueue, origin or "Frog.emit")
    end
    enqueue()
end

local function orderedActors(actors)
    local output = {}
    for _, instance in pairs(actors) do output[#output + 1] = instance end
    table.sort(output, function(left, right) return left.order < right.order end)
    return output
end

-- Defers actor cleanup until the surrounding render/message batch commits.
-- Failed candidate trees therefore never dispose the live actor.
function host:_stageActorUnmounts(previousActors, nextActors)
    local retained = {}
    for _, instance in pairs(nextActors or {}) do
        retained[instance.lifetime] = true
    end
    for _, instance in ipairs(orderedActors(previousActors or {})) do
        local cleanup = instance.token.definition.unmount
        if cleanup and not retained[instance.lifetime]
                and not self._pendingActorUnmountLifetimes[instance.lifetime] then
            self._pendingActorUnmountLifetimes[instance.lifetime] = true
            self._pendingActorUnmounts[#self._pendingActorUnmounts + 1] = {
                callback = cleanup,
                props = instance.props,
                state = deepCopy(instance.state),
                lifetime = instance.lifetime,
                source = instance.source,
                label = instance.token.name,
            }
        end
    end
end

-- Defers cleanup for committed resources that are absent from the next tree.
-- Matching lifetimes survive reorders, resizes, and ordinary rerenders.
function host:_stageResourceDisposals(previousResources, nextResources)
    local retained = {}
    for _, instance in ipairs(nextResources or {}) do
        retained[instance.lifetime] = true
    end
    for _, instance in ipairs(previousResources or {}) do
        if not retained[instance.lifetime]
                and not self._pendingResourceLifetimes[instance.lifetime]
                and not instance.disposed then
            self._pendingResourceLifetimes[instance.lifetime] = true
            self._pendingResourceDisposals[
                #self._pendingResourceDisposals + 1] = instance
        end
    end
end

-- Runs resource cleanup as a terminal authority boundary. Cleanup cannot send
-- UI messages or mutate presentation, and every resource is attempted once
-- even when an earlier cleanup fails.
function host:_disposeResources(resources, label)
    if not resources or #resources == 0 then return nil end
    local previousDepth = self._callbackDepth
    local previousOrigin = self._currentOrigin
    local previousSource = self._currentOriginSource
    local previousAuthority = self._authorityCallbackActive
    local previousAuthorityLabel = self._authorityLabel
    self._callbackDepth = previousDepth + 1
    self._authorityCallbackActive = true
    self._authorityLabel = label or "Resource cleanup"
    local firstError
    for _, instance in ipairs(resources) do
        if not instance.disposed then
            instance.disposed = true
            self._currentOrigin = instance.owner .. ":resource cleanup"
            self._currentOriginSource = instance.source
            local ok, err = pcall(instance.cleanup)
            if not ok and not firstError then firstError = err end
        end
    end
    self._authorityCallbackActive = previousAuthority
    self._authorityLabel = previousAuthorityLabel
    self._callbackDepth = previousDepth
    self._currentOrigin = previousOrigin
    self._currentOriginSource = previousSource
    return firstError
end

-- Commits every resource disposal staged by successful reconciliation.
function host:_commitResourceDisposals()
    if #self._pendingResourceDisposals == 0 then return nil end
    local pending = self._pendingResourceDisposals
    self._pendingResourceDisposals = {}
    self._pendingResourceLifetimes = {}
    return self:_disposeResources(pending, "Resource cleanup")
end

-- Runs every committed actor cleanup exactly once as a terminal authority
-- boundary. All callbacks run even when one fails; the first error is surfaced.
function host:_commitActorUnmounts()
    if #self._pendingActorUnmounts == 0 then return nil end
    local pending = self._pendingActorUnmounts
    self._pendingActorUnmounts = {}
    self._pendingActorUnmountLifetimes = {}
    local previousDepth = self._callbackDepth
    local previousOrigin = self._currentOrigin
    local previousSource = self._currentOriginSource
    self._callbackDepth = previousDepth + 1
    self._authorityCallbackActive = true
    self._authorityLabel = "Actor unmount"
    local firstError
    for _, entry in ipairs(pending) do
        self._currentOrigin = entry.label .. ":unmount"
        self._currentOriginSource = entry.source
        local ok, err = pcall(entry.callback, entry.props, entry.state)
        if not ok and not firstError then firstError = err end
    end
    self._authorityCallbackActive = nil
    self._authorityLabel = nil
    self._callbackDepth = previousDepth
    self._currentOrigin = previousOrigin
    self._currentOriginSource = previousSource
    return firstError
end

local function orderedEventReceivers(actors, motions)
    local output = {}
    for _, instance in pairs(actors) do
        output[#output + 1] = { kind = "actor", instance = instance }
    end
    for _, instance in pairs(motions) do
        output[#output + 1] = { kind = "motion", instance = instance }
    end
    table.sort(output, function(left, right)
        return left.instance.eventOrder < right.instance.eventOrder
    end)
    return output
end

function host:_resolveTarget(target)
    if Message.isAddress(target) then
        local instance = self._addresses[target]
        assert(instance, "actor address " .. target.name .. " is not mounted")
        return instance
    end
    assert(type(target) == "table" and target.identity and target.token
            and target.lifetime,
        "FrogUI action target must be an actor address")
    local mounted = self._actors[target.identity]
    assert(mounted and mounted.token == target.token
            and mounted.lifetime == target.lifetime,
        "cannot send through an unmounted actor")
    return mounted
end

function host:_emitTransitionFact(template, props, origin, originSource)
    if not template then return end
    local token = Message.token(template)
    assert(token and token.messageKind == "event", "Frog.go emit must be a typed event")
    local resolved = Message.resolve(template, props, "emit")
    local record = Message.snapshot(token(resolved), "event")
    self._messageQueue[#self._messageQueue + 1] = {
        kind = "event",
        record = record,
        origin = origin,
        originSource = originSource,
    }
end

function host:_applyTransition(instance, spec, record, origin)
    local profiling = self._diagnostics.enabled
    local transitionStarted = profiling and self._diagnostics:start() or nil
    local previous = instance.state
    local nextState
    local emitted
    if type(spec) == "function" then
        -- Reducers own one detached draft. Returning nil discards it; returning
        -- any valid state publishes one semantic change. Message and props are
        -- read-only inputs by contract rather than recursively policed copies.
        local reducerState = deepCopy(instance.state)
        self._dispatching = true
        local ok, result = pcall(spec, reducerState, record, instance.props)
        self._dispatching = false
        if not ok then error(result, 0) end
        if result == nil then
            if profiling then
                self._diagnostics:increment("actorTransitions")
                self._diagnostics:finish("actorTransitions", transitionStarted)
            end
            return false, false
        end
        assert(not Message.isTransition(result),
            instance.token.name .. " reducer must return nextState or nil, not Frog.go")
        nextState = result
    elseif Message.isTransition(spec) then
        if not stateAllowed(instance.state, spec.from) then
            if profiling then
                self._diagnostics:increment("actorTransitions")
                self._diagnostics:finish("actorTransitions", transitionStarted)
            end
            return false, false
        end
        nextState = spec.value
        emitted = spec.emit
    else
        nextState = spec
    end
    validateActorState(instance.token, nextState,
        instance.token.name .. " transition result")
    if type(spec) ~= "function" then nextState = deepCopy(nextState) end
    instance.state = nextState
    if emitted then
        self:_emitTransitionFact(emitted, instance.props,
            origin .. " -> " .. instance.token.name, instance.source)
    end
    local changed = type(instance.state) == "table" or instance.state ~= previous
    if profiling then
        self._diagnostics:increment("actorTransitions")
        self._diagnostics:increment("acceptedActorTransitions")
        if changed then
            self._diagnostics:increment("changedActorTransitions")
        end
        self._diagnostics:finish("actorTransitions", transitionStarted)
    end
    return true, changed
end

function host:_processAction(entry)
    local record, token = Message.validate(entry.record, "action")
    local instance = self:_resolveTarget(entry.target)
    assert(instance.token.definition.actions[token] ~= nil,
        "action " .. token.name .. " does not belong to actor " .. instance.token.name)
    local handler = instance.token.definition.actions[token]
    local spec
    if type(handler) == "table" then spec = handler[instance.state]
    else spec = handler end
    local accepted, changed = false, false
    if spec ~= nil then
        accepted, changed = self:_applyTransition(instance, spec, record,
            entry.origin or "action:" .. token.name)
    end
    local recipient = actorLabel(instance)
    local traceIndex = self:_appendTrace({
        kind = "action",
        token = token.name,
        origin = entry.origin,
        source = {
            token = deepCopy(token.source),
            origin = deepCopy(entry.originSource),
        },
        recipients = { recipient },
        transitions = { {
            recipient = recipient,
            accepted = accepted,
            changed = changed,
        } },
        reconciled = false,
    })
    return changed, traceIndex
end

function host:_processEvent(entry)
    local record, token = Message.validate(entry.record, "event")
    local recipients = {}
    local transitions = {}
    local changed = false
    for _, receiver in ipairs(orderedEventReceivers(self._actors, self._motions)) do
        local instance = receiver.instance
        for _, reaction in ipairs(instance.reactions) do
            if reaction.event == token then
                if receiver.kind == "actor" then
                    local recipient = actorLabel(instance)
                    recipients[#recipients + 1] = recipient
                    local accepted, didChange = false, false
                    -- Each actor reducer owns one detached delivery record.
                    -- An impure reducer cannot corrupt the canonical broadcast
                    -- inspected by a later ordered recipient.
                    local delivery = Message.snapshot(record, "event")
                    if Message.matches(reaction.match, delivery, instance.props) then
                        accepted, didChange = self:_applyTransition(
                            instance, reaction.transition, delivery,
                            entry.origin or "event:" .. token.name)
                    end
                    transitions[#transitions + 1] = {
                        recipient = recipient,
                        accepted = accepted,
                        changed = didChange,
                    }
                    changed = changed or didChange
                else
                    local recipient = "juice:" .. instance.identity
                    recipients[#recipients + 1] = recipient
                    local accepted = Message.matches(
                        reaction.match, record, instance.props)
                    if accepted then Motion.play(instance, reaction.do_, self) end
                    transitions[#transitions + 1] = {
                        recipient = recipient,
                        accepted = accepted,
                        changed = accepted,
                    }
                end
            end
        end
    end
    self:_transformTree(nil, "messageTransform")
    local traceIndex = self:_appendTrace({
        kind = "event",
        token = token.name,
        origin = entry.origin,
        source = {
            token = deepCopy(token.source),
            origin = deepCopy(entry.originSource),
        },
        recipients = recipients,
        transitions = transitions,
        reconciled = false,
    })
    return changed, traceIndex
end

function host:_drainMessages(budget)
    local dirty = false
    local profiling = self._diagnostics.enabled
    budget = budget or { processed = 0 }
    local lastTraceIndex
    while #self._messageQueue > 0 do
        budget.processed = budget.processed + 1
        assert(budget.processed <= self._messageLoopLimit,
            "FrogUI message loop exceeded " .. self._messageLoopLimit .. " deliveries")
        local entry = table.remove(self._messageQueue, 1)
        local changed, traceIndex
        local processingStarted = profiling and self._diagnostics:start() or nil
        if entry.kind == "action" then changed, traceIndex = self:_processAction(entry)
        else changed, traceIndex = self:_processEvent(entry) end
        if profiling then
            local phase = entry.kind == "action"
                    and "actionProcessing" or "eventProcessing"
            self._diagnostics:increment(entry.kind .. "Messages")
            self._diagnostics:finish(phase, processingStarted)
        end
        if changed and traceIndex and self._diagnostics.enabled then
            local trace = self._messageTrace[traceIndex]
            self._diagnostics:cause((trace.kind or entry.kind)
                .. ":" .. tostring(trace.token))
        end
        dirty = dirty or changed
        lastTraceIndex = traceIndex or lastTraceIndex
    end
    return dirty, lastTraceIndex
end

function host:_runCallback(callback, origin, originSource, ...)
    assert(type(callback) == "function", "FrogUI callback must be a function")
    assertOperational(self, "run another callback")
    if self._callbackDepth > 0 then return callback(...) end
    self._diagnostics:ensureFrame()
    local externalStarted = not self._diagnosticUpdateActive
            and (self._diagnosticExternalDepth or 0) == 0
            and origin ~= "Host:render" and origin ~= "Host:resize"
        and self._diagnostics:start() or nil
    local previousQueue = self._messageQueue
    local feedbackMark = #self._feedbackQueue
    self._messageQueue = {}
    self._callbackDepth = 1
    self._currentOrigin = origin or "callback"
    self._currentOriginSource = originSource
    local args = { ... }
    local callbackStarted = self._diagnostics:start()
    local results = { pcall(function() return callback(unpack(args)) end) }
    if origin == "Host:update frames" then
        self._diagnostics:finish("frameCallbacks", callbackStarted)
    end
    if results[1] then
        local budget = { processed = 0 }
        local settled = false
        while not settled do
            local deliveryStarted = self._diagnostics:start()
            local ok, dirty, traceIndex = pcall(
                self._drainMessages, self, budget)
            self._diagnostics:finish("messageDelivery", deliveryStarted)
            if not ok then
                results = { false, dirty }
                break
            end
            if dirty then
                local rendered, renderError = pcall(self.render, self)
                if not rendered then
                    results = { false, renderError }
                    break
                end
                if traceIndex and self._messageTrace[traceIndex] then
                    self._messageTrace[traceIndex].reconciled = true
                end
            end
            settled = #self._messageQueue == 0
        end
        self._diagnostics:increment("messages", budget.processed)
    end
    self._callbackDepth = 0
    self._currentOrigin = nil
    self._currentOriginSource = nil
    self._messageQueue = previousQueue
    local failure = not results[1] and results[2] or nil
    if failure then self:_trimFeedback(feedbackMark) end
    local feedbackOk, feedbackError = true, nil
    if not failure then
        feedbackOk, feedbackError = pcall(self._commitFeedback, self)
    end
    local resourceError = self:_commitResourceDisposals()
    local actorError = self:_commitActorUnmounts()
    failure = failure or (not feedbackOk and feedbackError or nil)
    failure = appendFailure(failure, "resource cleanup failed", resourceError)
    failure = appendFailure(failure, "actor cleanup failed", actorError)
    self._diagnostics:finish("external", externalStarted)
    if failure then
        faultHost(self, origin or "callback", failure)
        error(failure, 0)
    end
    table.remove(results, 1)
    return unpack(results)
end

-- Activates either an ordinary Button or its explicit one-shot authority
-- boundary. A successful commit spends this exact mounted control first.
function host:_activateButton(button)
    if self._spentAuthorities[button.identity] then return false end
    if not button.props.onCommit then
        if not button.props.onPress then return false end
        self:_runCallback(function()
            local cue = soundCue(self, button.props.sound, "activate")
            if cue then self:_stageFeedback("sound", cue) end
            button.props.onPress()
        end,
            "Button:" .. button.identity, button.source)
        return true
    end
    self._spentAuthorities[button.identity] = true
    local ok, detail = self:_runAuthorityCallback(
        "Button onCommit", button.props.onCommit)
    local status = ok and "committed" or "rejected"
    if not ok then self._spentAuthorities[button.identity] = nil end
    local notify = function()
        local cue = ok
            and soundCue(self, button.props.sound, "activate")
            or soundCue(self, button.props.rejectSound, "reject")
        if cue then self:_stageFeedback("sound", cue) end
        button.props.onResult(status, detail)
    end
    self:_runCallback(notify, "Button:onResult", button.source)
    return true
end

function host.send(address, record)
    assert(renderingHost == nil, "FrogUI messages may not be sent during render")
    assert(activeHost, "Frog.send requires a mounted Host")
    assert(not activeHost._drawing,
        "Host drawing phase may not send FrogUI messages")
    assert(Message.isAddress(address), "Frog.send expects an Actor:address target")
    return activeHost:_enqueueAction(address, record, "Frog.send")
end

function host.emit(record)
    assert(renderingHost == nil, "FrogUI messages may not be emitted during render")
    assert(activeHost, "Frog.emit requires a mounted Host")
    assert(not activeHost._drawing,
        "Host drawing phase may not emit FrogUI messages")
    return activeHost:_enqueueEvent(record, "Frog.emit")
end

-- Delivers one dt to the callbacks committed at the start of this update.
-- Their typed publications share one callback batch and therefore
-- reconcile only after every frame subscriber has run.
function host:_runFrames(dt)
    if #self._frames == 0 then return end
    local frames = {}
    for index, frame in ipairs(self._frames) do frames[index] = frame end
    self:_runCallback(function()
        self._frameCallbacksActive = true
        local ok, failure = pcall(function()
            for _, frame in ipairs(frames) do
                local delivered, err = pcall(frame.callback, dt)
                if not delivered then
                    error(frame.owner .. " " .. frame.id
                        .. " failed: " .. tostring(err), 0)
                end
            end
        end)
        self._frameCallbacksActive = nil
        if not ok then error(failure, 0) end
    end, "Host:update frames")
end

function host:update(dt)
    assert(self._mounted, "Host is not mounted")
    assertOperational(self, "update")
    assertPresentationAllowed(self, "advance")
    assertInputBoundary(self)
    assert(type(dt) == "number" and dt >= 0, "Host:update dt must be non-negative")
    self._diagnostics:beginFrame()
    self._diagnosticUpdateActive = true
    local updateStarted = self._diagnostics:start()
    self:_runFrames(dt)
    local feedbackMark = #self._feedbackQueue
    local motionCompletions, effectCompletions
    local runtimeStarted = self._diagnostics:start()
    local profiling = self._diagnostics.enabled
    local runtimeHeapStarted = profiling and self._diagnostics:heapStart() or nil
    local runtimeHeapCursor = runtimeHeapStarted
    local ok, err = pcall(function()
        local interactionStarted = self._diagnostics:start()
        self._rawClock:advance(dt)
        Interaction.update(self, dt)
        self._diagnostics:finish("interaction", interactionStarted)
        if profiling then
            runtimeHeapCursor = self._diagnostics:heapMark(
                "interaction", runtimeHeapCursor)
        end
        local motionStarted = self._diagnostics:start()
        local motionUpdateStarted = profiling
            and self._diagnostics:start() or nil
        local motionAttribution
        _, motionCompletions, motionAttribution =
            Motion.updateAll(self._motions, self)
        if profiling then
            self._diagnostics:finish("motionUpdate", motionUpdateStarted)
        end
        local _, transformAttribution = self:_transformTree(nil,
            "committedTransform", motionAttribution)
        self._diagnostics:finish("motion", motionStarted)
        if profiling then
            runtimeHeapCursor = self._diagnostics:heapMark(
                "motion", runtimeHeapCursor)
        end
        local refsStarted = self._diagnostics:start()
        self:_refreshCommittedRefs("committed", transformAttribution)
        self._diagnostics:finish("refs", refsStarted)
        if profiling then
            runtimeHeapCursor = self._diagnostics:heapMark(
                "refs", runtimeHeapCursor)
        end
        local effectsStarted = self._diagnostics:start()
        local refreshStarted = profiling and self._diagnostics:start() or nil
        Effect.refreshAll(self._effects, self)
        if profiling then
            self._diagnostics:finish("effectRefresh", refreshStarted)
        end
        local effectUpdateStarted = profiling
            and self._diagnostics:start() or nil
        effectCompletions = Effect.updateAll(self._effects)
        if profiling then
            self._diagnostics:finish("effectUpdate", effectUpdateStarted)
        end
        local boundsStarted = profiling and self._diagnostics:start() or nil
        Effect.updateBounds(self._effects, self)
        if profiling then
            self._diagnostics:finish("effectBounds", boundsStarted)
        end
        self._diagnostics:finish("effects", effectsStarted)
        if profiling then
            runtimeHeapCursor = self._diagnostics:heapMark(
                "effects", runtimeHeapCursor)
        end
    end)
    if profiling then
        self._diagnostics:heapRecord(
            "runtime", runtimeHeapStarted, runtimeHeapCursor)
    end
    self._diagnostics:finish("runtime", runtimeStarted)
    if not ok then
        self._diagnosticUpdateActive = nil
        self:_trimFeedback(feedbackMark)
        faultHost(self, "Host:update", err)
        error(err, 0)
    end
    local feedbackOk, feedbackError = pcall(self._commitFeedback, self)
    if not feedbackOk then
        self._diagnosticUpdateActive = nil
        faultHost(self, "Host:update feedback", feedbackError)
        error(feedbackError, 0)
    end
    for _, completion in ipairs(motionCompletions or {}) do
        if self._mounted
                and Motion.completionIsMounted(self._motions, completion) then
            self:_runCallback(completion.callback,
                "juice:" .. completion.identity .. ":" .. completion.name,
                completion.source)
        end
    end
    for _, completion in ipairs(effectCompletions or {}) do
        if self._mounted
                and Effect.completionIsMounted(self._effects, completion) then
            self:_runCallback(completion.callback,
                "effect:" .. completion.identity .. ":" .. completion.kind,
                completion.source)
        end
    end
    self._diagnostics:finishUpdate(updateStarted)
    self._diagnosticUpdateActive = nil
end

function host:draw(customPainter)
    assert(self._mounted, "Host is not mounted")
    assert(not self._drawing, "Host:draw cannot re-enter its drawing phase")
    assertInputBoundary(self)
    self._diagnostics:ensureFrame()
    self._drawing = true
    local paintStarted = self._diagnostics:start()
    local ok, reason = pcall(Painter.draw, self,
        customPainter or self._customPainter)
    self._drawing = nil
    self._diagnostics:finishDraw(paintStarted)
    if not ok then error(reason, 0) end
end

-- Returns the development profiler's detached rolling summary. Ordinary Hosts
-- keep diagnostics disabled and therefore retain no per-frame history.
---@return FrogUIDiagnosticsSnapshot
function host:diagnostics()
    return self._diagnostics:snapshot()
end

local function assertDiagnosticToolBoundary(self, operation)
    assert(self._mounted,
        "cannot " .. operation .. " on an unmounted FrogUI Host")
    assertOperational(self, operation)
    assert(self._diagnostics.enabled,
        operation .. " requires diagnostics = true")
    assert(not self._diagnosticUpdateActive,
        "cannot " .. operation .. " during Host update")
    assert(not self._drawing,
        "cannot " .. operation .. " during Host draw")
    assert(self._callbackDepth == 0,
        "cannot " .. operation .. " during a FrogUI callback")
    assert((self._diagnosticExternalDepth or 0) == 0,
        "cannot " .. operation .. " during external Host input")
end

-- Resets an opt-in diagnostic ring before one isolated developer measurement.
function host:clearDiagnostics()
    assertDiagnosticToolBoundary(self, "clear diagnostics")
    self._diagnostics:clear()
end

-- Returns the opt-in diagnostic ring in chronological order. This allocates a
-- detached row per sample and is intended for one-shot tools, not live paint.
function host:diagnosticTrace()
    assertDiagnosticToolBoundary(self, "export a diagnostic trace")
    return self._diagnostics:trace()
end

function host:resize(width, height)
    assert(self._mounted, "Host is not mounted")
    assertOperational(self, "resize")
    assertPresentationAllowed(self, "resize")
    assertFramePublication(self, "resize")
    self._diagnostics:ensureFrame()
    local externalStarted = not self._diagnosticUpdateActive
            and (self._diagnosticExternalDepth or 0) == 0
        and self._diagnostics:start() or nil
    if externalStarted then
        self._diagnostics:increment("externalResizeOperations")
    end
    local reconcileStarted = self._diagnostics:start()
    self._diagnostics:increment("reconciles")
    self._diagnostics:cause("resize")
    local previousPhysicalWidth = self._viewport.physicalWidth
    local previousPhysicalHeight = self._viewport.physicalHeight
    self._viewport:resize(width, height)
    local ok, candidate, context = pcall(self._build, self, self._rootDescriptor)
    if not ok then
        self._viewport:resize(previousPhysicalWidth, previousPhysicalHeight)
        self._diagnostics:finish("reconcile", reconcileStarted)
        self._diagnostics:finish("external", externalStarted)
        error(candidate, 0)
    end
    local previous = {
        actors = self._actors,
        modals = self._modals or {},
        modalIdentity = self._modal and self._modal.identity or nil,
        tree = self._tree,
        modal = self._modal,
        chrome = self._chrome,
        focusedIdentity = self._focusedIdentity,
        hoveredIdentity = self._hoveredIdentity,
    }
    local published = false
    local function commit()
        self._tree = candidate
        clearTransformWork(self)
        self._pendingTransformAttribution = nil
        self._actors = context.actors
        self._addresses = context.addresses
        self._semanticTokens = context.semanticTokens
        self._motions = context.motions
        self._effects = context.effects
        self._scrolls = context.scrolls
        self._radials = context.radials
        self._modals = context.modals
        self._modal = context.modal
        self._chrome = context.chrome
        self._generation = self._generation + 1
        for identity in pairs(self._spentAuthorities) do
            if not findIdentity(self._tree, identity) then
                self._spentAuthorities[identity] = nil
            end
        end
        reconcileModalFocus(self, previous.modals, previous.focusedIdentity)
        if self._selectedIdentity
                and not Interaction.findActiveIdentity(self,
                    self._selectedIdentity) then
            self._selectedIdentity = nil
        end
        self:_publishRenderHooks(context)
        published = true
        self:_stageActorUnmounts(previous.actors, context.actors)
        Interaction.cancel(self, "resize")
        Interaction.afterCommit(self, previous)
    end
    local committed, commitError
    local commitStarted = self._diagnostics:start()
    if self._callbackDepth == 0 then
        committed, commitError = pcall(self._runCallback, self, commit,
            "Host:resize")
    else
        committed, commitError = pcall(commit)
    end
    self._diagnostics:finish("commit", commitStarted)
    if not committed then
        local cleanupError
        if not published then
            cleanupError = self:_disposeResources(
                context.createdResources, "Unpublished candidate cleanup")
        end
        faultHost(self, "Host:resize commit", commitError)
        self._diagnostics:finish("reconcile", reconcileStarted)
        self._diagnostics:finish("external", externalStarted)
        error(appendFailure(commitError,
            "unpublished candidate cleanup failed", cleanupError), 0)
    end
    self._diagnostics:finish("reconcile", reconcileStarted)
    self._diagnostics:finish("external", externalStarted)
end

function host:_pointerId(pointerId)
    if pointerId == nil then return "mouse" end
    if pointerId == "mouse" or pointerId == "touch" then return pointerId end
    return "touch:" .. tostring(pointerId)
end

function host:_virtual(x, y)
    assert(finite(x) and finite(y), "pointer coordinates must be finite numbers")
    return self._viewport:toVirtual(x, y)
end

function host:_pointerDown(x, y, pointerId, button)
    assert(self._mounted, "Host is not mounted")
    assertOperational(self, "route pointer input")
    assertPresentationAllowed(self, "route pointer input through")
    assertInputBoundary(self)
    if self._inspectorVisible then
        self:inspect(x, y)
        return true
    end
    local virtualX, virtualY = self:_virtual(x, y)
    local id = self:_pointerId(pointerId)
    return Interaction.pointerDown(self, virtualX, virtualY, id, button)
end

function host:pointerDown(x, y, pointerId, button)
    return runExternal(self, "Input", host._pointerDown,
        x, y, pointerId, button)
end

function host:_pointerMove(x, y, pointerId)
    assert(self._mounted, "Host is not mounted")
    assertOperational(self, "route pointer input")
    assertPresentationAllowed(self, "route pointer input through")
    assertInputBoundary(self)
    local virtualX, virtualY = self:_virtual(x, y)
    return Interaction.pointerMove(self, virtualX, virtualY,
        self:_pointerId(pointerId))
end

function host:pointerMove(x, y, pointerId)
    return runExternal(self, "Input", host._pointerMove,
        x, y, pointerId)
end

function host:_pointerUp(x, y, pointerId, button)
    assert(self._mounted, "Host is not mounted")
    assertOperational(self, "route pointer input")
    assertPresentationAllowed(self, "route pointer input through")
    assertInputBoundary(self)
    local virtualX, virtualY = self:_virtual(x, y)
    return Interaction.pointerUp(self, virtualX, virtualY,
        self:_pointerId(pointerId), button)
end

function host:pointerUp(x, y, pointerId, button)
    return runExternal(self, "Input", host._pointerUp,
        x, y, pointerId, button)
end

function host:_keyDown(key, scancode, isrepeat)
    assert(self._mounted, "Host is not mounted")
    assertOperational(self, "route key input")
    assertPresentationAllowed(self, "route key input through")
    assertInputBoundary(self)
    if key == "f6" then
        Interaction.cancel(self, "inspector")
        self._inspectorVisible = true
        return true
    end
    if isrepeat then return self._modal ~= nil end
    if key == "escape" and Interaction.keyBack(self) then return true end
    local focusables, seen = {}, {}
    for _, inputRoot in ipairs(Interaction.inputRoots(self)) do
        local found = {}
        collectFocusables(inputRoot, found, self._spentAuthorities)
        for _, control in ipairs(found) do
            if not seen[control.identity] then
                seen[control.identity] = true
                focusables[#focusables + 1] = control
            end
        end
    end
    if key == "tab" then
        if #focusables == 0 then return self._modal ~= nil end
        local nextIndex = 1
        for index, control in ipairs(focusables) do
            if control.identity == self._focusedIdentity then
                nextIndex = index % #focusables + 1
                break
            end
        end
        self._focusedIdentity = focusables[nextIndex].identity
        Interaction.revealFocus(self, self._focusedIdentity)
        return true
    end
    local activated
    local activationKey = key == "return" or key == "space"
        or key == "kpenter"
    if activationKey then
        local focused = Interaction.findActiveIdentity(
            self, self._focusedIdentity)
        if focused and focused.type == "Button" and not focused.props.disabled
                and not self._spentAuthorities[focused.identity]
                and (focused.props.onPress or focused.props.onCommit) then
            activated = focused
        end
    end
    if not activated then
        for _, control in ipairs(focusables) do
            local shortcut = control.type == "Button"
                and control.props.shortcut
            local matches = shortcut == key
            if type(shortcut) == "table" then
                for _, accepted in ipairs(shortcut) do
                    if accepted == key then matches = true break end
                end
            end
            if matches then activated = control break end
        end
    end
    if activated and (activated.props.onPress or activated.props.onCommit) then
        self:_activateButton(activated)
        return true
    end
    local focusedControl = Interaction.findActiveIdentity(
        self, self._focusedIdentity)
    if focusedControl and focusedControl.type == "RadialDial"
            and Interaction.keyRadialDial(self, focusedControl, key) then
        return true
    end
    return self._modal ~= nil
end

function host:keyDown(key, scancode, isrepeat)
    return runExternal(self, "Input", host._keyDown,
        key, scancode, isrepeat)
end

function host:_keyUp(key)
    assert(self._mounted, "Host is not mounted")
    assertOperational(self, "route key input")
    assertPresentationAllowed(self, "route key input through")
    assertInputBoundary(self)
    if key == "f6" then
        self._inspectorVisible = false
        self._selectedIdentity = nil
        return true
    end
    return self._modal ~= nil
end

function host:keyUp(key)
    return runExternal(self, "Input", host._keyUp, key)
end

function host:_textInput(text)
    assert(self._mounted, "Host is not mounted")
    assertOperational(self, "route text input")
    assertPresentationAllowed(self, "route text input through")
    assertInputBoundary(self)
    assert(type(text) == "string", "Host:textInput expects text")
    self._lastInputText = text
    return self._modal ~= nil
end

function host:textInput(text)
    return runExternal(self, "Input", host._textInput, text)
end

function host:setInspectorVisible(visible)
    assert(self._mounted, "Host is not mounted")
    assertPresentationAllowed(self, "change inspector state in")
    assert(type(visible) == "boolean", "inspector visibility must be boolean")
    if visible and not self._inspectorVisible and not self._fault then
        Interaction.cancel(self, "inspector")
    end
    self._inspectorVisible = visible
    if not visible then self._selectedIdentity = nil end
end

function host:_inspect(x, y)
    assert(self._mounted, "Host is not mounted")
    assertPresentationAllowed(self, "change inspection selection in")
    local virtualX, virtualY = self:_virtual(x, y)
    local roots = Interaction.inputRoots(self)
    local selected, root, selectedArea
    for _, candidate in ipairs(roots) do
        local portalRoot = candidate._portal and candidate or nil
        local concrete = deepest(candidate, virtualX, virtualY,
            concreteInspectionHit, portalRoot)
        if concrete then
            selected, root = concrete, candidate
            break
        end
        local fallback = deepest(candidate, virtualX, virtualY,
            function() return true end, portalRoot)
        if fallback then
            local bounds = fallback._visualBounds or fallback
            local area = bounds.width * bounds.height
            if selectedArea == nil or area < selectedArea then
                selected, root, selectedArea = fallback, candidate, area
            end
        end
    end
    self._selectedIdentity = selected and selected.identity or nil
    if not selected then return nil end
    local nodes = {}
    flatten(root, 0, nodes, nil, root._portal and root or nil)
    for _, entry in ipairs(nodes) do
        if entry.identity == selected.identity then return entry end
    end
end

function host:inspect(x, y)
    return runExternal(self, "Input", host._inspect, x, y)
end

function host:inspectionTree()
    assert(self._mounted, "Host is not mounted")
    local nodes = {}
    local roots = Interaction.inputRoots(self)
    for index = #roots, 1, -1 do
        local root = roots[index]
        if root then
            flatten(root, 0, nodes, nil, root._portal and root or nil)
        end
    end
    local selected
    for _, entry in ipairs(nodes) do
        if entry.identity == self._selectedIdentity then selected = entry break end
    end
    local actors = {}
    for _, instance in ipairs(orderedActors(self._actors)) do
        actors[#actors + 1] = {
            name = instance.token.name,
            identity = instance.identity,
            address = instance.address and instance.address.name or nil,
            state = deepCopy(instance.state),
            order = instance.order,
            reactions = #instance.reactions,
            source = deepCopy(instance.source),
            mountSource = deepCopy(instance.mountSource),
        }
    end
    return {
        visible = self._inspectorVisible,
        fault = deepCopy(self._fault),
        nodes = nodes,
        selected = selected,
        messages = self:messageTrace(),
        actors = actors,
        interaction = Interaction.inspect(self),
    }
end

function host:messageTrace()
    assert(self._mounted, "Host is not mounted")
    return deepCopy(self._messageTrace)
end

function host:unmount()
    assert(self._mounted, "Host is not mounted")
    assertPresentationAllowed(self, "unmount")
    assertFramePublication(self, "unmount")
    if self._fault then
        -- A faulted Host is no longer allowed to run authored callbacks.
        self._interactionSession = nil
        self._pressedIdentity = nil
        self._hoveredIdentity = nil
    else
        Interaction.cancel(self, "unmount")
    end
    self:_stageActorUnmounts(self._actors, {})
    self:_stageResourceDisposals(self._resources, {})
    self._captures = {}
    self._pressedIdentity = nil
    self._hoveredIdentity = nil
    self._focusedIdentity = nil
    self._selectedIdentity = nil
    clearTransformWork(self)
    self._pendingTransformAttribution = nil
    self._tree = nil
    self._rootDescriptor = nil
    self._actors = {}
    self._addresses = {}
    self._semanticTokens = {}
    local committedRefs = self._refs
    self._hookOwners = {}
    self._resources = {}
    self._frames = {}
    self._refs = {}
    Ref.publish(committedRefs, self._refs, {})
    self._motions = {}
    self._effects = {}
    Shader.clear(self)
    self._scrolls = {}
    self._radials = {}
    self._modals = {}
    self._modal = nil
    self._chrome = nil
    self._modalFocusStack = {}
    self._feedbackQueue = {}
    self._rawClock:reset()
    self._messageQueue = {}
    self._mounted = false
    if activeHost == self then activeHost = nil end
    local resourceError = self:_commitResourceDisposals()
    local actorError = self:_commitActorUnmounts()
    if resourceError or actorError then
        error(resourceError or actorError, 0)
    end
end

function host:_fontSize(role)
    role = role or "body"
    local fonts = self.theme.fonts or {}
    local value = fonts[role]
    if type(value) == "number" then return value end
    if value and value.getHeight then return value:getHeight() end
    local fontSizes = self.theme.fontSizes or {}
    return fontSizes[role] or DEFAULT_FONT_SIZES[role] or DEFAULT_FONT_SIZES.body
end

function host:_font(role, exactSize)
    role = role or "body"
    local value = (self.theme.fonts or {})[role]
    if not exactSize and value and type(value) ~= "number" then return value end
    local size = exactSize or self:_fontSize(role)
    if self._fontCache[size] then return self._fontCache[size] end
    local g = love and love.graphics
    if g and g.newFont then
        local ok, font
        if self.theme.fontFile then
            ok, font = pcall(g.newFont, self.theme.fontFile, size)
        end
        if not ok or not font then ok, font = pcall(g.newFont, size) end
        if ok then self._fontCache[size] = font return font end
    end
    return nil
end

function host:_asset(source)
    if assetObject(source) then return source end
    if source == nil then return nil end
    local declared = self.assets[source]
    if assetObject(declared) then return declared end
    local path = type(declared) == "string" and declared or nil
    if not path then return nil end
    if self._assetCache[path] ~= nil then
        return self._assetCache[path] or nil
    end
    local g = love and love.graphics
    if g and g.newImage then
        local ok, image = pcall(g.newImage, path)
        self._assetCache[path] = ok and image or false
        return ok and image or nil
    end
    return nil
end

function host:_color(value, fallbackName, directFallback)
    if type(value) == "table" then return value end
    local colors = self.theme.colors or {}
    if type(value) == "string" then
        assert(colors[value] or Painter.defaults[value],
            "unknown FrogUI color token " .. value)
        return colors[value] or Painter.defaults[value]
    end
    if fallbackName and colors[fallbackName] then return colors[fallbackName] end
    return directFallback or (fallbackName and Painter.defaults[fallbackName])
        or { 1, 1, 1, 1 }
end

-- Thin LÖVE-boundary aliases. The canonical API stays pointerDown/keyDown.
function host:mousepressed(x, y, button)
    return self:pointerDown(x, y, "mouse", button)
end

function host:mousemoved(x, y)
    return self:pointerMove(x, y, "mouse")
end

function host:mousereleased(x, y, button)
    return self:pointerUp(x, y, "mouse", button)
end

function host:touchpressed(id, x, y)
    return self:pointerDown(x, y, id, 1)
end

function host:touchmoved(id, x, y)
    return self:pointerMove(x, y, id)
end

function host:touchreleased(id, x, y)
    return self:pointerUp(x, y, id, 1)
end

function host:_wheelMoved(dx, dy)
    assert(self._mounted, "Host is not mounted")
    assertOperational(self, "route wheel input")
    assertPresentationAllowed(self, "route wheel input through")
    assertInputBoundary(self)
    assert(finite(dx) and finite(dy), "wheel delta must be finite")
    return Interaction.wheelMoved(self, dx, dy)
end

function host:wheelMoved(dx, dy)
    return runExternal(self, "Input", host._wheelMoved, dx, dy)
end

host.keypressed = host.keyDown
host.keyreleased = host.keyUp
host.textinput = host.textInput
host.wheelmoved = host.wheelMoved

return host
