-- Paints the committed resolved tree with generic primitive rendering and
-- optional application painter overrides.

local painter = {}

local DEFAULTS = {
    clear = { 0.05, 0.06, 0.08, 1 },
    text = { 0.94, 0.94, 0.94, 1 },
    panel = { 0.13, 0.15, 0.19, 1 },
    border = { 0.33, 0.37, 0.44, 1 },
    button = { 0.20, 0.31, 0.40, 1 },
    buttonHover = { 0.25, 0.39, 0.50, 1 },
    buttonPressed = { 0.16, 0.25, 0.33, 1 },
    buttonSelected = { 0.20, 0.47, 0.38, 1 },
    buttonDisabled = { 0.14, 0.16, 0.18, 0.75 },
    inspector = { 0.25, 1, 0.45, 0.9 },
    inspectorSelected = { 1, 0.8, 0.15, 1 },
}

local function graphics()
    return love and love.graphics or nil
end

local function setColor(color)
    local g = graphics()
    if not g then return end
    g.setColor(color[1] or color.r or 1, color[2] or color.g or 1,
        color[3] or color.b or 1, color[4] or color.a or 1)
end

local function faded(color, opacity)
    if not color then return nil end
    return {
        color[1] or color.r or 1,
        color[2] or color.g or 1,
        color[3] or color.b or 1,
        (color[4] or color.a or 1) * opacity,
    }
end

local function tinted(color, tint)
    if not color or not tint then return color end
    return {
        (color[1] or color.r or 1) * (tint[1] or tint.r or 1),
        (color[2] or color.g or 1) * (tint[2] or tint.g or 1),
        (color[3] or color.b or 1) * (tint[3] or tint.b or 1),
        (color[4] or color.a or 1) * (tint[4] or tint.a or 1),
    }
end

local function beginClip(state, drawShape)
    local g = graphics()
    if not g or not state then return end
    local parentDepth = state.depth
    if parentDepth == 0 then
        g.stencil(drawShape, "replace", 1, true)
    else
        g.stencil(drawShape, "increment", 1, true)
    end
    state.depth = parentDepth + 1
    g.setStencilTest("equal", state.depth)
end

local function endClip(state, drawShape)
    local g = graphics()
    if not g or not state then return end
    local currentDepth = state.depth
    assert(currentDepth > 0, "FrogUI clip stack underflow")
    g.stencil(drawShape, "decrement", 1, true)
    state.depth = currentDepth - 1
    if state.depth == 0 then g.setStencilTest()
    else g.setStencilTest("equal", state.depth) end
end

local function nodeShape(node, content)
    return function()
        local g = graphics()
        if content then
            g.rectangle("fill", node.contentX, node.contentY,
                node.contentWidth, node.contentHeight)
        else
            g.rectangle("fill", node.x, node.y, node.width, node.height)
        end
    end
end

local function styleFor(host, node, inheritedOpacity, inheritedTint)
    local props = node.props
    local presentation = node.presentation or {}
    local authoredOpacity = node.type ~= "Motion"
        and type(props.opacity) == "number" and props.opacity or 1
    local opacity = inheritedOpacity * authoredOpacity * (presentation.opacity or 1)
    local tint = tinted(inheritedTint or { 1, 1, 1, 1 }, presentation.tint)
    local style = {
        background = props.background and host:_color(props.background) or nil,
        border = props.border and host:_color(props.border) or nil,
        borderWidth = props.borderWidth or (props.border and 1 or 0),
        radius = props.radius or 0,
        opacity = opacity,
        tint = tint,
        transform = {
            x = presentation.x or 0,
            y = presentation.y or 0,
            rotation = presentation.rotation or 0,
            scale = presentation.scale or 1,
            bounds = node._visualBounds,
            world = node._worldTransform,
        },
    }
    if node.type == "Button" then
        local button = ((host.theme.controls or {}).button or {})
        local background = props.background or button.background
        local border = props.border or button.border
        if props.disabled then
            background = props.background or button.disabled
            style.background = host:_color(background,
                "buttonDisabled")
        elseif host._pressedIdentity == node.identity then
            background = props.pressedBackground or props.background
                or button.pressed
            border = props.pressedBorder or props.border or button.border
            style.background = host:_color(background,
                "buttonPressed")
        elseif host._focusedIdentity == node.identity then
            background = props.focusedBackground or props.background
                or button.focused or button.hover
            border = props.focusedBorder or button.focusedBorder
                or props.hoverBorder or props.border or button.border
            style.background = host:_color(background,
                "buttonFocused")
        elseif props.selected then
            background = props.selectedBackground or button.selected
                or props.background
            border = props.selectedBorder or props.border or button.border
            style.background = host:_color(background,
                "buttonSelected")
        elseif host._hoveredIdentity == node.identity then
            background = props.hoverBackground or props.background
                or button.hover
            border = props.hoverBorder or props.border or button.border
            style.background = host:_color(background,
                "buttonHover")
        else
            style.background = host:_color(background, "button")
        end
        if border then
            style.border = host:_color(border, "border")
            style.borderWidth = props.borderWidth or 1
        end
        style.radius = props.radius or button.radius or 5
    end
    style.background = faded(tinted(style.background, tint), opacity)
    style.border = faded(tinted(style.border, tint), opacity)
    return style
end

local function defaultBox(host, node, style)
    local g = graphics()
    if not g then return end
    if style.background then
        setColor(style.background)
        g.rectangle("fill", node.x, node.y, node.width, node.height,
            style.radius, style.radius)
    end
    if style.border and style.borderWidth > 0 then
        setColor(style.border)
        g.setLineWidth(style.borderWidth)
        g.rectangle("line", node.x, node.y, node.width, node.height,
            style.radius, style.radius)
    end
end

local function defaultText(host, node, style)
    local g = graphics()
    if not g then return end
    local font = node._resolvedFont or host:_font(node.props.role)
    if font then g.setFont(font) end
    local align = node.props.align or "left"
    if align == "start" then align = "left"
    elseif align == "end" then align = "right" end
    local value = tostring(node.props.text or "")
    local function stamp(dx, dy)
        g.printf(value, node.x + (dx or 0), node.y + (dy or 0),
            math.max(0, node.width), align)
    end
    if style.outlineWidth > 0 then
        local width = style.outlineWidth
        setColor(style.outlineColor)
        for _, offset in ipairs({
            { -width, 0 }, { width, 0 }, { 0, -width }, { 0, width },
            { -width * 0.7, -width * 0.7 },
            { width * 0.7, -width * 0.7 },
            { -width * 0.7, width * 0.7 },
            { width * 0.7, width * 0.7 },
        }) do
            stamp(offset[1], offset[2])
        end
    end
    setColor(style.color)
    stamp(0, 0)
end

local function imageGeometry(node, asset, fit)
    local imageWidth, imageHeight = asset:getWidth(), asset:getHeight()
    local scaleX, scaleY = node.width / imageWidth, node.height / imageHeight
    if fit == "contain" then
        local scale = math.min(scaleX, scaleY)
        scaleX, scaleY = scale, scale
    elseif fit == "cover" then
        local scale = math.max(scaleX, scaleY)
        scaleX, scaleY = scale, scale
    else
        assert(fit == "stretch", "Image fit must be contain, cover, or stretch")
    end
    local width, height = imageWidth * scaleX, imageHeight * scaleY
    return {
        imageWidth = imageWidth,
        imageHeight = imageHeight,
        scaleX = scaleX,
        scaleY = scaleY,
        width = width,
        height = height,
        x = node.x + (node.width - width) / 2,
        y = node.y + (node.height - height) / 2,
        centerX = node.x + node.width / 2,
        centerY = node.y + node.height / 2,
    }
end

local function missingAsset(node, style)
    local g = graphics()
    setColor(style.tint)
    g.rectangle("line", node.x, node.y, node.width, node.height)
    g.line(node.x, node.y, node.x + node.width, node.y + node.height)
    g.line(node.x + node.width, node.y, node.x, node.y + node.height)
end

local function defaultImage(host, node, asset, style, clipState)
    local g = graphics()
    if not g then return end
    if not asset or not asset.getWidth or not asset.getHeight then
        missingAsset(node, style)
        return
    end
    local geometry = imageGeometry(node, asset, style.fit)
    setColor(style.tint)
    local shape = nodeShape(node, false)
    if style.fit == "cover" then beginClip(clipState, shape) end
    g.draw(asset, geometry.x, geometry.y, 0,
        geometry.scaleX, geometry.scaleY)
    if style.fit == "cover" then endClip(clipState, shape) end
end

local maskShader
local function alphaMaskShader()
    if maskShader then return maskShader end
    local g = graphics()
    local ok, value = pcall(g.newShader, [[
        vec4 effect(vec4 color, Image texture, vec2 textureCoords,
                vec2 screenCoords) {
            float alpha = Texel(texture, textureCoords).a;
            return vec4(color.rgb, color.a * alpha);
        }
    ]])
    assert(ok, "Frog.Icon alpha-mask shader failed: " .. tostring(value))
    maskShader = value
    return maskShader
end

-- Icon is the semantic silhouette primitive: unlike Image it deliberately
-- ignores source RGB and recolors from alpha. This keeps black legacy glyphs
-- and white authored glyphs on one predictable path.
local function defaultIcon(host, node, asset, style, clipState)
    local g = graphics()
    if not g then return end
    if not asset or not asset.getWidth or not asset.getHeight then
        missingAsset(node, style)
        return
    end
    local geometry = imageGeometry(node, asset, style.fit)
    local scaleX = style.mirror and -geometry.scaleX or geometry.scaleX
    local function stamp(dx, dy)
        g.draw(asset, geometry.centerX + (dx or 0),
            geometry.centerY + (dy or 0), 0,
            scaleX, geometry.scaleY,
            geometry.imageWidth / 2, geometry.imageHeight / 2)
    end

    local shape = nodeShape(node, false)
    if style.fit == "cover" then beginClip(clipState, shape) end
    local previousShader = g.getShader and g.getShader() or nil
    g.setShader(alphaMaskShader())
    if style.outline and style.outline.width > 0 then
        local width = style.outline.width
        setColor(style.outline.color)
        for _, offset in ipairs({
            { -width, 0 }, { width, 0 }, { 0, -width }, { 0, width },
            { -width * 0.7, -width * 0.7 },
            { width * 0.7, -width * 0.7 },
            { -width * 0.7, width * 0.7 },
            { width * 0.7, width * 0.7 },
        }) do
            stamp(offset[1], offset[2])
        end
    end
    setColor(style.tint)
    stamp(0, 0)
    g.setShader(previousShader)
    if style.fit == "cover" then endClip(clipState, shape) end
end

local function customCall(custom, method, ...)
    if custom and custom[method] then custom[method](custom, ...) end
end

local function drawNode(host, node, custom, inheritedOpacity, inheritedTint,
        clipState, portalRoot)
    if node._portal and node ~= portalRoot then return end
    local session = host._interactionSession
    if session and session.claimed == "drag"
            and node.identity == session.sourceIdentity then return end
    local g = graphics()
    local presentation = node.presentation or {}
    if not custom and g then
        local centerX, centerY = node.x + node.width / 2, node.y + node.height / 2
        g.push("all")
        g.translate(presentation.x or 0, presentation.y or 0)
        g.translate(centerX, centerY)
        g.rotate(presentation.rotation or 0)
        g.scale(presentation.scale or 1)
        g.translate(-centerX, -centerY)
    end
    local style = styleFor(host, node, inheritedOpacity or 1, inheritedTint)
    if custom then
        customCall(custom, "box", node, style)
    else
        defaultBox(host, node, style)
    end

    if node.type == "Text" then
        local textStyle = {
            color = faded(tinted(host:_color(node.props.color, "text"),
                style.tint), style.opacity),
            font = node._resolvedFont or host:_font(node.props.role),
            role = node.props.role or "body",
            outlineWidth = node.props.outlineWidth or 0,
            outlineColor = faded(tinted(host:_color(node.props.outlineColor, nil,
                { 0, 0, 0, 1 }), style.tint), style.opacity),
        }
        if custom then
            customCall(custom, "text", node, node.props.text or "", textStyle)
        else
            local shape = nodeShape(node, false)
            if node.props.maxLines and g then beginClip(clipState, shape) end
            defaultText(host, node, textStyle)
            if node.props.maxLines and g then endClip(clipState, shape) end
        end
    elseif node.type == "Image" then
        local imageStyle = {
            tint = faded(tinted(host:_color(node.props.tint, nil, { 1, 1, 1, 1 }),
                style.tint), style.opacity),
            fit = node.props.fit or "contain",
        }
        local asset = host:_asset(node.props.source)
        if custom then customCall(custom, "image", node, asset, imageStyle)
        else defaultImage(host, node, asset, imageStyle, clipState) end
    elseif node.type == "Icon" then
        local outline = node.props.outline
        local iconStyle = {
            tint = faded(tinted(host:_color(node.props.tint, nil, { 1, 1, 1, 1 }),
                style.tint), style.opacity),
            fit = node.props.fit or "contain",
            mirror = node.props.mirror == true,
            alphaMask = true,
            outline = outline and {
                width = outline.width or 1,
                color = faded(tinted(host:_color(outline.color, nil,
                    { 0, 0, 0, 0.85 }), style.tint), style.opacity),
            } or nil,
        }
        local asset = host:_asset(node.props.source)
        if custom then customCall(custom, "icon", node, asset, iconStyle)
        else defaultIcon(host, node, asset, iconStyle, clipState) end
    end

    local clipped = node.type == "Scroll" or node.props.clip
        or node.props.overflow == "clip"
    local contentShape = nodeShape(node, true)
    if clipped and not custom and g then beginClip(clipState, contentShape) end
    for _, child in ipairs(node.children) do
        drawNode(host, child, custom, style.opacity, style.tint,
            clipState, portalRoot)
    end
    if clipped and not custom and g then endClip(clipState, contentShape) end
    if node.type == "Scroll" and node.props.bar and node._scroll
            and node._scroll.extent > 0 and not custom and g then
        local scroll = node._scroll
        local ratio = scroll.viewport / math.max(scroll.viewport, scroll.content)
        local progress = scroll.offset / scroll.extent
        setColor(host:_color(nil, "textDim", { 0.65, 0.7, 0.72, 0.65 }))
        if scroll.axis == "vertical" then
            local length = math.max(16, node.contentHeight * ratio)
            g.rectangle("fill", node.contentX + node.contentWidth - 3,
                node.contentY + (node.contentHeight - length) * progress,
                3, length, 1.5, 1.5)
        else
            local length = math.max(16, node.contentWidth * ratio)
            g.rectangle("fill", node.contentX
                    + (node.contentWidth - length) * progress,
                node.contentY + node.contentHeight - 3,
                length, 3, 1.5, 1.5)
        end
    end
    if not custom and g then g.pop() end
end

local function defaultInspector(host, entry, selected)
    local g = graphics()
    if not g then return end
    setColor(host:_color(nil, selected and "inspectorSelected" or "inspector"))
    g.setLineWidth(selected and 2 or 1)
    local bounds = entry.bounds
    g.rectangle("line", bounds.x, bounds.y, bounds.width, bounds.height)
    if selected then
        local font = host:_font("caption")
        if font then g.setFont(font) end
        local source = entry.source
        local sourceLabel = source and ((source.path or "?") .. ":"
            .. tostring(source.line or "?")) or "source unknown"
        local actorLabel = ""
        if entry.actor then
            local state = entry.actor.state
            if type(state) == "table" then state = "{...}" end
            actorLabel = " / actor " .. entry.actor.name .. "=" .. tostring(state)
        elseif entry.view then
            actorLabel = " / view " .. entry.view.name .. " -> " .. entry.view.target
        end
        g.print((entry.owner or "?") .. " / " .. entry.type .. actorLabel
                .. " / " .. sourceLabel,
            bounds.x + 3, bounds.y + 2)
        if entry.motion then
            local declared = {}
            for _, recipe in ipairs(entry.motion.declared or {}) do
                local key = recipe.key == nil and ""
                    or " key=" .. tostring(recipe.key)
                declared[#declared + 1] = recipe.name .. "["
                    .. tostring(recipe.clock) .. key .. "]"
            end
            local active = {}
            for _, recipe in ipairs(entry.motion.activeDetails or {}) do
                local timing
                if recipe.duration == math.huge then
                    timing = ("%.2fs"):format(recipe.elapsed)
                else
                    timing = ("%.2f/%.2fs %.0f%%"):format(recipe.elapsed,
                        recipe.duration, (recipe.progress or 0) * 100)
                end
                active[#active + 1] = recipe.name .. "["
                    .. tostring(recipe.clock) .. " " .. timing .. "]"
            end
            local motionLabel = "juice "
                .. (#declared > 0 and table.concat(declared, ", ") or "none")
                .. " / "
                .. (#active > 0 and "active " .. table.concat(active, ", ")
                    or "idle")
                .. " / reactions " .. tostring(entry.motion.reactionCount or 0)
                .. (entry.motion.reducedMotion and " / reduced" or "")
            local lineHeight = font and font:getHeight() + 2 or 15
            g.print(motionLabel, bounds.x + 3, bounds.y + 2 + lineHeight)
        end
    end
end

local function defaultMessages(host, messages)
    local g = graphics()
    if not g or #messages == 0 then return end
    local font = host:_font("caption")
    if font then g.setFont(font) end
    local lineHeight = font and font:getHeight() + 2 or 15
    local shown = math.min(6, #messages)
    local panelHeight = shown * lineHeight + 8
    local width = math.min(520, host._viewport.width - 16)
    local x = 8
    local y = host._viewport.height - panelHeight - 8
    setColor({ 0.03, 0.04, 0.05, 0.92 })
    g.rectangle("fill", x, y, width, panelHeight, 4, 4)
    setColor(host:_color(nil, "inspector"))
    local function clipped(value, limit)
        value = tostring(value or "?")
        if #value <= limit then return value end
        return value:sub(1, math.max(1, limit - 1)) .. "…"
    end
    for row = 1, shown do
        local entry = messages[#messages - shown + row]
        local transition = entry.transitions and entry.transitions[1]
        local result = transition and (transition.accepted and "accepted" or "no-op")
            or "delivered"
        local recipient = transition and transition.recipient
            or entry.recipients[1] or "none"
        local label = ("#%d %s %s · %s -> %s %s%s"):format(
            entry.sequence, entry.kind, clipped(entry.token, 24),
            clipped(entry.origin, 24), clipped(recipient, 22), result,
            entry.reconciled and ", render" or "")
        g.print(label, x + 4, y + 4 + (row - 1) * lineHeight)
    end
end

local function defaultActors(host, actors)
    local g = graphics()
    if not g or #actors == 0 then return end
    local font = host:_font("caption")
    if font then g.setFont(font) end
    local lineHeight = font and font:getHeight() + 2 or 15
    local shown = math.min(8, #actors)
    local width = math.min(260, host._viewport.width - 16)
    local x = host._viewport.width - width - 8
    local y = 8
    setColor({ 0.03, 0.04, 0.05, 0.92 })
    g.rectangle("fill", x, y, width, shown * lineHeight + 8, 4, 4)
    setColor(host:_color(nil, "inspector"))
    for row = 1, shown do
        local actor = actors[row]
        local state = type(actor.state) == "table" and "{...}" or tostring(actor.state)
        g.print(("%d. %s%s = %s"):format(actor.order, actor.name,
                actor.address and (" @" .. actor.address) or "", state),
            x + 4, y + 4 + (row - 1) * lineHeight)
    end
end

local function defaultInteraction(host, state)
    local g = graphics()
    if not g or not state then return end
    local session = state.session
    if not session and #(state.scrolls or {}) == 0 and not state.modal then return end
    local font = host:_font("caption")
    if font then g.setFont(font) end
    local lineHeight = font and font:getHeight() + 2 or 15
    local lines = {}
    if session then
        lines[#lines + 1] = ("gesture %s · %.1fpx · %s"):format(
            tostring(session.claimed or "pending"), session.distance or 0,
            tostring(session.payloadKind or session.press or "pointer"))
    end
    if state.modal then
        lines[#lines + 1] = ("modal top %s (%d deep)"):format(
            state.modal, #(state.modals or {}))
    end
    for _, scroll in ipairs(state.scrolls or {}) do
        lines[#lines + 1] = ("scroll %s %.1f/%.1f"):format(
            scroll.axis, scroll.offset, scroll.extent)
    end
    local width, x, y = math.min(330, host._viewport.width - 16), 8, 8
    setColor({ 0.03, 0.04, 0.05, 0.92 })
    g.rectangle("fill", x, y, width, #lines * lineHeight + 8, 4, 4)
    setColor(host:_color(nil, "inspector"))
    for index, line in ipairs(lines) do
        g.print(line, x + 4, y + 4 + (index - 1) * lineHeight)
    end
end

function painter.draw(host, custom)
    if not host._tree then return end
    local g = graphics()
    local snapshot = host._viewport:snapshot()
    customCall(custom, "begin", snapshot)
    if not custom and g then
        g.push("all")
        g.setStencilTest()
        g.clear(false, true, false)
        g.translate(host._viewport.x, host._viewport.y)
        g.scale(host._viewport.scale)
    end
    drawNode(host, host._tree, custom, nil, nil,
        not custom and { depth = 0 } or nil)
    for _, modal in ipairs(host._modals or {}) do
        drawNode(host, modal, custom, nil, nil,
            not custom and { depth = 0 } or nil, modal)
    end
    local session = host._interactionSession
    local preview = session and session.claimed == "drag"
        and session.source and session.source._dragPreview or nil
    if preview then
        customCall(custom, "dragPreview", preview, session)
        if not custom and g then
            g.push("all")
            g.translate(session.x - preview.width / 2,
                session.y - preview.height / 2)
        end
        drawNode(host, preview, custom, nil, nil,
            not custom and { depth = 0 } or nil, preview)
        if not custom and g then g.pop() end
    end
    if host._inspectorVisible then
        local inspection = host:inspectionTree()
        for _, entry in ipairs(inspection.nodes) do
            if custom then customCall(custom, "inspector", entry,
                inspection.selected == entry)
            else defaultInspector(host, entry, inspection.selected == entry) end
        end
        if custom then customCall(custom, "messages", inspection.messages)
        else defaultMessages(host, inspection.messages) end
        if custom then customCall(custom, "actors", inspection.actors)
        else defaultActors(host, inspection.actors) end
        if custom then customCall(custom, "interaction", inspection.interaction)
        else defaultInteraction(host, inspection.interaction) end
    end
    if not custom and g then g.pop() end
    customCall(custom, "finish")
end

painter.defaults = DEFAULTS

return painter
