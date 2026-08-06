-- Paints the committed resolved tree with generic primitive rendering and
-- optional application painter overrides.

local Effect = require("src.frogui.effects.runtime")

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

-- Mixes one resolved text color toward white for the impact highlight pass.
local function brightened(color, amount)
    return {
        color[1] + (1 - color[1]) * amount,
        color[2] + (1 - color[2]) * amount,
        color[3] + (1 - color[3]) * amount,
        color[4],
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
    local authoredOpacity = node.type ~= "Motion" and node.type ~= "PopupText"
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

local function defaultText(host, node, style, clipState)
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
    if style.shadowOffset > 0 then
        setColor(style.shadowColor)
        stamp(style.shadowOffset, style.shadowOffset)
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
    if style.shine > 0 and style.shineSplit > 0 then
        local shineShape = function()
            g.rectangle("fill", node.x, node.y,
                node.width, node.height * style.shineSplit)
        end
        beginClip(clipState, shineShape)
        setColor(brightened(style.color, style.shine))
        stamp(0, 0)
        endClip(clipState, shineShape)
    end
end

-- Draws one image frame at an effect-owned center/pivot and authored size.
local function drawEffectFrame(asset, center, props, rotation, tint)
    local g = graphics()
    if not g or not asset or not center then return false end
    local imageWidth, imageHeight = asset:getDimensions()
    local height = props.height or Effect.defaults.frameHeight
    local width = props.width or height * imageWidth / imageHeight
    local anchor = props.anchor or { x = 0.5, y = 0.5 }
    local scaleX = width / imageWidth
    if props.mirror then scaleX = -scaleX end
    setColor(tint)
    g.draw(asset, center.x, center.y, rotation or 0,
        scaleX, height / imageHeight,
        imageWidth * anchor.x, imageHeight * anchor.y)
    return true
end

-- Paints an animated or primitive projectile head plus fading point trail.
local function defaultProjectile(host, node, state, style)
    local g = graphics()
    if not g or not state or not state.visible or not state.head then return end
    local props = node.props
    local color = style.color
    local radius = props.radius or Effect.defaults.projectileRadius
    local trailDuration = props.trailDuration or Effect.defaults.trailDuration
    if trailDuration > 0 then
        for _, sample in ipairs(state.trail) do
            local life = math.max(0, 1 - sample.age / trailDuration)
            setColor({ color[1], color[2], color[3],
                color[4] * (props.trailAlpha
                    or Effect.defaults.trailAlpha) * life * life })
            g.circle("fill", sample.x, sample.y,
                radius * (0.35 + 0.55 * life))
        end
    end
    local frames = props.frames or {}
    local source = state.frame and frames[state.frame]
    local asset = source and host:_asset(source) or nil
    local rotation = props.rotate == false and 0 or state.rotation
    if drawEffectFrame(asset, state.head, props, rotation, style.tint) then return end
    setColor(color)
    g.circle("fill", state.head.x, state.head.y, radius)
    setColor({ 1, 1, 1, color[4] })
    g.circle("fill", state.head.x, state.head.y,
        radius * (props.coreRatio or Effect.defaults.projectileCoreRatio))
end

-- Paints the retained frame or a clear missing-art contact ring fallback.
local function defaultFlipbook(host, node, state, style)
    local g = graphics()
    if not g or not state or not state.visible or not state.center then return end
    local source = node.props.frames[state.frame]
    local asset = source and host:_asset(source) or nil
    if drawEffectFrame(asset, state.center, node.props,
            node.props.rotation or 0, style.tint) then return end
    local radius = (node.props.height or Effect.defaults.frameHeight) / 2
    setColor(style.tint)
    g.setLineWidth(3)
    g.circle("line", state.center.x, state.center.y, radius)
end

local function imageGeometry(node, asset, fit, sourceRect)
    local imageWidth = sourceRect and sourceRect.width or asset:getWidth()
    local imageHeight = sourceRect and sourceRect.height or asset:getHeight()
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

local quadCache = setmetatable({}, { __mode = "k" })

-- Caches source-pixel crops by image identity so drawing a stable component
-- never allocates a new LÖVE Quad each frame.
local function sourceQuad(asset, rect)
    if not rect then return nil end
    local key = table.concat({ rect.x, rect.y, rect.width, rect.height }, ":")
    local cached = quadCache[asset]
    if not cached then
        cached = {}
        quadCache[asset] = cached
    end
    if not cached[key] then
        cached[key] = graphics().newQuad(rect.x, rect.y,
            rect.width, rect.height, asset:getWidth(), asset:getHeight())
    end
    return cached[key]
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
    local geometry = imageGeometry(node, asset, style.fit, style.sourceRect)
    setColor(style.tint)
    local shape = nodeShape(node, false)
    if style.fit == "cover" then beginClip(clipState, shape) end
    local quad = sourceQuad(asset, style.sourceRect)
    if quad then
        g.draw(asset, quad, geometry.x, geometry.y, 0,
            geometry.scaleX, geometry.scaleY)
    else
        g.draw(asset, geometry.x, geometry.y, 0,
            geometry.scaleX, geometry.scaleY)
    end
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
    local geometry = imageGeometry(node, asset, style.fit, style.sourceRect)
    local quad = sourceQuad(asset, style.sourceRect)
    local scaleX = style.mirror and -geometry.scaleX or geometry.scaleX
    local function stamp(dx, dy)
        if quad then
            g.draw(asset, quad, geometry.centerX + (dx or 0),
                geometry.centerY + (dy or 0), 0,
                scaleX, geometry.scaleY,
                geometry.imageWidth / 2, geometry.imageHeight / 2)
        else
            g.draw(asset, geometry.centerX + (dx or 0),
                geometry.centerY + (dy or 0), 0,
                scaleX, geometry.scaleY,
                geometry.imageWidth / 2, geometry.imageHeight / 2)
        end
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

    if node.type == "Projectile" then
        local effectStyle = {
            color = faded(tinted(host:_color(node.props.color, "text"),
                style.tint), style.opacity),
            tint = faded(tinted(host:_color(node.props.tint, nil,
                node.props.color and host:_color(node.props.color)
                    or { 1, 1, 1, 1 }), style.tint), style.opacity),
        }
        if custom then
            customCall(custom, "projectile", node, node._effect, effectStyle)
        else
            defaultProjectile(host, node, node._effect, effectStyle)
        end
    elseif node.type == "Flipbook" then
        local effectStyle = {
            tint = faded(tinted(host:_color(node.props.tint, nil,
                { 1, 1, 1, 1 }), style.tint), style.opacity),
        }
        if custom then
            customCall(custom, "flipbook", node, node._effect, effectStyle)
        else
            defaultFlipbook(host, node, node._effect, effectStyle)
        end
    elseif node.type == "Text" or node.type == "PopupText" then
        local textStyle = {
            color = faded(tinted(host:_color(node.props.color, "text"),
                style.tint), style.opacity),
            font = node._resolvedFont or host:_font(node.props.role),
            role = node.props.role or "body",
            outlineWidth = node.props.outlineWidth or 0,
            outlineColor = faded(tinted(host:_color(node.props.outlineColor, nil,
                { 0, 0, 0, 1 }), style.tint), style.opacity),
            shadowOffset = node.props.shadowOffset or 0,
            shadowColor = faded(tinted(host:_color(node.props.shadowColor, nil,
                { 0, 0, 0, 1 }), style.tint), style.opacity),
            shine = node.props.shine or 0,
            shineSplit = node.props.shineSplit or 0.5,
        }
        if custom then
            customCall(custom, "text", node, node.props.text or "", textStyle)
        else
            local shape = nodeShape(node, false)
            if node.props.maxLines and g then beginClip(clipState, shape) end
            defaultText(host, node, textStyle, clipState)
            if node.props.maxLines and g then endClip(clipState, shape) end
        end
    elseif node.type == "Image" then
        local imageStyle = {
            tint = faded(tinted(host:_color(node.props.tint, nil, { 1, 1, 1, 1 }),
                style.tint), style.opacity),
            fit = node.props.fit or "contain",
            sourceRect = node.props.sourceRect,
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
            sourceRect = node.props.sourceRect,
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
        local lineHeight = font and font:getHeight() + 2 or 15
        local detailLine = 1
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
        if entry.ref then
            local current = entry.ref.current
            local key = entry.ref.key == nil and ""
                or (" key=" .. tostring(entry.ref.key))
            local rectangle = current
                and (" @ %.1f,%.1f %.1fx%.1f"):format(
                    current.x, current.y, current.width, current.height)
                or " @ unattached"
            g.print("ref " .. entry.ref.id .. key .. rectangle,
                bounds.x + 3, bounds.y + 2 + detailLine * lineHeight)
            detailLine = detailLine + 1
        end
        for _, process in ipairs(entry.processes or {}) do
            local hooks = {}
            for _, hook in ipairs(process.hooks or {}) do
                local state = hook.kind == "useResource"
                    and (hook.mounted and " mounted" or " disposed") or ""
                hooks[#hooks + 1] = hook.kind .. " " .. hook.id .. state
            end
            g.print("process " .. process.owner .. ": "
                    .. table.concat(hooks, " / "),
                bounds.x + 3, bounds.y + 2 + detailLine * lineHeight)
            detailLine = detailLine + 1
        end
        if entry.effectLayer then
            g.print("effect layer / " .. entry.effectLayer.input
                    .. " / " .. tostring(entry.effectLayer.count) .. " children",
                bounds.x + 3, bounds.y + 2 + detailLine * lineHeight)
            detailLine = detailLine + 1
        elseif entry.effect then
            local effect = entry.effect
            local label
            if effect.kind then
                local head = effect.head or { x = 0, y = 0 }
                label = ("%s @ %.1f,%.1f / %.2f/%.2fs / frame %s/%d"):format(
                    effect.kind:lower(), head.x, head.y,
                    effect.elapsed, effect.duration,
                    tostring(effect.frame or "-"), effect.frameCount)
            else
                local at = effect.at
                label = ("popup %s @ %.1f,%.1f / %.2fs / rise %.1f"):format(
                    tostring(effect.variant), at.x, at.y,
                    effect.duration, effect.distance)
            end
            g.print(label, bounds.x + 3,
                bounds.y + 2 + detailLine * lineHeight)
            detailLine = detailLine + 1
        end
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
            g.print(motionLabel,
                bounds.x + 3, bounds.y + 2 + detailLine * lineHeight)
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
    local clipState = not custom and { depth = 0 } or nil
    drawNode(host, host._tree, custom, nil, nil, clipState)
    local chrome = host._chrome
    local chromeAboveModal = chrome and host._modal
        and host._modal.props.allowChrome == true
    if chrome and not chromeAboveModal then
        drawNode(host, chrome, custom, nil, nil, clipState, chrome)
    end
    for _, modal in ipairs(host._modals or {}) do
        drawNode(host, modal, custom, nil, nil, clipState, modal)
    end
    if chromeAboveModal then
        drawNode(host, chrome, custom, nil, nil, clipState, chrome)
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
