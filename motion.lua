-- Retains and evaluates per-element Motion/juice state. Application code
-- declares recipes; this runtime alone advances presentation properties.

local Juice = require("src.frogui.juice")

local motion = {}

local composeActive

local DEFAULT_VALUES = {
    x = 0, y = 0, rotation = 0, scale = 1, opacity = 1,
}

local SPRINGS = {
    gentle = { frequency = 8, damping = 1 },
    snappy = { frequency = 14, damping = 0.82 },
    bouncy = { frequency = 11, damping = 0.55 },
}

-- Motion and PopupText both declare presentation targets directly. Other
-- primitives may own named juice without turning their static props into
-- animated targets.
local function ownsMotionTargets(node)
    return node.type == "Motion" or node.type == "PopupText"
end

local function finite(value)
    return type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

local function copyColor(value)
    if value == nil then return nil end
    return {
        value[1] or value.r, value[2] or value.g, value[3] or value.b,
        value[4] or value.a or 1,
    }
end

local function copyValues(values)
    local out = {}
    for name, fallback in pairs(DEFAULT_VALUES) do
        local value = values and values[name]
        out[name] = value == nil and fallback or value
    end
    out.tint = copyColor(values and values.tint)
    return out
end

local function sameValue(left, right)
    if left == right then return true end
    if type(left) ~= "table" or type(right) ~= "table" then return false end
    for index = 1, 4 do
        local a = left[index]
        if a == nil and index == 4 then a = 1 end
        local b = right[index]
        if b == nil and index == 4 then b = 1 end
        if a ~= b then return false end
    end
    return true
end

local function setValue(values, name, value)
    values[name] = name == "tint" and copyColor(value) or value
end

local function sortedKeys(input)
    local out = {}
    for key in pairs(input) do out[#out + 1] = key end
    table.sort(out)
    return out
end

local function lerp(left, right, amount)
    return left + (right - left) * amount
end

local function lerpValue(left, right, amount)
    if type(right) ~= "table" then return lerp(left, right, amount) end
    left = left or { 1, 1, 1, 1 }
    local out = {}
    for index = 1, 4 do
        local a = left[index]
        if a == nil and index == 4 then a = 1 end
        local b = right[index]
        if b == nil and index == 4 then b = 1 end
        out[index] = lerp(a, b, amount)
    end
    return out
end

local function eased(name, amount)
    if name == "in_quad" then return amount * amount end
    if name == "out_quad" then return 1 - (1 - amount) * (1 - amount) end
    if name == "in_out_quad" then
        if amount < 0.5 then return 2 * amount * amount end
        return 1 - ((-2 * amount + 2) ^ 2) / 2
    end
    return amount
end

local function duration(recipe)
    local kind = recipe.kind
    if kind == "tween" or kind == "shake" or kind == "delay" then
        return recipe.duration
    elseif kind == "spring" then
        return math.max(0.1, 7 / (recipe.frequency * recipe.damping))
    elseif kind == "sound" or kind == "haptic" then
        return 0
    elseif kind == "with_clock" then
        return duration(recipe.recipe)
    elseif kind == "sequence" then
        local total = 0
        for _, child in ipairs(recipe.recipes) do total = total + duration(child) end
        return total
    elseif kind == "parallel" then
        local longest = 0
        for _, child in ipairs(recipe.recipes) do
            longest = math.max(longest, duration(child))
        end
        return longest
    elseif kind == "loop" then
        local childDuration = duration(recipe.recipe)
        assert(childDuration > 0,
            "Frog.loop cannot repeat a zero-duration recipe")
        return recipe.count and childDuration * recipe.count or math.huge
    end
    error("unknown FrogUI recipe kind " .. tostring(kind), 0)
end

local function writtenProperties(recipe, out)
    out = out or {}
    local kind = recipe.kind
    if kind == "tween" or kind == "spring" then
        for name in pairs(recipe.to) do out[name] = "replace" end
    elseif kind == "shake" then
        if recipe.x ~= 0 then out.x = out.x or "add" end
        if recipe.y ~= 0 then out.y = out.y or "add" end
        if recipe.rotation ~= 0 then out.rotation = out.rotation or "add" end
    elseif kind == "sequence" or kind == "parallel" then
        for _, child in ipairs(recipe.recipes) do writtenProperties(child, out) end
    elseif kind == "loop" or kind == "with_clock" then
        writtenProperties(recipe.recipe, out)
    end
    return out
end

local sample

local function finalValues(recipe, base)
    local total = duration(recipe)
    if total == math.huge then return copyValues(base) end
    return sample(recipe, total, base)
end

sample = function(recipe, elapsed, base)
    local kind = recipe.kind
    local values = copyValues(base)
    if kind == "tween" then
        local amount = recipe.duration == 0 and 1
            or math.min(1, math.max(0, elapsed / recipe.duration))
        amount = eased(recipe.ease, amount)
        for name, target in pairs(recipe.to) do
            values[name] = lerpValue(values[name], target, amount)
        end
    elseif kind == "spring" then
        local total = duration(recipe)
        local amount
        if elapsed >= total then
            amount = 1
        else
            local time = math.max(0, elapsed)
            local decay = math.exp(-recipe.frequency * recipe.damping * time)
            amount = 1 - decay * math.cos(recipe.frequency * time)
        end
        for name, target in pairs(recipe.to) do
            values[name] = lerpValue(values[name], target, amount)
        end
    elseif kind == "shake" then
        if recipe.duration > 0 and elapsed < recipe.duration then
            local progress = math.max(0, elapsed) / recipe.duration
            local envelope = (1 - progress) * (1 - progress)
            local phase = math.max(0, elapsed) * recipe.frequency * math.pi * 2
            values.x = values.x + math.sin(phase) * recipe.x * envelope
            values.y = values.y + math.sin(phase * 1.17 + 1.3) * recipe.y * envelope
            values.rotation = values.rotation
                + math.sin(phase * 0.83 + 2.1) * recipe.rotation * envelope
        end
    elseif kind == "sequence" then
        local remaining = math.max(0, elapsed)
        for _, child in ipairs(recipe.recipes) do
            local childDuration = duration(child)
            if remaining < childDuration then
                return sample(child, remaining, values)
            end
            values = finalValues(child, values)
            remaining = remaining - childDuration
        end
    elseif kind == "parallel" then
        for _, child in ipairs(recipe.recipes) do
            local branch = sample(child, elapsed, base)
            for name, mode in pairs(writtenProperties(child)) do
                if mode == "add" then
                    values[name] = values[name] + branch[name] - base[name]
                else
                    values[name] = name == "tint"
                        and copyColor(branch[name]) or branch[name]
                end
            end
        end
    elseif kind == "loop" then
        local childDuration = duration(recipe.recipe)
        local completed = math.floor(math.max(0, elapsed) / childDuration)
        if recipe.count then completed = math.min(completed, recipe.count) end
        if completed > 0 then values = finalValues(recipe.recipe, values) end
        if not recipe.count or completed < recipe.count then
            local localTime = math.max(0, elapsed) - completed * childDuration
            values = sample(recipe.recipe, localTime, values)
        end
    elseif kind == "with_clock" then
        values = sample(recipe.recipe, elapsed, values)
    elseif kind ~= "delay" and kind ~= "sound" and kind ~= "haptic" then
        error("unknown FrogUI recipe kind " .. tostring(kind), 0)
    end
    return values
end

local function callFeedback(host, kind, cue)
    host:_stageFeedback(kind, cue)
end

local function emitFeedback(recipe, previous, current, host, offset, budget)
    offset = offset or 0
    budget = budget or { remaining = 1024 }
    local kind = recipe.kind
    if kind == "sound" or kind == "haptic" then
        if previous < offset and current >= offset then
            budget.remaining = budget.remaining - 1
            assert(budget.remaining >= 0,
                "FrogUI recipe emitted more than 1024 feedback cues in one update")
            callFeedback(host, kind, recipe.cue)
        end
    elseif kind == "sequence" then
        local cursor = offset
        for _, child in ipairs(recipe.recipes) do
            emitFeedback(child, previous, current, host, cursor, budget)
            cursor = cursor + duration(child)
        end
    elseif kind == "parallel" then
        for _, child in ipairs(recipe.recipes) do
            emitFeedback(child, previous, current, host, offset, budget)
        end
    elseif kind == "loop" then
        local childDuration = duration(recipe.recipe)
        local first = math.max(0, math.floor((previous - offset) / childDuration))
        local last = math.max(0, math.floor((current - offset) / childDuration))
        if recipe.count then last = math.min(last, recipe.count - 1) end
        assert(last - first + 1 <= 1024,
            "FrogUI loop crossed more than 1024 cycles in one update")
        for cycle = first, last do
            emitFeedback(recipe.recipe, previous, current, host,
                offset + cycle * childDuration, budget)
        end
    elseif kind == "with_clock" then
        emitFeedback(recipe.recipe, previous, current, host, offset, budget)
    end
end

local function emitAllFeedback(recipe, host)
    local kind = recipe.kind
    if kind == "sound" or kind == "haptic" then
        callFeedback(host, kind, recipe.cue)
    elseif kind == "sequence" or kind == "parallel" then
        for _, child in ipairs(recipe.recipes) do emitAllFeedback(child, host) end
    elseif kind == "loop" or kind == "with_clock" then
        emitAllFeedback(recipe.recipe, host)
    end
end

local function unwrap(recipe, rawClock)
    if recipe.kind == "with_clock" then return recipe.recipe, recipe.clock end
    return recipe, rawClock
end

local function cloneRunner(runner)
    return {
        recipe = runner.recipe,
        clock = runner.clock,
        startedAt = runner.startedAt,
        previous = runner.previous,
        base = copyValues(runner.base),
        order = runner.order,
        clockKind = runner.clockKind,
        bindingKey = runner.bindingKey,
    }
end

local function cloneInstance(old)
    local instance = {
        identity = old.identity,
        order = old.order,
        props = old.props,
        reactions = old.reactions,
        source = old.source,
        primitiveType = old.primitiveType,
        eventOrder = old.eventOrder,
        reducedMotion = old.reducedMotion,
        values = copyValues(old.values),
        settled = copyValues(old.settled),
        recipes = {},
        bindingKeys = {},
        active = {},
        motionTargets = {},
        node = old.node,
        lifetime = old.lifetime,
        pendingCompletions = {},
        latestStarts = {},
    }
    for name, binding in pairs(old.recipes) do
        instance.recipes[name] = {
            recipe = binding.recipe,
            key = binding.key,
            onComplete = binding.onComplete,
        }
    end
    for name, key in pairs(old.bindingKeys) do instance.bindingKeys[name] = key end
    for name, runner in pairs(old.active) do instance.active[name] = cloneRunner(runner) end
    for name, pending in pairs(old.pendingCompletions or {}) do
        instance.pendingCompletions[name] = {
            key = pending.key,
            order = pending.order,
        }
    end
    for name, order in pairs(old.latestStarts or {}) do
        instance.latestStarts[name] = order
    end
    for name, value in pairs(old.motionTargets) do
        instance.motionTargets[name] = name == "tint" and copyColor(value) or value
    end
    return instance
end

local function validateClockPlacement(recipe, root)
    if recipe.kind == "with_clock" then
        assert(root,
            "Frog.withClock must wrap the entire named juice recipe")
        validateClockPlacement(recipe.recipe, false)
    elseif recipe.kind == "sequence" or recipe.kind == "parallel" then
        for _, child in ipairs(recipe.recipes) do
            validateClockPlacement(child, false)
        end
    elseif recipe.kind == "loop" then
        validateClockPlacement(recipe.recipe, false)
    end
end

local function parseBinding(name, value)
    if Juice.isRecipe(value) then
        local snapshot = Juice.snapshot(value)
        validateClockPlacement(snapshot, true)
        duration(snapshot)
        return { recipe = snapshot }
    end
    assert(type(value) == "table" and Juice.isRecipe(value.recipe),
        "juice." .. tostring(name)
            .. " must be a recipe or { recipe, key, onComplete }")
    for key in pairs(value) do
        assert(key == "recipe" or key == "key" or key == "onComplete",
            "juice." .. tostring(name) .. " has unknown field " .. tostring(key))
    end
    assert(value.key == nil or type(value.key) == "string"
            or type(value.key) == "number" or type(value.key) == "boolean",
        "juice." .. tostring(name) .. " key must be a scalar")
    assert(value.onComplete == nil or type(value.onComplete) == "function",
        "juice." .. tostring(name) .. " onComplete must be a function")
    local snapshot = Juice.snapshot(value.recipe)
    validateClockPlacement(snapshot, true)
    local recipeDuration = duration(snapshot)
    assert(value.onComplete == nil or recipeDuration < math.huge,
        "juice." .. tostring(name)
            .. " cannot complete an infinite recipe")
    return {
        recipe = snapshot,
        key = value.key,
        onComplete = value.onComplete,
    }
end

local function validatedSpring(value, label)
    assert(type(value) == "table" and getmetatable(value) == nil,
        label .. " must be a plain { frequency, damping } table")
    for key in pairs(value) do
        assert(key == "frequency" or key == "damping",
            label .. " has unknown field " .. tostring(key))
    end
    local probe = Juice.spring {
        to = { x = 0 },
        frequency = value.frequency,
        damping = value.damping,
    }
    return { frequency = probe.frequency, damping = probe.damping }
end

local function springSpec(value, theme)
    if type(value) == "string" then
        local themed = theme.motion and theme.motion.springs
            and theme.motion.springs[value]
        local preset = themed or SPRINGS[value]
        assert(preset, "unknown Frog.Motion spring preset " .. value)
        return validatedSpring(preset,
            "Frog.Motion spring preset " .. value)
    end
    return validatedSpring(value, "Frog.Motion spring")
end

local function start(instance, name, host)
    local binding = assert(instance.recipes[name],
        "Frog.play references unknown juice recipe " .. tostring(name))
    local recipe, clock = unwrap(binding.recipe, host._rawClock)
    local runner = {
        recipe = recipe,
        clock = clock,
        startedAt = clock:now(),
        previous = -1e-12,
        base = copyValues(instance.values),
        order = host:_nextMotionOrder(),
        clockKind = binding.recipe.kind == "with_clock" and "explicit" or "raw",
        bindingKey = binding.key,
    }
    instance.latestStarts[name] = runner.order
    instance.pendingCompletions[name] = nil
    if host.reducedMotion then
        emitAllFeedback(recipe, host)
        local result = finalValues(recipe, runner.base)
        for property, mode in pairs(writtenProperties(recipe)) do
            if mode ~= "add" then setValue(instance.settled, property, result[property]) end
        end
        instance.values = copyValues(instance.settled)
        if binding.onComplete then
            instance.pendingCompletions[name] = {
                key = binding.key,
                order = runner.order,
            }
        end
        return
    end
    emitFeedback(recipe, runner.previous, 0, host)
    runner.previous = 0
    instance.active[name] = runner
    instance.values = sample(recipe, 0, runner.base)
end

local function reconcileMotionTargets(instance, props, host, firstMount)
    local changedAny = false
    for _, name in ipairs({ "x", "y", "rotation", "scale", "opacity", "tint" }) do
        local spec = props[name]
        if spec == nil then
            if instance.motionTargets[name] ~= nil then
                instance.motionTargets[name] = nil
                instance.active["$motion:" .. name] = nil
                instance.recipes["$motion:" .. name] = nil
                setValue(instance.settled, name, DEFAULT_VALUES[name])
                setValue(instance.values, name, DEFAULT_VALUES[name])
                changedAny = true
            end
        else
            local target, spring
            if type(spec) == "table" and spec.target ~= nil then
                for key in pairs(spec) do
                    assert(key == "target" or key == "spring",
                        "Frog.Motion " .. name .. " has unknown field " .. tostring(key))
                end
                target, spring = spec.target, springSpec(spec.spring or "gentle", host.theme)
            else
                target = spec
            end
            if name == "tint" then
                assert(Juice.isColor(target), "Frog.Motion tint target must be a numeric color")
            else
                assert(finite(target),
                    "Frog.Motion " .. name .. " target must be finite")
                assert(name ~= "opacity" or target >= 0 and target <= 1,
                    "Frog.Motion opacity target must be between 0 and 1")
                assert(name ~= "scale" or target >= 0,
                    "Frog.Motion scale target must be non-negative")
            end
            if spring then
                Juice.spring {
                    to = { [name] = target },
                    frequency = spring.frequency,
                    damping = spring.damping,
                }
            end
            local changed = not sameValue(instance.motionTargets[name], target)
            changedAny = changedAny or changed
            instance.motionTargets[name] = name == "tint" and copyColor(target) or target
            if firstMount or not spring or host.reducedMotion then
                setValue(instance.values, name, target)
                setValue(instance.settled, name, target)
                instance.active["$motion:" .. name] = nil
            elseif changed then
                local recipe = Juice.spring {
                    to = { [name] = target },
                    frequency = spring.frequency,
                    damping = spring.damping,
                }
                instance.recipes["$motion:" .. name] = { recipe = recipe }
                start(instance, "$motion:" .. name, host)
            end
        end
    end
    return changedAny
end

-- Reconciles one mounted primitive without mutating the committed instance.
function motion.reconcile(old, node, props, logicalIdentity, order, host)
    local compatible = old and old.primitiveType == node.type
    local instance = compatible and cloneInstance(old) or {
        identity = logicalIdentity,
        values = copyValues(),
        settled = copyValues(),
        recipes = {}, bindingKeys = {}, active = {}, motionTargets = {},
        lifetime = {}, pendingCompletions = {}, latestStarts = {},
    }
    instance.identity = logicalIdentity
    instance.order = order
    instance.eventOrder = order
    instance.primitiveType = node.type
    instance.props = props
    instance.reactions = props.reactions or {}
    instance.source = node.source
    instance.node = node
    instance.reducedMotion = host.reducedMotion

    -- First-mount Motion props are the authored entrance base. Establish them
    -- before keyed recipes snapshot `instance.values`; compatible rerenders
    -- deliberately keep recipe restart-before-target reconciliation semantics.
    if ownsMotionTargets(node) and not compatible then
        reconcileMotionTargets(instance, props, host, true)
    end

    local nextRecipes = {}
    for name, value in pairs(props.juice or {}) do
        assert(type(name) == "string" and name ~= "",
            "juice recipe names must be non-empty strings")
        nextRecipes[name] = parseBinding(name, value)
    end
    for name in pairs(instance.recipes) do
        if not nextRecipes[name] and name:sub(1, 8) ~= "$motion:" then
            instance.active[name] = nil
            instance.bindingKeys[name] = nil
            instance.pendingCompletions[name] = nil
            instance.latestStarts[name] = nil
        end
    end
    for _, name in ipairs(sortedKeys(nextRecipes)) do
        local binding = nextRecipes[name]
        instance.recipes[name] = binding
        if binding.key == nil then
            instance.bindingKeys[name] = nil
        elseif instance.bindingKeys[name] ~= binding.key then
            instance.bindingKeys[name] = binding.key
            start(instance, name, host)
        end
    end
    for index, reaction in ipairs(instance.reactions) do
        local recipeName = reaction.do_ and reaction.do_.name
        assert(recipeName and instance.recipes[recipeName],
            node.type .. " reaction " .. index .. " plays undeclared juice recipe "
                .. tostring(recipeName))
    end
    if ownsMotionTargets(node) and compatible then
        local targetsChanged = reconcileMotionTargets(instance, props, host,
            false)
        if targetsChanged and composeActive then
            instance.values = composeActive(instance)
        end
    end
    node._motion = instance
    node.presentation = copyValues(instance.values)
    return instance
end

-- Starts a named recipe after a typed element reaction accepts an event.
function motion.play(instance, instruction, host)
    assert(Juice.isPlay(instruction), "element reaction do_ must be Frog.play")
    start(instance, instruction.name, host)
    if instance.node then instance.node.presentation = copyValues(instance.values) end
end

local function runnerOrder(left, right)
    if left.runner.order ~= right.runner.order then
        return left.runner.order < right.runner.order
    end
    return left.name < right.name
end

local function applyRunner(values, runner, elapsed)
    local sampled = sample(runner.recipe, elapsed, runner.base)
    for property, mode in pairs(writtenProperties(runner.recipe)) do
        if mode == "add" then
            values[property] = values[property] + sampled[property] - runner.base[property]
        else
            setValue(values, property, sampled[property])
        end
    end
end

composeActive = function(instance)
    local ordered = {}
    for name, runner in pairs(instance.active) do
        ordered[#ordered + 1] = { name = name, runner = runner }
    end
    table.sort(ordered, runnerOrder)
    local values = copyValues(instance.settled)
    for _, entry in ipairs(ordered) do
        local runner = entry.runner
        applyRunner(values, runner, runner.clock:now() - runner.startedAt)
    end
    return values
end

-- Advances every committed runner from its selected absolute clock. Active
-- names compose in stable start order: additive shake sums; later replacement
-- recipes own properties they share with earlier recipes.
function motion.updateAll(instances, host)
    local changed = false
    local completions = {}
    local orderedInstances = {}
    for _, instance in pairs(instances) do
        orderedInstances[#orderedInstances + 1] = instance
    end
    table.sort(orderedInstances, function(left, right)
        return left.eventOrder < right.eventOrder
    end)
    for _, instance in ipairs(orderedInstances) do
        for name, pending in pairs(instance.pendingCompletions or {}) do
            local binding = instance.recipes[name]
            if binding and binding.onComplete
                    and binding.key == pending.key then
                completions[#completions + 1] = {
                    callback = binding.onComplete,
                    identity = instance.identity,
                    lifetime = instance.lifetime,
                    name = name,
                    key = pending.key,
                    order = pending.order,
                    source = instance.source,
                }
            end
            instance.pendingCompletions[name] = nil
        end
        local ordered = {}
        for name, runner in pairs(instance.active) do
            ordered[#ordered + 1] = { name = name, runner = runner }
        end
        table.sort(ordered, runnerOrder)
        local values = copyValues(instance.settled)
        local completed = {}
        for _, entry in ipairs(ordered) do
            local runner = entry.runner
            local elapsed = runner.clock:now() - runner.startedAt
            if elapsed < runner.previous then runner.previous = -1e-12 end
            emitFeedback(runner.recipe, runner.previous, elapsed, host)
            applyRunner(values, runner, elapsed)
            runner.previous = elapsed
            if elapsed >= duration(runner.recipe) then completed[#completed + 1] = entry end
            changed = true
        end
        for _, entry in ipairs(completed) do
            local runner = entry.runner
            local result = finalValues(runner.recipe, runner.base)
            for property, mode in pairs(writtenProperties(runner.recipe)) do
                if mode ~= "add" then
                    setValue(instance.settled, property, result[property])
                end
            end
            instance.active[entry.name] = nil
            local binding = instance.recipes[entry.name]
            if binding and binding.onComplete
                    and binding.key == runner.bindingKey then
                completions[#completions + 1] = {
                    callback = binding.onComplete,
                    identity = instance.identity,
                    lifetime = instance.lifetime,
                    name = entry.name,
                    key = runner.bindingKey,
                    order = runner.order,
                    source = instance.source,
                }
            end
        end
        instance.values = values
        if instance.node then instance.node.presentation = copyValues(instance.values) end
    end
    table.sort(completions, function(left, right)
        if left.order ~= right.order then return left.order < right.order end
        if left.identity ~= right.identity then return left.identity < right.identity end
        return left.name < right.name
    end)
    return changed, completions
end

-- Confirms that a completed recipe still belongs to the same mounted element
-- before its terminal callback is delivered.
function motion.completionIsMounted(instances, completion)
    local instance = instances and instances[completion.identity]
    if not instance or instance.lifetime ~= completion.lifetime then return false end
    local binding = instance.recipes[completion.name]
    return binding ~= nil
        and binding.key == completion.key
        and instance.latestStarts[completion.name] == completion.order
end


-- Returns compact deterministic F6 metadata without exposing mutable runtime
-- tables to inspection callers.
function motion.inspect(instance)
    local declared = {}
    for _, name in ipairs(sortedKeys(instance.recipes)) do
        if name:sub(1, 8) ~= "$motion:" then
            local binding = instance.recipes[name]
            declared[#declared + 1] = {
                name = name,
                clock = binding.recipe.kind == "with_clock" and "explicit" or "raw",
                key = binding.key,
            }
        end
    end
    local active, details = {}, {}
    for _, name in ipairs(sortedKeys(instance.active)) do
        local runner = instance.active[name]
        local elapsed = math.max(0, runner.clock:now() - runner.startedAt)
        local total = duration(runner.recipe)
        active[#active + 1] = name
        details[#details + 1] = {
            name = name,
            clock = runner.clockKind,
            elapsed = elapsed,
            duration = total,
            progress = total == math.huge and nil
                or math.min(1, elapsed / math.max(total, 1e-12)),
        }
    end
    return {
        declared = declared,
        active = active,
        activeDetails = details,
        reactionCount = #instance.reactions,
        reducedMotion = instance.reducedMotion == true,
    }
end

local function multiply(left, right)
    return {
        a = left.a * right.a + left.c * right.b,
        b = left.b * right.a + left.d * right.b,
        c = left.a * right.c + left.c * right.d,
        d = left.b * right.c + left.d * right.d,
        tx = left.a * right.tx + left.c * right.ty + left.tx,
        ty = left.b * right.tx + left.d * right.ty + left.ty,
    }
end

local function localMatrix(node)
    local value = node.presentation or DEFAULT_VALUES
    local scale = value.scale or 1
    local rotation = value.rotation or 0
    local cosine, sine = math.cos(rotation) * scale, math.sin(rotation) * scale
    local centerX, centerY = node.x + node.width / 2, node.y + node.height / 2
    return {
        a = cosine, b = sine, c = -sine, d = cosine,
        tx = (value.x or 0) + centerX - cosine * centerX + sine * centerY,
        ty = (value.y or 0) + centerY - sine * centerX - cosine * centerY,
    }
end

local function inverse(value)
    local determinant = value.a * value.d - value.b * value.c
    if math.abs(determinant) < 1e-12 then return nil end
    return {
        a = value.d / determinant, b = -value.b / determinant,
        c = -value.c / determinant, d = value.a / determinant,
        tx = (value.c * value.ty - value.d * value.tx) / determinant,
        ty = (value.b * value.tx - value.a * value.ty) / determinant,
    }
end

local function point(matrix, x, y)
    return matrix.a * x + matrix.c * y + matrix.tx,
        matrix.b * x + matrix.d * y + matrix.ty
end

local IDENTITY = { a = 1, b = 0, c = 0, d = 1, tx = 0, ty = 0 }

local function transformNode(node, parent)
    -- Portals are painted and hit-tested in the Host root plane. Their
    -- authored tree position must not inherit Motion or Scroll transforms.
    if node._portal then parent = IDENTITY end
    node.presentation = node.presentation or copyValues()
    node._localTransform = localMatrix(node)
    node._worldTransform = multiply(parent or IDENTITY, node._localTransform)
    node._inverseWorldTransform = inverse(node._worldTransform)
    local x1, y1 = point(node._worldTransform, node.x, node.y)
    local x2, y2 = point(node._worldTransform, node.x + node.width, node.y)
    local x3, y3 = point(node._worldTransform, node.x, node.y + node.height)
    local x4, y4 = point(node._worldTransform,
        node.x + node.width, node.y + node.height)
    node._visualBounds = {
        x = math.min(x1, x2, x3, x4),
        y = math.min(y1, y2, y3, y4),
        width = math.max(x1, x2, x3, x4) - math.min(x1, x2, x3, x4),
        height = math.max(y1, y2, y3, y4) - math.min(y1, y2, y3, y4),
    }
    local cx1, cy1 = point(node._worldTransform, node.contentX, node.contentY)
    local cx2, cy2 = point(node._worldTransform,
        node.contentX + node.contentWidth, node.contentY)
    local cx3, cy3 = point(node._worldTransform,
        node.contentX, node.contentY + node.contentHeight)
    local cx4, cy4 = point(node._worldTransform,
        node.contentX + node.contentWidth, node.contentY + node.contentHeight)
    node._visualContentBounds = {
        x = math.min(cx1, cx2, cx3, cx4),
        y = math.min(cy1, cy2, cy3, cy4),
        width = math.max(cx1, cx2, cx3, cx4) - math.min(cx1, cx2, cx3, cx4),
        height = math.max(cy1, cy2, cy3, cy4) - math.min(cy1, cy2, cy3, cy4),
    }
    for _, child in ipairs(node.children) do transformNode(child, node._worldTransform) end
end

-- Recomputes paint/input/F6 transforms after layout or a clock tick.
function motion.transformTree(root)
    if root then transformNode(root, IDENTITY) end
end

-- Converts a virtual pointer into a node's untransformed layout space.
function motion.localPoint(node, x, y)
    local value = node._inverseWorldTransform
    if not value then return math.huge, math.huge end
    return point(value, x, y)
end

function motion.duration(recipe)
    return duration(recipe)
end

return motion
