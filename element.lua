-- Defines callable primitive/component tokens and the lightweight UI
-- descriptions produced when application code calls those tokens.

local element = {}

-- One private Host-owned allocation probe may observe source, identity, or
-- tree construction at a time. This is deliberately not FrogUI's public API;
-- the Battle performance harness owns the temporary observer.
local allocationProbeOwner
local sourceAllocationProbe
local structureAllocationProbe
local renderSourceOwner
local renderSource

function element._attachAllocationProbe(owner, probe)
    assert(owner ~= nil, "FrogUI allocation probe requires an owner")
    assert(allocationProbeOwner == nil,
        "another FrogUI allocation probe is already attached")
    assert(type(probe) == "table"
            and (probe.mode == "source" or probe.mode == "identity"
                or probe.mode == "structure"),
        "FrogUI allocation probe mode must be source, identity, or structure")
    allocationProbeOwner = owner
    sourceAllocationProbe = probe.mode == "source" and probe or nil
    structureAllocationProbe = probe.mode == "structure" and probe or nil
end

function element._detachAllocationProbe(owner)
    assert(allocationProbeOwner == owner,
        "FrogUI allocation probe detach owner mismatch")
    allocationProbeOwner = nil
    sourceAllocationProbe = nil
    structureAllocationProbe = nil
end

-- Descriptions created by one semantic render share that component, actor, or
-- view's permanent definition source. The Host brackets each render exactly;
-- descriptions created outside a render retain the one-shot caller fallback.
function element._beginRenderSource(owner, source)
    assert(owner ~= nil, "FrogUI render source requires an owner")
    assert(renderSourceOwner == nil,
        "another FrogUI semantic render already owns description provenance")
    renderSourceOwner = owner
    renderSource = source
end

function element._endRenderSource(owner)
    assert(renderSourceOwner == owner,
        "FrogUI render source end owner mismatch")
    renderSourceOwner = nil
    renderSource = nil
end

local function captureSource(excludedPath)
    local probe = sourceAllocationProbe
    local before = probe and collectgarbage("count") or nil
    local lookups = 0
    if not debug or not debug.getinfo then
        if probe then
            local after = collectgarbage("count")
            probe.sourceCalls = probe.sourceCalls + 1
            probe.sourceAllocatedKB = probe.sourceAllocatedKB + after - before
        end
        return nil
    end
    for level = 3, 16 do
        local info = debug.getinfo(level, "Sl")
        if probe then lookups = lookups + 1 end
        if not info then break end
        local path = info.short_src or info.source
        if path and not path:find(excludedPath, 1, true) then
            local result = { path = path, line = info.currentline }
            if probe then
                local after = collectgarbage("count")
                probe.sourceCalls = probe.sourceCalls + 1
                probe.sourceAllocatedKB = probe.sourceAllocatedKB
                    + after - before
                probe.sourceResults = probe.sourceResults + 1
                probe.sourceResultBytes = probe.sourceResultBytes + #path
                probe.sourceDebugLookups = probe.sourceDebugLookups + lookups
            end
            return result
        end
    end
    if probe then
        local after = collectgarbage("count")
        probe.sourceCalls = probe.sourceCalls + 1
        probe.sourceAllocatedKB = probe.sourceAllocatedKB + after - before
        probe.sourceDebugLookups = probe.sourceDebugLookups + lookups
    end
    return nil
end

local function sourceOutsideFrogUI()
    local result = captureSource("src/frogui/")
    return result
end

-- Captures a reusable component definition once. Unlike the descriptor
-- fallback, framework-owned components deliberately keep their own file:line
-- instead of borrowing whichever application module first required FrogUI.
local function componentSource()
    local result = captureSource("src/frogui/element.lua")
    return result
end

local function descriptionSource(token)
    if token.source ~= nil then return token.source end
    if renderSourceOwner ~= nil then return renderSource end
    return sourceOutsideFrogUI()
end

local function isPositiveInteger(value)
    return type(value) == "number" and value > 0 and value % 1 == 0
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

local EMPTY_INPUT = {}

-- Splits named props from ordered children. Dense arrays take no indexing
-- scratch table; sparse or very high indexes retain the exact sorted behavior
-- without scanning every hole. Text shorthand is normalized in the same pass.
local function splitInput(token, input)
    if input == nil then input = EMPTY_INPUT end
    if type(input) ~= "table" then
        assert(token.kind == "primitive" and token.name == "Text",
            token.name .. " expects a props table")
        return { text = tostring(input) }, {}
    end

    local props = {}
    local numericCount = 0
    local maximumIndex = 0
    for key, value in pairs(input) do
        if type(key) == "number" then
            assert(isPositiveInteger(key),
                "FrogUI numeric props must be positive integer child indexes")
            numericCount = numericCount + 1
            maximumIndex = math.max(maximumIndex, key)
        else
            props[key] = value
        end
    end

    local indexes
    if maximumIndex ~= numericCount then
        indexes = {}
        for key in pairs(input) do
            if type(key) == "number" then
                indexes[#indexes + 1] = key
            end
        end
        table.sort(indexes)
    end

    local children = {}
    if token.kind == "primitive" and token.name == "Text" then
        local valueCount = 0
        local onlyValue
        for position = 1, numericCount do
            local index = indexes and indexes[position] or position
            local value = input[index]
            if value ~= nil and value ~= false then
                valueCount = valueCount + 1
                if valueCount == 1 then onlyValue = value end
            end
        end
        if props.text == nil and valueCount == 1
                and (type(onlyValue) == "string"
                    or type(onlyValue) == "number") then
            props.text = tostring(onlyValue)
            valueCount = 0
        end
        assert(valueCount == 0,
            "Frog.Text accepts text, not element children")
    else
        for position = 1, numericCount do
            local index = indexes and indexes[position] or position
            addChild(children, input[index])
        end
    end

    return props, children
end

local function validateSiblingKeys(children, owner)
    local firstTyped
    local seen
    for _, child in ipairs(children) do
        local key = child.key
        if key ~= nil then
            assert(type(key) == "string" or type(key) == "number",
                owner .. " child keys must be strings or numbers")
            local typed = type(key) .. ":" .. tostring(key)
            if firstTyped == nil then
                firstTyped = typed
            elseif seen == nil then
                assert(firstTyped ~= typed,
                    owner .. " has duplicate child key " .. tostring(key))
                seen = { [firstTyped] = true, [typed] = true }
            else
                assert(not seen[typed],
                    owner .. " has duplicate child key " .. tostring(key))
                seen[typed] = true
            end
        end
    end
end

local function construct(token, input)
    local probe = structureAllocationProbe
    local before = probe and collectgarbage("count") or nil
    local props, children = splitInput(token, input)
    if token.kind == "primitive" then
        if token.name == "Box" or token.name == "Button"
                or token.name == "Motion" then
            assert(#children <= 1,
                "Frog." .. token.name .. " accepts at most one child")
    elseif token.name == "Text" or token.name == "PopupText"
            or token.name == "Image" or token.name == "Icon" then
        assert(#children == 0,
            "Frog." .. token.name .. " does not accept children")
        end
    end
    validateSiblingKeys(children, token.name)
    local result = {
        __frogDescriptor = true,
        token = token,
        props = props,
        children = children,
        key = props.key,
        source = descriptionSource(token),
    }
    if probe then
        local after = collectgarbage("count")
        probe.descriptorCalls = probe.descriptorCalls + 1
        probe.descriptorAllocatedKB = probe.descriptorAllocatedKB
            + after - before
    end
    return result
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
    return setmetatable({
        kind = "component",
        name = name,
        render = render,
        source = componentSource(),
    }, tokenMeta)
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
