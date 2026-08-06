-- Defines one self-animating text effect with an explicit finite lifetime.

local Clock = require("src.frogui.clock")
local Element = require("src.frogui.element")
local Juice = require("src.frogui.juice")

local PopupTextLeaf = Element.primitive("PopupText")

local VARIANTS = {
    float = {
        duration = 0.75,
        distance = 36,
        scale = 1,
        role = "body",
    },
    impact = {
        duration = 0.62,
        distance = 44,
        scale = 1.35,
        role = "impact",
        outlineWidth = 1,
        outlineColor = { 0, 0, 0, 0.95 },
        shadowOffset = 3,
        shadowColor = { 0, 0, 0, 0.95 },
        shine = 0.55,
        shineSplit = 0.46,
    },
    notice = {
        duration = 0.9,
        distance = 12,
        scale = 1.05,
        role = "heading",
    },
}

local ALLOWED_PROPS = {
    key = true,
    text = true,
    at = true,
    variant = true,
    duration = true,
    distance = true,
    delay = true,
    clock = true,
    onComplete = true,
    width = true,
    height = true,
    role = true,
    fontScale = true,
    color = true,
    wrap = true,
    maxLines = true,
    align = true,
    fitDown = true,
    outlineWidth = true,
    outlineColor = true,
    shadowOffset = true,
    shadowColor = true,
    shine = true,
    shineSplit = true,
    testId = true,
    children = true,
}

local function finite(value)
    return type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

-- Rejects misspelled convenience props before they disappear into the leaf.
local function validateProps(props)
    for name in pairs(props) do
        assert(ALLOWED_PROPS[name],
            "Frog.PopupText has unknown prop " .. tostring(name))
    end
    assert(type(props.key) == "string" or type(props.key) == "number",
        "Frog.PopupText requires a stable string/number key")
    assert(type(props.text) == "string" and props.text ~= "",
        "Frog.PopupText text must be a non-empty string")
    assert(type(props.at) == "table" and getmetatable(props.at) == nil,
        "Frog.PopupText at must be a plain { x, y } point")
    for name in pairs(props.at) do
        assert(name == "x" or name == "y",
            "Frog.PopupText at has unknown field " .. tostring(name))
    end
    assert(finite(props.at.x) and finite(props.at.y),
        "Frog.PopupText at.x/at.y must be finite numbers")
    assert(props.variant == nil or VARIANTS[props.variant],
        "Frog.PopupText variant must be float, impact, or notice")
    for _, name in ipairs({
        "duration", "distance", "delay", "shadowOffset",
    }) do
        local value = props[name]
        assert(value == nil or finite(value) and value >= 0,
            "Frog.PopupText " .. name .. " must be finite and non-negative")
    end
    for _, name in ipairs({ "shine", "shineSplit" }) do
        local value = props[name]
        assert(value == nil or finite(value) and value >= 0 and value <= 1,
            "Frog.PopupText " .. name .. " must be between 0 and 1")
    end
    assert(props.clock == nil or Clock.isClock(props.clock),
        "Frog.PopupText clock must come from Frog.clock")
    assert(props.onComplete == nil or type(props.onComplete) == "function",
        "Frog.PopupText onComplete must be a function")
    assert(#props.children == 0,
        "Frog.PopupText accepts text, not element children")
end

-- Builds the complete rise/fade recipe from one named visual variant.
local function lifetimeRecipe(props, variant)
    local duration = props.duration or variant.duration
    local distance = props.distance or variant.distance
    local fadeDelay = duration * 0.42
    local recipe = Juice.parallel {
        Juice.tween {
            to = { y = -distance },
            duration = duration,
            ease = "out_quad",
        },
        Juice.sequence {
            Juice.delay(fadeDelay),
            Juice.tween {
                to = { opacity = 0 },
                duration = duration - fadeDelay,
                ease = "in_quad",
            },
        },
    }
    if (props.delay or 0) > 0 then
        recipe = Juice.sequence { Juice.delay(props.delay), recipe }
    end
    if props.clock then recipe = Juice.withClock(props.clock, recipe) end
    return recipe, duration, distance
end

-- Renders one keyed popup. The EffectLayer positions `at` from its content
-- origin; Motion owns the relative trajectory and completion callback.
local PopupText = Element.component("PopupText", function(props)
    validateProps(props)
    local variant = VARIANTS[props.variant or "float"]
    local recipe, duration, distance = lifetimeRecipe(props, variant)
    return PopupTextLeaf {
        key = props.key,
        testId = props.testId,
        text = props.text,
        at = { x = props.at.x, y = props.at.y },
        variant = props.variant or "float",
        duration = duration,
        distance = distance,
        width = props.width,
        height = props.height,
        role = props.role or variant.role,
        fontScale = props.fontScale,
        color = props.color,
        wrap = props.wrap,
        maxLines = props.maxLines,
        align = props.align or "center",
        fitDown = props.fitDown,
        outlineWidth = props.outlineWidth == nil
            and variant.outlineWidth or props.outlineWidth,
        outlineColor = props.outlineColor or variant.outlineColor,
        shadowOffset = props.shadowOffset == nil
            and variant.shadowOffset or props.shadowOffset,
        shadowColor = props.shadowColor or variant.shadowColor,
        shine = props.shine == nil and variant.shine or props.shine,
        shineSplit = props.shineSplit == nil
            and variant.shineSplit or props.shineSplit,
        scale = variant.scale,
        juice = {
            lifetime = {
                recipe = recipe,
                key = props.key,
                onComplete = props.onComplete,
            },
        },
    }
end)

return PopupText
