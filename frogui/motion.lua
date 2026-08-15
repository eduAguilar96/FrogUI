-- Retains and evaluates per-element Motion/juice state. Application code
-- declares recipes; this runtime alone advances presentation properties.

local Juice = require("frogui.juice")

local motion = {}

local composeActive

local DEFAULT_VALUES = {
    x = 0, y = 0, rotation = 0,
    scale = 1, scaleX = 1, scaleY = 1,
    opacity = 1,
}
local DEFAULT_COLOR = { 1, 1, 1, 1 }
local MOTION_TARGET_NAMES = {
    "x", "y", "rotation", "scale", "scaleX", "scaleY",
    "opacity", "tint",
}
local STATIC_NUMERIC_TARGET_NAMES = {
    "x", "y", "rotation", "scale", "scaleX", "scaleY", "opacity",
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

-- A plain Motion wrapper can describe a fixed transform without owning an
-- animation process. Springs, recipes, and reactions still need retained
-- runtime state; direct scalar/color targets do not.
function motion.usesRetainedRuntime(node, props)
    if node.type ~= "Motion" then return true end
    if props.juice and next(props.juice)
            or props.reactions and next(props.reactions) then
        return true
    end
    for _, name in ipairs(MOTION_TARGET_NAMES) do
        local value = props[name]
        if type(value) == "table" and value.target ~= nil then return true end
    end
    return false
end

local function finite(value)
    return type(value) == "number" and value == value
        and value > -math.huge and value < math.huge
end

local function copyColorInto(out, value)
    if value == nil then return nil end
    out = out or {}
    out[1] = value[1] or value.r
    out[2] = value[2] or value.g
    out[3] = value[3] or value.b
    out[4] = value[4] or value.a or 1
    return out
end

local function copyColor(value)
    return copyColorInto(nil, value)
end

-- Copies the fixed presentation record into caller-owned storage. Runtime
-- sampling reuses this path so transient animation values never escape their
-- retained Motion owner.
local function copyValuesInto(out, values)
    out = out or {}
    for name, fallback in pairs(DEFAULT_VALUES) do
        local value = values and values[name]
        out[name] = value == nil and fallback or value
    end
    out.tint = copyColorInto(out.tint, values and values.tint)
    return out
end

local function copyValues(values)
    return copyValuesInto({}, values)
end

-- Publishes one fixed Motion transform without manufacturing retained recipe,
-- runner, target, completion, or lifetime tables. The candidate node owns any
-- non-default presentation record, so failed renders cannot touch live state.
function motion.reconcileStatic(node, props)
    assert(node.type == "Motion" and not motion.usesRetainedRuntime(node, props),
        "static Motion reconciliation requires a fixed Motion description")
    local presentation
    for _, name in ipairs(STATIC_NUMERIC_TARGET_NAMES) do
        local value = props[name]
        if value ~= nil then
            assert(finite(value),
                "Frog.Motion " .. name .. " target must be finite")
            assert(name ~= "opacity" or value >= 0 and value <= 1,
                "Frog.Motion opacity target must be between 0 and 1")
            assert(name ~= "scale" and name ~= "scaleX" and name ~= "scaleY"
                    or value >= 0,
                "Frog.Motion " .. name .. " target must be non-negative")
            if value ~= DEFAULT_VALUES[name] then
                presentation = presentation or {}
                presentation[name] = value
            end
        end
    end
    if props.tint ~= nil then
        assert(Juice.isColor(props.tint),
            "Frog.Motion tint target must be a numeric color")
        presentation = presentation or {}
        presentation.tint = copyColor(props.tint)
    end
    node.presentation = presentation
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

local function setBufferedValue(values, name, value)
    if name == "tint" then
        values.tint = copyColorInto(values.tint, value)
    else
        values[name] = value
    end
end

local function sameValues(left, right)
    for name in pairs(DEFAULT_VALUES) do
        if not sameValue(left[name], right[name]) then return false end
    end
    return sameValue(left.tint, right.tint)
end

local function sameGeometry(left, right)
    return left.x == right.x and left.y == right.y
        and left.rotation == right.rotation and left.scale == right.scale
        and left.scaleX == right.scaleX and left.scaleY == right.scaleY
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

local function lerpBufferedValue(values, name, left, right, amount)
    if type(right) ~= "table" then
        values[name] = lerp(left, right, amount)
        return
    end
    left = left or DEFAULT_COLOR
    local out = values[name] or {}
    for index = 1, 4 do
        local a = left[index]
        if a == nil and index == 4 then a = 1 end
        local b = right[index]
        if b == nil and index == 4 then b = 1 end
        out[index] = lerp(a, b, amount)
    end
    values[name] = out
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
        if recipe.scale ~= 0 then out.scale = out.scale or "add" end
    elseif kind == "sequence" or kind == "parallel" then
        for _, child in ipairs(recipe.recipes) do writtenProperties(child, out) end
    elseif kind == "loop" or kind == "with_clock" then
        writtenProperties(recipe.recipe, out)
    end
    return out
end

local function geometryMask(recipe)
    local written = writtenProperties(recipe)
    local translated = written.x ~= nil or written.y ~= nil
    local rotated = written.rotation ~= nil
    local scaled = written.scale ~= nil or written.scaleX ~= nil
        or written.scaleY ~= nil
    local kinds = (translated and 1 or 0) + (rotated and 1 or 0)
        + (scaled and 1 or 0)
    if kinds == 0 then return nil end
    if kinds > 1 then return "mixed" end
    if translated then return "translate" end
    if rotated then return "rotate" end
    return "scale"
end

-- Returns bounded recipe vocabulary for development diagnostics. It never
-- includes a binding key, event payload, logical identity, or source path.
local function diagnosticRecipe(name, recipe)
    local mask = geometryMask(recipe)
    if not mask then return nil end
    return {
        name = name,
        kind = recipe.kind,
        geometry = mask,
    }
end

-- Compiles immutable recipe facts once per retained runner. The authored
-- recipe remains inert data; duration, child shape, and write ownership stay
-- in a detached runtime record that can be shared by candidate runner clones.
local function analyzeRecipe(recipe)
    local analysis = {
        recipe = recipe,
        duration = duration(recipe),
        written = writtenProperties(recipe),
    }
    local kind = recipe.kind
    if kind == "sequence" or kind == "parallel" then
        analysis.children = {}
        for index, child in ipairs(recipe.recipes) do
            analysis.children[index] = analyzeRecipe(child)
        end
    elseif kind == "loop" or kind == "with_clock" then
        analysis.child = analyzeRecipe(recipe.recipe)
    end
    return analysis
end

local function scratchValues(scratch, depth)
    local values = scratch[depth]
    if not values then
        values = copyValues()
        scratch[depth] = values
    end
    return values
end

local sampleInto

local function finalValuesInto(analysis, base, out, scratch, depth)
    if analysis.duration == math.huge then
        return copyValuesInto(out, base)
    end
    return sampleInto(analysis, analysis.duration, base, out, scratch, depth)
end

-- Evaluates into retained owner scratch. No returned table is published or
-- retained outside that owner; callers copy only the fixed properties a recipe
-- declares into committed presentation state.
sampleInto = function(analysis, elapsed, base, out, scratch, depth)
    local recipe = analysis.recipe
    local kind = recipe.kind
    local values = copyValuesInto(out, base)
    if kind == "tween" then
        local amount = recipe.duration == 0 and 1
            or math.min(1, math.max(0, elapsed / recipe.duration))
        amount = eased(recipe.ease, amount)
        for name, target in pairs(recipe.to) do
            lerpBufferedValue(values, name, values[name], target, amount)
        end
    elseif kind == "spring" then
        local amount
        if elapsed >= analysis.duration then
            amount = 1
        else
            local time = math.max(0, elapsed)
            local decay = math.exp(-recipe.frequency * recipe.damping * time)
            amount = 1 - decay * math.cos(recipe.frequency * time)
        end
        for name, target in pairs(recipe.to) do
            lerpBufferedValue(values, name, values[name], target, amount)
        end
    elseif kind == "shake" then
        if recipe.duration > 0 and elapsed < recipe.duration then
            local progress = math.max(0, elapsed) / recipe.duration
            local envelope = recipe.damping
                and math.exp(-recipe.damping * math.max(0, elapsed))
                or (1 - progress) * (1 - progress)
            local phase = math.max(0, elapsed) * recipe.frequency * math.pi * 2
            local yPhase = recipe.coherent and phase
                or phase * 1.17 + 1.3
            local rotationPhase = recipe.coherent and phase
                or phase * 0.83 + 2.1
            values.x = values.x + math.sin(phase) * recipe.x * envelope
            values.y = values.y + math.sin(yPhase) * recipe.y * envelope
            values.rotation = values.rotation
                + math.sin(rotationPhase) * recipe.rotation * envelope
            values.scale = values.scale
                + math.sin(phase) * recipe.scale * envelope
        end
    elseif kind == "sequence" then
        local remaining = math.max(0, elapsed)
        for _, child in ipairs(analysis.children) do
            if remaining < child.duration then
                return sampleInto(child, remaining, values, values,
                    scratch, depth)
            end
            finalValuesInto(child, values, values, scratch, depth)
            remaining = remaining - child.duration
        end
    elseif kind == "parallel" then
        for _, child in ipairs(analysis.children) do
            local branch = scratchValues(scratch, depth)
            sampleInto(child, elapsed, base, branch, scratch, depth + 1)
            for name, mode in pairs(child.written) do
                if mode == "add" then
                    values[name] = values[name] + branch[name] - base[name]
                else
                    setBufferedValue(values, name, branch[name])
                end
            end
        end
    elseif kind == "loop" then
        local child = analysis.child
        local childDuration = child.duration
        local completed = math.floor(math.max(0, elapsed) / childDuration)
        if recipe.count then completed = math.min(completed, recipe.count) end
        if completed > 0 then
            finalValuesInto(child, values, values, scratch, depth)
        end
        if not recipe.count or completed < recipe.count then
            local localTime = math.max(0, elapsed) - completed * childDuration
            sampleInto(child, localTime, values, values, scratch, depth)
        end
    elseif kind == "with_clock" then
        sampleInto(analysis.child, elapsed, values, values, scratch, depth)
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

-- Records one stopped-collector interval in the private allocation probe.
local function recordReconciliationAllocation(probe, callsField, kbField,
        before)
    if not probe then return end
    probe[callsField] = probe[callsField] + 1
    probe[kbField] = probe[kbField]
        + collectgarbage("count") - before
end

-- Selects the current stopped-collector Host:update row. Ordinary Hosts and
-- every non-pipeline probe take the nil branch and retain no observer state.
local function runtimeAllocationRow(host)
    local probe = host and rawget(host, "_allocationProbe") or nil
    return probe and probe.active and probe.mode == "pipeline"
        and probe.runtimeActiveRow or nil
end

local function recordRuntimeAllocation(row, callsField, kbField, before)
    if not row then return end
    row[callsField] = row[callsField] + 1
    row[kbField] = row[kbField] + collectgarbage("count") - before
end

local function cloneRunner(runner)
    return {
        recipe = runner.recipe,
        analysis = runner.analysis,
        clock = runner.clock,
        startedAt = runner.startedAt,
        previous = runner.previous,
        base = copyValues(runner.base),
        -- Candidate reconciliation never samples through these shared runtime
        -- buffers. A successful compatible commit therefore keeps their warm
        -- shape; a failed candidate cannot mutate the committed owner.
        sampled = runner.sampled,
        sampleScratch = runner.sampleScratch,
        feedbackBudget = runner.feedbackBudget,
        order = runner.order,
        clockKind = runner.clockKind,
        bindingKey = runner.bindingKey,
    }
end

local function cloneInstance(old, allocationProbe)
    local shellBefore = allocationProbe and collectgarbage("count") or nil
    local instance = {
        identity = old.identity,
        order = old.order,
        props = old.props,
        reactions = old.reactions,
        source = old.source,
        primitiveType = old.primitiveType,
        eventOrder = old.eventOrder,
        reducedMotion = old.reducedMotion,
        node = old.node,
        lifetime = old.lifetime,
        _runtimeScratch = old._runtimeScratch,
    }
    recordReconciliationAllocation(allocationProbe,
        "pipelineMotionCloneShellCalls",
        "pipelineMotionCloneShellAllocatedKB", shellBefore)
    local valueBefore = allocationProbe and collectgarbage("count") or nil
    instance.values = copyValues(old.values)
    instance.settled = copyValues(old.settled)
    recordReconciliationAllocation(allocationProbe,
        "pipelineMotionCloneValueCalls",
        "pipelineMotionCloneValueAllocatedKB", valueBefore)
    local collectionBefore = allocationProbe
        and collectgarbage("count") or nil
    instance.recipes = {}
    instance.active = {}
    instance.motionTargets = {}
    recordReconciliationAllocation(allocationProbe,
        "pipelineMotionCloneCollectionCalls",
        "pipelineMotionCloneCollectionAllocatedKB", collectionBefore)
    local recipeBefore = allocationProbe and collectgarbage("count") or nil
    for name, binding in pairs(old.recipes) do
        if name:sub(1, 8) == "$motion:" then
            instance.recipes[name] = binding
        end
    end
    recordReconciliationAllocation(allocationProbe,
        "pipelineMotionCloneRecipeCalls",
        "pipelineMotionCloneRecipeAllocatedKB", recipeBefore)
    local indexBefore = allocationProbe and collectgarbage("count") or nil
    if old.latestStarts then
        instance.latestStarts = {}
        for name, order in pairs(old.latestStarts) do
            instance.latestStarts[name] = order
        end
    end
    recordReconciliationAllocation(allocationProbe,
        "pipelineMotionCloneIndexCalls",
        "pipelineMotionCloneIndexAllocatedKB", indexBefore)
    local runnerBefore = allocationProbe and collectgarbage("count") or nil
    for name, runner in pairs(old.active) do
        instance.active[name] = cloneRunner(runner)
    end
    recordReconciliationAllocation(allocationProbe,
        "pipelineMotionCloneRunnerCalls",
        "pipelineMotionCloneRunnerAllocatedKB", runnerBefore)
    local completionBefore = allocationProbe
        and collectgarbage("count") or nil
    if old.pendingCompletions then
        instance.pendingCompletions = {}
        for name, pending in pairs(old.pendingCompletions) do
            instance.pendingCompletions[name] = {
                key = pending.key,
                order = pending.order,
            }
        end
    end
    recordReconciliationAllocation(allocationProbe,
        "pipelineMotionCloneCompletionCalls",
        "pipelineMotionCloneCompletionAllocatedKB", completionBefore)
    local targetBefore = allocationProbe and collectgarbage("count") or nil
    for name, value in pairs(old.motionTargets) do
        instance.motionTargets[name] = name == "tint" and copyColor(value) or value
    end
    recordReconciliationAllocation(allocationProbe,
        "pipelineMotionCloneTargetCalls",
        "pipelineMotionCloneTargetAllocatedKB", targetBefore)
    return instance
end

-- Counts retained Motion collections without allocating diagnostic tables.
local MOTION_COLLECTION_PROBE_FIELDS = {
    { "recipes", "pipelineMotionRecipeEntries" },
    { "active", "pipelineMotionActiveEntries" },
    { "motionTargets", "pipelineMotionTargetEntries" },
    { "pendingCompletions", "pipelineMotionPendingEntries" },
    { "latestStarts", "pipelineMotionLatestEntries" },
}

local function countMotionCollections(probe, old)
    if not probe or not old then return end
    for _, field in ipairs(MOTION_COLLECTION_PROBE_FIELDS) do
        local collection = old[field[1]]
        if collection then
            for _ in pairs(collection) do
                probe[field[2]] = probe[field[2]] + 1
            end
        end
    end
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
        analysis = analyzeRecipe(recipe),
        clock = clock,
        startedAt = clock:now(),
        previous = -1e-12,
        base = copyValues(instance.values),
        sampled = copyValues(),
        sampleScratch = {},
        feedbackBudget = { remaining = 1024 },
        order = host:_nextMotionOrder(),
        clockKind = binding.recipe.kind == "with_clock" and "explicit" or "raw",
        bindingKey = binding.key,
    }
    if binding.onComplete then
        instance.latestStarts = instance.latestStarts or {}
        instance.latestStarts[name] = runner.order
    elseif instance.latestStarts then
        instance.latestStarts[name] = nil
    end
    if instance.pendingCompletions then
        instance.pendingCompletions[name] = nil
    end
    if host.reducedMotion then
        emitAllFeedback(recipe, host)
        finalValuesInto(runner.analysis, runner.base, runner.sampled,
            runner.sampleScratch, 1)
        for property, mode in pairs(runner.analysis.written) do
            if mode ~= "add" then
                setValue(instance.settled, property, runner.sampled[property])
            end
        end
        copyValuesInto(instance.values, instance.settled)
        if binding.onComplete then
            instance.pendingCompletions =
                instance.pendingCompletions or {}
            instance.pendingCompletions[name] = {
                key = binding.key,
                order = runner.order,
            }
        end
        return
    end
    runner.feedbackBudget.remaining = 1024
    emitFeedback(recipe, runner.previous, 0, host, nil,
        runner.feedbackBudget)
    runner.previous = 0
    instance.active[name] = runner
    sampleInto(runner.analysis, 0, runner.base, instance.values,
        runner.sampleScratch, 1)
end

local function reconcileMotionTargets(instance, props, host, firstMount)
    local changedAny = false
    for _, name in ipairs(MOTION_TARGET_NAMES) do
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
                assert(name ~= "scale" and name ~= "scaleX"
                        and name ~= "scaleY" or target >= 0,
                    "Frog.Motion " .. name
                        .. " target must be non-negative")
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
function motion.reconcile(old, node, props, logicalIdentity, order, host,
        allocationProbe)
    local compatible = old and old.primitiveType == node.type
    if allocationProbe then
        local field = compatible and "pipelineMotionCompatibleCalls"
            or "pipelineMotionFirstMountCalls"
        allocationProbe[field] = allocationProbe[field] + 1
        countMotionCollections(allocationProbe, compatible and old or nil)
    end
    local cloneBefore = allocationProbe and collectgarbage("count") or nil
    local instance
    if compatible then
        instance = cloneInstance(old, allocationProbe)
    else
        local initialBefore = allocationProbe
            and collectgarbage("count") or nil
        instance = {
            identity = logicalIdentity,
            values = copyValues(),
            settled = copyValues(),
            recipes = {}, active = {}, motionTargets = {}, lifetime = {},
            _runtimeScratch = {
                ordered = {}, completed = {}, values = copyValues(),
            },
        }
        recordReconciliationAllocation(allocationProbe,
            "pipelineMotionCloneInitialCalls",
            "pipelineMotionCloneInitialAllocatedKB", initialBefore)
    end
    recordReconciliationAllocation(allocationProbe,
        "pipelineMotionCloneCalls", "pipelineMotionCloneAllocatedKB",
        cloneBefore)
    local setupBefore = allocationProbe and collectgarbage("count") or nil
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
        local targetBefore = allocationProbe
            and collectgarbage("count") or nil
        local targetsChanged = reconcileMotionTargets(
            instance, props, host, true)
        if allocationProbe and targetsChanged then
            allocationProbe.pipelineMotionTargetChangedCalls =
                allocationProbe.pipelineMotionTargetChangedCalls + 1
        end
        recordReconciliationAllocation(allocationProbe,
            "pipelineMotionTargetCalls",
            "pipelineMotionTargetAllocatedKB", targetBefore)
    end

    local parseBefore = allocationProbe and collectgarbage("count") or nil
    local nextRecipes = {}
    for name, value in pairs(props.juice or {}) do
        assert(type(name) == "string" and name ~= "",
            "juice recipe names must be non-empty strings")
        nextRecipes[name] = parseBinding(name, value)
        if allocationProbe then
            allocationProbe.pipelineMotionDeclaredRecipeEntries =
                allocationProbe.pipelineMotionDeclaredRecipeEntries + 1
        end
    end
    recordReconciliationAllocation(allocationProbe,
        "pipelineMotionRecipeParseCalls",
        "pipelineMotionRecipeParseAllocatedKB", parseBefore)
    local cleanupBefore = allocationProbe and collectgarbage("count") or nil
    if compatible then
        for name in pairs(old.recipes) do
            if not nextRecipes[name] and name:sub(1, 8) ~= "$motion:" then
                instance.active[name] = nil
                if instance.pendingCompletions then
                    instance.pendingCompletions[name] = nil
                end
                if instance.latestStarts then
                    instance.latestStarts[name] = nil
                end
                if allocationProbe then
                    allocationProbe.pipelineMotionRemovedRecipes =
                        allocationProbe.pipelineMotionRemovedRecipes + 1
                end
            end
        end
    end
    recordReconciliationAllocation(allocationProbe,
        "pipelineMotionCleanupCalls",
        "pipelineMotionCleanupAllocatedKB", cleanupBefore)
    local bindingBefore = allocationProbe and collectgarbage("count") or nil
    for _, name in ipairs(sortedKeys(nextRecipes)) do
        local binding = nextRecipes[name]
        local previous = compatible and old.recipes[name] or nil
        instance.recipes[name] = binding
        if binding.key ~= nil
                and (not previous or previous.key ~= binding.key) then
            start(instance, name, host)
            if allocationProbe then
                allocationProbe.pipelineMotionKeyStarts =
                    allocationProbe.pipelineMotionKeyStarts + 1
            end
        end
    end
    recordReconciliationAllocation(allocationProbe,
        "pipelineMotionBindingCalls",
        "pipelineMotionBindingAllocatedKB", bindingBefore)
    local reactionBefore = allocationProbe and collectgarbage("count") or nil
    for index, reaction in ipairs(instance.reactions) do
        local recipeName = reaction.do_ and reaction.do_.name
        assert(recipeName and instance.recipes[recipeName],
            node.type .. " reaction " .. index .. " plays undeclared juice recipe "
                .. tostring(recipeName))
        if allocationProbe then
            allocationProbe.pipelineMotionReactionEntries =
                allocationProbe.pipelineMotionReactionEntries + 1
        end
    end
    recordReconciliationAllocation(allocationProbe,
        "pipelineMotionReactionCalls",
        "pipelineMotionReactionAllocatedKB", reactionBefore)
    if ownsMotionTargets(node) and compatible then
        local targetBefore = allocationProbe
            and collectgarbage("count") or nil
        local targetsChanged = reconcileMotionTargets(instance, props, host,
            false)
        if allocationProbe and targetsChanged then
            allocationProbe.pipelineMotionTargetChangedCalls =
                allocationProbe.pipelineMotionTargetChangedCalls + 1
        end
        recordReconciliationAllocation(allocationProbe,
            "pipelineMotionTargetCalls",
            "pipelineMotionTargetAllocatedKB", targetBefore)
        if targetsChanged and composeActive then
            instance.values = composeActive(instance)
        end
    end
    node._motion = instance
    recordReconciliationAllocation(allocationProbe,
        "pipelineMotionSetupCalls", "pipelineMotionSetupAllocatedKB",
        setupBefore)
    local presentationBefore = allocationProbe
        and collectgarbage("count") or nil
    node.presentation = copyValues(instance.values)
    recordReconciliationAllocation(allocationProbe,
        "pipelineMotionPresentationCalls",
        "pipelineMotionPresentationAllocatedKB", presentationBefore)
    return instance
end

-- Starts a named recipe after a typed element reaction accepts an event.
function motion.play(instance, instruction, host)
    assert(Juice.isPlay(instruction), "element reaction do_ must be Frog.play")
    local previous = instance.node and instance.node.presentation
    start(instance, instruction.name, host)
    if instance.node then
        instance.node.presentation = copyValues(instance.values)
        if not previous or not sameGeometry(previous, instance.values) then
            local binding = host._diagnostics.enabled
                and instance.recipes[instruction.name] or nil
            host:_invalidateTransform(instance.node, "Motion",
                "event-play", binding and {
                    diagnosticRecipe(instruction.name, binding.recipe),
                } or nil)
        end
    end
end

local function runnerOrder(left, right)
    if left.runner.order ~= right.runner.order then
        return left.runner.order < right.runner.order
    end
    return left.name < right.name
end

local function applyRunner(values, runner, elapsed)
    local sampled = sampleInto(runner.analysis, elapsed, runner.base,
        runner.sampled, runner.sampleScratch, 1)
    for property, mode in pairs(runner.analysis.written) do
        if mode == "add" then
            values[property] = values[property] + sampled[property] - runner.base[property]
        else
            setValue(values, property, sampled[property])
        end
    end
end

-- Candidate-only composition intentionally does not touch the warm buffers
-- shared with its compatible committed runner. The candidate owns these
-- temporary tables and may be discarded atomically after any render failure.
local function applyRunnerToCandidate(values, runner, elapsed)
    local sampled = sampleInto(runner.analysis, elapsed, runner.base,
        copyValues(), {}, 1)
    for property, mode in pairs(runner.analysis.written) do
        if mode == "add" then
            values[property] = values[property]
                + sampled[property] - runner.base[property]
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
        applyRunnerToCandidate(values, runner,
            runner.clock:now() - runner.startedAt)
    end
    return values
end

-- Samples one active owner. Keeping this separate lets updateAll preserve
-- pending-completion delivery while idle owners take a plain conditional fast
-- path with no runner/value allocations.
local function updateActive(instance, host, completions, attribution,
        runtimeRow)
    local scratch = instance._runtimeScratch
    local runnerOrderBefore = runtimeRow and collectgarbage("count") or nil
    local ordered = scratch.ordered
    local orderedCount = 0
    for name, runner in pairs(instance.active) do
        orderedCount = orderedCount + 1
        local entry = ordered[orderedCount]
        if not entry then
            entry = {}
            ordered[orderedCount] = entry
        end
        entry.name = name
        entry.runner = runner
    end
    for index = #ordered, orderedCount + 1, -1 do
        ordered[index] = nil
    end
    table.sort(ordered, runnerOrder)
    local geometryRecipes
    if attribution then
        geometryRecipes = {}
        for _, entry in ipairs(ordered) do
            local binding = instance.recipes[entry.name]
            local recipe = diagnosticRecipe(entry.name,
                binding and binding.recipe or entry.runner.recipe)
            if recipe then geometryRecipes[#geometryRecipes + 1] = recipe end
        end
        if #geometryRecipes > 0 then
            attribution.activeGeometryMotions =
                attribution.activeGeometryMotions + 1
        end
    end
    recordRuntimeAllocation(runtimeRow,
        "motionRunnerOrderCalls", "motionRunnerOrderAllocatedKB",
        runnerOrderBefore)
    local valueSeedBefore = runtimeRow and collectgarbage("count") or nil
    local values = copyValuesInto(scratch.values, instance.settled)
    recordRuntimeAllocation(runtimeRow,
        "motionValueSeedCalls", "motionValueSeedAllocatedKB",
        valueSeedBefore)
    local completedScratchBefore = runtimeRow
        and collectgarbage("count") or nil
    local completed = scratch.completed
    for index = #completed, 1, -1 do completed[index] = nil end
    recordRuntimeAllocation(runtimeRow,
        "motionCompletedScratchCalls", "motionCompletedScratchAllocatedKB",
        completedScratchBefore)
    for _, entry in ipairs(ordered) do
        local runnerSampleBefore = runtimeRow
            and collectgarbage("count") or nil
        local runner = entry.runner
        local elapsed = runner.clock:now() - runner.startedAt
        if elapsed < runner.previous then runner.previous = -1e-12 end
        runner.feedbackBudget.remaining = 1024
        emitFeedback(runner.recipe, runner.previous, elapsed, host, nil,
            runner.feedbackBudget)
        applyRunner(values, runner, elapsed)
        runner.previous = elapsed
        if elapsed >= runner.analysis.duration then
            completed[#completed + 1] = entry
        end
        recordRuntimeAllocation(runtimeRow,
            "motionRunnerSampleCalls", "motionRunnerSampleAllocatedKB",
            runnerSampleBefore)
    end
    local completionBefore = runtimeRow and collectgarbage("count") or nil
    for _, entry in ipairs(completed) do
        local runner = entry.runner
        for property, mode in pairs(runner.analysis.written) do
            if mode ~= "add" then
                setBufferedValue(instance.settled, property,
                    runner.sampled[property])
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
    recordRuntimeAllocation(runtimeRow,
        "motionCompletionFinalizeCalls",
        "motionCompletionFinalizeAllocatedKB", completionBefore)
    local presentationBefore = runtimeRow and collectgarbage("count") or nil
    local visualChanged = not sameValues(instance.values, values)
    local geometryChanged = not sameGeometry(instance.values, values)
    scratch.values = instance.values
    instance.values = values
    if instance.node and visualChanged then
        instance.node.presentation = copyValuesInto(
            instance.node.presentation or {}, instance.values)
        if geometryChanged then
            host:_invalidateTransform(instance.node, "Motion",
                "frame-sample", geometryRecipes)
        end
    end
    recordRuntimeAllocation(runtimeRow,
        "motionPresentationCalls", "motionPresentationAllocatedKB",
        presentationBefore)
end

-- Advances every committed runner from its selected absolute clock. Active
-- names compose in stable start order: additive shake sums; later replacement
-- recipes own properties they share with earlier recipes.
function motion.updateAll(instances, host)
    local runtimeRow = runtimeAllocationRow(host)
    local registryBefore = runtimeRow and collectgarbage("count") or nil
    local changed = false
    local completions = {}
    local orderedInstances = {}
    local attribution = host._diagnostics.enabled
        and { activeGeometryMotions = 0 } or nil
    for _, instance in pairs(instances) do
        orderedInstances[#orderedInstances + 1] = instance
    end
    table.sort(orderedInstances, function(left, right)
        return left.eventOrder < right.eventOrder
    end)
    recordRuntimeAllocation(runtimeRow,
        "motionRegistryCalls", "motionRegistryAllocatedKB", registryBefore)
    for _, instance in ipairs(orderedInstances) do
        local pendingBefore = runtimeRow and collectgarbage("count") or nil
        local pendingCompletions = instance.pendingCompletions
        if pendingCompletions then
            for name, pending in pairs(pendingCompletions) do
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
            end
            instance.pendingCompletions = nil
        end
        recordRuntimeAllocation(runtimeRow,
            "motionPendingCalls", "motionPendingAllocatedKB", pendingBefore)
        -- Most mounted juice owners are idle most of the time. Pending
        -- completions above still deliver, but an idle owner does not need a
        -- runner array, value snapshot, or replacement presentation table.
        if next(instance.active) ~= nil then
            local activeBefore = runtimeRow and collectgarbage("count") or nil
            updateActive(instance, host, completions, attribution, runtimeRow)
            recordRuntimeAllocation(runtimeRow,
                "motionActiveCalls", "motionActiveAllocatedKB", activeBefore)
            changed = true
        end
    end
    local completionSortBefore = runtimeRow
        and collectgarbage("count") or nil
    table.sort(completions, function(left, right)
        if left.order ~= right.order then return left.order < right.order end
        if left.identity ~= right.identity then return left.identity < right.identity end
        return left.name < right.name
    end)
    recordRuntimeAllocation(runtimeRow,
        "motionCompletionSortCalls", "motionCompletionSortAllocatedKB",
        completionSortBefore)
    return changed, completions, attribution
end

-- Confirms that a completed recipe still belongs to the same mounted element
-- before its terminal callback is delivered.
function motion.completionIsMounted(instances, completion)
    local instance = instances and instances[completion.identity]
    if not instance or instance.lifetime ~= completion.lifetime then return false end
    local binding = instance.recipes[completion.name]
    return binding ~= nil
        and binding.key == completion.key
        and instance.latestStarts ~= nil
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

local function localMatrix(node, out)
    local value = node.presentation or DEFAULT_VALUES
    local scale = value.scale or 1
    local scaleX = scale * (value.scaleX or 1)
    local scaleY = scale * (value.scaleY or 1)
    local rotation = value.rotation or 0
    local cosine, sine = math.cos(rotation), math.sin(rotation)
    local a, b = cosine * scaleX, sine * scaleX
    local c, d = -sine * scaleY, cosine * scaleY
    local pivot = node.props.pivot
    local pivotX = node.layout.x + node.layout.width
        * (pivot and pivot.x or 0.5)
    local pivotY = node.layout.y + node.layout.height
        * (pivot and pivot.y or 0.5)
    out = out or {}
    out.a, out.b, out.c, out.d = a, b, c, d
    out.tx = (value.x or 0) + pivotX - a * pivotX - c * pivotY
    out.ty = (value.y or 0) + pivotY - b * pivotX - d * pivotY
    return out
end

local function multiply(left, right, out)
    out = out or {}
    out.a = left.a * right.a + left.c * right.b
    out.b = left.b * right.a + left.d * right.b
    out.c = left.a * right.c + left.c * right.d
    out.d = left.b * right.c + left.d * right.d
    out.tx = left.a * right.tx + left.c * right.ty + left.tx
    out.ty = left.b * right.tx + left.d * right.ty + left.ty
    return out
end

local function inverse(value, out)
    local determinant = value.a * value.d - value.b * value.c
    if math.abs(determinant) < 1e-12 then return nil end
    out = out or {}
    out.a, out.b = value.d / determinant, -value.b / determinant
    out.c, out.d = -value.c / determinant, value.a / determinant
    out.tx = (value.c * value.ty - value.d * value.tx) / determinant
    out.ty = (value.b * value.tx - value.a * value.ty) / determinant
    return out
end

local function point(matrix, x, y)
    return matrix.a * x + matrix.c * y + matrix.tx,
        matrix.b * x + matrix.d * y + matrix.ty
end

local IDENTITY = { a = 1, b = 0, c = 0, d = 1, tx = 0, ty = 0 }
local BRANCH_ROOT_LIMIT = 128
local BRANCH_COVERAGE_FRACTION = 0.5
local nextTransformTreeToken = 0

local function writeBounds(out, x1, y1, x2, y2, x3, y3, x4, y4)
    out = out or {}
    local minimumX = math.min(x1, x2, x3, x4)
    local maximumX = math.max(x1, x2, x3, x4)
    local minimumY = math.min(y1, y2, y3, y4)
    local maximumY = math.max(y1, y2, y3, y4)
    out.x, out.y = minimumX, minimumY
    out.width, out.height = maximumX - minimumX, maximumY - minimumY
    return out
end

-- Attributes retained candidate-geometry tables to a private Host-owned
-- stopped-GC probe. Ordinary and committed transforms never enter this path.
local function recordGeometryAllocation(probe, createdField, kbField, before,
        created)
    local after = collectgarbage("count")
    if created then probe[createdField] = probe[createdField] + 1 end
    probe[kbField] = probe[kbField] + after - before
end

local function matrixIsIdentity(value)
    return value.a == 1 and value.b == 0 and value.c == 0 and value.d == 1
        and value.tx == 0 and value.ty == 0
end

local function matricesMatch(left, right)
    return left.a == right.a and left.b == right.b
        and left.c == right.c and left.d == right.d
        and left.tx == right.tx and left.ty == right.ty
end

-- Identifies primitives whose children can be visually clipped by this node.
-- Only these nodes consume transformed content bounds during inspection.
local function clipsChildren(node)
    return node.type == "Scroll" or node.props.clip
        or node.props.overflow == "clip"
end

local function noteDiagnosticTarget(observer, plane, node)
    if not observer.targets[node] then return false end
    local planeState = observer.planes[plane]
    if not planeState then
        planeState = {}
        observer.planes[plane] = planeState
    end
    if not planeState.lcaInitialized then
        planeState.lcaInitialized = true
        planeState.lcaPath = {}
        for index, ancestor in ipairs(observer.path) do
            planeState.lcaPath[index] = ancestor
        end
    else
        local shared = 0
        local limit = math.min(#planeState.lcaPath, #observer.path)
        while shared < limit
                and planeState.lcaPath[shared + 1]
                    == observer.path[shared + 1] do
            shared = shared + 1
        end
        for index = #planeState.lcaPath, shared + 1, -1 do
            planeState.lcaPath[index] = nil
        end
    end
    return true
end

-- Writes one node's authoritative transform geometry. Production and observed
-- recursion share this exact writer; only their traversal bookkeeping differs.
local function transformNodeGeometry(node, parent, parentInverse,
        allocationProbe, isRoot)
    if node._portal then
        parent = IDENTITY
        parentInverse = IDENTITY
    end
    if allocationProbe then
        allocationProbe.pipelineGeometryCalls =
            allocationProbe.pipelineGeometryCalls + 1
    end
    local staticPresentation = node.presentation == nil
        or node.presentation == DEFAULT_VALUES
    local defaultPresentation = allocationProbe and staticPresentation
    if allocationProbe then
        local presentationField = defaultPresentation
            and "pipelineDefaultPresentationNodes"
            or "pipelinePrivatePresentationNodes"
        allocationProbe[presentationField] =
            allocationProbe[presentationField] + 1
        if isRoot then
            allocationProbe.pipelineRootBoundaryNodes =
                allocationProbe.pipelineRootBoundaryNodes + 1
        elseif node._portal then
            allocationProbe.pipelinePortalBoundaryNodes =
                allocationProbe.pipelinePortalBoundaryNodes + 1
        end
    end
    local existed = node.presentation ~= nil
    local before = allocationProbe and collectgarbage("count") or nil
    -- Static primitives only read the canonical defaults. Motion reconciliation
    -- installs a private copy before any animated value can be mutated.
    node.presentation = node.presentation or DEFAULT_VALUES
    if allocationProbe then
        recordGeometryAllocation(allocationProbe,
            "pipelinePresentationCreated",
            "pipelinePresentationAllocatedKB", before,
            not existed and node.presentation ~= DEFAULT_VALUES)
    end
    existed = node._localTransform ~= nil
    before = allocationProbe and collectgarbage("count") or nil
    if staticPresentation then
        node._localTransform = IDENTITY
    else
        node._localTransform = localMatrix(node, node._localTransform)
    end
    local localIdentity = allocationProbe
        and matrixIsIdentity(node._localTransform)
    if allocationProbe and localIdentity then
        allocationProbe.pipelineLocalIdentityNodes =
            allocationProbe.pipelineLocalIdentityNodes + 1
        local identityField = defaultPresentation
            and "pipelineDefaultLocalIdentityNodes"
            or "pipelinePrivateLocalIdentityNodes"
        allocationProbe[identityField] = allocationProbe[identityField] + 1
    end
    if allocationProbe then
        recordGeometryAllocation(allocationProbe,
            "pipelineLocalMatrixCreated",
            "pipelineLocalMatrixAllocatedKB", before,
            not existed and node._localTransform ~= IDENTITY)
    end
    existed = node._worldTransform ~= nil
    before = allocationProbe and collectgarbage("count") or nil
    if staticPresentation then
        node._worldTransform = parent or IDENTITY
    else
        node._worldTransform = multiply(parent or IDENTITY,
            node._localTransform, node._worldTransform)
    end
    local worldMatchesBoundary = allocationProbe
        and matricesMatch(node._worldTransform, parent or IDENTITY)
    if allocationProbe and worldMatchesBoundary then
        allocationProbe.pipelineWorldBoundaryMatchNodes =
            allocationProbe.pipelineWorldBoundaryMatchNodes + 1
        if defaultPresentation then
            allocationProbe.pipelineDefaultWorldBoundaryMatchNodes =
                allocationProbe.pipelineDefaultWorldBoundaryMatchNodes + 1
            local shareField = (isRoot or node._portal)
                and "pipelineDefaultIdentityShareNodes"
                or "pipelineDefaultParentShareNodes"
            allocationProbe[shareField] = allocationProbe[shareField] + 1
        end
    end
    if allocationProbe then
        recordGeometryAllocation(allocationProbe,
            "pipelineWorldMatrixCreated",
            "pipelineWorldMatrixAllocatedKB", before,
            not existed and not staticPresentation
                and node._worldTransform ~= nil)
    end
    existed = node._inverseWorldTransform ~= nil
    before = allocationProbe and collectgarbage("count") or nil
    if staticPresentation then
        node._inverseWorldTransform = parentInverse
    else
        node._inverseWorldTransform = inverse(node._worldTransform,
            node._inverseWorldTransform)
    end
    if allocationProbe and node._inverseWorldTransform == nil then
        allocationProbe.pipelineInverseMissingNodes =
            allocationProbe.pipelineInverseMissingNodes + 1
        if defaultPresentation then
            allocationProbe.pipelineDefaultInverseMissingNodes =
                allocationProbe.pipelineDefaultInverseMissingNodes + 1
        end
    end
    local staticIdentity = node._worldTransform == IDENTITY
    local clipChildren = clipsChildren(node)
    if allocationProbe then
        local worldIdentity = matrixIsIdentity(node._worldTransform)
        if worldIdentity then
            allocationProbe.pipelineWorldIdentityNodes =
                allocationProbe.pipelineWorldIdentityNodes + 1
        end
        if staticIdentity then
            allocationProbe.pipelineVisualBoundsRestEquivalentNodes =
                allocationProbe.pipelineVisualBoundsRestEquivalentNodes + 1
        end
        if clipChildren then
            allocationProbe.pipelineClipNodes =
                allocationProbe.pipelineClipNodes + 1
            if not staticIdentity then
                allocationProbe.pipelineVisualContentBoundsRequiredNodes =
                    allocationProbe.pipelineVisualContentBoundsRequiredNodes
                        + 1
            end
        end
    end
    if allocationProbe then
        recordGeometryAllocation(allocationProbe,
            "pipelineInverseMatrixCreated",
            "pipelineInverseMatrixAllocatedKB", before,
            not existed and not staticPresentation
                and node._inverseWorldTransform ~= nil)
    end
    existed = node._visualBounds ~= nil
    before = allocationProbe and collectgarbage("count") or nil
    if staticIdentity then
        -- The authoritative flat layout fields already are the exact visual
        -- bounds for a static identity chain. Keeping a duplicate table would
        -- add no geometry and would be thrown away with this candidate.
        node._visualBounds = nil
    else
        local x1, y1 = point(node._worldTransform, node.layout.x, node.layout.y)
        local x2, y2 = point(node._worldTransform,
            node.layout.x + node.layout.width, node.layout.y)
        local x3, y3 = point(node._worldTransform,
            node.layout.x, node.layout.y + node.layout.height)
        local x4, y4 = point(node._worldTransform,
            node.layout.x + node.layout.width, node.layout.y + node.layout.height)
        node._visualBounds = writeBounds(node._visualBounds,
            x1, y1, x2, y2, x3, y3, x4, y4)
    end
    if allocationProbe then
        recordGeometryAllocation(allocationProbe,
            "pipelineVisualBoundsCreated",
            "pipelineVisualBoundsAllocatedKB", before,
            not existed and node._visualBounds ~= nil)
    end
    existed = node._visualContentBounds ~= nil
    before = allocationProbe and collectgarbage("count") or nil
    if clipChildren and not staticIdentity then
        local cx1, cy1 = point(node._worldTransform,
            node.layout.contentX, node.layout.contentY)
        local cx2, cy2 = point(node._worldTransform,
            node.layout.contentX + node.layout.contentWidth, node.layout.contentY)
        local cx3, cy3 = point(node._worldTransform,
            node.layout.contentX, node.layout.contentY + node.layout.contentHeight)
        local cx4, cy4 = point(node._worldTransform,
            node.layout.contentX + node.layout.contentWidth,
            node.layout.contentY + node.layout.contentHeight)
        node._visualContentBounds = writeBounds(node._visualContentBounds,
            cx1, cy1, cx2, cy2, cx3, cy3, cx4, cy4)
    else
        -- Content bounds are consumed only by clipping nodes. Identity clips
        -- read the authoritative content rectangle directly at the consumer.
        node._visualContentBounds = nil
    end
    if allocationProbe then
        recordGeometryAllocation(allocationProbe,
            "pipelineVisualContentBoundsCreated",
            "pipelineVisualContentBoundsAllocatedKB", before,
            not existed and node._visualContentBounds ~= nil)
    end
end

local function storeBoundary(instance, boundary)
    if not instance then return end
    instance._branchParentA, instance._branchParentB = boundary.a, boundary.b
    instance._branchParentC, instance._branchParentD = boundary.c, boundary.d
    instance._branchParentTx, instance._branchParentTy = boundary.tx, boundary.ty
end

local function boundaryIsValid(instance)
    return type(instance._branchParentA) == "number"
        and type(instance._branchParentB) == "number"
        and type(instance._branchParentC) == "number"
        and type(instance._branchParentD) == "number"
        and type(instance._branchParentTx) == "number"
        and type(instance._branchParentTy) == "number"
end

local function loadBoundary(instance, out)
    out.a, out.b = instance._branchParentA, instance._branchParentB
    out.c, out.d = instance._branchParentC, instance._branchParentD
    out.tx, out.ty = instance._branchParentTx, instance._branchParentTy
    return out
end

local function stampBranchInstance(instance, boundary, traversal, plane,
        preorder)
    if not instance then return end
    instance._branchTreeToken = traversal.token
    instance._branchGeneration = traversal.generation
    instance._branchPlane = plane
    instance._branchPreorderStart = preorder
    storeBoundary(instance, boundary)
end

local function stampFullNode(node, boundary, traversal, plane, preorder)
    stampBranchInstance(node._motion, boundary, traversal, plane, preorder)
    stampBranchInstance(node._radialDial, boundary, traversal, plane, preorder)
end

local function finishFullNode(node, preorderEnd)
    if node._motion then node._motion._branchPreorderEnd = preorderEnd end
    if node._radialDial then
        node._radialDial._branchPreorderEnd = preorderEnd
    end
end

local function beginPlane(traversal)
    traversal.nextPlane = traversal.nextPlane + 1
    return traversal.nextPlane
end

-- Full production traversal writes geometry and its acyclic branch metadata in
-- the same pass. Portal descendants get an independent interval namespace.
local function transformNode(node, parent, parentInverse, traversal, plane,
        preorder, isRoot)
    local boundary = node._portal and IDENTITY or parent or IDENTITY
    local inverseBoundary = node._portal and IDENTITY or parentInverse
    if isRoot or node._portal then
        plane = beginPlane(traversal)
        preorder = 0
    end
    preorder = preorder + 1
    stampFullNode(node, boundary, traversal, plane, preorder)
    transformNodeGeometry(node, boundary, inverseBoundary,
        traversal.allocationProbe, isRoot)
    traversal.nodesVisited = traversal.nodesVisited + 1
    local samePlaneEnd = preorder
    for _, child in ipairs(node.children or {}) do
        local childEnd = transformNode(child, node._worldTransform,
            node._inverseWorldTransform, traversal, plane, samePlaneEnd,
            false)
        if not child._portal then samePlaneEnd = childEnd end
    end
    finishFullNode(node, samePlaneEnd)
    return samePlaneEnd
end

-- Diagnostic full traversal observes the same single geometry write while
-- retaining the B4p.7 exact-branch and per-plane LCA measurements.
local function transformNodeObserved(node, parent, parentInverse, observer,
        dirtyAncestor, traversal, plane, preorder, isRoot)
    local boundary = node._portal and IDENTITY or parent or IDENTITY
    local inverseBoundary = node._portal and IDENTITY or parentInverse
    local previousPath
    if isRoot or node._portal then
        plane = beginPlane(traversal)
        preorder = 0
        if node._portal then
            dirtyAncestor = nil
            previousPath = observer.path
            observer.path = {}
        end
    end
    preorder = preorder + 1
    stampFullNode(node, boundary, traversal, plane, preorder)
    observer.nodesVisited = observer.nodesVisited + 1
    observer.path[#observer.path + 1] = node
    local isTarget = noteDiagnosticTarget(observer, plane, node)
    local isDirtyRoot = isTarget and dirtyAncestor == nil
    if isTarget then dirtyAncestor = node end
    transformNodeGeometry(node, boundary, inverseBoundary,
        traversal.allocationProbe, isRoot)
    traversal.nodesVisited = traversal.nodesVisited + 1
    local samePlaneEnd = preorder
    local samePlaneCount = 1
    for _, child in ipairs(node.children or {}) do
        local childEnd, childCount = transformNodeObserved(child,
            node._worldTransform, node._inverseWorldTransform, observer,
            dirtyAncestor, traversal, plane, samePlaneEnd, false)
        if not child._portal then
            samePlaneEnd = childEnd
            samePlaneCount = samePlaneCount + childCount
        end
    end
    finishFullNode(node, samePlaneEnd)
    if isDirtyRoot then
        observer.dirtyRoots = observer.dirtyRoots + 1
        observer.branchCoverage = observer.branchCoverage + samePlaneCount
    end
    local planeState = observer.planes[plane]
    if planeState and planeState.lcaPath
            and planeState.lcaPath[#planeState.lcaPath] == node then
        planeState.lcaCoverage = samePlaneCount
    end
    observer.path[#observer.path] = nil
    if previousPath then observer.path = previousPath end
    return samePlaneEnd, samePlaneCount
end

local function intervalIsValid(instance)
    local plane = instance._branchPlane
    local first = instance._branchPreorderStart
    local last = instance._branchPreorderEnd
    return type(plane) == "number" and plane > 0 and plane % 1 == 0
        and type(first) == "number" and first > 0 and first % 1 == 0
        and type(last) == "number" and last >= first and last % 1 == 0
end

local function branchOrder(left, right)
    if left._branchPlane ~= right._branchPlane then
        return left._branchPlane < right._branchPlane
    end
    if left._branchPreorderStart ~= right._branchPreorderStart then
        return left._branchPreorderStart < right._branchPreorderStart
    end
    return left._branchPreorderEnd > right._branchPreorderEnd
end

local function clearRoots(roots)
    for index = #roots, 1, -1 do roots[index] = nil end
end

local function fallback(roots, reason, pendingTargets)
    clearRoots(roots)
    return nil, reason, pendingTargets or 0, 0, 0
end

-- Builds the complete disjoint-root plan before the first geometry write.
-- It inspects only the pending set and stamped scalar metadata; committed
-- topology is immutable between successful Host candidates.
local function prepareBranches(root, request)
    local roots = request.roots
    clearRoots(roots)
    if request.requiresFull then
        return fallback(roots,
            request.fullReason or "non-motion-or-mixed", request.nodeCount)
    end
    if request.generation ~= root._motionTransformGeneration then
        return fallback(roots, "stale-generation", request.nodeCount)
    end
    if request.treeToken ~= root._motionTreeToken then
        return fallback(roots, "structural-token", request.nodeCount)
    end
    if type(root._motionTransformNodeCount) ~= "number"
            or root._motionTransformNodeCount < 1 then
        return fallback(roots, "missing-metadata", request.nodeCount)
    end
    local pendingTargets = 0
    for _ in pairs(request.nodes) do
        pendingTargets = pendingTargets + 1
    end
    if pendingTargets == 0 or pendingTargets ~= request.nodeCount then
        return fallback(roots, "node-set-mismatch", pendingTargets)
    end
    for instance in pairs(request.nodes) do
        local node = instance.node
        if not node or node._motion ~= instance
                and node._radialDial ~= instance then
            return fallback(roots, "detached", pendingTargets)
        end
        if instance._branchTreeToken ~= root._motionTreeToken then
            return fallback(roots, "detached", pendingTargets)
        end
        if instance._branchGeneration ~= root._motionTransformGeneration then
            return fallback(roots, "stale-node", pendingTargets)
        end
        if not intervalIsValid(instance) or not boundaryIsValid(instance) then
            return fallback(roots, "missing-metadata", pendingTargets)
        end
        roots[#roots + 1] = instance
    end
    table.sort(roots, branchOrder)
    local sourceCount, write, previous = #roots, 0, nil
    local descendantsSuppressed = 0
    for read = 1, sourceCount do
        local instance = roots[read]
        if previous and previous._branchPlane == instance._branchPlane
                and instance._branchPreorderStart
                    <= previous._branchPreorderEnd then
            if instance._branchPreorderEnd > previous._branchPreorderEnd then
                return fallback(roots, "ambiguous-overlap", pendingTargets)
            end
            descendantsSuppressed = descendantsSuppressed + 1
        else
            write = write + 1
            roots[write] = instance
            previous = instance
        end
    end
    for index = sourceCount, write + 1, -1 do roots[index] = nil end
    if write > BRANCH_ROOT_LIMIT then
        return fallback(roots, "root-limit", pendingTargets)
    end
    local coverage = 0
    for index = 1, write do
        local instance = roots[index]
        coverage = coverage + instance._branchPreorderEnd
            - instance._branchPreorderStart + 1
    end
    local coverageLimit = math.max(1,
        math.floor(root._motionTransformNodeCount * BRANCH_COVERAGE_FRACTION))
    if coverage > coverageLimit then
        return fallback(roots, "coverage-limit", pendingTargets)
    end
    return roots, nil, pendingTargets, write, descendantsSuppressed, coverage
end

local function transformBranch(node, parent, parentInverse, token, generation,
        plane, cursor)
    local motionInstance = node._motion
    local radialInstance = node._radialDial
    if motionInstance then
        assert(motionInstance.node == node
            and motionInstance._branchTreeToken == token
            and motionInstance._branchGeneration == generation
            and motionInstance._branchPlane == plane
            and motionInstance._branchPreorderStart == cursor,
            "FrogUI committed Motion topology changed before branch write")
    end
    if radialInstance then
        assert(radialInstance.node == node
            and radialInstance._branchTreeToken == token
            and radialInstance._branchGeneration == generation
            and radialInstance._branchPlane == plane
            and radialInstance._branchPreorderStart == cursor,
            "FrogUI committed RadialDial topology changed before branch write")
    end
    local boundary = node._portal and IDENTITY or parent
    local inverseBoundary = node._portal and IDENTITY or parentInverse
    if motionInstance then storeBoundary(motionInstance, boundary) end
    if radialInstance then storeBoundary(radialInstance, boundary) end
    transformNodeGeometry(node, boundary, inverseBoundary)
    local visited = 1
    local nextCursor = cursor + 1
    for _, child in ipairs(node.children or {}) do
        if not child._portal then
            local childCursor, childVisited = transformBranch(child,
                node._worldTransform, node._inverseWorldTransform, token,
                generation, plane, nextCursor)
            nextCursor = childCursor
            visited = visited + childVisited
        end
    end
    if motionInstance then
        assert(motionInstance._branchPreorderEnd == nextCursor - 1,
            "FrogUI committed Motion subtree changed during branch write")
    end
    if radialInstance then
        assert(radialInstance._branchPreorderEnd == nextCursor - 1,
            "FrogUI committed RadialDial subtree changed during branch write")
    end
    return nextCursor, visited
end

-- Marks the committed root's geometry stale. Motion and the two retained
-- layout mutators (Scroll and RadialDial) call this at their exact mutation
-- point. Callers pass the Host root explicitly so the tree remains acyclic.
-- The root bit remains the clean-skip authority. A Host may additionally route
-- its bounded committed Motion-only batch through exact branches; bare calls,
-- retained interaction layout, mixed causes, and unsafe metadata stay full.
function motion.invalidate(root)
    if not root then return end
    root._motionTransformDirty = true
end

-- Recomputes paint/input/F6 transforms only after layout or a clock tick
-- invalidates committed geometry. Motion matrices and all bounds retain
-- identity; static nodes alias their immutable transform boundary.
function motion.transformTree(root, diagnosticTargets, options,
        allocationProbe)
    if not root then
        return false, diagnosticTargets and { nodesVisited = 0 } or nil
    end
    if root._motionTransformReady and not root._motionTransformDirty then
        return false, diagnosticTargets and {
            nodesVisited = 0,
            mode = "skip",
            lcaMeasured = 0,
            branchRuns = 0,
            fullRuns = 0,
            fallbackRuns = 0,
            branchNodes = 0,
            fullNodes = 0,
            pendingTargets = 0,
            survivingRoots = 0,
            descendantsSuppressed = 0,
            routingTreeVisits = 0,
        } or nil
    end
    options = options or {}
    local branchRequest = options.branch
    local roots, fallbackReason, pendingTargets, survivingRoots
    local descendantsSuppressed, coverage
    if branchRequest then
        roots, fallbackReason, pendingTargets, survivingRoots,
            descendantsSuppressed, coverage = prepareBranches(root,
                branchRequest)
    end
    if roots then
        local visited = 0
        local boundary = branchRequest.boundary
        for index = 1, survivingRoots do
            local instance = roots[index]
            local node = instance.node
            local portal = node._portal
            local nextCursor, branchVisited = transformBranch(node,
                portal and IDENTITY or loadBoundary(instance, boundary),
                portal and IDENTITY or nil, root._motionTreeToken,
                root._motionTransformGeneration, instance._branchPlane,
                instance._branchPreorderStart)
            assert(nextCursor == instance._branchPreorderEnd + 1,
                "FrogUI committed transform interval ended unexpectedly")
            visited = visited + branchVisited
        end
        assert(visited == coverage,
            "FrogUI committed transform topology changed during branch write")
        root._motionTransformRevision =
            (root._motionTransformRevision or 0) + 1
        root._motionTransformReady = true
        root._motionTransformDirty = false
        if not diagnosticTargets then return true, nil end
        return true, {
            nodesVisited = visited,
            dirtyRoots = survivingRoots,
            branchCoverage = coverage,
            lcaCoverage = 0,
            lcaMeasured = 0,
            mode = "branch",
            branchRuns = 1,
            fullRuns = 0,
            fallbackRuns = 0,
            branchNodes = visited,
            fullNodes = 0,
            pendingTargets = pendingTargets,
            survivingRoots = survivingRoots,
            descendantsSuppressed = descendantsSuppressed,
            routingTreeVisits = 0,
        }
    end
    nextTransformTreeToken = nextTransformTreeToken + 1
    local traversal = options.scratch or {}
    traversal.allocationProbe = allocationProbe
    traversal.token = nextTransformTreeToken
    traversal.generation = options.generation
        or root._motionTransformGeneration or 0
    traversal.nextPlane = 0
    traversal.nodesVisited = 0
    local observer
    if diagnosticTargets then
        observer = {
            targets = diagnosticTargets,
            path = {},
            planes = {},
            nodesVisited = 0,
            dirtyRoots = 0,
            branchCoverage = 0,
            lcaCoverage = 0,
            lcaMeasured = 1,
            mode = "full",
            fallbackReason = fallbackReason,
            branchRuns = 0,
            fullRuns = 1,
            fallbackRuns = fallbackReason and 1 or 0,
            branchNodes = 0,
            fullNodes = 0,
            pendingTargets = pendingTargets or 0,
            survivingRoots = 0,
            descendantsSuppressed = 0,
            routingTreeVisits = 0,
        }
        transformNodeObserved(root, IDENTITY, IDENTITY, observer, nil,
            traversal, 0, 0, true)
        for _, planeState in pairs(observer.planes) do
            observer.lcaCoverage = observer.lcaCoverage
                + (planeState.lcaCoverage or 0)
        end
        observer.fullNodes = observer.nodesVisited
        observer.targets = nil
        observer.path = nil
        observer.planes = nil
    else
        transformNode(root, IDENTITY, IDENTITY, traversal, 0, 0, true)
    end
    root._motionTreeToken = traversal.token
    root._motionTransformGeneration = traversal.generation
    root._motionTransformNodeCount = traversal.nodesVisited
    root._motionTransformRevision = (root._motionTransformRevision or 0) + 1
    root._motionTransformReady = true
    root._motionTransformDirty = false
    traversal.allocationProbe = nil
    return true, observer
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
