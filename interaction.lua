-- Owns FrogUI's generic pointer session, retained Scroll state, modal input
-- isolation, and source-owned drag/drop lifecycle. Application components see
-- only the small primitive props exported by src/frogui/init.lua.

local Message = require("src.frogui.message")
local Motion = require("src.frogui.motion")

local interaction = {}

interaction.HOLD_SECONDS = 0.35
interaction.CLAIM_DISTANCE = 8
interaction.AXIS_BIAS = 1.25
interaction.WHEEL_STEP = 40
interaction.MOMENTUM_FRICTION = 12

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

function interaction.snapshot(host)
    local scrolls = {}
    for identity, instance in pairs(host._scrolls or {}) do
        scrolls[identity] = copyScroll(instance)
    end
    local session = host._interactionSession
    local sessionCopy
    if session then
        sessionCopy = {}
        for key, value in pairs(session) do sessionCopy[key] = value end
        sessionCopy.payload = session.payload
            and snapshotPlain(session.payload, "drag payload") or nil
        sessionCopy.lastTarget = session.lastTarget and {
            key = session.lastTarget.key,
            address = snapshotPlain(session.lastTarget.address,
                "drop target address"),
        } or nil
    end
    return {
        scrolls = scrolls,
        session = sessionCopy,
        hoveredIdentity = host._hoveredIdentity,
        pressedIdentity = host._pressedIdentity,
        pointerX = host._pointerX,
        pointerY = host._pointerY,
    }
end

function interaction.restore(host, state)
    host._scrolls = state.scrolls
    host._interactionSession = state.session
    host._hoveredIdentity = state.hoveredIdentity
    host._pressedIdentity = state.pressedIdentity
    host._pointerX, host._pointerY = state.pointerX, state.pointerY
    interaction.rebind(host)
    for _, scroll in pairs(host._scrolls or {}) do
        if scroll.node then
            require("src.frogui.layout").arrangeScroll(scroll.node, host)
        end
    end
end

local function localInside(node, x, y)
    local localX, localY = Motion.localPoint(node, x, y)
    return localX >= node.x and localY >= node.y
        and localX <= node.x + node.width and localY <= node.y + node.height
end

local function insideContent(node, x, y)
    local localX, localY = Motion.localPoint(node, x, y)
    return localX >= node.contentX and localY >= node.contentY
        and localX <= node.contentX + node.contentWidth
        and localY <= node.contentY + node.contentHeight
end

local function clipped(node)
    return node.type == "Scroll" or node.props.clip
        or node.props.overflow == "clip"
end

local POINTER_TYPES = {
    Button = true, Pressable = true, DragSource = true, Scroll = true,
}

local function hitPath(node, x, y, predicate)
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
        local path = hitPath(root, x, y,
            function(node) return POINTER_TYPES[node.type] == true end)
        if path then return path, root end
    end
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
local function stageSound(host, override, defaultKey)
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
        assert(type(ok) == "boolean", "DragSource onDrop must return ok, detail")
        status = ok and "committed" or "rejected"
        safeDetail = returned == nil and nil
            or snapshotPlain(returned, "drag completion detail")
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
    local source = deepestOf(path, "DragSource")
    local scroll = nearestScroll(path)
    if not press and not source and not scroll then return modal ~= nil end
    local session = {
        kind = "pointer", pointerId = pointerId,
        x0 = x, y0 = y, x = x, y = y,
        started = host._rawClock:now(), elapsed = 0, distance = 0,
        pressIdentity = press and press.identity or nil,
        pressType = press and press.type or nil,
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
    if press and press.type == "Button" then host._focusedIdentity = press.identity end
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
    if not session.claimed and session.distance >= interaction.CLAIM_DISTANCE then
        claimGesture(host, session, dx, dy)
    end
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
                Motion.transformTree(host._tree)
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
    if session.claimed == "drag" then
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
                Motion.transformTree(host._tree)
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
        if not session.claimed and session.distance < interaction.CLAIM_DISTANCE
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
        else
            host._interactionSession = nil
            host._pressedIdentity = nil
        end
    end
    if pointerId ~= "mouse" then setHover(host, nil, pointerId) end
    return true
end

function interaction.update(host, dt)
    local session = host._interactionSession
    if session and session.kind == "pointer" and not session.claimed then
        session.elapsed = session.elapsed + dt
        if session.elapsed >= interaction.HOLD_SECONDS and session.pressIdentity then
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
    local decay = interaction.MOMENTUM_FRICTION
    local identities = {}
    for identity in pairs(host._scrolls or {}) do identities[#identities + 1] = identity end
    table.sort(identities)
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
            if scroll.node then require("src.frogui.layout").arrangeScroll(scroll.node, host) end
        elseif math.abs(scroll.velocity or 0) <= 0.1 then
            scroll.velocity = 0
        end
    end
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
    Motion.transformTree(host._tree)
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
            local low = scroll.axis == "vertical" and focused.y or focused.x
            local high = low + (scroll.axis == "vertical"
                and focused.height or focused.width)
            local viewLow = scroll.axis == "vertical"
                and node.contentY or node.contentX
            local viewHigh = viewLow + (scroll.axis == "vertical"
                and node.contentHeight or node.contentWidth)
            if low < viewLow then scroll.offset = scroll.offset + low - viewLow
            elseif high > viewHigh then scroll.offset = scroll.offset + high - viewHigh end
            scroll.offset = math.max(0, math.min(scroll.extent, scroll.offset))
            require("src.frogui.layout").arrangeScroll(node, host)
        end
    end
    Motion.transformTree(host._tree)
end

function interaction.keyBack(host)
    if host._interactionSession and host._interactionSession.claimed == "drag" then
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
