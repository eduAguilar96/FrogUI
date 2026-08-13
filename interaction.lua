-- Owns FrogUI's generic pointer session, retained Scroll state, modal input
-- isolation, and source-owned drag/drop lifecycle. Application components see
-- only the small primitive props exported by src/frogui/init.lua.

local Message = require("src.frogui.message")
local Motion = require("src.frogui.motion")

local interaction = {}
local stageSound

-- Selects the Host's existing stopped-collector diagnostics row. Ordinary
-- Hosts take the nil path and keep no interaction observer state.
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

interaction.HOLD_SECONDS = 0.35
interaction.CLAIM_DISTANCE = 8
interaction.AXIS_BIAS = 1.25
interaction.WHEEL_STEP = 40
interaction.MOMENTUM_FRICTION = 12

-- HorizontalSwipe intentionally preserves Battle's proven two-stage feel:
-- qualifying horizontal movement first suppresses a descendant inspection
-- action, while only a longer release commits the semantic swipe. This is the
-- sole code authority; application components and docs never repeat values.
local HORIZONTAL_SWIPE = {
    claimDistance = 12,
    commitDistance = 60,
    axisBias = 1.5,
}

-- RadialDial owns angular preview internally. Callers provide only controlled
-- values and receive one settled numeric value after release/key activation.
local RADIAL_DIAL = {
    dragRadians = 0.10,
    deadZoneRatio = 0.12,
    settleSpeed = 10,
    bounceAmplitude = 0.05,
    bounceDuration = 0.28,
}

local function normalizeAngle(value)
    while value > math.pi do value = value - math.pi * 2 end
    while value < -math.pi do value = value + math.pi * 2 end
    return value
end

local function radialStep(count)
    return math.pi * 2 / count
end

local function radialAngle(index, count)
    return -(index - 1) * radialStep(count)
end

local function radialIndex(angle, count)
    return math.floor(-angle / radialStep(count) + 0.5) % count + 1
end

local function radialSignature(values)
    local parts = { tostring(#values) }
    for index, value in ipairs(values) do
        parts[index + 1] = string.format("%.17g", value)
    end
    return table.concat(parts, ":")
end

local function radialTarget(angle, index, count)
    local canonical = radialAngle(index, count)
    return angle + normalizeAngle(canonical - angle)
end

local function copyRadial(instance)
    if not instance then return nil end
    local values = {}
    for index, value in ipairs(instance.values) do values[index] = value end
    return {
        identity = instance.identity,
        signature = instance.signature,
        values = values,
        value = instance.value,
        index = instance.index,
        angle = instance.angle,
        targetAngle = instance.targetAngle,
        previewAngle = instance.previewAngle,
        bounce = instance.bounce,
        reducedMotion = instance.reducedMotion,
        trackRadius = instance.trackRadius,
        geometrySignature = instance.geometrySignature,
        optionSizes = instance.optionSizes,
        pendingCommit = instance.pendingCommit and {
            value = instance.pendingCommit.value,
            restartBounce = instance.pendingCommit.restartBounce,
        } or nil,
        node = instance.node,
    }
end

-- Retains the visual settle process while the keyed controlled dial remains
-- compatible. The application owns only value; angular state stays here.
function interaction.reconcileRadialDial(old, node, props, identity, reducedMotion)
    local values, index = {}, nil
    for position, value in ipairs(props.values) do
        values[position] = value
        if value == props.value then index = position end
    end
    local signature = radialSignature(values)
    local compatible = old and old.signature == signature
    local controlledChanged = compatible and old.value ~= props.value
    local instance = compatible and copyRadial(old) or {
        angle = radialAngle(index, #values),
        bounce = 0,
    }
    instance.identity = identity
    instance.signature = signature
    instance.values = values
    instance.value = props.value
    instance.index = assert(index, "RadialDial value must occur in values")
    instance.targetAngle = radialTarget(instance.angle, index, #values)
    instance.previewAngle = nil
    instance.node = node
    instance.reducedMotion = reducedMotion == true
    if controlledChanged then
        local internalCommit = instance.pendingCommit
            and instance.pendingCommit.value == props.value
        if not internalCommit or instance.pendingCommit.restartBounce then
            instance.bounce = reducedMotion and 0 or 1
        end
    end
    instance.pendingCommit = nil
    if reducedMotion or not compatible then
        instance.angle = instance.targetAngle
        instance.bounce = 0
    end
    node._radialDial = instance
    return instance
end

-- Internal check seam. Values remain code-owned rather than copied into docs.
function interaction.radialDialPolicy()
    return {
        dragRadians = RADIAL_DIAL.dragRadians,
        deadZoneRatio = RADIAL_DIAL.deadZoneRatio,
        settleSpeed = RADIAL_DIAL.settleSpeed,
        bounceAmplitude = RADIAL_DIAL.bounceAmplitude,
        bounceDuration = RADIAL_DIAL.bounceDuration,
    }
end

-- Returns the current visual angle and bounce scale without exposing either to
-- application components.
function interaction.radialPresentation(node)
    local dial = assert(node._radialDial, "unprepared RadialDial")
    return {
        angle = dial.previewAngle or dial.angle,
        scale = 1 + RADIAL_DIAL.bounceAmplitude
            * math.sin((dial.bounce or 0) * math.pi),
    }
end

-- Keeps arranged option centers and transformed/F6 bounds truthful in the
-- same pointer frame without asking application code to rerender.
local function refreshRadial(host, node, detail)
    local row = runtimeAllocationRow(host)
    local refreshBefore = row and collectgarbage("count") or nil
    local arrangeBefore = row and collectgarbage("count") or nil
    require("src.frogui.layout").orbitRadialDial(node, host)
    recordRuntimeAllocation(row,
        "interactionRadialArrangeCalls",
        "interactionRadialArrangeAllocatedKB", arrangeBefore)
    local invalidateBefore = row and collectgarbage("count") or nil
    host:_invalidateTransform(node, "RadialDial", detail)
    recordRuntimeAllocation(row,
        "interactionRadialInvalidateCalls",
        "interactionRadialInvalidateAllocatedKB", invalidateBefore)
    local transformBefore = row and collectgarbage("count") or nil
    local _, transform = host:_transformTree(nil, "interactionTransform")
    recordRuntimeAllocation(row,
        "interactionRadialTransformCalls",
        "interactionRadialTransformAllocatedKB", transformBefore)
    -- RadialDial option descendants are contractually static and ref-free.
    -- The dial root may own a ref, but its arranged rectangle does not move
    -- when options orbit, so its already-published rectangle remains exact.
    local refsBefore = row and collectgarbage("count") or nil
    recordRuntimeAllocation(row,
        "interactionRadialRefsCalls",
        "interactionRadialRefsAllocatedKB", refsBefore)
    recordRuntimeAllocation(row,
        "interactionRadialRefreshCalls",
        "interactionRadialRefreshAllocatedKB", refreshBefore)
end

-- Internal check seam. Returns a copy so tests cannot mutate input policy.
function interaction.horizontalSwipePolicy()
    return {
        claimDistance = HORIZONTAL_SWIPE.claimDistance,
        commitDistance = HORIZONTAL_SWIPE.commitDistance,
        axisBias = HORIZONTAL_SWIPE.axisBias,
    }
end

local function snapshotPlain(value, label, seen)
    return Message.snapshotPlain(value, label, seen)
end

interaction.snapshotPlain = snapshotPlain

local function validatePointer(event)
    assert(type(event.pointerId) == "string" and event.pointerId ~= "",
        "drag pointerId must be a non-empty normalized string")
    local payload = assert(event.payload, "drag event requires payload")
    assert(type(payload) == "table" and type(payload.kind) == "string"
            and payload.kind ~= "", "drag payload requires a non-empty kind")
end

local DragStarted = Message.event("frog.drag-started", validatePointer)
local DragEnded = Message.event("frog.drag-ended", function(event)
    validatePointer(event)
    assert(event.status == "committed" or event.status == "rejected"
            or event.status == "cancelled", "invalid drag completion status")
end)

interaction.events = {
    DragStarted = DragStarted,
    DragEnded = DragEnded,
}

local function copyScroll(instance)
    if not instance then return nil end
    return {
        identity = instance.identity,
        axis = instance.axis,
        offset = instance.offset,
        velocity = instance.velocity,
        extent = instance.extent,
        viewport = instance.viewport,
        content = instance.content,
        node = instance.node,
    }
end

function interaction.reconcileScroll(old, node, props, identity)
    local compatible = old and old.axis == props.axis
    local instance = compatible and copyScroll(old) or {
        identity = identity,
        axis = props.axis,
        offset = 0,
        velocity = 0,
        extent = 0,
        viewport = 0,
        content = 0,
    }
    instance.identity = identity
    instance.axis = props.axis
    instance.node = node
    if props.scrollPosition ~= nil then
        instance.offset = props.scrollPosition
        instance.velocity = 0
    end
    node._scroll = instance
    return instance
end

local function localInside(node, x, y)
    local localX, localY = Motion.localPoint(node, x, y)
    return localX >= node.layout.x and localY >= node.layout.y
        and localX <= node.layout.x + node.layout.width and localY <= node.layout.y + node.layout.height
end

local function insideContent(node, x, y)
    local localX, localY = Motion.localPoint(node, x, y)
    return localX >= node.layout.contentX and localY >= node.layout.contentY
        and localX <= node.layout.contentX + node.layout.contentWidth
        and localY <= node.layout.contentY + node.layout.contentHeight
end

local function clipped(node)
    return node.type == "Scroll" or node.props.clip
        or node.props.overflow == "clip"
end

local POINTER_TYPES = {
    Button = true, Pressable = true, HorizontalSwipe = true,
    TextInput = true, RadialDial = true, DragSource = true, Scroll = true,
}

local function radialInside(node, x, y)
    local localX, localY = Motion.localPoint(node, x, y)
    local centerX, centerY = node.layout.x + node.layout.width / 2, node.layout.y + node.layout.height / 2
    local dx, dy = localX - centerX, localY - centerY
    local radius = math.min(node.layout.width, node.layout.height) / 2
    return dx * dx + dy * dy <= radius * radius
end

local function hitPath(node, x, y, predicate)
    if node.type == "EffectLayer" then return nil end
    local contained = localInside(node, x, y)
    if clipped(node) and (not contained or not insideContent(node, x, y)) then
        return nil
    end
    for index = #node.children, 1, -1 do
        local childPath = hitPath(node.children[index], x, y, predicate)
        if childPath then
            table.insert(childPath, 1, node)
            return childPath
        end
    end
    if contained and predicate(node) then return { node } end
    return nil
end

local function findIdentity(node, identity)
    if not node then return nil end
    if node.identity == identity then return node end
    for _, child in ipairs(node.children or {}) do
        local found = findIdentity(child, identity)
        if found then return found end
    end
end

local function identityPath(node, identity, output)
    if not node then return nil end
    output = output or {}
    output[#output + 1] = node
    if node.identity == identity then return output end
    for _, child in ipairs(node.children or {}) do
        local found = identityPath(child, identity, output)
        if found then return found end
    end
    output[#output] = nil
end

local function activeRoot(host)
    return host._modal or host._tree
end

-- Returns input planes from highest to lowest. Chrome participates beside the
-- base tree, or above only a top Modal that explicitly opts into it.
local function inputRoots(host)
    local modal = host._modal
    local chrome = host._chrome
    if modal then
        if chrome and modal.props.allowChrome == true then
            return { chrome, modal }
        end
        return { modal }
    end
    if chrome then return { chrome, host._tree } end
    return host._tree and { host._tree } or {}
end

local function findActiveIdentity(host, identity)
    if not identity then return nil end
    for _, root in ipairs(inputRoots(host)) do
        local found = findIdentity(root, identity)
        if found then return found end
    end
end

local function pointerPath(host, x, y)
    for _, root in ipairs(inputRoots(host)) do
        local path = hitPath(root, x, y, function(node)
            return POINTER_TYPES[node.type] == true
                and (node.type ~= "RadialDial" or radialInside(node, x, y))
        end)
        if path then return path, root end
    end
end

local function radialPoint(node, x, y)
    local localX, localY = Motion.localPoint(node, x, y)
    local centerX, centerY = node.layout.x + node.layout.width / 2, node.layout.y + node.layout.height / 2
    local dx, dy = localX - centerX, localY - centerY
    return dx, dy, math.sqrt(dx * dx + dy * dy),
        math.min(node.layout.width, node.layout.height) / 2
end

local function beginRadial(host, node, session, x, y)
    local dx, dy, distance, radius = radialPoint(node, x, y)
    local dial = node._radialDial
    session.claimed = "radial-dial"
    session.radialIdentity = node.identity
    session.radialSignature = dial.signature
    session.radialValue = dial.value
    session.radialBounds = {
        x = node.layout.x, y = node.layout.y, width = node.layout.width, height = node.layout.height,
    }
    session.radialGeometrySignature = dial.geometrySignature
    session.radialPointerAngle = distance > radius * RADIAL_DIAL.deadZoneRatio
        and math.atan2(dy, dx) or nil
    session.radialAccumulated = 0
    session.radialBaseAngle = dial.angle
    session.radialPreviewAngle = dial.angle
    session.radialPreviewIndex = dial.index
    if distance == 0 then
        session.radialTapStep = nil
    else
        session.radialTapStep = dx < 0 and -1 or 1
    end
    session.radialMoved = false
    dial.bounce = host.reducedMotion and 0 or 1
    host._focusedIdentity = node.identity
    host._pressedIdentity = nil
end

local function moveRadial(host, session, x, y)
    local node = findActiveIdentity(host, session.radialIdentity)
    if not node then return end
    local dx, dy, distance, radius = radialPoint(node, x, y)
    if distance <= radius * RADIAL_DIAL.deadZoneRatio then
        session.radialPointerAngle = nil
        return
    end
    local pointerAngle = math.atan2(dy, dx)
    if session.radialPointerAngle == nil then
        session.radialPointerAngle = pointerAngle
        return
    end
    local delta = normalizeAngle(pointerAngle - session.radialPointerAngle)
    session.radialPointerAngle = pointerAngle
    session.radialAccumulated = session.radialAccumulated + delta
    if math.abs(session.radialAccumulated) > RADIAL_DIAL.dragRadians
            and not session.radialMoved then
        session.radialMoved = true
        host:_runCallback(function()
            stageSound(host, node.props.spinSound, "dialSpin")
        end, "RadialDial:spin:" .. node.identity, node.source)
    end
    if session.radialMoved then
        session.radialPreviewAngle = session.radialBaseAngle
            + session.radialAccumulated
        session.radialPreviewIndex = radialIndex(
            session.radialPreviewAngle, #node._radialDial.values)
        node._radialDial.previewAngle = session.radialPreviewAngle
        refreshRadial(host, node, "drag")
    end
end

local function armRadialSettle(host, node, restartBounce)
    local dial = node._radialDial
    dial.angle = dial.previewAngle or dial.angle
    dial.previewAngle = nil
    dial.targetAngle = radialTarget(dial.angle, dial.index, #dial.values)
    if restartBounce then dial.bounce = host.reducedMotion and 0 or 1 end
    if host.reducedMotion then dial.angle = dial.targetAngle end
    refreshRadial(host, node, "settle")
end

local function commitRadial(host, node, value, restartBounce, origin)
    local ok, reason = pcall(host._runCallback, host, function()
        node._radialDial.pendingCommit = {
            value = value,
            restartBounce = restartBounce == true,
        }
        stageSound(host, node.props.sound, "dialCommit")
        node.props.onChange(value)
    end,
        origin or ("RadialDial:" .. node.identity), node.source)
    local current = findActiveIdentity(host, node.identity)
    if current and current._radialDial then
        current._radialDial.pendingCommit = nil
    end
    if not ok then error(reason, 0) end
end

-- Handles only focused dial keys. Application-owned Button shortcuts remain
-- authoritative because the Host resolves them before this fallback.
function interaction.keyRadialDial(host, node, key)
    if not node or node.type ~= "RadialDial" or node.props.disabled then
        return false
    end
    local dial = node._radialDial
    local index
    if key == "left" or key == "down" then
        index = (dial.index - 2) % #dial.values + 1
    elseif key == "right" or key == "up"
            or key == "return" or key == "space" or key == "kpenter" then
        index = dial.index % #dial.values + 1
    elseif key == "home" then
        index = 1
    elseif key == "end" then
        index = #dial.values
    else
        return false
    end
    armRadialSettle(host, node, true)
    commitRadial(host, node, dial.values[index], true,
        "RadialDial:key:" .. node.identity)
    return true
end

local function deepestOf(path, kind, predicate)
    for index = #(path or {}), 1, -1 do
        local node = path[index]
        if node.type == kind and (not predicate or predicate(node)) then
            return node
        end
    end
end

local function scrollable(node)
    return node and node._scroll and node._scroll.extent > 0
end

local function nearestScroll(path)
    return deepestOf(path, "Scroll", scrollable)
end

local function buttonAvailable(host, node)
    return not node.props.disabled
        and not host._spentAuthorities[node.identity]
end

local function hoverNode(host, x, y)
    local path = pointerPath(host, x, y)
    return deepestOf(path, "Pressable")
        or deepestOf(path, "Button", function(node)
            return buttonAvailable(host, node)
        end)
end

-- Resolves a primitive cue override against the application theme defaults.
local function soundCue(host, override, defaultKey)
    if override == false then return nil end
    return override or (host.theme.sounds or {})[defaultKey]
end

-- Stages sound with the surrounding Host transaction when one is declared.
stageSound = function(host, override, defaultKey)
    local cue = soundCue(host, override, defaultKey)
    if cue then host:_stageFeedback("sound", cue) end
end

local function setHover(host, nextNode, pointerId)
    if pointerId ~= "mouse" then nextNode = nil end
    local previousIdentity = host._hoveredIdentity
    local nextIdentity = nextNode and nextNode.identity or nil
    if previousIdentity == nextIdentity then return end
    local previous = findActiveIdentity(host, previousIdentity)
    local previousCallback = previous
        and (previous.type == "Pressable" or previous.type == "Button")
        and previous.props.onHoverChange or nil
    local nextCallback = nextNode
        and (nextNode.type == "Pressable" or nextNode.type == "Button")
        and nextNode.props.onHoverChange or nil
    local nextSound = nextNode and soundCue(
        host, nextNode.props.hoverSound, "hover") or nil
    if previousCallback or nextCallback or nextSound then
        host:_runCallback(function()
            host._hoveredIdentity = nextIdentity
            if previousCallback then previousCallback(false) end
            if nextSound then host:_stageFeedback("sound", nextSound) end
            if nextCallback then nextCallback(true) end
        end, "FrogUI:hover", nextNode and nextNode.source or nil)
    else
        host._hoveredIdentity = nextIdentity
    end
end

local function enqueueEvent(host, record, origin)
    host:_enqueueEvent(record, origin)
end

local function notifyDragEnd(host, session, status, safeDetail, terminal)
    host:_runCallback(function()
        if not terminal then
            host._interactionSession = nil
            host._pressedIdentity = nil
            session.ended = true
        end
        if status == "committed" then
            stageSound(host, session.source.props.dropSound, "dragDrop")
        elseif status == "rejected" then
            stageSound(host, session.source.props.rejectSound, "reject")
        end
        if session.onDragEnd then session.onDragEnd(status, safeDetail) end
        enqueueEvent(host, DragEnded {
            pointerId = session.pointerId,
            payload = snapshotPlain(session.payload, "drag payload"),
            status = status,
            detail = safeDetail,
        }, "DragSource:" .. session.sourceIdentity)
    end, "DragSource:end", session.source and session.source.source)
end

local function finishDrag(host, session, status, detail, target)
    local safeDetail = detail == nil and nil
        or snapshotPlain(detail, "drag completion detail")
    local terminal = false
    if target then
        -- A compatible drop may cross an irreversible domain boundary. End
        -- capture before invoking it so a throw can never retry the same Run
        -- command. The dedicated callback also refuses Frog.send/Frog.emit.
        host._interactionSession = nil
        host._pressedIdentity = nil
        session.ended = true
        terminal = true
        local ok, returned = host:_runDropCallback(session.onDrop,
            snapshotPlain(session.payload, "drag payload"), {
                key = target.key,
                address = snapshotPlain(target.address,
                    "drop target address"),
            })
        status = ok and "committed" or "rejected"
        safeDetail = returned
    end
    notifyDragEnd(host, session, status, safeDetail, terminal)
    return status, safeDetail
end

function interaction.cancel(host, reason)
    local session = host._interactionSession
    if not session then return false end
    if session.claimed == "drag" then
        finishDrag(host, session, "cancelled", reason or "cancelled")
    else
        if session.radialIdentity then
            local radial = findActiveIdentity(host, session.radialIdentity)
            if radial and radial._radialDial then
                local dial = radial._radialDial
                dial.angle = dial.previewAngle or dial.angle
                dial.previewAngle = nil
                dial.targetAngle = radialTarget(
                    dial.angle, dial.index, #dial.values)
                if host.reducedMotion then dial.angle = dial.targetAngle end
                refreshRadial(host, radial, "settle")
            end
        end
        host._interactionSession = nil
        host._pressedIdentity = nil
    end
    return true
end

local function normalizedPayload(node)
    local payload = snapshotPlain(node.props.payload, "DragSource payload")
    assert(type(payload.kind) == "string" and payload.kind ~= "",
        "DragSource payload requires a non-empty string kind")
    return payload
end

local function beginDrag(host, session)
    host:_runCallback(function()
        session.claimed = "drag"
        session.source = findActiveIdentity(host, session.sourceIdentity)
            or session.source
        host._pressedIdentity = nil
        stageSound(host, session.source.props.grabSound, "dragGrab")
        if session.onDragStart then
            session.onDragStart(snapshotPlain(session.payload, "drag payload"))
        end
        enqueueEvent(host, DragStarted {
            pointerId = session.pointerId,
            payload = snapshotPlain(session.payload, "drag payload"),
        }, "DragSource:" .. session.sourceIdentity)
    end, "DragSource:start", session.source and session.source.source)
end

local function claimGesture(host, session, dx, dy)
    local scroll = session.scrollIdentity
        and (host._scrolls or {})[session.scrollIdentity] or nil
    local hasScroll = scroll and scroll.extent > 0
    local hasDrag = session.sourceIdentity ~= nil
    if not hasScroll and not hasDrag then
        session.claimed = "moved"
        host._pressedIdentity = nil
        return
    end
    if hasScroll and hasDrag then
        local primary = scroll.axis == "vertical" and math.abs(dy) or math.abs(dx)
        local cross = scroll.axis == "vertical" and math.abs(dx) or math.abs(dy)
        if primary >= cross * interaction.AXIS_BIAS then
            session.claimed = "scroll"
        else
            beginDrag(host, session)
        end
    elseif hasScroll then
        session.claimed = "scroll"
    else
        beginDrag(host, session)
    end
    if session.claimed == "scroll" then
        host._pressedIdentity = nil
        scroll.velocity = 0
        session.lastAxis = scroll.axis == "vertical" and session.y or session.x
        session.lastMoveTime = host._rawClock:now()
    end
end

-- Advances the one unresolved pointer through framework-owned arbitration.
-- HorizontalSwipe remains a candidate while a descendant press is provisional;
-- no claimed owner is ever transferred to another recognizer.
local function updatePointerClaim(host, session, dx, dy, fromRelease)
    if session.claimed then return end
    local dragOrScroll = session.sourceIdentity or session.scrollIdentity
    if dragOrScroll then
        -- Existing DragSource/Scroll ownership begins only from a delivered
        -- move. A coalesced release may finish HorizontalSwipe, but must not
        -- silently broaden those older primitives' lifecycle.
        if not fromRelease
                and session.distance >= interaction.CLAIM_DISTANCE then
            claimGesture(host, session, dx, dy)
        end
        return
    end
    if session.swipeIdentity then
        if session.distance > HORIZONTAL_SWIPE.claimDistance then
            session.swipePending = true
        end
        if math.abs(dx) > HORIZONTAL_SWIPE.claimDistance
                and math.abs(dx) > math.abs(dy) * HORIZONTAL_SWIPE.axisBias then
            session.claimed = "horizontal-swipe"
            session.swipeDirection = dx < 0 and "left" or "right"
            session.pressSuppressed = true
            host._pressedIdentity = nil
        elseif session.swipeTapBlocked
                and session.distance >= HORIZONTAL_SWIPE.commitDistance then
            -- Preserve hold tolerance during moderate off-axis jitter. At the
            -- semantic band shipped descendant inspection becomes terminal
            -- dragging, so this path cannot become either a press or swipe.
            -- A blank arena path has no inspection owner and stays eligible.
            session.claimed = "moved"
            session.pressSuppressed = true
            host._pressedIdentity = nil
        end
        return
    end
    if session.distance >= interaction.CLAIM_DISTANCE then
        claimGesture(host, session, dx, dy)
    end
end

-- A swipe surface deliberately keeps descendant tap tolerance through its
-- private claim boundary. Other pointer primitives retain the original
-- generic tolerance; callers do not need to understand either policy.
local function tapEligible(session)
    if session.swipeIdentity then
        return not session.swipePending
            and session.distance <= HORIZONTAL_SWIPE.claimDistance
    end
    return session.distance < interaction.CLAIM_DISTANCE
end

function interaction.pointerDown(host, x, y, pointerId, button)
    if button ~= nil and button ~= 1 then return host._modal ~= nil end
    host._pointerX, host._pointerY = x, y
    if host._interactionSession then return true end
    local modal = host._modal
    local path, pathRoot = pointerPath(host, x, y)
    if modal and (not host._chrome or pathRoot ~= host._chrome) then
        local child = modal.children[1]
        if not child or not localInside(child, x, y) then
            host._interactionSession = {
                kind = "modal-outside", pointerId = pointerId,
                x0 = x, y0 = y, x = x, y = y, modalIdentity = modal.identity,
            }
            return true
        end
    end
    if not path then return modal ~= nil end
    local press = deepestOf(path, "Pressable")
        or deepestOf(path, "Button", function(node)
            return buttonAvailable(host, node)
        end)
    local pressSurface = deepestOf(path, "Pressable")
        or deepestOf(path, "Button")
    local textInput = deepestOf(path, "TextInput",
        function(node) return not node.props.disabled end)
    local radial = deepestOf(path, "RadialDial",
        function(node) return not node.props.disabled end)
    local swipe = not radial and deepestOf(path, "HorizontalSwipe") or nil
    local source = deepestOf(path, "DragSource")
    local scroll = nearestScroll(path)
    if not press and not textInput and not swipe and not radial
            and not source and not scroll then
        return modal ~= nil
    end
    local session = {
        kind = "pointer", pointerId = pointerId,
        x0 = x, y0 = y, x = x, y = y,
        started = host._rawClock:now(), elapsed = 0, distance = 0,
        pressIdentity = press and press.identity or nil,
        pressType = press and press.type or nil,
        textInputIdentity = textInput and textInput.identity or nil,
        swipeIdentity = swipe and swipe.identity or nil,
        swipeTapBlocked = pressSurface ~= nil,
        sourceIdentity = source and source.identity or nil,
        scrollIdentity = scroll and scroll.logicalIdentity or nil,
    }
    if source then
        session.source = source
        session.payload = normalizedPayload(source)
        session.onDrop = source.props.onDrop
        session.onDragStart = source.props.onDragStart
        session.onDragEnd = source.props.onDragEnd
    end
    host._interactionSession = session
    host._pressedIdentity = press and press.identity or nil
    if radial and not press and not source and not scroll then
        beginRadial(host, radial, session, x, y)
    elseif press and press.type == "Button" then
        host._focusedIdentity = press.identity
    elseif textInput then
        host._focusedIdentity = textInput.identity
    end
    setHover(host, hoverNode(host, x, y), pointerId)
    return true
end

local function acceptedTarget(host, x, y, kind)
    for _, root in ipairs(inputRoots(host)) do
        local path = hitPath(root, x, y, function(node)
            return node.type == "DropTarget" and node.props.accepts == kind
        end)
        local node = deepestOf(path, "DropTarget",
            function(candidate) return candidate.props.accepts == kind end)
        if node then
            return {
                identity = node.identity,
                key = node.key,
                address = snapshotPlain(node.props.address,
                    "DropTarget address"),
                node = node,
            }
        end
    end
end

function interaction.pointerMove(host, x, y, pointerId)
    host._pointerX, host._pointerY = x, y
    local session = host._interactionSession
    if not session then
        setHover(host, hoverNode(host, x, y), pointerId)
        return host._modal ~= nil
    end
    if session.pointerId ~= pointerId then return true end
    session.x, session.y = x, y
    local dx, dy = x - session.x0, y - session.y0
    session.distance = math.sqrt(dx * dx + dy * dy)
    if session.kind == "modal-outside" then return true end
    if session.claimed == "radial-dial" then
        moveRadial(host, session, x, y)
        return true
    end
    updatePointerClaim(host, session, dx, dy)
    if session.claimed == "scroll" then
        local scroll = (host._scrolls or {})[session.scrollIdentity]
        if scroll then
            local axis = scroll.axis == "vertical" and y or x
            local delta = (session.lastAxis or axis) - axis
            local now = host._rawClock:now()
            local dt = math.max(1 / 240, now - (session.lastMoveTime or now))
            scroll.offset = math.max(0, math.min(scroll.extent, scroll.offset + delta))
            scroll.velocity = delta / dt
            session.lastAxis, session.lastMoveTime = axis, now
            if scroll.node then
                require("src.frogui.layout").arrangeScroll(scroll.node, host)
                host:_invalidateTransform(scroll.node, "Scroll", "drag")
                local _, transform = host:_transformTree(
                    nil, "interactionTransform")
                host:_refreshCommittedRefs("interaction", transform)
            end
        end
    elseif session.claimed == "drag" then
        session.lastTarget = acceptedTarget(host, x, y, session.payload.kind)
    end
    return true
end

local function modalDismisses(modal, way)
    local dismiss = modal.props.dismiss or "back"
    return dismiss == way or dismiss == "both"
end

function interaction.pointerUp(host, x, y, pointerId, button)
    if button ~= nil and button ~= 1 then return host._modal ~= nil end
    host._pointerX, host._pointerY = x, y
    local session = host._interactionSession
    if not session then return host._modal ~= nil end
    if session.pointerId ~= pointerId then return true end
    if session.kind == "modal-outside" then
        local modal = host._modal
        if modal and modal.identity == session.modalIdentity
                and modalDismisses(modal, "outside") then
            local ok, err = pcall(host._runCallback, host, function()
                host._interactionSession = nil
                stageSound(host, modal.props.dismissSound, "dismiss")
                modal.props.onDismiss()
            end, "Modal:outside", modal.source)
            if not ok then
                host._interactionSession = nil
                host._pressedIdentity = nil
                error(err, 0)
            end
        else
            host._interactionSession = nil
        end
        return true
    end
    session.x, session.y = x, y
    local releaseDx, releaseDy = x - session.x0, y - session.y0
    session.distance = math.sqrt(releaseDx * releaseDx + releaseDy * releaseDy)
    updatePointerClaim(host, session, releaseDx, releaseDy, true)
    if session.claimed == "radial-dial" then
        local radial = findActiveIdentity(host, session.radialIdentity)
        local value
        if radial then
            local dial = radial._radialDial
            local index
            if session.radialMoved then
                index = session.radialPreviewIndex
            elseif session.radialTapStep then
                index = (dial.index - 1 + session.radialTapStep)
                    % #dial.values + 1
            end
            value = index and dial.values[index] or nil
        end
        if radial and value ~= nil then
            armRadialSettle(host, radial, not session.radialMoved)
        end
        host._interactionSession = nil
        host._pressedIdentity = nil
        if radial and value ~= nil then
            local ok, err = pcall(commitRadial, host, radial, value,
                not session.radialMoved)
            if not ok then error(err, 0) end
        end
    elseif session.claimed == "horizontal-swipe" then
        local dx, dy = x - session.x0, y - session.y0
        local qualifies = math.abs(dx) > HORIZONTAL_SWIPE.commitDistance
            and math.abs(dx) > math.abs(dy) * HORIZONTAL_SWIPE.axisBias
        local direction = qualifies and (dx < 0 and "left" or "right") or nil
        local swipe = findActiveIdentity(host, session.swipeIdentity)
        host._interactionSession = nil
        host._pressedIdentity = nil
        if direction and swipe then
            local ok, err = pcall(host._runCallback, host, function()
                swipe.props.onSwipe(direction)
            end, "HorizontalSwipe:" .. swipe.identity, swipe.source)
            if not ok then error(err, 0) end
        end
    elseif session.claimed == "drag" then
        local target = acceptedTarget(host, x, y, session.payload.kind)
        finishDrag(host, session, "cancelled", "no-target", target)
    elseif session.claimed == "scroll" then
        local scroll = (host._scrolls or {})[session.scrollIdentity]
        local callback, source, position
        if scroll then
            local node = scroll.node
            local interval = node and node.props.snapInterval or nil
            if interval then
                scroll.offset = math.max(0, math.min(scroll.extent,
                    math.floor(scroll.offset / interval + 0.5) * interval))
                scroll.velocity = 0
                require("src.frogui.layout").arrangeScroll(node, host)
                host:_invalidateTransform(node, "Scroll", "snap")
                local _, transform = host:_transformTree(
                    nil, "interactionTransform")
                host:_refreshCommittedRefs("interaction", transform)
            end
            callback = node and node.props.onScrollEnd or nil
            -- A completion observer defines the release position as terminal,
            -- even when it does not request interval snapping.
            if callback then scroll.velocity = 0 end
            source = node and node.source or nil
            position = scroll.offset
        end
        host._interactionSession = nil
        host._pressedIdentity = nil
        if callback then
            local ok, err = pcall(host._runCallback, host, function()
                callback(position)
            end, "Scroll:end", source)
            if not ok then error(err, 0) end
        end
    else
        local pressed
        if not session.claimed and not session.pressSuppressed
                and tapEligible(session)
                and session.pressIdentity then
            pressed = findActiveIdentity(host, session.pressIdentity)
            if pressed and (not localInside(pressed, x, y)
                    or pressed.props.disabled
                    or host._spentAuthorities[pressed.identity]) then
                pressed = nil
            end
        end
        if pressed then
            host._interactionSession = nil
            host._pressedIdentity = nil
            local ok, err
            if pressed.type == "Button" then
                ok, err = pcall(host._activateButton, host, pressed)
            else
                ok, err = pcall(host._runCallback, host, function()
                    stageSound(host, pressed.props.sound, "activate")
                    pressed.props.onPress()
                end, pressed.type .. ":" .. pressed.identity, pressed.source)
            end
            if not ok then
                host._interactionSession = nil
                host._pressedIdentity = nil
                error(err, 0)
            end
        elseif not session.claimed and not session.pressSuppressed
                and tapEligible(session)
                and session.swipeIdentity and not session.swipeTapBlocked then
            local swipe = findActiveIdentity(host, session.swipeIdentity)
            host._interactionSession = nil
            host._pressedIdentity = nil
            if swipe and swipe.props.onPress and localInside(swipe, x, y) then
                local ok, err = pcall(host._runCallback, host, function()
                    swipe.props.onPress()
                end, "HorizontalSwipe:press:" .. swipe.identity, swipe.source)
                if not ok then error(err, 0) end
            end
        else
            host._interactionSession = nil
            host._pressedIdentity = nil
        end
    end
    if pointerId ~= "mouse" then setHover(host, nil, pointerId) end
    return true
end

function interaction.update(host, dt)
    local runtimeRow = runtimeAllocationRow(host)
    local sessionBefore = runtimeRow and collectgarbage("count") or nil
    local session = host._interactionSession
    if session and session.kind == "pointer" and not session.claimed then
        session.elapsed = session.elapsed + dt
        if session.elapsed >= interaction.HOLD_SECONDS
                and not session.pressSuppressed and session.pressIdentity then
            local pressed = findActiveIdentity(host, session.pressIdentity)
            if pressed and pressed.props.onLongPress then
                host:_runCallback(function()
                    session.claimed = "hold"
                    host._pressedIdentity = nil
                    stageSound(host, pressed.props.sound, "activate")
                    pressed.props.onLongPress()
                end, pressed.type .. ":hold", pressed.source)
            end
        end
    end
    recordRuntimeAllocation(runtimeRow,
        "interactionSessionCalls", "interactionSessionAllocatedKB",
        sessionBefore)
    local decay = interaction.MOMENTUM_FRICTION
    local scrollRegistryBefore = runtimeRow
        and collectgarbage("count") or nil
    local identities = {}
    for identity in pairs(host._scrolls or {}) do identities[#identities + 1] = identity end
    table.sort(identities)
    recordRuntimeAllocation(runtimeRow,
        "interactionScrollRegistryCalls",
        "interactionScrollRegistryAllocatedKB", scrollRegistryBefore)
    local scrollUpdateBefore = runtimeRow and collectgarbage("count") or nil
    for _, identity in ipairs(identities) do
        local scroll = host._scrolls[identity]
        local captured = session and session.claimed == "scroll"
            and session.scrollIdentity == identity
        if not captured and math.abs(scroll.velocity or 0) > 0.1 then
            local factor = math.exp(-decay * dt)
            local travel = scroll.velocity * (1 - factor) / decay
            local nextOffset = math.max(0,
                math.min(scroll.extent, scroll.offset + travel))
            if nextOffset == 0 or nextOffset == scroll.extent then scroll.velocity = 0
            else scroll.velocity = scroll.velocity * factor end
            scroll.offset = nextOffset
            if scroll.node then
                require("src.frogui.layout").arrangeScroll(scroll.node, host)
                host:_invalidateTransform(scroll.node, "Scroll", "momentum")
            end
        elseif math.abs(scroll.velocity or 0) <= 0.1 then
            scroll.velocity = 0
        end
    end
    recordRuntimeAllocation(runtimeRow,
        "interactionScrollUpdateCalls", "interactionScrollUpdateAllocatedKB",
        scrollUpdateBefore)
    local radialRegistryBefore = runtimeRow
        and collectgarbage("count") or nil
    local radialIdentities = {}
    for identity in pairs(host._radials or {}) do
        radialIdentities[#radialIdentities + 1] = identity
    end
    table.sort(radialIdentities)
    recordRuntimeAllocation(runtimeRow,
        "interactionRadialRegistryCalls",
        "interactionRadialRegistryAllocatedKB", radialRegistryBefore)
    local radialUpdateBefore = runtimeRow and collectgarbage("count") or nil
    for _, identity in ipairs(radialIdentities) do
        local dial = host._radials[identity]
        local captured = session and session.claimed == "radial-dial"
            and dial.node and session.radialIdentity == dial.node.identity
        local changed = false
        if not captured then
            if host.reducedMotion then
                if dial.angle ~= dial.targetAngle or dial.bounce ~= 0 then
                    dial.angle, dial.bounce = dial.targetAngle, 0
                    changed = true
                end
            else
                local delta = normalizeAngle(dial.targetAngle - dial.angle)
                if math.abs(delta) > 0.0001 then
                    local progress = 1
                        - math.exp(-RADIAL_DIAL.settleSpeed * dt)
                    dial.angle = dial.angle + delta * progress
                    changed = true
                else
                    dial.angle = dial.targetAngle
                end
            end
        end
        if not host.reducedMotion and (dial.bounce or 0) > 0 then
            dial.bounce = math.max(0,
                dial.bounce - dt / RADIAL_DIAL.bounceDuration)
            changed = true
        end
        if changed and dial.node then
            refreshRadial(host, dial.node, "settle")
        end
    end
    recordRuntimeAllocation(runtimeRow,
        "interactionRadialUpdateCalls", "interactionRadialUpdateAllocatedKB",
        radialUpdateBefore)
end

function interaction.wheelMoved(host, dx, dy)
    local path = pointerPath(host, host._pointerX or 0, host._pointerY or 0)
    local node = nearestScroll(path)
    if not node then return host._modal ~= nil end
    local scroll = node._scroll
    local amount = scroll.axis == "vertical" and -dy
        or -(dx ~= 0 and dx or dy)
    scroll.offset = math.max(0, math.min(scroll.extent,
        scroll.offset + amount * interaction.WHEEL_STEP))
    scroll.velocity = 0
    require("src.frogui.layout").arrangeScroll(node, host)
    host:_invalidateTransform(node, "Scroll", "wheel")
    local _, transform = host:_transformTree(nil, "interactionTransform")
    host:_refreshCommittedRefs("interaction", transform)
    return true
end

-- Keeps keyboard focus visible without exposing Scroll offsets to components.
function interaction.revealFocus(host, identity)
    local path
    for _, root in ipairs(inputRoots(host)) do
        path = identityPath(root, identity)
        if path then break end
    end
    local focused = path and path[#path]
    if not focused then return end
    for _, node in ipairs(path) do
        if node.type == "Scroll" and node._scroll then
            local scroll = node._scroll
            local focusedBox = focused.layout
            local low = scroll.axis == "vertical"
                and focusedBox.y or focusedBox.x
            local high = low + (scroll.axis == "vertical"
                and focusedBox.height or focusedBox.width)
            local viewLow = scroll.axis == "vertical"
                and node.layout.contentY or node.layout.contentX
            local viewHigh = viewLow + (scroll.axis == "vertical"
                and node.layout.contentHeight or node.layout.contentWidth)
            if low < viewLow then scroll.offset = scroll.offset + low - viewLow
            elseif high > viewHigh then scroll.offset = scroll.offset + high - viewHigh end
            scroll.offset = math.max(0, math.min(scroll.extent, scroll.offset))
            require("src.frogui.layout").arrangeScroll(node, host)
            host:_invalidateTransform(node, "Scroll", "focus")
        end
    end
    local _, transform = host:_transformTree(nil, "interactionTransform")
    host:_refreshCommittedRefs("interaction", transform)
end

function interaction.keyBack(host)
    if host._interactionSession
            and (host._interactionSession.claimed == "drag"
                or host._interactionSession.claimed == "radial-dial") then
        interaction.cancel(host, "back")
        return true
    end
    local modal = host._modal
    if not modal then return false end
    if modalDismisses(modal, "back") then
        host:_runCallback(function()
            stageSound(host, modal.props.dismissSound, "dismiss")
            modal.props.onDismiss()
        end, "Modal:back", modal.source)
    end
    return true
end

function interaction.rebind(host)
    for identity, scroll in pairs(host._scrolls or {}) do
        scroll.node = findIdentity(host._tree, scroll.node and scroll.node.identity)
            or findIdentity(host._tree, identity)
        if scroll.node then scroll.node._scroll = scroll end
    end
    for _, radial in pairs(host._radials or {}) do
        local node = findIdentity(host._tree,
            radial.node and radial.node.identity)
        if node and node.type == "RadialDial" then
            radial.node = node
            node._radialDial = radial
        end
    end
    local session = host._interactionSession
    if not session then return end
    if session.scrollIdentity then
        local scroll = host._scrolls[session.scrollIdentity]
        if not scroll then interaction.cancel(host, "navigation") return end
    end
    if session.sourceIdentity then
        local source = findActiveIdentity(host, session.sourceIdentity)
        if not source then interaction.cancel(host, "navigation") return end
        session.source = source
    end
    if session.radialIdentity then
        local radial = findActiveIdentity(host, session.radialIdentity)
        local bounds = session.radialBounds
        local radialBox = radial and radial.layout
        local geometryChanged = radial and bounds
            and (radialBox.x ~= bounds.x or radialBox.y ~= bounds.y
                or radialBox.width ~= bounds.width
                or radialBox.height ~= bounds.height)
        if not radial or radial.type ~= "RadialDial"
                or radial.props.disabled
                or radial._radialDial.signature ~= session.radialSignature
                or radial._radialDial.value ~= session.radialValue
                or radial._radialDial.geometrySignature
                    ~= session.radialGeometrySignature
                or geometryChanged then
            interaction.cancel(host, "controlled-change")
            return
        end
        radial._radialDial.previewAngle = session.radialPreviewAngle
        refreshRadial(host, radial, "controlled-refresh")
    end
    if session.swipeIdentity and not findActiveIdentity(host,
            session.swipeIdentity) then
        interaction.cancel(host, "navigation")
        return
    end
    if session.pressIdentity and not findActiveIdentity(host,
            session.pressIdentity) then
        interaction.cancel(host, "navigation")
    end
end

function interaction.afterCommit(host, previous)
    previous = previous or {}
    local oldModalIdentity = previous.modalIdentity
    local newModalIdentity = host._modal and host._modal.identity or nil
    if host._interactionSession and newModalIdentity
            and newModalIdentity ~= oldModalIdentity then
        interaction.cancel(host, "modal-takeover")
    else
        interaction.rebind(host)
    end

    local hoveredIdentity = previous.hoveredIdentity
    if hoveredIdentity
            and not findActiveIdentity(host, hoveredIdentity) then
        local previousRoot = previous.modal or previous.tree
        local oldNode = findIdentity(previous.chrome, hoveredIdentity)
            or findIdentity(previousRoot, hoveredIdentity)
        local callback = oldNode
            and (oldNode.type == "Pressable" or oldNode.type == "Button")
            and oldNode.props.onHoverChange or nil
        if callback then
            host:_runCallback(function()
                host._hoveredIdentity = nil
                callback(false)
            end, "FrogUI:hover-removed", oldNode.source)
        else
            host._hoveredIdentity = nil
        end
    end
end

-- Exposes the one input/inspection plane without exposing hit-test mechanics.
function interaction.activeRoot(host)
    return activeRoot(host)
end

-- Exposes the current top-to-bottom input planes to Host keyboard/inspection.
function interaction.inputRoots(host)
    return inputRoots(host)
end

function interaction.findActiveIdentity(host, identity)
    return findActiveIdentity(host, identity)
end

-- Collects root portals once, rejects ambiguous portal nesting, and preserves
-- authored Modal order. Components may wrap a portal; a portal may not own
-- another root plane that paints and routes outside its visible parent.
function interaction.planesFromTree(root)
    local modals, chrome = {}, nil
    local function walk(node, portalAncestor)
        local isPortal = node.type == "Modal" or node.type == "Chrome"
        if isPortal and portalAncestor then
            error("FrogUI root portals cannot be nested ("
                .. portalAncestor.type .. " contains " .. node.type .. ")")
        end
        if node.type == "Modal" then
            modals[#modals + 1] = node
        elseif node.type == "Chrome" then
            assert(chrome == nil,
                "FrogUI permits only one Frog.Chrome portal")
            chrome = node
        end
        local ancestor = isPortal and node or portalAncestor
        for _, child in ipairs(node.children or {}) do walk(child, ancestor) end
    end
    if root then walk(root, nil) end
    return modals, chrome
end

function interaction.inspect(host)
    local scrolls = {}
    local identities = {}
    for identity in pairs(host._scrolls or {}) do identities[#identities + 1] = identity end
    table.sort(identities)
    for _, identity in ipairs(identities) do
        local value = host._scrolls[identity]
        scrolls[#scrolls + 1] = {
            identity = identity, axis = value.axis, offset = value.offset,
            extent = value.extent, velocity = value.velocity,
        }
    end
    local session = host._interactionSession
    return {
        pointer = { x = host._pointerX, y = host._pointerY },
        hovered = host._hoveredIdentity,
        pressed = host._pressedIdentity,
        focused = host._focusedIdentity,
        session = session and {
            pointerId = session.pointerId, claimed = session.claimed,
            distance = session.distance, elapsed = session.elapsed,
            press = session.pressIdentity, source = session.sourceIdentity,
            scroll = session.scrollIdentity,
            swipe = session.swipeIdentity,
            swipePhase = session.claimed == "horizontal-swipe" and "claimed"
                or session.claimed and session.swipeIdentity and "blocked"
                or session.swipePending and "pending"
                or session.swipeIdentity and "candidate" or nil,
            swipeDirection = session.swipeDirection,
            radial = session.radialIdentity,
            radialPhase = session.radialIdentity
                and (session.radialMoved and "preview" or "armed") or nil,
            radialPreviewAngle = session.radialPreviewAngle,
            radialPreviewIndex = session.radialPreviewIndex,
            radialAccumulated = session.radialAccumulated,
            radialOriginEstablished = session.radialPointerAngle ~= nil,
            payloadKind = session.payload and session.payload.kind or nil,
            target = session.lastTarget and session.lastTarget.key or nil,
        } or nil,
        scrolls = scrolls,
        modal = host._modal and host._modal.identity or nil,
        chrome = host._chrome and host._chrome.identity or nil,
        chromeActive = host._chrome ~= nil and (host._modal == nil
            or host._modal.props.allowChrome == true),
        modals = (function()
            local out = {}
            for index, modal in ipairs(host._modals or {}) do
                out[index] = modal.identity
            end
            return out
        end)(),
    }
end

return interaction
