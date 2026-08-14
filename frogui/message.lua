-- Defines stateful actor tokens, typed actions/events, declarative transitions,
-- addressed views, and their validation rules.

local Element = require("src.frogui.element")
local Juice = require("src.frogui.juice")

local message = {}

local recordTokens = setmetatable({}, { __mode = "k" })

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

local function denseArray(value, label)
    assert(type(value) == "table", label .. " must be an array")
    local count = 0
    for key in pairs(value) do
        assert(type(key) == "number" and key > 0 and key % 1 == 0,
            label .. " must be a dense array")
        count = math.max(count, key)
    end
    for index = 1, count do
        assert(value[index] ~= nil, label .. " must be a dense array")
    end
    return count
end

local function copyPayload(payload, label)
    if payload == nil then payload = {} end
    assert(type(payload) == "table", label .. " payload must be a table")
    local output = {}
    for key, value in pairs(payload) do output[key] = value end
    return output
end

local function containsBinding(value, seen)
    if type(value) ~= "table" then return false end
    if value.__frogBinding then return true end
    seen = seen or {}
    if seen[value] then return false end
    seen[value] = true
    for key, nested in pairs(value) do
        if containsBinding(key, seen) or containsBinding(nested, seen) then return true end
    end
    return false
end

local function assertAcyclic(value, label, active, complete)
    if type(value) ~= "table" or value.__frogBinding then return end
    active = active or {}
    complete = complete or {}
    assert(not active[value], label .. " may not contain cycles")
    if complete[value] then return end
    active[value] = true
    for key, nested in pairs(value) do
        assertAcyclic(key, label, active, complete)
        assertAcyclic(nested, label, active, complete)
    end
    active[value] = nil
    complete[value] = true
end

local function validateRecord(token, record)
    assert(type(record) == "table" and recordTokens[record] == token,
        token.name .. " expects a record created by its typed constructor")
    if token.validate and not containsBinding(record) then
        token.validate(record)
    end
    return record
end

local recordTokenMeta = {
    __call = function(token, payload)
        local record = copyPayload(payload, token.name)
        recordTokens[record] = token
        validateRecord(token, record)
        return record
    end,
    __tostring = function(token)
        return "FrogUI." .. token.messageKind .. "(" .. token.name .. ")"
    end,
}

local function namedToken(kind, name, validate)
    assert(type(name) == "string" and name ~= "", kind .. " name is required")
    assert(validate == nil or type(validate) == "function",
        name .. " validator must be a function")
    return setmetatable({
        __frogMessageToken = true,
        messageKind = kind,
        name = name,
        validate = validate,
        source = sourceOutsideFrogUI(),
    }, recordTokenMeta)
end

function message.action(name, validate)
    return namedToken("action", name, validate)
end

function message.event(name, validate)
    return namedToken("event", name, validate)
end

function message.token(record)
    return type(record) == "table" and recordTokens[record] or nil
end

function message.validate(record, expectedKind)
    local token = message.token(record)
    assert(token, "FrogUI message must come from a typed action/event constructor")
    if expectedKind then
        assert(token.messageKind == expectedKind,
            "expected a FrogUI " .. expectedKind .. ", received " .. token.messageKind)
    end
    return validateRecord(token, record), token
end

local function finite(value)
    return type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

-- Takes the defensive finite, acyclic, plain-data snapshot promised by every
-- delivered action/event. Bindings must already have resolved at this edge.
local function snapshotPlain(value, label, seen)
    local kind = type(value)
    if kind == "nil" or kind == "boolean" or kind == "string" then
        return value
    end
    if kind == "number" then
        assert(finite(value), label .. " contains a non-finite number")
        return value
    end
    assert(kind == "table" and getmetatable(value) == nil,
        label .. " must contain only plain data")
    assert(not value.__frogBinding,
        "Frog.prop/Frog.oneOf bindings must be resolved before delivery")
    seen = seen or {}
    assert(not seen[value], label .. " must be acyclic")
    seen[value] = true
    local output = {}
    for key, nested in pairs(value) do
        local keyKind = type(key)
        assert(keyKind == "string" or keyKind == "number"
                or keyKind == "boolean",
            label .. " keys must be scalar")
        if keyKind == "number" then
            assert(finite(key), label .. " contains a non-finite key")
        end
        output[key] = snapshotPlain(nested, label, seen)
    end
    seen[value] = nil
    return output
end

function message.snapshot(record, expectedKind)
    local _, token = message.validate(record, expectedKind)
    local output = snapshotPlain(record, token.name .. " payload")
    -- The validated copy is already detached plain data. Mark it directly
    -- instead of sending it back through the public constructor, which would
    -- copy and validate the same top-level payload a second time.
    recordTokens[output] = token
    return output, token
end

message.snapshotPlain = snapshotPlain

local addressMeta = {
    __tostring = function(address)
        return address.actor.name .. ":address(" .. address.name .. ")"
    end,
}

local viewMeta = {
    __call = function(view, input) return Element.construct(view, input) end,
    __tostring = function(view) return "FrogUI.view(" .. view.name .. ")" end,
}

local actorMethods = {}

function actorMethods:address(name)
    assert(type(name) == "string" and name ~= "", "actor address name is required")
    self._addresses = self._addresses or {}
    if not self._addresses[name] then
        self._addresses[name] = setmetatable({
            __frogAddress = true,
            actor = self,
            name = name,
            source = sourceOutsideFrogUI(),
        }, addressMeta)
    end
    return self._addresses[name]
end

function actorMethods:view(name, render)
    assert(type(name) == "string" and name ~= "", "view name is required")
    assert(type(render) == "function", name .. " view render must be a function")
    local token = {
        kind = "view",
        name = name,
        actor = self,
        render = render,
        source = sourceOutsideFrogUI(),
    }
    return setmetatable(token, viewMeta)
end

local actorMeta = {
    __index = actorMethods,
    __call = function(actor, input) return Element.construct(actor, input) end,
    __tostring = function(actor) return "FrogUI.actor(" .. actor.name .. ")" end,
}

local function validateActionDefinitions(name, actions)
    assert(type(actions) == "table", name .. " actions must be a table")
    for token, handler in pairs(actions) do
        assert(type(token) == "table" and token.__frogMessageToken
                and token.messageKind == "action",
            name .. " action keys must be Frog.action tokens")
        assert(type(handler) == "function" or type(handler) == "table",
            name .. " action handler for " .. token.name .. " must be a reducer or scalar map")
        assert(not message.isTransition(handler),
            name .. " action " .. token.name
                .. " must use a scalar map or reducer, not direct Frog.go")
        if type(handler) == "table" then
            local count = 0
            for state, target in pairs(handler) do
                count = count + 1
                assert(type(state) == "string" or type(state) == "number"
                        or type(state) == "boolean",
                    name .. " action " .. token.name
                        .. " scalar-map keys must be scalar states")
                assert(message.isTransition(target) or type(target) == "string"
                        or type(target) == "number" or type(target) == "boolean",
                    name .. " action " .. token.name
                        .. " scalar-map values must be scalar states or Frog.go")
            end
            assert(count > 0,
                name .. " action " .. token.name .. " scalar map may not be empty")
        end
    end
end

function message.actor(name, definition)
    assert(type(name) == "string" and name ~= "", "actor name is required")
    assert(type(definition) == "table", name .. " definition must be a table")
    assert(definition.initial ~= nil, name .. " initial state is required")
    assert(type(definition.initial) == "string" or type(definition.initial) == "number"
            or type(definition.initial) == "boolean" or type(definition.initial) == "table"
            or type(definition.initial) == "function",
        name .. " initial state must be a scalar, table, or function")
    validateActionDefinitions(name, definition.actions or {})
    if type(definition.initial) == "table" then
        for token, handler in pairs(definition.actions or {}) do
            assert(type(handler) == "function",
                name .. " uses table state, so action " .. token.name
                    .. " must use a reducer rather than a scalar map")
        end
    end
    assert(definition.reactions == nil or type(definition.reactions) == "table",
        name .. " reactions must be an array")
    if definition.reactions then denseArray(definition.reactions, name .. " reactions") end
    assert(definition.unmount == nil or type(definition.unmount) == "function",
        name .. " unmount must be a function")
    assert(type(definition.render) == "function", name .. " render must be a function")
    local allowed = {
        initial = true, actions = true, reactions = true,
        unmount = true, render = true,
    }
    for key in pairs(definition) do
        assert(allowed[key], "unknown " .. name .. " actor definition field " .. tostring(key))
    end
    return setmetatable({
        kind = "actor",
        name = name,
        definition = definition,
        source = sourceOutsideFrogUI(),
    }, actorMeta)
end

function message.isAddress(value)
    return type(value) == "table" and value.__frogAddress == true
end

-- Returns whether one value is a genuine actor, addressed-view, or typed
-- message definition token. Records created from a message use `token()`.
function message.isDefinitionToken(value)
    if type(value) ~= "table" then return false end
    local meta = getmetatable(value)
    return meta == actorMeta or meta == viewMeta or meta == recordTokenMeta
end

local function binding(kind, value)
    return { __frogBinding = kind, value = value }
end

function message.prop(name)
    assert(type(name) == "string" and name ~= "", "Frog.prop name is required")
    return binding("prop", name)
end

function message.oneOf(values)
    local count = denseArray(values, "Frog.oneOf values")
    assert(count > 0, "Frog.oneOf requires at least one value")
    local copy = {}
    for index = 1, count do copy[index] = values[index] end
    return binding("oneOf", copy)
end

local function transition(value, options)
    options = options or {}
    assert(type(options) == "table", "Frog.go options must be a table")
    local allowed = { from = true, emit = true }
    for key in pairs(options) do assert(allowed[key], "unknown Frog.go option " .. tostring(key)) end
    if options.from ~= nil then
        assert(type(options.from) == "string" or type(options.from) == "number"
                or type(options.from) == "boolean" or type(options.from) == "table",
            "Frog.go from must be a scalar or array")
        if type(options.from) == "table" then
            local count = denseArray(options.from, "Frog.go from")
            assert(count > 0, "Frog.go from array may not be empty")
            for index = 1, count do
                local state = options.from[index]
                assert(type(state) == "string" or type(state) == "number"
                        or type(state) == "boolean",
                    "Frog.go from values must be scalar states")
            end
        end
    end
    if options.emit ~= nil then message.validate(options.emit, "event") end
    return {
        __frogTransition = true,
        value = value,
        from = options.from,
        emit = options.emit,
    }
end

function message.go(value, options)
    assert(type(value) == "string" or type(value) == "number"
            or type(value) == "boolean",
        "Frog.go target must be a scalar state; table state uses a reducer")
    return transition(value, options)
end

function message.isTransition(value)
    return type(value) == "table" and value.__frogTransition == true
end

local onMeta = {
    __call = function(builder, spec)
        spec = spec or {}
        assert(type(spec) == "table", "Frog.on reaction must be a table")
        local allowed = { match = true, transition = true, do_ = true }
        for key in pairs(spec) do
            assert(allowed[key], "unknown Frog.on field " .. tostring(key))
        end
        assert(spec.match == nil or type(spec.match) == "table",
            "Frog.on match must be a table")
        if spec.match then assertAcyclic(spec.match, "Frog.on match") end
        assert(spec.transition ~= nil or spec.do_ ~= nil,
            "Frog.on requires transition or do_")
        assert(spec.transition == nil or message.isTransition(spec.transition)
                or type(spec.transition) == "function",
            "Frog.on transition must be Frog.go or a reducer")
        assert(spec.do_ == nil or Juice.isPlay(spec.do_),
            "Frog.on do_ must be Frog.play(name)")
        return {
            __frogReaction = true,
            event = builder.event,
            match = spec.match,
            transition = spec.transition,
            do_ = spec.do_,
            source = sourceOutsideFrogUI(),
        }
    end,
}

function message.on(event)
    assert(type(event) == "table" and event.__frogMessageToken
            and event.messageKind == "event",
        "Frog.on expects a Frog.event token")
    return setmetatable({ event = event }, onMeta)
end

function message.isReaction(value)
    return type(value) == "table" and value.__frogReaction == true
end

function message.containsBinding(value)
    return containsBinding(value)
end

function message.resolve(value, props, mode, seen)
    if type(value) ~= "table" then return value end
    if value.__frogBinding == "prop" then
        assert(mode ~= "match" or true)
        return props[value.value]
    elseif value.__frogBinding == "oneOf" then
        assert(mode == "match", "Frog.oneOf is only valid in reaction matches")
        return value
    end
    seen = seen or {}
    assert(not seen[value], "FrogUI message payloads may not contain cycles")
    seen[value] = true
    local output = {}
    for key, nested in pairs(value) do
        output[message.resolve(key, props, mode, seen)] = message.resolve(nested, props, mode, seen)
    end
    seen[value] = nil
    return output
end

function message.matches(pattern, value, props)
    if pattern == nil then return true end
    if type(pattern) == "table" and pattern.__frogBinding == "prop" then
        return value == props[pattern.value]
    end
    if type(pattern) == "table" and pattern.__frogBinding == "oneOf" then
        for _, candidate in ipairs(pattern.value) do
            if value == candidate then return true end
        end
        return false
    end
    if type(pattern) ~= "table" then return pattern == value end
    if type(value) ~= "table" then return false end
    for key, expected in pairs(pattern) do
        if not message.matches(expected, value[key], props) then return false end
    end
    return true
end

return message
