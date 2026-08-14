-- Owns FrogUI's opt-in, post-hoc comparison of one committed primitive
-- tree with one fully resolved candidate. It reports scalar observations only;
-- it never decides reconciliation, retention, invalidation, or reuse.

local comparison = {}

-- Private diagnostic prop families. A prop may belong to more than one family
-- because one authored value can affect several consumers (for example Text
-- content affects layout and paint). These sets are observations only; they do
-- not define invalidation or authorize FrogUI to skip any work.
local DIAGNOSTIC_PROP_FAMILIES = {
    layout = {
        width = true, height = true, grow = true, offset = true,
        padding = true, gap = true, align = true, justify = true, wrap = true,
        text = true, role = true, fontScale = true, maxLines = true,
        fitDown = true, source = true, sourceRect = true, fit = true,
        frameCount = true, at = true, from = true, to = true,
        fromOffset = true, toOffset = true, atOffset = true,
        tileWidth = true, tileHeight = true, repeatAxis = true,
        trackRadius = true, axis = true, bar = true, scrollPosition = true,
    },
    paint = {
        opacity = true, background = true, border = true, borderWidth = true,
        radius = true, clip = true, overflow = true, text = true, role = true,
        fontScale = true, color = true, wrap = true, maxLines = true,
        align = true, fitDown = true, outlineWidth = true,
        outlineColor = true, shadowOffset = true, shadowColor = true,
        shine = true, shineSplit = true, variant = true, source = true,
        sourceRect = true, fit = true, tint = true, mirror = true,
        outline = true, frames = true, fps = true, anchor = true,
        rotate = true, rotation = true, filter = true, tileWidth = true,
        tileHeight = true, phase = true, velocity = true,
        phaseImpulse = true, repeatAxis = true,
        shader = true, uniforms = true, fallback = true, blend = true,
        draw = true, hoverBackground = true, hoverBorder = true,
        pressedBackground = true, pressedBorder = true,
        focusedBackground = true, focusedBorder = true,
        selectedBackground = true, selectedBorder = true,
        disabled = true, selected = true, trackRadius = true,
        x = true, y = true, scale = true, scaleX = true, scaleY = true,
        pivot = true, coreRatio = true,
        trailDuration = true, trailAlpha = true,
        count = true, angle = true, spread = true, gravity = true,
        endRadius = true,
    },
    interaction = {
        onPress = true, onLongPress = true, onHoverChange = true,
        onCommit = true, onResult = true, onChange = true,
        onSubmit = true, onCancel = true,
        onScrollEnd = true, onDismiss = true, onDrop = true,
        onDragStart = true, onDragEnd = true, onSwipe = true,
        disabled = true, selected = true, shortcut = true, value = true,
        values = true, axis = true, scrollPosition = true,
        snapInterval = true, dismiss = true, allowChrome = true,
        payload = true, preview = true, accepts = true, address = true,
        ref = true,
    },
    retained = {
        juice = true, reactions = true, ref = true, duration = true,
        distance = true, clock = true, feedbackClock = true,
        seed = true, count = true, angle = true, spread = true,
        gravity = true, endRadius = true,
        onComplete = true, contactAt = true, onContact = true,
        fps = true, phase = true, velocity = true, phaseImpulse = true,
        value = true,
        values = true, axis = true, scrollPosition = true,
        snapInterval = true, onScrollEnd = true, x = true, y = true,
        rotation = true, scale = true, scaleX = true, scaleY = true,
        opacity = true, tint = true,
        sound = true, rejectSound = true, hoverSound = true,
        spinSound = true, dismissSound = true, grabSound = true,
        dropSound = true,
    },
}

local DIAGNOSTIC_NEUTRAL_PROPS = {
    key = true, testId = true,
}

-- Fails beside the validation catalogs when a new public prop has no explicit
-- diagnostic disposition. This is deliberately a classification check, not a
-- claim that these families are disjoint.
function comparison.validateProps(commonProps, typeProps)
    local classified = {}
    for _, props in pairs(DIAGNOSTIC_PROP_FAMILIES) do
        for name in pairs(props) do classified[name] = true end
    end
    for name in pairs(DIAGNOSTIC_NEUTRAL_PROPS) do classified[name] = true end
    for name in pairs(commonProps) do
        assert(classified[name], "FrogUI diagnostic prop is unclassified: " .. name)
    end
    for _, props in pairs(typeProps) do
        for name in pairs(props) do
            assert(classified[name],
                "FrogUI diagnostic prop is unclassified: " .. name)
        end
    end
end


local DIAGNOSTIC_CATEGORIES = {
    "physical", "type", "topology", "layout", "geometry", "paint",
    "interaction", "retained",
}

local function diagnosticOwner(value)
    value = tostring(value or "unknown")
    value = value:gsub("[^%w_:%.$%-]", "?")
    if #value > 64 then value = value:sub(1, 61) .. "..." end
    return value
end

-- Compares detached plain data without invoking metamethods. A shared table is
-- unknown rather than stable because a mutable alias cannot prove what the
-- previous render contained. Opaque values and callbacks likewise stay
-- unknown; this probe never infers semantic callback equality.
local function observeDiagnosticValue(left, right, seen)
    local leftType, rightType = type(left), type(right)
    if leftType ~= rightType then return "changed", 0 end
    if leftType == "nil" or leftType == "boolean" or leftType == "number"
            or leftType == "string" then
        return left == right and "stable" or "changed", 0
    end
    if leftType == "function" then return "unknown", 1 end
    if leftType ~= "table" then return "unknown", 0 end
    if rawequal(left, right) or getmetatable(left) ~= nil
            or getmetatable(right) ~= nil then
        return "unknown", 0
    end
    seen = seen or {}
    local paired = seen[left]
    if paired then
        return paired == right and "unknown" or "changed", 0
    end
    seen[left] = right
    local status, callbacks = "stable", 0
    for key, value in pairs(left) do
        local keyType = type(key)
        if keyType ~= "string" and keyType ~= "number"
                and keyType ~= "boolean" then
            status = "unknown"
        else
            local nested, nestedCallbacks = observeDiagnosticValue(
                value, rawget(right, key), seen)
            callbacks = callbacks + nestedCallbacks
            if nested == "changed" then return "changed", callbacks end
            if nested == "unknown" then status = "unknown" end
        end
    end
    for key in pairs(right) do
        if rawget(left, key) == nil and rawget(right, key) ~= nil then
            return "changed", callbacks
        end
    end
    return status, callbacks
end

local function mergeDiagnosticStatus(left, right)
    if left == "changed" or right == "changed" then return "changed" end
    if left == "unknown" or right == "unknown" then return "unknown" end
    return "stable"
end

local function observeDiagnosticProps(previous, candidate, family)
    local status, callbacks = "stable", 0
    local names = {}
    for name in pairs(previous.props or {}) do
        if family[name] then names[name] = true end
    end
    for name in pairs(candidate.props or {}) do
        if family[name] then names[name] = true end
    end
    for name in pairs(names) do
        local observed, nestedCallbacks = observeDiagnosticValue(
            previous.props[name], candidate.props[name])
        callbacks = callbacks + nestedCallbacks
        status = mergeDiagnosticStatus(status, observed)
    end
    return status, callbacks
end

local DIAGNOSTIC_GEOMETRY_FIELDS = {
    "x", "y", "width", "height", "contentX", "contentY",
    "contentWidth", "contentHeight", "measuredWidth", "measuredHeight",
    "derivedWidth", "derivedHeight", "resolvedFont", "resolvedFontSize",
}

local function observeDiagnosticGeometry(previous, candidate)
    local previousLayout = previous.layout or {}
    local candidateLayout = candidate.layout or {}
    for _, name in ipairs(DIAGNOSTIC_GEOMETRY_FIELDS) do
        if previousLayout[name] ~= candidateLayout[name] then return "changed" end
    end
    if previous._portal ~= candidate._portal
            or previous._portalLayout ~= candidate._portalLayout then
        return "changed"
    end
    for _, name in ipairs { "top", "right", "bottom", "left" } do
        if (previousLayout.padding or {})[name]
                ~= (candidateLayout.padding or {})[name] then
            return "changed"
        end
    end
    for _, field in ipairs { "_worldTransform", "_visualBounds",
            "_visualContentBounds" } do
        local left, right = previous[field] or {}, candidate[field] or {}
        for _, name in ipairs { "a", "b", "c", "d", "tx", "ty",
                "x", "y", "width", "height" } do
            if left[name] ~= right[name] then return "changed" end
        end
    end
    return "stable"
end

-- Compares only values owned by the two-pass layout result. Paint transforms
-- are intentionally excluded: an unchanged layout may animate afterward.
local function sameDiagnosticLayoutOutput(previous, candidate)
    local previousLayout = previous.layout or {}
    local candidateLayout = candidate.layout or {}
    for _, name in ipairs {
            "x", "y", "width", "height",
            "contentX", "contentY", "contentWidth", "contentHeight",
            "measuredWidth", "measuredHeight",
            "derivedWidth", "derivedHeight",
            "resolvedFont", "resolvedFontSize",
        } do
        if previousLayout[name] ~= candidateLayout[name] then return false end
    end
    if previous._portal ~= candidate._portal
            or previous._portalLayout ~= candidate._portalLayout then
        return false
    end
    for _, name in ipairs { "top", "right", "bottom", "left" } do
        if (previousLayout.padding or {})[name]
                ~= (candidateLayout.padding or {})[name] then
            return false
        end
    end
    return true
end

local function sameDiagnosticSequence(previous, candidate, valueFor)
    if #previous ~= #candidate then return false end
    for index = 1, #previous do
        if valueFor(previous[index]) ~= valueFor(candidate[index]) then
            return false
        end
    end
    return true
end

local function observeDiagnosticRetainedMembership(previous, candidate)
    local function samePresence(field)
        return (previous[field] == nil) == (candidate[field] == nil)
    end
    for _, field in ipairs {
            "_motion", "_effect", "_scroll", "_radialDial", "_ref" } do
        if not samePresence(field) then return "changed" end
    end
    if previous._motion
            and previous._motion.lifetime ~= candidate._motion.lifetime then
        return "changed"
    end
    if previous._effect
            and previous._effect.lifetime ~= candidate._effect.lifetime then
        return "changed"
    end
    if previous._scroll and previous._scroll.axis ~= candidate._scroll.axis then
        return "changed"
    end
    if previous._radialDial
            and previous._radialDial.signature ~= candidate._radialDial.signature then
        return "changed"
    end
    if previous._ref and previous._ref ~= candidate._ref then return "changed" end
    if not sameDiagnosticSequence(previous._actorInstances or {},
            candidate._actorInstances or {}, function(instance)
                return instance.lifetime
            end) then
        return "changed"
    end
    local owners = observeDiagnosticValue(previous._processOwners or {},
        candidate._processOwners or {})
    return owners
end

local function diagnosticChildSequence(entry)
    local output = {}
    for _, child in ipairs(entry.node.children or {}) do
        output[#output + 1] = "child:" .. tostring(child.logicalIdentity)
    end
    if entry.node._dragPreview then
        output[#output + 1] = "preview:"
            .. tostring(entry.node._dragPreview.logicalIdentity)
    end
    return output
end

local function indexDiagnosticTree(root)
    local entries, ordered = {}, {}
    local function visit(node, parentIdentity)
        local identity = assert(node.logicalIdentity,
            "FrogUI diagnostic node omitted logical identity")
        assert(not entries[identity],
            "duplicate FrogUI diagnostic logical identity " .. identity)
        local entry = { node = node, parentIdentity = parentIdentity }
        entries[identity] = entry
        ordered[#ordered + 1] = entry
        for _, child in ipairs(node.children or {}) do
            visit(child, identity)
        end
        if node._dragPreview then visit(node._dragPreview, identity) end
    end
    visit(root, nil)
    return entries, ordered
end

local function sameDiagnosticTopology(previous, candidate)
    local left, right = previous.node, candidate.node
    if left.type ~= right.type or left.key ~= right.key
            or left.owner ~= right.owner
            or previous.parentIdentity ~= candidate.parentIdentity
            or left._portal ~= right._portal
            or left._portalLayout ~= right._portalLayout then
        return false
    end
    return sameDiagnosticSequence(diagnosticChildSequence(previous),
        diagnosticChildSequence(candidate), function(value) return value end)
end

local function addDiagnosticCategory(row, category, status, owner)
    row[status][category] = row[status][category] + 1
    if status == "changed" then
        local owners = row.changedOwners[category]
        owners[owner] = (owners[owner] or 0) + 1
    end
end

local function stableDiagnosticBranches(candidateRoot, entries, category)
    local ranked, subtree = {}, {}
    local function measure(node)
        local entry = entries[node.logicalIdentity]
        local stable = entry and entry.status and entry.status.topology == "stable"
            and (category == "topology" or entry.status.geometry == "stable")
        local nodes = 1
        for _, child in ipairs(node.children or {}) do
            local childStable, childNodes = measure(child)
            stable = stable and childStable
            nodes = nodes + childNodes
        end
        if node._dragPreview then
            local childStable, childNodes = measure(node._dragPreview)
            stable = stable and childStable
            nodes = nodes + childNodes
        end
        subtree[node.logicalIdentity] = { stable = stable, nodes = nodes }
        return stable, nodes
    end
    measure(candidateRoot)
    local function collect(node, parentStable)
        local measured = subtree[node.logicalIdentity]
        if measured.stable and not parentStable then
            ranked[#ranked + 1] = {
                owner = diagnosticOwner(node.owner),
                logicalIdentity = node.logicalIdentity,
                nodes = measured.nodes,
            }
        end
        for _, child in ipairs(node.children or {}) do
            collect(child, measured.stable)
        end
        if node._dragPreview then collect(node._dragPreview, measured.stable) end
    end
    collect(candidateRoot, false)
    table.sort(ranked, function(left, right)
        if left.nodes ~= right.nodes then return left.nodes > right.nodes end
        if left.owner ~= right.owner then return left.owner < right.owner end
        return left.logicalIdentity < right.logicalIdentity
    end)
    while #ranked > 5 do table.remove(ranked) end
    return ranked
end

-- Estimates a deliberately conservative incremental-layout ceiling after the
-- ordinary full candidate has already completed. Only the closed layout prop
-- family may prove an input stable; callbacks and unrelated props are absent.
-- This observer never makes a runtime choice.
local LAYOUT_REUSE_BARRIER_TYPES = {
    Scroll = true,
    RadialDial = true,
    EffectLayer = true,
    Modal = true,
    Chrome = true,
}

local function layoutReuseCensus(candidateRoot, entries)
    local ranked, subtree = {}, {}
    local stableInputNodes, exactOutputNodes, barrierNodes = 0, 0, 0

    local function measure(node, belowBarrier)
        local entry = entries[node.logicalIdentity]
        local old = entry and entry.previous
        local ownBarrier = belowBarrier
            or LAYOUT_REUSE_BARRIER_TYPES[node.type] == true
            or node._portal == true or node._portalLayout == true
        if ownBarrier then barrierNodes = barrierNodes + 1 end
        local exactInput = old ~= nil and entry.status
            and entry.status.topology == "stable"
            and entry.status.layout == "stable"
        if exactInput then stableInputNodes = stableInputNodes + 1 end
        local exactOutput = exactInput
            and sameDiagnosticLayoutOutput(old.node, node)
        if exactOutput then exactOutputNodes = exactOutputNodes + 1 end

        local eligible = exactOutput and not ownBarrier
        local nodes = 1
        for _, child in ipairs(node.children or {}) do
            local childEligible, childNodes = measure(child, ownBarrier)
            eligible = eligible and childEligible
            nodes = nodes + childNodes
        end
        if node._dragPreview then
            local childEligible, childNodes = measure(
                node._dragPreview, ownBarrier)
            eligible = eligible and childEligible
            nodes = nodes + childNodes
        end
        subtree[node.logicalIdentity] = { eligible = eligible, nodes = nodes }
        return eligible, nodes
    end
    measure(candidateRoot, false)

    local eligibleNodes, branchCount = 0, 0
    local function collect(node, parentEligible)
        local measured = subtree[node.logicalIdentity]
        if measured.eligible and not parentEligible then
            eligibleNodes = eligibleNodes + measured.nodes
            branchCount = branchCount + 1
            ranked[#ranked + 1] = {
                owner = diagnosticOwner(node.owner),
                logicalIdentity = node.logicalIdentity,
                nodes = measured.nodes,
            }
        end
        for _, child in ipairs(node.children or {}) do
            collect(child, measured.eligible)
        end
        if node._dragPreview then
            collect(node._dragPreview, measured.eligible)
        end
    end
    collect(candidateRoot, false)
    table.sort(ranked, function(left, right)
        if left.nodes ~= right.nodes then return left.nodes > right.nodes end
        if left.owner ~= right.owner then return left.owner < right.owner end
        return left.logicalIdentity < right.logicalIdentity
    end)
    while #ranked > 5 do table.remove(ranked) end
    return {
        stableInputNodes = stableInputNodes,
        exactOutputNodes = exactOutputNodes,
        barrierNodes = barrierNodes,
        eligibleNodes = eligibleNodes,
        branchCount = branchCount,
        branches = ranked,
    }
end

-- Produces scalar post-hoc observations only. Equal results in this one build
-- and viewport are upper bounds, not proof that any earlier pipeline phase was
-- unnecessary or that a subtree can be retained safely.
function comparison.compare(previousRoot, candidateRoot)
    if not previousRoot then return nil end
    local previous, previousOrder = indexDiagnosticTree(previousRoot)
    local candidate, candidateOrder = indexDiagnosticTree(candidateRoot)
    local row = {
        candidateNodes = #candidateOrder,
        committedNodes = #previousOrder,
        matchedNodes = 0, addedNodes = 0, removedNodes = 0,
        callbackUnknownObservations = 0,
        stable = {}, changed = {}, unknown = {}, changedOwners = {},
    }
    for _, category in ipairs(DIAGNOSTIC_CATEGORIES) do
        row.stable[category] = 0
        row.changed[category] = 0
        row.unknown[category] = 0
        row.changedOwners[category] = {}
    end
    if candidateRoot.actor then
        row.rootActor = candidateRoot.actor.name
        local state = candidateRoot.actor.state
        local revision = type(state) == "number" and state
            or type(state) == "table" and state.revision or nil
        if type(revision) == "number" and revision == revision
                and revision > -math.huge and revision < math.huge then
            row.rootRevision = revision
        end
    end
    for _, entry in ipairs(candidateOrder) do
        local identity = entry.node.logicalIdentity
        local old = previous[identity]
        if not old then
            row.addedNodes = row.addedNodes + 1
        else
            row.matchedNodes = row.matchedNodes + 1
            entry.previous = old
            local owner = diagnosticOwner(entry.node.owner)
            local status = {}
            status.physical = old.node.identity == entry.node.identity
                and "stable" or "changed"
            status.type = old.node.type == entry.node.type
                and "stable" or "changed"
            status.topology = sameDiagnosticTopology(old, entry)
                and "stable" or "changed"
            local callbacks
            status.layout, callbacks = observeDiagnosticProps(old.node,
                entry.node, DIAGNOSTIC_PROP_FAMILIES.layout)
            row.callbackUnknownObservations =
                row.callbackUnknownObservations + callbacks
            status.geometry = observeDiagnosticGeometry(old.node, entry.node)
            status.paint, callbacks = observeDiagnosticProps(old.node,
                entry.node, DIAGNOSTIC_PROP_FAMILIES.paint)
            row.callbackUnknownObservations =
                row.callbackUnknownObservations + callbacks
            local paintOutput, outputCallbacks = observeDiagnosticValue(
                { opacity = (old.node.presentation or {}).opacity,
                    tint = (old.node.presentation or {}).tint },
                { opacity = (entry.node.presentation or {}).opacity,
                    tint = (entry.node.presentation or {}).tint })
            row.callbackUnknownObservations =
                row.callbackUnknownObservations + outputCallbacks
            status.paint = mergeDiagnosticStatus(status.paint, paintOutput)
            status.interaction, callbacks = observeDiagnosticProps(old.node,
                entry.node, DIAGNOSTIC_PROP_FAMILIES.interaction)
            row.callbackUnknownObservations =
                row.callbackUnknownObservations + callbacks
            status.retained, callbacks = observeDiagnosticProps(old.node,
                entry.node, DIAGNOSTIC_PROP_FAMILIES.retained)
            row.callbackUnknownObservations =
                row.callbackUnknownObservations + callbacks
            status.retained = mergeDiagnosticStatus(status.retained,
                observeDiagnosticRetainedMembership(old.node, entry.node))
            entry.status = status
            for _, category in ipairs(DIAGNOSTIC_CATEGORIES) do
                addDiagnosticCategory(row, category, status[category], owner)
            end
        end
    end
    for identity in pairs(previous) do
        if not candidate[identity] then row.removedNodes = row.removedNodes + 1 end
    end
    assert(row.candidateNodes == row.matchedNodes + row.addedNodes
            and row.committedNodes == row.matchedNodes + row.removedNodes,
        "FrogUI diagnostic candidate coverage is inconsistent")
    row.stableTopologyBranches = stableDiagnosticBranches(candidateRoot,
        candidate, "topology")
    row.stableGeometryBranches = stableDiagnosticBranches(candidateRoot,
        candidate, "geometry")
    local layoutReuse = layoutReuseCensus(candidateRoot, candidate)
    row.layoutReuseStableInputNodes = layoutReuse.stableInputNodes
    row.layoutReuseExactOutputNodes = layoutReuse.exactOutputNodes
    row.layoutReuseBarrierNodes = layoutReuse.barrierNodes
    row.layoutReuseEligibleNodes = layoutReuse.eligibleNodes
    row.layoutReuseBranchCount = layoutReuse.branchCount
    row.layoutReuseBranches = layoutReuse.branches
    return row
end

return comparison
