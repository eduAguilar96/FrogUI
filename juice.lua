-- Defines the small declarative motion/feedback recipe vocabulary. Recipes
-- are inert data until a mounted Host plays them on an element.

local Clock = require("src.frogui.clock")

local juice = {}

local PROPERTIES = {
    x = true, y = true, rotation = true, scale = true,
    opacity = true, tint = true,
}

local EASES = {
    linear = true, in_quad = true, out_quad = true, in_out_quad = true,
}

local function finite(value)
    return type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

local function positive(value, label, allowZero)
    assert(finite(value) and (allowZero and value >= 0 or value > 0),
        label .. " must be a finite " .. (allowZero and "non-negative" or "positive")
            .. " number")
    return value
end

local function recipe(kind, fields)
    fields.__frogRecipe = true
    fields.kind = kind
    return fields
end

local function isColor(value)
    if type(value) ~= "table" then return false end
    local r, g, b = value[1] or value.r, value[2] or value.g, value[3] or value.b
    local a = value[4]
    if a == nil then a = value.a end
    if a == nil then a = 1 end
    return finite(r) and finite(g) and finite(b) and finite(a)
        and r >= 0 and r <= 1 and g >= 0 and g <= 1
        and b >= 0 and b <= 1 and a >= 0 and a <= 1
end

local function properties(input, label)
    assert(type(input) == "table", label .. " must be a property table")
    local out = {}
    local count = 0
    for name, value in pairs(input) do
        assert(PROPERTIES[name], label .. " has unknown property " .. tostring(name))
        if name == "tint" then
            assert(isColor(value), label .. ".tint must be a numeric color")
        elseif name == "opacity" then
            assert(finite(value) and value >= 0 and value <= 1,
                label .. ".opacity must be between 0 and 1")
        elseif name == "scale" then
            assert(finite(value) and value >= 0,
                label .. ".scale must be finite and non-negative")
        else
            assert(finite(value), label .. "." .. name .. " must be finite")
        end
        out[name] = value
        count = count + 1
    end
    assert(count > 0, label .. " must change at least one property")
    return out
end

local function copyRecipe(value)
    local out = {}
    for key, nested in pairs(value) do
        if key == "clock" then
            out[key] = nested
        elseif type(nested) == "table" then
            local copy = {}
            for childKey, childValue in pairs(nested) do
                copy[childKey] = type(childValue) == "table"
                    and copyRecipe(childValue) or childValue
            end
            out[key] = copy
        else
            out[key] = nested
        end
    end
    return out
end

local function onlyFields(input, allowed, label)
    for key in pairs(input) do
        assert(allowed[key], label .. " has unknown field " .. tostring(key))
    end
end

-- Moves declared presentation properties from their current values to `to`.
function juice.tween(spec)
    assert(type(spec) == "table", "Frog.tween expects a table")
    onlyFields(spec, { to = true, duration = true, ease = true }, "Frog.tween")
    local ease = spec.ease or "linear"
    assert(EASES[ease], "Frog.tween has unsupported ease " .. tostring(ease))
    return recipe("tween", {
        to = properties(spec.to, "Frog.tween.to"),
        duration = positive(spec.duration, "Frog.tween duration", true),
        ease = ease,
    })
end

-- Settles declared presentation properties with a deterministic damped curve.
function juice.spring(spec)
    assert(type(spec) == "table", "Frog.spring expects a table")
    onlyFields(spec, { to = true, frequency = true, damping = true }, "Frog.spring")
    return recipe("spring", {
        to = properties(spec.to, "Frog.spring.to"),
        frequency = positive(spec.frequency or 12, "Frog.spring frequency"),
        damping = positive(spec.damping or 1, "Frog.spring damping"),
    })
end

-- Adds a decaying deterministic impact displacement, then returns to rest.
function juice.shake(spec)
    spec = spec or {}
    assert(type(spec) == "table", "Frog.shake expects a table")
    onlyFields(spec, {
        x = true, y = true, rotation = true,
        duration = true, frequency = true,
    }, "Frog.shake")
    for _, name in ipairs({ "x", "y", "rotation" }) do
        assert(spec[name] == nil or finite(spec[name]),
            "Frog.shake " .. name .. " must be finite")
    end
    return recipe("shake", {
        x = spec.x or 0,
        y = spec.y or 0,
        rotation = spec.rotation or 0,
        duration = positive(spec.duration or 0.15, "Frog.shake duration", true),
        frequency = positive(spec.frequency or 24, "Frog.shake frequency"),
    })
end

local function feedback(kind, spec)
    assert(type(spec) == "table", "Frog." .. kind .. " expects a table")
    onlyFields(spec, { cue = true }, "Frog." .. kind)
    assert(type(spec.cue) == "string" and spec.cue ~= "",
        "Frog." .. kind .. " cue must be a non-empty string")
    return recipe(kind, { cue = spec.cue })
end

-- Requests one named sound cue from the Host feedback service.
function juice.sound(spec)
    return feedback("sound", spec)
end

-- Requests one named haptic cue from the Host feedback service.
function juice.haptic(spec)
    return feedback("haptic", spec)
end

-- Holds the current presentation values for a deterministic duration.
function juice.delay(seconds)
    return recipe("delay", {
        duration = positive(seconds, "Frog.delay", true),
    })
end

local function recipeArray(input, label)
    assert(type(input) == "table", label .. " expects an array of recipes")
    local out = {}
    for index, child in ipairs(input) do
        assert(juice.isRecipe(child), label .. " item " .. index .. " is not a recipe")
        out[index] = copyRecipe(child)
    end
    assert(#out > 0, label .. " needs at least one recipe")
    for key in pairs(input) do
        assert(type(key) == "number" and key >= 1 and key % 1 == 0
                and key <= #out,
            label .. " expects a dense array without named fields")
    end
    return out
end

-- Runs recipes in listed order, carrying each result into the next.
function juice.sequence(recipes)
    return recipe("sequence", { recipes = recipeArray(recipes, "Frog.sequence") })
end

-- Runs independent recipes at the same time. Later recipes own any property
-- both branches write; additive shake is combined by the runtime.
function juice.parallel(recipes)
    return recipe("parallel", { recipes = recipeArray(recipes, "Frog.parallel") })
end

-- Repeats a recipe a finite number of times or forever when count is omitted.
function juice.loop(child, count)
    assert(juice.isRecipe(child), "Frog.loop expects a recipe")
    if count ~= nil then
        assert(finite(count) and count >= 1 and count % 1 == 0
                and count <= 10000,
            "Frog.loop count must be a positive integer at most 10000")
    end
    return recipe("loop", { recipe = copyRecipe(child), count = count })
end

-- Selects an explicit deterministic clock instead of the Host raw clock.
function juice.withClock(value, child)
    assert(Clock.isClock(value), "Frog.withClock expects a Frog.clock")
    assert(juice.isRecipe(child), "Frog.withClock expects a recipe")
    return recipe("with_clock", { clock = value, recipe = copyRecipe(child) })
end

-- Creates the reaction instruction consumed by `Frog.on(...).do_`.
function juice.play(name)
    assert(type(name) == "string" and name ~= "",
        "Frog.play expects a non-empty recipe name")
    return { __frogPlay = true, name = name }
end

function juice.isRecipe(value)
    return type(value) == "table" and value.__frogRecipe == true
end

function juice.isPlay(value)
    return type(value) == "table" and value.__frogPlay == true
end

function juice.isColor(value)
    return isColor(value)
end

function juice.properties()
    local out = {}
    for name in pairs(PROPERTIES) do out[name] = true end
    return out
end

-- Takes the defensive recipe snapshot retained by a mounted element. This is
-- internal framework vocabulary; application code uses the constructors.
function juice.snapshot(value)
    assert(juice.isRecipe(value), "FrogUI expected a juice recipe")
    return copyRecipe(value)
end

return juice
