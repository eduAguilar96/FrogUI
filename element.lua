-- Defines callable primitive/component tokens and the lightweight UI
-- descriptions produced when application code calls those tokens.

local element = {}

local function sourceOutsideFrogUI()
    if not debug or not debug.getinfo then return nil end
    for level = 3, 14 do
        local info = debug.getinfo(level, "Sl")
        if not info then break end
        local path = info.short_src or info.source
        if path and not path:find("src/frogui/", 1, true) then
            return { path = path, line = info.currentline }
        end
    end
    return nil
end

local function isPositiveInteger(value)
    return type(value) == "number" and value > 0 and value % 1 == 0
end

local function numericValues(input)
    local indexes = {}
    for key in pairs(input) do
        if type(key) == "number" then
            assert(isPositiveInteger(key),
                "FrogUI numeric props must be positive integer child indexes")
            indexes[#indexes + 1] = key
        end
    end
    table.sort(indexes)

    local values = {}
    for _, index in ipairs(indexes) do
        local value = input[index]
        if value ~= nil and value ~= false then values[#values + 1] = value end
    end
    return values
end

local function descriptor(value)
    return type(value) == "table" and value.__frogDescriptor == true
end

local function addChild(out, child)
    if child == nil or child == false then return end
    if type(child) == "table" and child.__frogEach == true then
        for _, nested in ipairs(child) do addChild(out, nested) end
        return
    end
    assert(descriptor(child),
        "FrogUI children must be elements/components (received "
            .. type(child) .. ")")
    out[#out + 1] = child
end

local function splitInput(token, input)
    if input == nil then input = {} end
    if type(input) ~= "table" then
        assert(token.kind == "primitive" and token.name == "Text",
            token.name .. " expects a props table")
        input = { text = tostring(input) }
    end

    local props = {}
    for key, value in pairs(input) do
        if not isPositiveInteger(key) then props[key] = value end
    end

    local children = {}
    local values = numericValues(input)
    if token.kind == "primitive" and token.name == "Text" then
        if props.text == nil and #values == 1
                and (type(values[1]) == "string" or type(values[1]) == "number") then
            props.text = tostring(values[1])
            values = {}
        end
        assert(#values == 0, "Frog.Text accepts text, not element children")
    else
        for _, child in ipairs(values) do addChild(children, child) end
    end

    return props, children
end

local function validateSiblingKeys(children, owner)
    local seen = {}
    for _, child in ipairs(children) do
        local key = child.key
        if key ~= nil then
            assert(type(key) == "string" or type(key) == "number",
                owner .. " child keys must be strings or numbers")
            local typed = type(key) .. ":" .. tostring(key)
            assert(not seen[typed], owner .. " has duplicate child key " .. tostring(key))
            seen[typed] = true
        end
    end
end

local function construct(token, input)
    local props, children = splitInput(token, input)
    if token.kind == "primitive" then
        if token.name == "Box" or token.name == "Button"
                or token.name == "Motion" then
            assert(#children <= 1,
                "Frog." .. token.name .. " accepts at most one child")
    elseif token.name == "Text" or token.name == "Image"
            or token.name == "Icon" then
        assert(#children == 0,
            "Frog." .. token.name .. " does not accept children")
        end
    end
    validateSiblingKeys(children, token.name)
    return {
        __frogDescriptor = true,
        token = token,
        props = props,
        children = children,
        key = props.key,
        source = sourceOutsideFrogUI(),
    }
end

element.construct = construct

local tokenMeta = {
    __call = function(token, input)
        return construct(token, input)
    end,
    __tostring = function(token)
        return "FrogUI." .. token.name
    end,
}

function element.primitive(name)
    return setmetatable({ kind = "primitive", name = name }, tokenMeta)
end

function element.component(name, render)
    assert(type(name) == "string" and name ~= "", "component name is required")
    assert(type(render) == "function", name .. " render must be a function")
    return setmetatable({ kind = "component", name = name, render = render }, tokenMeta)
end

function element.each(array, render)
    assert(type(array) == "table", "Frog.each expects an array")
    assert(type(render) == "function", "Frog.each expects a render function")
    local result = { __frogEach = true }
    local seen = {}
    local indexes = {}
    for key in pairs(array) do
        if type(key) == "number" then
            assert(isPositiveInteger(key), "Frog.each expects a dense array")
            indexes[#indexes + 1] = key
        else
            assert(key == "n", "Frog.each expects an array without named fields")
        end
    end
    table.sort(indexes)
    for expected, index in ipairs(indexes) do
        assert(index == expected, "Frog.each expects a dense array")
        local value = array[index]
        local child = render(value, index)
        if child ~= nil and child ~= false then
            assert(descriptor(child), "Frog.each render must return an element or nil")
            assert(child.key ~= nil,
                "Frog.each children require a stable key (item " .. index .. ")")
            assert(type(child.key) == "string" or type(child.key) == "number",
                "Frog.each keys must be strings or numbers")
            local typed = type(child.key) .. ":" .. tostring(child.key)
            assert(not seen[typed], "Frog.each has duplicate key " .. tostring(child.key))
            seen[typed] = true
            result[#result + 1] = child
        end
    end
    return result
end

function element.isDescriptor(value)
    return descriptor(value)
end

return element
