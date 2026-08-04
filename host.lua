-- Owns FrogUI's one mounted tree: component expansion, actor reconciliation,
-- input routing, inspection, resource lookup, and committed rendering.

local Layout = require("src.frogui.layout")
local Painter = require("src.frogui.painter")
local Viewport = require("src.frogui.viewport")
local Element = require("src.frogui.element")
local Message = require("src.frogui.message")
local Clock = require("src.frogui.clock")
local Motion = require("src.frogui.motion")
local Interaction = require("src.frogui.interaction")

local host = {}
host.__index = host

local activeHost = nil
local renderingHost = nil

local PRIMITIVES = {
    Box = true, Row = true, Column = true, Overlay = true,
    Text = true, Image = true, Icon = true, Button = true, Motion = true,
    Pressable = true, Scroll = true, Modal = true, Chrome = true,
    DragSource = true, DropTarget = true,
}

local DEFAULT_FONT_SIZES = { title = 28, heading = 22, body = 18, caption = 13 }

local COMMON_PROPS = {
    key = true, width = true, height = true, grow = true,
    opacity = true, offset = true, testId = true,
    juice = true, reactions = true,
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
    Text = {
        text = true, role = true, fontScale = true,
        color = true, wrap = true, maxLines = true,
        align = true, fitDown = true,
        outlineWidth = true, outlineColor = true,
    },
    Image = { source = true, sourceRect = true, fit = true, tint = true },
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
    Scroll = { axis = true, bar = true },
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
            or Clock.isClock(value) then
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

local function deepEqual(left, right, seen)
    if left == right then return true end
    if type(left) ~= type(right) or type(left) ~= "table" then return false end
    seen = seen or {}
    if seen[left] == right then return true end
    seen[left] = right
    for key, value in pairs(left) do
        if not deepEqual(value, right[key], seen) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function actorLabel(instance)
    if instance.address then return instance.address.name end
    return instance.identity
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
    elseif name == "Pressable" or name == "Scroll" or name == "Modal"
            or name == "Chrome"
            or name == "DragSource" or name == "DropTarget" then
        assert(#children == 1, "Frog." .. name .. " accepts exactly one child")
    elseif name == "Text" or name == "Image" or name == "Icon" then
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
    validateSize(props.width, name .. " width")
    validateSize(props.height, name .. " height")
    validateNumber(props.grow, name .. " grow", 0)
    validateOffset(props.offset)
    validatePadding(props.padding)
    validateNumber(props.borderWidth, name .. " borderWidth", 0)
    validateNumber(props.radius, name .. " radius", 0)
    if name ~= "Motion" then
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
        assert(props.source ~= nil, name .. " source token is required")
        if type(props.source) == "string" then
            local declared = self.assets[props.source]
            assert(declared ~= nil,
                "unknown FrogUI asset token " .. tostring(props.source))
            assert(type(declared) == "string" or assetObject(declared),
                "malformed FrogUI asset " .. tostring(props.source))
        else
            assert(assetObject(props.source), "malformed direct FrogUI asset")
        end
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
        if name == "Icon" then
            assert(props.mirror == nil or type(props.mirror) == "boolean",
                "Icon mirror must be a boolean")
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
    elseif name == "Text" then
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
        oneOf(props.align, { "left", "center", "right", "start", "end" },
            "Text align")
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
    elseif name == "Scroll" then
        oneOf(props.axis, { "vertical", "horizontal" }, "Scroll axis")
        assert(props.axis ~= nil, "Scroll axis is required")
        assert(props.bar == nil or type(props.bar) == "boolean",
            "Scroll bar must be a boolean")
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
    return localX >= node.x and localY >= node.y
        and localX <= node.x + node.width and localY <= node.y + node.height
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
    if node._scroll then
        entry.scroll = {
            axis = node._scroll.axis,
            offset = node._scroll.offset,
            extent = node._scroll.extent,
            velocity = node._scroll.velocity,
        }
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
    if node.type == "Text" or node.type == "Image" or node.type == "Icon"
            or node.type == "Button" or node.type == "Pressable"
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

local function collectButtons(node, output, spent)
    if node.type == "Button" and not node.props.disabled
            and not spent[node.identity] then
        output[#output + 1] = node
    end
    for _, child in ipairs(node.children) do
        collectButtons(child, output, spent)
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

-- Captures every Host-owned value that render/input callbacks may change.
-- Candidate builds and lifecycle callbacks restore this exact checkpoint on
-- failure, including focus, interaction, and physical viewport dimensions.
local function snapshotHost(self)
    local snapshot = {
        tree = self._tree,
        descriptor = self._rootDescriptor,
        actors = self._actors,
        addresses = self._addresses,
        semanticTokens = self._semanticTokens,
        motions = Motion.snapshot(self._motions),
        modals = self._modals,
        modal = self._modal,
        chrome = self._chrome,
        modalFocusStack = deepCopy(self._modalFocusStack),
        focusedIdentity = self._focusedIdentity,
        selectedIdentity = self._selectedIdentity,
        inspectorVisible = self._inspectorVisible,
        lastInputText = self._lastInputText,
        interaction = Interaction.snapshot(self),
        motionStartSequence = self._motionStartSequence,
        feedbackQueue = deepCopy(self._feedbackQueue),
        generation = self._generation,
        states = {},
        queue = self._messageQueue,
        trace = deepCopy(self._messageTrace),
        messageSequence = self._messageSequence,
        spentAuthorities = deepCopy(self._spentAuthorities),
        pendingActorUnmounts = shallowCopy(self._pendingActorUnmounts),
        pendingActorUnmountLifetimes = shallowCopy(
            self._pendingActorUnmountLifetimes),
        physicalWidth = self._viewport.physicalWidth,
        physicalHeight = self._viewport.physicalHeight,
    }
    for identity, instance in pairs(self._actors or {}) do
        snapshot.states[identity] = deepCopy(instance.state)
    end
    return snapshot
end

-- Restores a checkpoint without rerendering application components.
local function restoreHost(self, snapshot)
    if self._viewport.physicalWidth ~= snapshot.physicalWidth
            or self._viewport.physicalHeight ~= snapshot.physicalHeight then
        self._viewport:resize(snapshot.physicalWidth, snapshot.physicalHeight)
    end
    self._tree = snapshot.tree
    self._rootDescriptor = snapshot.descriptor
    self._actors = snapshot.actors
    self._addresses = snapshot.addresses
    self._semanticTokens = snapshot.semanticTokens
    self._motions = snapshot.motions
    self._modals = snapshot.modals
    self._modal = snapshot.modal
    self._chrome = snapshot.chrome
    self._modalFocusStack = snapshot.modalFocusStack
    self._focusedIdentity = snapshot.focusedIdentity
    self._selectedIdentity = snapshot.selectedIdentity
    self._inspectorVisible = snapshot.inspectorVisible
    self._lastInputText = snapshot.lastInputText
    Interaction.restore(self, snapshot.interaction)
    Motion.bindAll(self._motions)
    Motion.transformTree(self._tree)
    self._motionStartSequence = snapshot.motionStartSequence
    self._feedbackQueue = snapshot.feedbackQueue
    self._generation = snapshot.generation
    for identity, state in pairs(snapshot.states) do
        if self._actors[identity] then self._actors[identity].state = state end
    end
    self._messageQueue = snapshot.queue
    self._messageTrace = snapshot.trace
    self._messageSequence = snapshot.messageSequence
    self._spentAuthorities = snapshot.spentAuthorities
    self._pendingActorUnmounts = snapshot.pendingActorUnmounts
    self._pendingActorUnmountLifetimes = snapshot.pendingActorUnmountLifetimes
end

local function assertPresentationAllowed(self, operation)
    assert(not self._authorityCallbackActive,
        (self._authorityLabel or "authority callback") .. " may not " .. operation
            .. " presentation; return the domain result")
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
    local viewportOptions = shallowCopy(options)
    if viewportOptions.wideRatio == nil and self.theme.breakpoints then
        viewportOptions.wideRatio = self.theme.breakpoints.wideRatio
    end
    self._viewport = Viewport.new(viewportOptions)
    self._fontCache = {}
    self._assetCache = {}
    self._captures = {}
    self._inspectorVisible = options.inspectorActive == true
    self._lastInputText = nil
    self._generation = 0
    self._actors = {}
    self._addresses = {}
    self._semanticTokens = {}
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
    self._scrolls = {}
    self._interactionSession = nil
    self._modals = {}
    self._modal = nil
    self._chrome = nil
    self._modalFocusStack = {}
    self._pointerX, self._pointerY = 0, 0
    self._motionStartSequence = 0
    self._feedbackQueue = {}
    self._pendingActorUnmounts = {}
    self._pendingActorUnmountLifetimes = {}
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

function host:mount(root)
    assert(Element.isDescriptor(root), "Host:mount expects a FrogUI element/component")
    assert(not self._mounted, "Host is already mounted")
    assert(activeHost == nil,
        "FrogUI permits only one mounted Host")
    local feedbackMark = #self._feedbackQueue
    local motionSequence = self._motionStartSequence
    local ok, candidate, context = pcall(self._build, self, root)
    if not ok then
        self:_trimFeedback(feedbackMark)
        self._motionStartSequence = motionSequence
        error(candidate, 0)
    end
    activeHost = self
    self._mounted = true
    self._rootDescriptor = root
    self._tree = candidate
    self._actors = context.actors
    self._addresses = context.addresses
    self._semanticTokens = context.semanticTokens
    self._motions = context.motions
    self._scrolls = context.scrolls
    self._modals = context.modals
    self._modal = context.modal
    self._chrome = context.chrome
    reconcileModalFocus(self, {}, nil)
    self._generation = self._generation + 1
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
    assert((context.previewDepth or 0) == 0,
        "DragSource preview must be stateless presentation")
    local token = descriptor.token
    assert(not context.actors[logicalPath],
        "duplicate mounted actor identity " .. logicalPath)
    local props = shallowCopy(descriptor.props)
    props.children = descriptor.children
    local old = self._actors[logicalPath]
    local instance = {
        token = token,
        identity = logicalPath,
        props = props,
        state = old and old.token == token and deepCopy(old.state)
            or self:_initialState(token, props),
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

    local stateForRender = deepCopy(instance.state)
    local before = deepCopy(stateForRender)
    local rendered = self:_withRender(token.name,
        token.definition.render, props, stateForRender, self:_actorSend(instance))
    assert(deepEqual(before, stateForRender),
        token.name .. " mutated its state during render; return state from an action/reaction")
    if rendered == nil or rendered == false then return nil end
    assert(Element.isDescriptor(rendered), token.name .. " must return one FrogUI element or nil")
    local outputPath = childPath(path .. "/output", rendered, 1)
    local resolved = self:_resolve(rendered, token.name, outputPath, path, context,
        logicalOutputPath(logicalPath, rendered))
    if resolved then
        resolved._actorInstances = resolved._actorInstances or {}
        table.insert(resolved._actorInstances, 1, instance)
        if descriptor.key ~= nil then resolved.key = descriptor.key end
        resolved.actor = {
            name = token.name,
            state = deepCopy(instance.state),
            address = address and address.name or nil,
            reactions = #reactions,
        }
    end
    return resolved
end

function host:_resolveView(descriptor, owner, path, descendantPath, context,
        logicalPath)
    assert((context.previewDepth or 0) == 0,
        "DragSource preview cannot mount an actor view")
    local token = descriptor.token
    local props = shallowCopy(descriptor.props)
    props.children = descriptor.children
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
    local stateForRender = instance and deepCopy(instance.state) or nil
    local before = deepCopy(stateForRender)
    local rendered = self:_withRender(token.name, token.render, props, stateForRender,
        self:_addressSend(address), status)
    assert(deepEqual(before, stateForRender),
        token.name .. " mutated observed actor state during render")
    if rendered == nil or rendered == false then return nil end
    assert(Element.isDescriptor(rendered), token.name .. " must return one FrogUI element or nil")
    local outputPath = childPath(path .. "/output", rendered, 1)
    local resolved = self:_resolve(rendered, token.name, outputPath,
        descendantPath or path, context, logicalOutputPath(logicalPath, rendered))
    if resolved then
        if descriptor.key ~= nil then resolved.key = descriptor.key end
        resolved.view = {
            name = token.name,
            target = address.name,
            mounted = instance ~= nil,
        }
    end
    return resolved
end

function host:_resolve(descriptor, owner, path, descendantPath, context,
        logicalPath)
    local token = descriptor.token
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
    if token.kind == "component" then
        local props = shallowCopy(descriptor.props)
        props.children = descriptor.children
        local rendered = self:_withRender(token.name, token.render, props)
        if rendered == nil or rendered == false then return nil end
        assert(Element.isDescriptor(rendered),
            token.name .. " must return one FrogUI element or nil")
        local outputPath = childPath(path .. "/output", rendered, 1)
        local resolved = self:_resolve(rendered, token.name, outputPath, path,
            context, logicalOutputPath(logicalPath, rendered))
        if resolved and descriptor.key ~= nil then resolved.key = descriptor.key end
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

    validatePrimitive(token.name, descriptor.children)
    validatePrimitiveProps(self, token.name, descriptor.props)
    if (context.previewDepth or 0) > 0 then
        assert(token.name ~= "Pressable" and token.name ~= "Scroll"
                and token.name ~= "Modal" and token.name ~= "Chrome"
                and token.name ~= "DragSource"
                and token.name ~= "DropTarget" and token.name ~= "Button",
            "DragSource preview must be static presentation")
        assert(token.name ~= "Motion" and descriptor.props.juice == nil
                and descriptor.props.reactions == nil,
            "DragSource preview cannot own Motion or event reactions")
    end
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
    if token.name == "Scroll" then
        local instance = Interaction.reconcileScroll(
            self._scrolls[logicalPath], node, node.props, logicalPath)
        context.scrolls[logicalPath] = instance
    end
    if token.name == "Motion" or descriptor.props.juice
            or descriptor.props.reactions then
        local instance = Motion.reconcile(self._motions[logicalPath], node,
            node.props, logicalPath, context.nextReceiverOrder, self)
        context.nextReceiverOrder = context.nextReceiverOrder + 1
        context.motions[logicalPath] = instance
    end
    local childrenPath = descendantPath or path
    for index, child in ipairs(descriptor.children) do
        local resolved = self:_resolve(child, owner,
            childPath(childrenPath, child, index), nil, context,
            logicalChildPath(logicalPath, child, index))
        if resolved then node.children[#node.children + 1] = resolved end
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
    if not node then return nil end
    if node.__frogDeferredView then
        return self:_resolveView(node.descriptor, node.owner, node.path,
            node.descendantPath, context, node.logicalPath)
    end
    local children = {}
    for _, child in ipairs(node.children or {}) do
        local resolved = self:_resolveDeferred(child, context)
        if resolved then children[#children + 1] = resolved end
    end
    node.children = children
    return node
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

function host:_build(root)
    local context = {
        actors = {},
        addresses = {},
        addressNames = {},
        semanticTokens = {},
        nextOrder = 1,
        motions = {},
        scrolls = {},
        previewDepth = 0,
        nextReceiverOrder = 1,
    }
    local rootPath = childPath("root", root, 1)
    local rootLogicalPath = logicalChildPath("logical-root", root, 1)
    local candidate = self:_resolve(root, nil, rootPath, nil, context,
        rootLogicalPath)
    candidate = self:_resolveDeferred(candidate, context)
    assert(candidate, "Host root component returned nil")
    local nextEventOrder = assignEventOrder(candidate, 1)
    local hiddenActors = {}
    for _, instance in pairs(context.actors) do
        hiddenActors[#hiddenActors + 1] = instance
    end
    table.sort(hiddenActors, function(left, right) return left.order < right.order end)
    for _, instance in ipairs(hiddenActors) do
        if not instance.eventOrder then
            instance.eventOrder = nextEventOrder
            nextEventOrder = nextEventOrder + 1
        end
    end
    candidate = Layout.run(candidate,
        self._viewport.width, self._viewport.height, self)
    Motion.transformTree(candidate)
    context.modals, context.chrome = Interaction.planesFromTree(candidate)
    context.modal = context.modals[#context.modals]
    return candidate, context
end

function host:render(root)
    assert(self._mounted and activeHost == self, "Host is not mounted")
    assertPresentationAllowed(self, "render")
    local requested = root or self._rootDescriptor
    assert(Element.isDescriptor(requested), "Host:render expects a FrogUI element/component")
    local checkpoint = snapshotHost(self)
    local ok, candidate, context = pcall(self._build, self, requested)
    if not ok then
        restoreHost(self, checkpoint)
        error(candidate, 0)
    end
    local previous = {
        actors = checkpoint.actors,
        modals = checkpoint.modals or {},
        modalIdentity = checkpoint.modal and checkpoint.modal.identity or nil,
        tree = checkpoint.tree,
        modal = checkpoint.modal,
        chrome = checkpoint.chrome,
        focusedIdentity = checkpoint.focusedIdentity,
        hoveredIdentity = checkpoint.interaction.hoveredIdentity,
    }
    local commitFinished = false
    local function commit()
        self:_stageActorUnmounts(previous.actors, context.actors)
        self._rootDescriptor = requested
        self._tree = candidate
        self._actors = context.actors
        self._addresses = context.addresses
        self._semanticTokens = context.semanticTokens
        self._motions = context.motions
        self._scrolls = context.scrolls
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
        Interaction.afterCommit(self, previous)
        commitFinished = true
    end
    local committed, commitError
    if self._callbackDepth == 0 then
        committed, commitError = pcall(self._runCallback, self, commit,
            "Host:render")
    else
        committed, commitError = pcall(commit)
    end
    if not committed then
        if not commitFinished then restoreHost(self, checkpoint) end
        error(commitError, 0)
    end
    if self._callbackDepth == 0 then self:_commitFeedback() end
    return candidate
end

-- Dev presentation reload keeps the mounted Host and actor state, but drops
-- resource caches before rebuilding the committed tree. Component modules
-- reload separately by preserving their token-table identity.
function host:refreshTheme(theme, assets, root)
    assert(self._mounted and activeHost == self, "Host is not mounted")
    assertPresentationAllowed(self, "refresh")
    assert(type(theme) == "table", "Host:refreshTheme needs a theme table")
    assert(type(assets) == "table", "Host:refreshTheme needs an asset table")
    validateTheme(theme)
    local previousTheme, previousAssets = self.theme, self.assets
    local previousFonts, previousAssetCache = self._fontCache, self._assetCache
    self.theme = theme
    self.assets = assets
    self._fontCache = {}
    self._assetCache = {}
    local ok, result = pcall(self.render, self, root)
    if not ok then
        self.theme, self.assets = previousTheme, previousAssets
        self._fontCache, self._assetCache = previousFonts, previousAssetCache
        error(result, 0)
    end
    return result
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
    local results = { pcall(function() return callback(unpack(args)) end) }
    self._authorityCallbackActive = nil
    self._authorityLabel = nil
    self._callbackDepth = previousDepth
    self._currentOrigin = previousOrigin
    self._currentOriginSource = previousSource
    if not results[1] then error(results[2], 0) end
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

-- Defers actor cleanup until the surrounding render/message transaction has
-- committed. Failed candidate trees therefore never dispose the live actor.
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
    local from = deepCopy(instance.state)
    local nextState
    local emitted
    if type(spec) == "function" then
        local reducerState = deepCopy(instance.state)
        local reducerMessage = deepCopy(record)
        local reducerProps = deepCopy(instance.props)
        local beforeState = deepCopy(reducerState)
        local beforeMessage = deepCopy(reducerMessage)
        local beforeProps = deepCopy(reducerProps)
        self._dispatching = true
        local ok, result = pcall(spec, reducerState, reducerMessage, reducerProps)
        self._dispatching = false
        if not ok then error(result, 0) end
        assert(deepEqual(beforeState, reducerState),
            instance.token.name .. " reducer mutated state; return a replacement")
        assert(deepEqual(beforeMessage, reducerMessage),
            instance.token.name .. " reducer mutated its delivered message")
        assert(deepEqual(beforeProps, reducerProps),
            instance.token.name .. " reducer mutated its props")
        if result == nil then return false, from, from end
        assert(not Message.isTransition(result),
            instance.token.name .. " reducer must return nextState or nil, not Frog.go")
        nextState = result
    elseif Message.isTransition(spec) then
        if not stateAllowed(instance.state, spec.from) then return false, from, from end
        nextState = spec.value
        emitted = spec.emit
    else
        nextState = spec
    end
    validateActorState(instance.token, nextState,
        instance.token.name .. " transition result")
    instance.state = deepCopy(nextState)
    if emitted then
        self:_emitTransitionFact(emitted, instance.props,
            origin .. " -> " .. instance.token.name, instance.source)
    end
    return true, from, deepCopy(instance.state), not deepEqual(from, instance.state)
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
    local accepted, from, to, changed = false, deepCopy(instance.state), deepCopy(instance.state), false
    if spec ~= nil then
        accepted, from, to, changed = self:_applyTransition(instance, spec, record,
            entry.origin or "action:" .. token.name)
    end
    local recipient = actorLabel(instance)
    local traceIndex = self:_appendTrace({
        kind = "action",
        token = token.name,
        origin = entry.origin,
        payload = deepCopy(record),
        source = {
            token = deepCopy(token.source),
            origin = deepCopy(entry.originSource),
        },
        recipients = { recipient },
        transitions = { {
            recipient = recipient,
            from = from,
            to = to,
            accepted = accepted,
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
                    local accepted, from, to, didChange = false,
                        deepCopy(instance.state), deepCopy(instance.state), false
                    if Message.matches(reaction.match, record, instance.props) then
                        accepted, from, to, didChange = self:_applyTransition(
                            instance, reaction.transition, record,
                            entry.origin or "event:" .. token.name)
                    end
                    transitions[#transitions + 1] = {
                        recipient = recipient,
                        from = from,
                        to = to,
                        accepted = accepted,
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
                    }
                end
            end
        end
    end
    Motion.transformTree(self._tree)
    local traceIndex = self:_appendTrace({
        kind = "event",
        token = token.name,
        origin = entry.origin,
        payload = deepCopy(record),
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
    budget = budget or { processed = 0 }
    local lastTraceIndex
    while #self._messageQueue > 0 do
        budget.processed = budget.processed + 1
        assert(budget.processed <= self._messageLoopLimit,
            "FrogUI message loop exceeded " .. self._messageLoopLimit .. " deliveries")
        local entry = table.remove(self._messageQueue, 1)
        local changed, traceIndex
        if entry.kind == "action" then changed, traceIndex = self:_processAction(entry)
        else changed, traceIndex = self:_processEvent(entry) end
        dirty = dirty or changed
        lastTraceIndex = traceIndex or lastTraceIndex
    end
    return dirty, lastTraceIndex
end

function host:_runCallback(callback, origin, originSource, ...)
    assert(type(callback) == "function", "FrogUI callback must be a function")
    if self._callbackDepth > 0 then return callback(...) end
    local snapshot = snapshotHost(self)
    self._messageQueue = {}
    self._callbackDepth = 1
    self._currentOrigin = origin or "callback"
    self._currentOriginSource = originSource
    local args = { ... }
    local results = { pcall(function() return callback(unpack(args)) end) }
    if results[1] then
        local budget = { processed = 0 }
        local settled = false
        while not settled do
            local ok, dirty, traceIndex = pcall(
                self._drainMessages, self, budget)
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
    end
    self._callbackDepth = 0
    self._currentOrigin = nil
    self._currentOriginSource = nil
    if not results[1] then
        restoreHost(self, snapshot)
        error(results[2], 0)
    end
    self._messageQueue = snapshot.queue
    local feedbackOk, feedbackError = pcall(self._commitFeedback, self)
    local cleanupError = self:_commitActorUnmounts()
    if not feedbackOk or cleanupError then
        error(not feedbackOk and feedbackError or cleanupError, 0)
    end
    table.remove(results, 1)
    return unpack(results)
end

-- Settles UI follow-up after a successful irreversible domain call without
-- restoring pre-call actor state. A transient failed render is retried once;
-- the spent control remains inert if recovery is still impossible.
function host:_runTerminalCallback(callback, origin, originSource, ...)
    assert(type(callback) == "function", "FrogUI callback must be a function")
    assert(self._callbackDepth == 0,
        "terminal UI follow-up requires the root input boundary")
    self._messageQueue = {}
    self._callbackDepth = 1
    self._currentOrigin = origin or "terminal callback"
    self._currentOriginSource = originSource
    local args = { ... }
    local results = { pcall(function() return callback(unpack(args)) end) }
    local failure = not results[1] and results[2] or nil
    local budget = { processed = 0 }
    while #self._messageQueue > 0 do
        local ok, dirty, traceIndex = pcall(
            self._drainMessages, self, budget)
        if not ok then failure = failure or dirty break end
        if dirty then
            local rendered, renderError = pcall(self.render, self)
            if not rendered then failure = failure or renderError break end
            if traceIndex and self._messageTrace[traceIndex] then
                self._messageTrace[traceIndex].reconciled = true
            end
        end
    end
    self._callbackDepth = 0
    self._currentOrigin = nil
    self._currentOriginSource = nil
    self._messageQueue = {}
    if failure then pcall(self.render, self) end
    local feedbackOk, feedbackError = pcall(self._commitFeedback, self)
    local cleanupError = self:_commitActorUnmounts()
    failure = failure or (not feedbackOk and feedbackError or nil)
        or cleanupError
    if failure then error(failure, 0) end
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
    assert(type(ok) == "boolean",
        "Button onCommit must return ok, detail")
    local status = ok and "committed" or "rejected"
    if not ok then self._spentAuthorities[button.identity] = nil end
    detail = Message.snapshotPlain(detail, "Button onCommit detail")
    local notify = function()
        local cue = ok
            and soundCue(self, button.props.sound, "activate")
            or soundCue(self, button.props.rejectSound, "reject")
        if cue then self:_stageFeedback("sound", cue) end
        button.props.onResult(status, detail)
    end
    if ok then
        self:_runTerminalCallback(notify,
            "Button:onResult", button.source)
    else
        self:_runCallback(notify, "Button:onResult", button.source)
    end
    return true
end

function host.send(address, record)
    assert(renderingHost == nil, "FrogUI messages may not be sent during render")
    assert(activeHost, "Frog.send requires a mounted Host")
    assert(Message.isAddress(address), "Frog.send expects an Actor:address target")
    return activeHost:_enqueueAction(address, record, "Frog.send")
end

function host.emit(record)
    assert(renderingHost == nil, "FrogUI messages may not be emitted during render")
    assert(activeHost, "Frog.emit requires a mounted Host")
    return activeHost:_enqueueEvent(record, "Frog.emit")
end

function host:update(dt)
    assert(self._mounted, "Host is not mounted")
    assertPresentationAllowed(self, "advance")
    assert(type(dt) == "number" and dt >= 0, "Host:update dt must be non-negative")
    local time = self._rawClock:now()
    local instances = Motion.snapshot(self._motions)
    local interactionState = Interaction.snapshot(self)
    local feedback = deepCopy(self._feedbackQueue)
    local completions
    local ok, err = pcall(function()
        self._rawClock:advance(dt)
        Interaction.update(self, dt)
        _, completions = Motion.updateAll(self._motions, self)
        Motion.transformTree(self._tree)
    end)
    if not ok then
        self._rawClock:reset(time)
        self._motions = instances
        Interaction.restore(self, interactionState)
        self._feedbackQueue = feedback
        Motion.bindAll(self._motions)
        Motion.transformTree(self._tree)
        error(err, 0)
    end
    local feedbackOk, feedbackError = pcall(self._commitFeedback, self)
    local firstError = not feedbackOk and feedbackError or nil
    for _, completion in ipairs(completions or {}) do
        if self._mounted
                and Motion.completionIsMounted(self._motions, completion) then
            local delivered, deliveryError = pcall(
                self._runTerminalCallback, self, completion.callback,
                "juice:" .. completion.identity .. ":" .. completion.name,
                completion.source)
            if not delivered and not firstError then firstError = deliveryError end
        end
    end
    if firstError then error(firstError, 0) end
end

function host:draw(customPainter)
    assert(self._mounted, "Host is not mounted")
    Painter.draw(self, customPainter or self._customPainter)
end

function host:resize(width, height)
    assert(self._mounted, "Host is not mounted")
    assertPresentationAllowed(self, "resize")
    local checkpoint = snapshotHost(self)
    self._viewport:resize(width, height)
    local ok, candidate, context = pcall(self._build, self, self._rootDescriptor)
    if not ok then
        restoreHost(self, checkpoint)
        error(candidate, 0)
    end
    local previous = {
        actors = checkpoint.actors,
        modals = checkpoint.modals or {},
        modalIdentity = checkpoint.modal and checkpoint.modal.identity or nil,
        tree = checkpoint.tree,
        modal = checkpoint.modal,
        chrome = checkpoint.chrome,
        focusedIdentity = checkpoint.focusedIdentity,
        hoveredIdentity = checkpoint.interaction.hoveredIdentity,
    }
    local commitFinished = false
    local function commit()
        self:_stageActorUnmounts(previous.actors, context.actors)
        self._tree = candidate
        self._actors = context.actors
        self._addresses = context.addresses
        self._semanticTokens = context.semanticTokens
        self._motions = context.motions
        self._scrolls = context.scrolls
        self._modals = context.modals
        self._modal = context.modal
        self._chrome = context.chrome
        self._generation = self._generation + 1
        reconcileModalFocus(self, previous.modals, previous.focusedIdentity)
        if self._selectedIdentity
                and not Interaction.findActiveIdentity(self,
                    self._selectedIdentity) then
            self._selectedIdentity = nil
        end
        Interaction.cancel(self, "resize")
        Interaction.afterCommit(self, previous)
        commitFinished = true
    end
    local committed, commitError
    if self._callbackDepth == 0 then
        committed, commitError = pcall(self._runCallback, self, commit,
            "Host:resize")
    else
        committed, commitError = pcall(commit)
    end
    if not committed then
        if not commitFinished then restoreHost(self, checkpoint) end
        error(commitError, 0)
    end
    if self._callbackDepth == 0 then self:_commitFeedback() end
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

function host:pointerDown(x, y, pointerId, button)
    assert(self._mounted, "Host is not mounted")
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

function host:pointerMove(x, y, pointerId)
    assert(self._mounted, "Host is not mounted")
    assertPresentationAllowed(self, "route pointer input through")
    assertInputBoundary(self)
    local virtualX, virtualY = self:_virtual(x, y)
    return Interaction.pointerMove(self, virtualX, virtualY,
        self:_pointerId(pointerId))
end

function host:pointerUp(x, y, pointerId, button)
    assert(self._mounted, "Host is not mounted")
    assertPresentationAllowed(self, "route pointer input through")
    assertInputBoundary(self)
    local virtualX, virtualY = self:_virtual(x, y)
    return Interaction.pointerUp(self, virtualX, virtualY,
        self:_pointerId(pointerId), button)
end

function host:keyDown(key, scancode, isrepeat)
    assert(self._mounted, "Host is not mounted")
    assertPresentationAllowed(self, "route key input through")
    assertInputBoundary(self)
    if key == "f6" then
        Interaction.cancel(self, "inspector")
        self._inspectorVisible = true
        return true
    end
    if isrepeat then return self._modal ~= nil end
    if key == "escape" and Interaction.keyBack(self) then return true end
    local buttons, seen = {}, {}
    for _, inputRoot in ipairs(Interaction.inputRoots(self)) do
        local found = {}
        collectButtons(inputRoot, found, self._spentAuthorities)
        for _, button in ipairs(found) do
            if not seen[button.identity] then
                seen[button.identity] = true
                buttons[#buttons + 1] = button
            end
        end
    end
    if key == "tab" then
        if #buttons == 0 then return self._modal ~= nil end
        local nextIndex = 1
        for index, button in ipairs(buttons) do
            if button.identity == self._focusedIdentity then
                nextIndex = index % #buttons + 1
                break
            end
        end
        self._focusedIdentity = buttons[nextIndex].identity
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
        for _, button in ipairs(buttons) do
            local shortcut = button.props.shortcut
            local matches = shortcut == key
            if type(shortcut) == "table" then
                for _, accepted in ipairs(shortcut) do
                    if accepted == key then matches = true break end
                end
            end
            if matches then activated = button break end
        end
    end
    if activated and (activated.props.onPress or activated.props.onCommit) then
        self:_activateButton(activated)
        return true
    end
    return self._modal ~= nil
end

function host:keyUp(key)
    assert(self._mounted, "Host is not mounted")
    assertPresentationAllowed(self, "route key input through")
    assertInputBoundary(self)
    if key == "f6" then
        self._inspectorVisible = false
        self._selectedIdentity = nil
        return true
    end
    return self._modal ~= nil
end

function host:textInput(text)
    assert(self._mounted, "Host is not mounted")
    assertPresentationAllowed(self, "route text input through")
    assertInputBoundary(self)
    assert(type(text) == "string", "Host:textInput expects text")
    self._lastInputText = text
    return self._modal ~= nil
end

function host:setInspectorVisible(visible)
    assert(self._mounted, "Host is not mounted")
    assertPresentationAllowed(self, "change inspector state in")
    assert(type(visible) == "boolean", "inspector visibility must be boolean")
    if visible and not self._inspectorVisible then
        Interaction.cancel(self, "inspector")
    end
    self._inspectorVisible = visible
    if not visible then self._selectedIdentity = nil end
end

function host:inspect(x, y)
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
    Interaction.cancel(self, "unmount")
    self:_stageActorUnmounts(self._actors, {})
    self._captures = {}
    self._pressedIdentity = nil
    self._hoveredIdentity = nil
    self._focusedIdentity = nil
    self._selectedIdentity = nil
    self._tree = nil
    self._rootDescriptor = nil
    self._actors = {}
    self._addresses = {}
    self._semanticTokens = {}
    self._motions = {}
    self._scrolls = {}
    self._modals = {}
    self._modal = nil
    self._chrome = nil
    self._modalFocusStack = {}
    self._feedbackQueue = {}
    self._rawClock:reset()
    self._messageQueue = {}
    self._mounted = false
    if activeHost == self then activeHost = nil end
    local cleanupError = self:_commitActorUnmounts()
    if cleanupError then error(cleanupError, 0) end
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

function host:wheelMoved(dx, dy)
    assert(self._mounted, "Host is not mounted")
    assertPresentationAllowed(self, "route wheel input through")
    assertInputBoundary(self)
    assert(finite(dx) and finite(dy), "wheel delta must be finite")
    return Interaction.wheelMoved(self, dx, dy)
end

host.keypressed = host.keyDown
host.keyreleased = host.keyUp
host.textinput = host.textInput
host.wheelmoved = host.wheelMoved

return host
