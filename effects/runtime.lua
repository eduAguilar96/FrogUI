-- Retains finite Projectile, Flipbook, and ParticleBurst state across Host
-- reconciliation.
-- PopupText stays on the shared Motion runtime because its trajectory is a
-- pure local recipe; ref-following effects need endpoint-aware reprojection.

local Ref = require("src.frogui.ref")

local runtime = {}

local DEFAULTS = {
    fps = 24,
    frameHeight = 64,
    projectileRadius = 8,
    projectileCoreRatio = 0.45,
    trailDuration = 0.35,
    trailAlpha = 0.45,
    particleCount = 12,
    particleDistance = 52,
    particleRadius = 4,
    particleEndRadius = 0,
    particleSpread = math.pi * 2,
}
runtime.defaults = DEFAULTS

local MAX_PARTICLE_COUNT = 64
local RANDOM_MODULUS = 2147483647
local RANDOM_MULTIPLIER = 48271

runtime.maxParticleCount = MAX_PARTICLE_COUNT

local PARTICLE_CONTRACT_DEFAULTS = {
    count = DEFAULTS.particleCount,
    distance = DEFAULTS.particleDistance,
    angle = 0,
    spread = DEFAULTS.particleSpread,
    gravity = 0,
    radius = DEFAULTS.particleRadius,
    endRadius = DEFAULTS.particleEndRadius,
}

-- Creates one detached logical point.
local function point(x, y)
    return { x = x, y = y }
end

-- Copies an optional point so authored/runtime tables never alias.
local function copyPoint(value)
    return value and point(value.x, value.y) or nil
end

-- Copies every retained trail sample for transactional rollback.
local function copyTrail(values)
    local out = {}
    for index, value in ipairs(values or {}) do
        out[index] = { x = value.x, y = value.y, age = value.age }
    end
    return out
end

-- Copies one retained deterministic particle catalog and its sampled pose.
local function copyParticles(values)
    local out = {}
    for index, value in ipairs(values or {}) do
        out[index] = {
            angle = value.angle,
            distance = value.distance,
            radiusScale = value.radiusScale,
            x = value.x,
            y = value.y,
            radius = value.radius,
            alpha = value.alpha,
        }
    end
    return out
end

-- Returns a local deterministic scalar generator independent of simulation RNG.
local function randomSource(seed)
    local state = seed % RANDOM_MODULUS
    if state == 0 then state = 1 end
    return function()
        state = state * RANDOM_MULTIPLIER % RANDOM_MODULUS
        return (state - 1) / (RANDOM_MODULUS - 1)
    end
end

-- Generates one balanced cone/ring catalog exactly once for a keyed lifetime.
local function particleCatalog(props)
    local count = props.count or DEFAULTS.particleCount
    local distance = props.distance or DEFAULTS.particleDistance
    local spread = props.spread == nil and DEFAULTS.particleSpread
        or props.spread
    local centerAngle = props.angle or 0
    local random = randomSource(props.seed)
    local particles = {}
    for index = 1, count do
        local lane = (index - 0.5) / count
        local jitter = (random() - 0.5) * spread / count * 0.7
        particles[index] = {
            angle = centerAngle - spread / 2 + spread * lane + jitter,
            distance = distance * (0.62 + random() * 0.38),
            radiusScale = 0.72 + random() * 0.56,
        }
    end
    return particles
end

-- Compares two resolved anchors exactly in logical coordinates.
local function samePoint(left, right)
    return left and right and left.x == right.x and left.y == right.y
end

-- Captures only the viewport transform needed for physical reprojection.
local function viewport(host)
    local value = host._viewport
    return {
        x = value.x,
        y = value.y,
        scale = value.scale,
    }
end

-- Reports whether two virtual-to-physical transforms are equivalent.
local function sameViewport(left, right)
    return left and right and left.x == right.x and left.y == right.y
        and left.scale == right.scale
end

-- Preserves one physical point while the Host changes virtual viewport scale.
local function reproject(value, oldViewport, newViewport)
    if not value or not oldViewport or sameViewport(oldViewport, newViewport) then
        return copyPoint(value)
    end
    local physicalX = oldViewport.x + value.x * oldViewport.scale
    local physicalY = oldViewport.y + value.y * oldViewport.scale
    return point(
        (physicalX - newViewport.x) / newViewport.scale,
        (physicalY - newViewport.y) / newViewport.scale)
end

-- Clones one retained lifetime without replacing its identity token.
local function clone(old)
    return {
        identity = old.identity,
        lifetime = old.lifetime,
        type = old.type,
        order = old.order,
        node = old.node,
        props = old.props,
        reducedMotion = old.reducedMotion,
        travelClock = old.travelClock,
        frameClock = old.frameClock,
        lastTravelTime = old.lastTravelTime,
        lastFrameTime = old.lastFrameTime,
        elapsed = old.elapsed,
        frameElapsed = old.frameElapsed,
        duration = old.duration,
        source = copyPoint(old.source),
        target = copyPoint(old.target),
        head = copyPoint(old.head),
        segmentStart = copyPoint(old.segmentStart),
        segmentStartedAt = old.segmentStartedAt,
        center = copyPoint(old.center),
        trail = copyTrail(old.trail),
        particles = copyParticles(old.particles),
        frame = old.frame,
        rotation = old.rotation,
        visible = old.visible,
        contactFired = old.contactFired,
        completeFired = old.completeFired,
        viewport = old.viewport and {
            x = old.viewport.x,
            y = old.viewport.y,
            scale = old.viewport.scale,
        } or nil,
    }
end

-- Resolves the finite lifetime from one validated effect description.
local function durationFor(node)
    if node.type == "Projectile" or node.type == "ParticleBurst" then
        return node.props.duration
    end
    return #node.props.frames / (node.props.fps or DEFAULTS.fps)
end

-- Compares frame catalogs by ordered semantic asset identity.
local function sameFrames(left, right)
    left, right = left or {}, right or {}
    if #left ~= #right then return false end
    for index, value in ipairs(left) do
        if value ~= right[index] then return false end
    end
    return true
end

-- Normalizes an omitted particle option before comparing one retained key.
local function particleContractValue(props, name)
    if props[name] ~= nil then return props[name] end
    return PARTICLE_CONTRACT_DEFAULTS[name]
end

-- A stable key retains timing semantics; changing them starts a new key instead
-- of silently warping an already-visible lifetime.
local function validateRetainedContract(old, node)
    if node.type == "Projectile" then
        assert(old.duration == node.props.duration,
            "Projectile duration changed without a new key")
        assert((old.props.fps or DEFAULTS.fps)
                == (node.props.fps or DEFAULTS.fps),
            "Projectile fps changed without a new key")
        assert(sameFrames(old.props.frames, node.props.frames),
            "Projectile frames changed without a new key")
    elseif node.type == "Flipbook" then
        assert((old.props.fps or DEFAULTS.fps)
                == (node.props.fps or DEFAULTS.fps),
            "Flipbook fps changed without a new key")
        assert((old.props.contactAt or 1) == (node.props.contactAt or 1),
            "Flipbook contactAt changed without a new key")
        assert(sameFrames(old.props.frames, node.props.frames),
            "Flipbook frames changed without a new key")
    else
        local props = node.props
        assert(old.duration == props.duration,
            "ParticleBurst duration changed without a new key")
        for _, name in ipairs({
                "seed", "count", "distance", "angle", "spread",
                "gravity", "radius", "endRadius",
            }) do
            assert(particleContractValue(old.props, name)
                    == particleContractValue(props, name),
                "ParticleBurst " .. name .. " changed without a new key")
        end
    end
end

-- Reconciles one effect primitive while retaining its semantic lifetime.
function runtime.reconcile(old, node, identity, order, host)
    local compatible = old and old.type == node.type
    if compatible then validateRetainedContract(old, node) end
    local instance = compatible and clone(old) or {
        lifetime = {},
        elapsed = 0,
        frameElapsed = 0,
        segmentStartedAt = 0,
        trail = {},
        frame = 1,
        visible = true,
        contactFired = false,
        completeFired = false,
        particles = node.type == "ParticleBurst"
            and particleCatalog(node.props) or nil,
    }
    instance.identity = identity
    instance.type = node.type
    instance.order = order
    instance.node = node
    instance.props = node.props
    instance.reducedMotion = host.reducedMotion
    instance.duration = durationFor(node)

    local travelClock = node.props.clock or host._rawClock
    local frameClock = node.props.feedbackClock or travelClock
    if compatible then
        assert(instance.travelClock == travelClock,
            node.type .. " clock changed without a new key")
        assert(instance.frameClock == frameClock,
            node.type .. " feedbackClock changed without a new key")
    else
        instance.travelClock = travelClock
        instance.frameClock = frameClock
        instance.lastTravelTime = travelClock:now()
        instance.lastFrameTime = frameClock:now()
    end
    node._effect = instance
    return instance
end

-- Reads candidate geometry during build and committed geometry during updates.
local function resolveRect(handle, rectangles)
    if rectangles ~= nil then return rectangles[handle] end
    return handle.current
end

-- Resolves one ref center or one layer-local authored point.
local function resolveAnchor(anchor, offset, layer, rectangles)
    local result
    if Ref.isRef(anchor) then
        local rect = resolveRect(anchor, rectangles)
        if rect then
            result = point(rect.x + rect.width / 2, rect.y + rect.height / 2)
        end
    elseif anchor then
        result = point(layer.x + anchor.x, layer.y + anchor.y)
    end
    if result and offset then
        result.x = result.x + (offset.x or 0)
        result.y = result.y + (offset.y or 0)
    end
    return result
end

-- Reprojects the current head, segment, and trail into a new viewport.
local function reprojectProjectile(instance, nextViewport)
    if sameViewport(instance.viewport, nextViewport) then return end
    instance.head = reproject(instance.head, instance.viewport, nextViewport)
    instance.segmentStart = reproject(
        instance.segmentStart, instance.viewport, nextViewport)
    for _, sample in ipairs(instance.trail) do
        local moved = reproject(sample, instance.viewport, nextViewport)
        sample.x, sample.y = moved.x, moved.y
    end
end

-- Resolves candidate or committed anchors and rebases a moving head without
-- changing its elapsed/remaining lifetime.
local function arrangeProjectile(instance, rectangles, host)
    local props = instance.props
    local layer = assert(instance.node._effectLayerRect,
        "Projectile must be arranged directly inside Frog.EffectLayer")
    local nextViewport = viewport(host)
    reprojectProjectile(instance, nextViewport)
    local source = resolveAnchor(
        props.from, props.fromOffset, layer, rectangles) or instance.source
    local target = resolveAnchor(
        props.to, props.toOffset, layer, rectangles) or instance.target
    assert(source, "Projectile from ref is not attached to a primitive")
    assert(target, "Projectile to ref is not attached to a primitive")
    if not instance.head and source then
        instance.source = copyPoint(source)
        instance.head = copyPoint(source)
        instance.segmentStart = copyPoint(source)
        instance.segmentStartedAt = instance.elapsed
    end
    if target and (not instance.target or not samePoint(instance.target, target)) then
        if instance.head then
            instance.segmentStart = copyPoint(instance.head)
            instance.segmentStartedAt = instance.elapsed
        end
        instance.target = copyPoint(target)
    end
    instance.source = source and copyPoint(source) or instance.source
    if instance.reducedMotion and instance.target then
        instance.head = copyPoint(instance.target)
    end
    instance.viewport = nextViewport
end

-- Keeps a flipbook attached to its current semantic owner while preserving
-- elapsed time, current frame, and the already-fired contact bit.
local function arrangeFlipbook(instance, rectangles, host)
    local props = instance.props
    local layer = assert(instance.node._effectLayerRect,
        "Flipbook must be arranged directly inside Frog.EffectLayer")
    local center = resolveAnchor(
        props.at, props.atOffset, layer, rectangles) or instance.center
    assert(center, "Flipbook at ref is not attached to a primitive")
    instance.center = center
    instance.viewport = viewport(host)
end

-- Samples every particle pose from immutable seed output and absolute progress.
local function updateParticleGeometry(instance)
    if not instance.center then return end
    local props = instance.props
    local progress = instance.duration == 0 and 1
        or math.min(1, instance.elapsed / instance.duration)
    local elapsed = instance.duration * progress
    local startRadius = props.radius or DEFAULTS.particleRadius
    local endRadius = props.endRadius == nil
        and DEFAULTS.particleEndRadius or props.endRadius
    local gravity = props.gravity or 0
    for _, particle in ipairs(instance.particles) do
        particle.x = instance.center.x
            + math.cos(particle.angle) * particle.distance * progress
        particle.y = instance.center.y
            + math.sin(particle.angle) * particle.distance * progress
            + gravity * elapsed * elapsed / 2
        particle.radius = (startRadius
            + (endRadius - startRadius) * progress) * particle.radiusScale
        particle.alpha = 1 - progress
    end
end

-- Resolves every candidate effect against one complete arranged ref snapshot.
function runtime.arrangeAll(instances, rectangles, host)
    for _, instance in pairs(instances or {}) do
        if instance.type == "Projectile" then
            arrangeProjectile(instance, rectangles, host)
        else
            arrangeFlipbook(instance, rectangles, host)
            if instance.type == "ParticleBurst" then
                updateParticleGeometry(instance)
            end
        end
        instance.node._effect = instance
    end
end

-- Refreshes committed moving targets without rebuilding the component tree.
function runtime.refreshAll(instances, host)
    runtime.arrangeAll(instances, nil, host)
end

-- Samples one explicit clock monotonically for this mounted lifetime.
local function clockDelta(instance, clock, field)
    local now = clock:now()
    local previous = instance[field]
    if now < previous then previous = now end
    instance[field] = now
    return math.max(0, now - previous)
end

-- Captures one callback with the identity needed to reject stale delivery.
local function completion(instance, kind, callback)
    return {
        identity = instance.identity,
        lifetime = instance.lifetime,
        kind = kind,
        callback = callback,
        order = instance.order,
        source = instance.node.source,
    }
end

-- Selects a looping Projectile frame or a finite Flipbook frame.
local function updateFrame(instance, delta)
    instance.frameElapsed = instance.frameElapsed + delta
    local count = #(instance.props.frames or {})
    if count == 0 then
        instance.frame = nil
        return
    end
    local fps = instance.props.fps or DEFAULTS.fps
    if instance.type == "Projectile" then
        instance.frame = math.floor(instance.frameElapsed
            * fps) % count + 1
    else
        instance.frame = math.min(count,
            math.floor(instance.elapsed * fps) + 1)
    end
end

-- Advances one travel head, visual trail, and terminal arrival.
local function updateProjectile(instance, completions)
    local travelDelta = clockDelta(
        instance, instance.travelClock, "lastTravelTime")
    local frameDelta = clockDelta(
        instance, instance.frameClock, "lastFrameTime")
    instance.elapsed = instance.reducedMotion and instance.duration
        or math.min(instance.duration, instance.elapsed + travelDelta)
    updateFrame(instance, frameDelta)

    local props = instance.props
    for index = #instance.trail, 1, -1 do
        local sample = instance.trail[index]
        sample.age = sample.age + frameDelta
        if sample.age >= (props.trailDuration or DEFAULTS.trailDuration) then
            table.remove(instance.trail, index)
        end
    end
    if instance.head and (props.trailDuration or DEFAULTS.trailDuration) > 0
            and travelDelta > 0 and not instance.reducedMotion then
        table.insert(instance.trail, 1, {
            x = instance.head.x,
            y = instance.head.y,
            age = 0,
        })
    end

    if instance.reducedMotion then
        instance.head = copyPoint(instance.target or instance.head)
    elseif instance.head and instance.target then
        local remainingSpan = math.max(1e-12,
            instance.duration - instance.segmentStartedAt)
        local progress = math.min(1, math.max(0,
            (instance.elapsed - instance.segmentStartedAt) / remainingSpan))
        instance.head = point(
            instance.segmentStart.x
                + (instance.target.x - instance.segmentStart.x) * progress,
            instance.segmentStart.y
                + (instance.target.y - instance.segmentStart.y) * progress)
        instance.rotation = math.atan2(
            instance.target.y - instance.segmentStart.y,
            instance.target.x - instance.segmentStart.x)
    end
    if instance.elapsed >= instance.duration and not instance.completeFired then
        instance.completeFired = true
        instance.visible = false
        if props.onComplete then
            completions[#completions + 1] = completion(
                instance, "complete", props.onComplete)
        end
    end
end

-- Advances one finite frame sequence and its contact/completion beats.
local function updateFlipbook(instance, completions)
    local delta = clockDelta(instance,
        instance.travelClock, "lastTravelTime")
    instance.elapsed = instance.reducedMotion and instance.duration
        or math.min(instance.duration, instance.elapsed + delta)
    updateFrame(instance, delta)
    local props = instance.props
    local contactAt = instance.duration * (props.contactAt or 1)
    if instance.elapsed >= contactAt and not instance.contactFired then
        instance.contactFired = true
        if props.onContact then
            completions[#completions + 1] = completion(
                instance, "contact", props.onContact)
        end
    end
    if instance.elapsed >= instance.duration and not instance.completeFired then
        instance.completeFired = true
        instance.visible = false
        if props.onComplete then
            completions[#completions + 1] = completion(
                instance, "complete", props.onComplete)
        end
    end
end

-- Advances one deterministic burst and queues its terminal removal callback.
local function updateParticleBurst(instance, completions)
    local delta = clockDelta(instance,
        instance.travelClock, "lastTravelTime")
    instance.elapsed = instance.reducedMotion and instance.duration
        or math.min(instance.duration, instance.elapsed + delta)
    updateParticleGeometry(instance)
    if instance.elapsed >= instance.duration and not instance.completeFired then
        instance.completeFired = true
        instance.visible = false
        if instance.props.onComplete then
            completions[#completions + 1] = completion(
                instance, "complete", instance.props.onComplete)
        end
    end
end

-- Advances every committed effect and returns ordered terminal callbacks.
function runtime.updateAll(instances)
    local ordered, completions = {}, {}
    for _, instance in pairs(instances or {}) do ordered[#ordered + 1] = instance end
    table.sort(ordered, function(left, right) return left.order < right.order end)
    for _, instance in ipairs(ordered) do
        if instance.type == "Projectile" then
            updateProjectile(instance, completions)
        elseif instance.type == "ParticleBurst" then
            updateParticleBurst(instance, completions)
        else
            updateFlipbook(instance, completions)
        end
        instance.node._effect = instance
    end
    table.sort(completions, function(left, right)
        if left.order ~= right.order then return left.order < right.order end
        if left.kind ~= right.kind then return left.kind == "contact" end
        return left.identity < right.identity
    end)
    return completions
end

-- Confirms a queued terminal beat still belongs to the mounted keyed effect.
function runtime.completionIsMounted(instances, value)
    local instance = instances and instances[value.identity]
    if not instance or instance.lifetime ~= value.lifetime then return false end
    if value.kind == "contact" then return instance.contactFired end
    return instance.completeFired
end

-- Resolves exact painted size, including an available frame's aspect ratio.
local function visualSize(instance, host)
    local props = instance.props
    local frames = props.frames or {}
    local hasFrames = #frames > 0
    local height = props.height
        or (hasFrames and DEFAULTS.frameHeight
            or instance.type == "Projectile"
                and 2 * (props.radius or DEFAULTS.projectileRadius)
            or DEFAULTS.frameHeight)
    local width = props.width
    if not width and hasFrames and host then
        local source = instance.frame and frames[instance.frame]
        local asset = source and host:_asset(source) or nil
        if asset then
            local imageWidth, imageHeight = asset:getDimensions()
            width = height * imageWidth / imageHeight
        end
    end
    width = width or height
    return width, height
end

-- Publishes tight F6 bounds without making the whole EffectLayer selectable.
function runtime.updateBounds(instances, host)
    for _, instance in pairs(instances or {}) do
        if instance.type == "ParticleBurst" and instance.center then
            local source = instance.props.source
            local asset = source and host and host:_asset(source) or nil
            local aspect = 1
            if asset then
                local width, height = asset:getDimensions()
                aspect = width / height
            end
            local minX, minY = math.huge, math.huge
            local maxX, maxY = -math.huge, -math.huge
            for _, particle in ipairs(instance.particles) do
                local radius = math.max(0, particle.radius or 0)
                if radius > 0 and (particle.alpha or 0) > 0 then
                    local radiusX = radius * aspect
                    minX = math.min(minX, particle.x - radiusX)
                    maxX = math.max(maxX, particle.x + radiusX)
                    minY = math.min(minY, particle.y - radius)
                    maxY = math.max(maxY, particle.y + radius)
                end
            end
            instance.node._visualBounds = maxX == -math.huge and {
                x = instance.center.x,
                y = instance.center.y,
                width = 0,
                height = 0,
            } or {
                x = minX,
                y = minY,
                width = maxX - minX,
                height = maxY - minY,
            }
        else
            local center = instance.type == "Projectile" and instance.head
                or instance.center
            if center then
                local width, height = visualSize(instance, host)
                instance.node._visualBounds = {
                    x = center.x - width / 2,
                    y = center.y - height / 2,
                    width = width,
                    height = height,
                }
            end
        end
    end
end

-- Returns detached lifecycle metadata for F6 and focused checks.
function runtime.inspect(instance)
    return {
        kind = instance.type,
        elapsed = instance.elapsed,
        duration = instance.duration,
        progress = instance.duration == 0 and 1
            or instance.elapsed / instance.duration,
        frame = instance.frame,
        frameCount = #(instance.props.frames or {}),
        head = copyPoint(instance.head or instance.center),
        target = copyPoint(instance.target),
        trailCount = #instance.trail,
        contactFired = instance.contactFired,
        completeFired = instance.completeFired,
        reducedMotion = instance.reducedMotion,
        particleCount = #(instance.particles or {}),
        seed = instance.type == "ParticleBurst" and instance.props.seed or nil,
    }
end

return runtime
