-- Paints the committed resolved tree with generic primitive rendering and
-- optional application painter overrides.

local Effect = require("src.frogui.effects.runtime")
local Shader = require("src.frogui.shader")
local Canvas = require("src.frogui.canvas")
local Interaction = require("src.frogui.interaction")

local painter = {}

-- One malformed leaf must never turn a single frame into unbounded draw work.
local MAX_TILE_COPIES = 4096

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

-- Returns the preallocated row used only by the private Battle allocation
-- harness. Ordinary Hosts do not own a probe, so normal painting takes the
-- single raw lookup and no diagnostic storage or snapshots.
local function paintAllocationRow(host)
    local probe = rawget(host, "_allocationProbe")
    return probe and probe.mode == "pipeline" and probe.active
        and probe.paintActiveRow or nil
end

-- Adds one measured site's already-bounded scalar delta to its active cohort.
local function recordAllocation(row, callsField, allocatedField, before)
    if not row then return end
    row[callsField] = row[callsField] + 1
    row[allocatedField] = row[allocatedField]
        + collectgarbage("count") - before
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

local WHITE = { 1, 1, 1, 1 }
local BLACK = { 0, 0, 0, 1 }
local ICON_OUTLINE = { 0, 0, 0, 0.85 }

-- Writes one multiplied color into caller-owned scratch. The default Painter
-- keeps this scratch across compatible committed candidates; custom painters
-- still receive fresh per-draw descriptors and styles.
local function writeTint(out, color, tint)
    out = out or {}
    color = color or WHITE
    tint = tint or WHITE
    out[1] = (color[1] or color.r or 1) * (tint[1] or tint.r or 1)
    out[2] = (color[2] or color.g or 1) * (tint[2] or tint.g or 1)
    out[3] = (color[3] or color.b or 1) * (tint[3] or tint.b or 1)
    out[4] = (color[4] or color.a or 1) * (tint[4] or tint.a or 1)
    return out
end

-- Writes the Canvas command's final tint and inherited opacity in one owned
-- color record; Canvas callbacks never receive intermediate theme aliases.
local function writeTintOpacity(out, color, tint, opacity)
    writeTint(out, color, tint)
    out[4] = out[4] * opacity
    return out
end

-- Combines tint and opacity in one pass instead of allocating intermediate
-- tinted and faded colors for every primitive on every draw.
local function writePaintColor(out, color, tint, opacity)
    if not color then return nil end
    out = writeTint(out, color, tint)
    out[4] = out[4] * opacity
    return out
end

-- Mixes one resolved text color toward white for the impact highlight pass.
local function writeBrightened(out, color, amount)
    out = out or {}
    out[1] = color[1] + (1 - color[1]) * amount
    out[2] = color[2] + (1 - color[2]) * amount
    out[3] = color[3] + (1 - color[3]) * amount
    out[4] = color[4]
    return out
end

-- Creates one Host-lifetime stencil callback over scalar rectangle scratch.
-- It never retains a committed or candidate node between synchronous calls.
local function clipStateFor(host, paintRow)
    local state = host._paintClipState
    if state then
        state.depth = 0
        return state
    end
    local before = paintRow and collectgarbage("count") or nil
    state = { depth = 0 }
    state.drawShape = function()
        local g = graphics()
        g.rectangle("fill", state.x, state.y, state.width, state.height)
    end
    host._paintClipState = state
    recordAllocation(paintRow, "clipProgramCreated",
        "clipProgramAllocatedKB", before)
    return state
end

-- Copies one arranged rectangle into Host-owned scalar stencil scratch.
local function prepareClip(state, node, kind, shineSplit)
    local box = node.layout
    if kind == "content" then
        state.x, state.y = box.contentX, box.contentY
        state.width, state.height = box.contentWidth, box.contentHeight
    else
        state.x, state.y = box.x, box.y
        state.width = box.width
        state.height = kind == "shine"
            and box.height * shineSplit or box.height
    end
end

local function beginClip(state, node, kind, shineSplit)
    local g = graphics()
    if not g or not state then return end
    prepareClip(state, node, kind, shineSplit)
    local parentDepth = state.depth
    if parentDepth == 0 then
        g.stencil(state.drawShape, "replace", 1, true)
    else
        g.stencil(state.drawShape, "increment", 1, true)
    end
    state.depth = parentDepth + 1
    g.setStencilTest("equal", state.depth)
end

local function endClip(state, node, kind, shineSplit)
    local g = graphics()
    if not g or not state then return end
    local currentDepth = state.depth
    assert(currentDepth > 0, "FrogUI clip stack underflow")
    prepareClip(state, node, kind, shineSplit)
    g.stencil(state.drawShape, "decrement", 1, true)
    state.depth = currentDepth - 1
    if state.depth == 0 then g.setStencilTest()
    else g.setStencilTest("equal", state.depth) end
end

local function styleFor(host, node, inheritedOpacity, inheritedTint, scratch,
        paintRow)
    local props = node.props
    local presentation = node.presentation or {}
    local authoredOpacity = node.type ~= "Motion" and node.type ~= "PopupText"
        and type(props.opacity) == "number" and props.opacity or 1
    local opacity = inheritedOpacity * authoredOpacity * (presentation.opacity or 1)
    local retainedScratch = scratch ~= nil
    scratch = scratch or {}
    local style = scratch.style
    local coldBefore = retainedScratch and not style and paintRow
        and collectgarbage("count") or nil
    if not style then
        style = { transform = {} }
        scratch.style = style
    end
    local tint = writeTint(scratch.tint, inheritedTint, presentation.tint)
    scratch.tint = tint
    local background = props.background and host:_color(props.background) or nil
    local border = props.border and host:_color(props.border) or nil
    style.borderWidth = props.borderWidth or (props.border and 1 or 0)
    style.radius = props.radius or 0
    style.opacity = opacity
    style.tint = tint
    local transform = style.transform
    transform.x = presentation.x or 0
    transform.y = presentation.y or 0
    transform.rotation = presentation.rotation or 0
    transform.scale = presentation.scale or 1
    transform.scaleX = presentation.scaleX or 1
    transform.scaleY = presentation.scaleY or 1
    transform.pivotX = node.props.pivot and node.props.pivot.x or 0.5
    transform.pivotY = node.props.pivot and node.props.pivot.y or 0.5
    if retainedScratch then
        -- Static identity nodes use their authoritative layout rectangle
        -- directly instead of retaining a duplicate transformed-bounds table.
        transform.bounds = node._visualBounds or node.layout
        transform.world = node._worldTransform
    else
        local bounds = node._visualBounds or node.layout
        transform.bounds = {
            x = bounds.x,
            y = bounds.y,
            width = bounds.width,
            height = bounds.height,
        }
        local world = node._worldTransform
        transform.world = world and {
            a = world.a,
            b = world.b,
            c = world.c,
            d = world.d,
            tx = world.tx,
            ty = world.ty,
        } or nil
    end
    if node.type == "Button" or node.type == "TextInput" then
        local button = ((host.theme.controls or {}).button or {})
        background = props.background or button.background
        border = props.border or button.border
        if props.disabled then
            background = props.background or button.disabled
            background = host:_color(background, "buttonDisabled")
        elseif node.type == "Button" and host._pressedIdentity == node.identity then
            background = props.pressedBackground or props.background
                or button.pressed
            border = props.pressedBorder or props.border or button.border
            background = host:_color(background, "buttonPressed")
        elseif host._focusedIdentity == node.identity then
            background = props.focusedBackground or props.background
                or button.focused or button.hover
            border = props.focusedBorder or button.focusedBorder
                or props.hoverBorder or props.border or button.border
            background = host:_color(background, "buttonFocused")
        elseif props.selected then
            background = props.selectedBackground or button.selected
                or props.background
            border = props.selectedBorder or props.border or button.border
            background = host:_color(background, "buttonSelected")
        elseif host._hoveredIdentity == node.identity then
            background = props.hoverBackground or props.background
                or button.hover
            border = props.hoverBorder or props.border or button.border
            background = host:_color(background, "buttonHover")
        else
            background = host:_color(background, "button")
        end
        if border then
            border = host:_color(border, "border")
            style.borderWidth = props.borderWidth or 1
        end
        style.radius = props.radius or button.radius or 5
    elseif node.type == "RadialDial" then
        local button = ((host.theme.controls or {}).button or {})
        background = props.background
            and host:_color(props.background) or nil
        border = props.border
        if host._focusedIdentity == node.identity and not props.disabled then
            border = props.focusedBorder or button.focusedBorder
            border = border and host:_color(border, "inspectorSelected")
                or host:_color(nil, "inspectorSelected")
            style.borderWidth = math.max(2, props.borderWidth or 0)
        elseif border then
            border = host:_color(border, "border")
            style.borderWidth = props.borderWidth or 1
        end
    end
    style.background = writePaintColor(
        scratch.background, background, tint, opacity)
    style.border = writePaintColor(scratch.border, border, tint, opacity)
    if style.background then scratch.background = style.background end
    if style.border then scratch.border = style.border end
    if coldBefore then
        recordAllocation(paintRow, "styleColdCalls",
            "styleColdAllocatedKB", coldBefore)
    end
    return style
end

-- Default painting owns reusable ephemeral style storage on the committed
-- primitive. It carries no semantic state and may move only to the same
-- primitive type at the same logical identity after a successful commit.
local function defaultScratch(node, paintRow)
    local scratch = node._paintScratch
    if not scratch then
        local before = paintRow and collectgarbage("count") or nil
        scratch = {}
        node._paintScratch = scratch
        recordAllocation(paintRow, "scratchCreated", "scratchAllocatedKB",
            before)
    end
    return scratch
end

-- Default leaf styles reuse storage beneath their committed node. Custom
-- painters take the fresh branch so retained user arguments can never alias
-- or mutate the default Painter's next frame.
local function leafScratch(node, custom, name, paintRow)
    if custom then return {}, {} end
    local root = defaultScratch(node, paintRow)
    local leaves = root.leaves
    if not leaves then
        leaves = {}
        root.leaves = leaves
    end
    local entry = leaves[name]
    if not entry then
        entry = { style = {} }
        leaves[name] = entry
    end
    return entry.style, entry
end

local function textStyleFor(host, node, inherited, custom, paintRow)
    local root = node._paintScratch
    local leaves = root and root.leaves
    local coldBefore = not custom and not (leaves and leaves.text)
        and paintRow and collectgarbage("count") or nil
    local style, scratch = leafScratch(node, custom, "text", paintRow)
    scratch.color = writePaintColor(scratch.color,
        host:_color(node.props.color, "text"),
        inherited.tint, inherited.opacity)
    scratch.outlineColor = writePaintColor(scratch.outlineColor,
        host:_color(node.props.outlineColor, nil, BLACK),
        inherited.tint, inherited.opacity)
    scratch.shadowColor = writePaintColor(scratch.shadowColor,
        host:_color(node.props.shadowColor, nil, BLACK),
        inherited.tint, inherited.opacity)
    style.color = scratch.color
    style.font = node.layout.resolvedFont or host:_font(node.props.role)
    style.role = node.props.role or "body"
    style.outlineWidth = node.props.outlineWidth or 0
    style.outlineColor = scratch.outlineColor
    style.shadowOffset = node.props.shadowOffset or 0
    style.shadowColor = scratch.shadowColor
    style.shine = node.props.shine or 0
    style.shineSplit = node.props.shineSplit or 0.5
    if coldBefore then
        recordAllocation(paintRow, "textLeafColdCalls",
            "textLeafColdAllocatedKB", coldBefore)
    end
    return style
end

local function imageStyleFor(host, node, inherited, custom, name, paintRow)
    local root = node._paintScratch
    local leaves = root and root.leaves
    local coldBefore = not custom and not (leaves and leaves[name])
        and paintRow and collectgarbage("count") or nil
    local style, scratch = leafScratch(node, custom, name, paintRow)
    scratch.tint = writePaintColor(scratch.tint,
        host:_color(node.props.tint, nil, WHITE),
        inherited.tint, inherited.opacity)
    style.tint = scratch.tint
    if coldBefore then
        recordAllocation(paintRow, "imageLeafColdCalls",
            "imageLeafColdAllocatedKB", coldBefore)
    end
    return style, scratch
end

local function sourceRectFor(node, custom)
    local rect = node.props.sourceRect
    if not rect or not custom then return rect end
    return {
        x = rect.x,
        y = rect.y,
        width = rect.width,
        height = rect.height,
    }
end

local function defaultBox(host, node, style)
    local g = graphics()
    if not g then return end
    if node.type == "RadialDial" then
        local centerX = node.layout.x + node.layout.width / 2
        local centerY = node.layout.y + node.layout.height / 2
        local radius = math.min(node.layout.width, node.layout.height) / 2
        if style.background then
            setColor(style.background)
            g.circle("fill", centerX, centerY, radius)
        end
        if style.border and style.borderWidth > 0 then
            setColor(style.border)
            g.setLineWidth(style.borderWidth)
            g.circle("line", centerX, centerY,
                math.max(0, radius - style.borderWidth / 2))
        end
        return
    end
    if style.background then
        setColor(style.background)
        g.rectangle("fill", node.layout.x, node.layout.y, node.layout.width, node.layout.height,
            style.radius, style.radius)
    end
    if style.border and style.borderWidth > 0 then
        setColor(style.border)
        g.setLineWidth(style.borderWidth)
        g.rectangle("line", node.layout.x, node.layout.y, node.layout.width, node.layout.height,
            style.radius, style.radius)
    end
end

local OUTLINE_DIRECTIONS = {
    { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 },
    { -0.7, -0.7 }, { 0.7, -0.7 },
    { -0.7, 0.7 }, { 0.7, 0.7 },
}

local function stampText(g, node, value, align, dx, dy)
    g.printf(value, node.layout.x + (dx or 0), node.layout.y + (dy or 0),
        math.max(0, node.layout.width), align)
end

local function defaultText(host, node, style, clipState, paintRow)
    local g = graphics()
    if not g then return end
    local font = node.layout.resolvedFont or host:_font(node.props.role)
    if font then g.setFont(font) end
    local align = node.props.align or "left"
    if align == "start" then align = "left"
    elseif align == "end" then align = "right" end
    local value = tostring(node.props.text or "")
    if style.shadowOffset > 0 then
        setColor(style.shadowColor)
        stampText(g, node, value, align,
            style.shadowOffset, style.shadowOffset)
    end
    if style.outlineWidth > 0 then
        local width = style.outlineWidth
        setColor(style.outlineColor)
        for _, direction in ipairs(OUTLINE_DIRECTIONS) do
            stampText(g, node, value, align,
                direction[1] * width, direction[2] * width)
        end
    end
    setColor(style.color)
    stampText(g, node, value, align, 0, 0)
    if style.shine > 0 and style.shineSplit > 0 then
        beginClip(clipState, node, "shine", style.shineSplit)
        local scratch = defaultScratch(node, paintRow)
        local coldBefore = not scratch.shineColor and paintRow
            and collectgarbage("count") or nil
        scratch.shineColor = writeBrightened(
            scratch.shineColor, style.color, style.shine)
        if coldBefore then
            recordAllocation(paintRow, "shineColorCreated",
                "shineColorAllocatedKB", coldBefore)
        end
        setColor(scratch.shineColor)
        stampText(g, node, value, align, 0, 0)
        endClip(clipState, node, "shine", style.shineSplit)
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

-- Paints one deterministic particle catalog as semantic circles or one asset.
local function defaultParticleBurst(host, node, state, style)
    local g = graphics()
    if not g or not state or not state.visible or not state.center then return end
    local asset = node.props.source and host:_asset(node.props.source) or nil
    local imageWidth, imageHeight
    if asset then imageWidth, imageHeight = asset:getDimensions() end
    for _, particle in ipairs(state.particles or {}) do
        local radius = math.max(0, particle.radius or 0)
        local alpha = math.max(0, particle.alpha or 0)
        if radius > 0 and alpha > 0 then
            if asset then
                g.setColor(style.tint[1], style.tint[2], style.tint[3],
                    style.tint[4] * alpha)
                local height = radius * 2
                local width = height * imageWidth / imageHeight
                g.draw(asset, particle.x, particle.y, 0,
                    width / imageWidth, height / imageHeight,
                    imageWidth / 2, imageHeight / 2)
            else
                g.setColor(style.color[1], style.color[2], style.color[3],
                    style.color[4] * alpha)
                g.circle("fill", particle.x, particle.y, radius)
            end
        end
    end
end

local function imageGeometry(node, asset, fit, sourceRect)
    local imageWidth = sourceRect and sourceRect.width or asset:getWidth()
    local imageHeight = sourceRect and sourceRect.height or asset:getHeight()
    local scaleX, scaleY = node.layout.width / imageWidth, node.layout.height / imageHeight
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
        x = node.layout.x + (node.layout.width - width) / 2,
        y = node.layout.y + (node.layout.height - height) / 2,
        centerX = node.layout.x + node.layout.width / 2,
        centerY = node.layout.y + node.layout.height / 2,
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
    g.rectangle("line", node.layout.x, node.layout.y, node.layout.width, node.layout.height)
    g.line(node.layout.x, node.layout.y, node.layout.x + node.layout.width, node.layout.y + node.layout.height)
    g.line(node.layout.x + node.layout.width, node.layout.y, node.layout.x, node.layout.y + node.layout.height)
end

local function defaultImage(host, node, asset, style, clipState, paintRow)
    local g = graphics()
    if not g then return end
    if not asset or not asset.getWidth or not asset.getHeight then
        missingAsset(node, style)
        return
    end
    local geometry = imageGeometry(node, asset, style.fit, style.sourceRect)
    setColor(style.tint)
    if style.fit == "cover" then beginClip(clipState, node, "bounds") end
    local quad = sourceQuad(asset, style.sourceRect)
    local scaleX = style.mirror and -geometry.scaleX or geometry.scaleX
    if quad then
        g.draw(asset, quad, geometry.centerX, geometry.centerY, 0,
            scaleX, geometry.scaleY,
            geometry.imageWidth / 2, geometry.imageHeight / 2)
    else
        g.draw(asset, geometry.centerX, geometry.centerY, 0,
            scaleX, geometry.scaleY,
            geometry.imageWidth / 2, geometry.imageHeight / 2)
    end
    if style.fit == "cover" then endClip(clipState, node, "bounds") end
end

-- Resolves one horizontal sheet frame directly from explicit clock time.
-- SpriteSheet has no retained playback state: rewinding the clock rewinds art.
local function spriteSheetGeometry(node, asset)
    local props = node.props
    local time = props.clock:now()
    local frame = math.floor(time * props.fps) % props.frameCount + 1
    local frameWidth = asset and asset:getWidth() / props.frameCount or 48
    local frameHeight = asset and asset:getHeight() or 48
    local geometry = {
        status = asset and "ready" or "missing",
        frame = frame,
        frameCount = props.frameCount,
        fps = props.fps,
        time = time,
        clock = "explicit",
        fit = props.fit or "contain",
        filter = props.filter or "nearest",
        mirror = props.mirror == true,
        frameWidth = frameWidth,
        frameHeight = frameHeight,
    }
    if asset then
        geometry.sourceRect = {
            x = (frame - 1) * frameWidth,
            y = 0,
            width = frameWidth,
            height = frameHeight,
        }
        local fitted = imageGeometry(node, asset, geometry.fit,
            geometry.sourceRect)
        for key, value in pairs(fitted) do geometry[key] = value end
    end
    return geometry
end

-- Draws one clock-selected horizontal sheet frame and restores the shared
-- Image object's previous filter even when LÖVE rejects the draw.
local function drawSpriteSheetFrame(g, asset, geometry, style)
    local quad = sourceQuad(asset, geometry.sourceRect)
    local scaleX = geometry.mirror and -geometry.scaleX
        or geometry.scaleX
    setColor(style.tint)
    g.draw(asset, quad, geometry.centerX, geometry.centerY, 0,
        scaleX, geometry.scaleY,
        geometry.imageWidth / 2, geometry.imageHeight / 2)
end

local function defaultSpriteSheet(host, node, asset, geometry, style,
        clipState, paintRow)
    local g = graphics()
    if not g then return end
    if not asset or not asset.getWidth or not asset.getHeight then
        missingAsset(node, style)
        return
    end
    local previousMin, previousMag, previousAnisotropy
    if asset.getFilter and asset.setFilter then
        previousMin, previousMag, previousAnisotropy = asset:getFilter()
        asset:setFilter(geometry.filter, geometry.filter)
    end
    if geometry.fit == "cover" then
        beginClip(clipState, node, "bounds")
    end
    local ok, reason = pcall(
        drawSpriteSheetFrame, g, asset, geometry, style)
    if geometry.fit == "cover" then
        endClip(clipState, node, "bounds")
    end
    if previousMin then
        asset:setFilter(previousMin, previousMag, previousAnisotropy)
    end
    if not ok then error(reason, 0) end
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
local function stampIcon(g, asset, quad, geometry, scaleX, dx, dy)
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

local function defaultIcon(host, node, asset, style, clipState, paintRow)
    local g = graphics()
    if not g then return end
    if not asset or not asset.getWidth or not asset.getHeight then
        missingAsset(node, style)
        return
    end
    local geometry = imageGeometry(node, asset, style.fit, style.sourceRect)
    local quad = sourceQuad(asset, style.sourceRect)
    local scaleX = style.mirror and -geometry.scaleX or geometry.scaleX

    if style.fit == "cover" then beginClip(clipState, node, "bounds") end
    local previousShader = g.getShader and g.getShader() or nil
    g.setShader(alphaMaskShader())
    if style.outline and style.outline.width > 0 then
        local width = style.outline.width
        setColor(style.outline.color)
        for _, direction in ipairs(OUTLINE_DIRECTIONS) do
            stampIcon(g, asset, quad, geometry, scaleX,
                direction[1] * width, direction[2] * width)
        end
    end
    setColor(style.tint)
    stampIcon(g, asset, quad, geometry, scaleX, 0, 0)
    g.setShader(previousShader)
    if style.fit == "cover" then endClip(clipState, node, "bounds") end
end

local function modulo(value, size)
    return ((value % size) + size) % size
end

-- Samples one bounded rise-and-return tile phase without retained Motion.
local function tiledImpulse(impulse)
    if not impulse then return 0, 0 end
    local elapsed = impulse.clock:now() - impulse.startedAt
    if elapsed <= 0 or elapsed >= impulse.duration then return 0, 0 end
    local peakTime = impulse.duration * impulse.peakAt
    local amount
    if elapsed <= peakTime then
        local progress = elapsed / peakTime
        amount = 1 - (1 - progress) * (1 - progress)
    else
        local progress = (elapsed - peakTime)
            / (impulse.duration - peakTime)
        local eased = progress < 0.5
            and 2 * progress * progress
            or 1 - (-2 * progress + 2) ^ 2 / 2
        amount = 1 - eased
    end
    return (impulse.offset.x or 0) * amount,
        (impulse.offset.y or 0) * amount
end

-- Plans one repeated axis with bounded integer work and no floating while-loop.
local function tilePlan(start, size, tileSize, phase, repeats, snap)
    local origin = start + (repeats and modulo(phase, tileSize) or phase)
    if snap then origin = math.floor(origin / snap + 0.5) * snap end
    if not repeats then return origin, 1 end
    local first = origin - math.ceil((origin - start) / tileSize) * tileSize
    if first + tileSize <= start then first = first + tileSize end
    local count = math.max(0,
        math.ceil((start + size - first) / tileSize))
    assert(count < math.huge,
        "TiledImage repeat count must remain finite")
    return first, count
end

-- Materializes one already-budgeted adjacent position list by integer index.
local function tilePositions(first, tileSize, count)
    local positions = {}
    for index = 0, count - 1 do
        positions[#positions + 1] = first + index * tileSize
    end
    return positions
end

-- Resolves repeat geometry from intrinsic art, authored phase, and one clock.
local function tiledGeometry(node, asset)
    local props = node.props
    local imageWidth = asset and asset:getWidth() or 48
    local imageHeight = asset and asset:getHeight() or 48
    local tileWidth, tileHeight = props.tileWidth, props.tileHeight
    if tileWidth and not tileHeight then
        tileHeight = tileWidth * imageHeight / imageWidth
    elseif tileHeight and not tileWidth then
        tileWidth = tileHeight * imageWidth / imageHeight
    else
        tileWidth = tileWidth or imageWidth
        tileHeight = tileHeight or imageHeight
    end
    local time = props.clock and props.clock:now() or 0
    local phase, velocity = props.phase or {}, props.velocity or {}
    local impulseX, impulseY = tiledImpulse(props.phaseImpulse)
    local phaseX = (phase.x or 0) + (velocity.x or 0) * time + impulseX
    local phaseY = (phase.y or 0) + (velocity.y or 0) * time + impulseY
    local axis = props.repeatAxis or "both"
    local snap = props.filter == "nearest" and 1 or nil
    local columnFirst, columnCount = tilePlan(node.layout.x, node.layout.width, tileWidth,
        phaseX, axis == "x" or axis == "both", snap)
    local rowFirst, rowCount = tilePlan(node.layout.y, node.layout.height, tileHeight,
        phaseY, axis == "y" or axis == "both", snap)
    assert(columnCount * rowCount <= MAX_TILE_COPIES,
        "TiledImage exceeds its per-leaf copy budget")
    local columns = tilePositions(columnFirst, tileWidth, columnCount)
    local rows = tilePositions(rowFirst, tileHeight, rowCount)
    return {
        phase = { x = phaseX, y = phaseY },
        tileWidth = tileWidth,
        tileHeight = tileHeight,
        columns = columns,
        rows = rows,
        repeatAxis = axis,
        filter = props.filter or "linear",
        clock = props.clock and "explicit" or "none",
        phaseImpulse = props.phaseImpulse and "explicit" or "none",
    }
end

-- Clips tiles to one leaf while preserving any surrounding shader and filter.
local function drawTiles(g, asset, geometry)
    local scaleX = geometry.tileWidth / asset:getWidth()
    local scaleY = geometry.tileHeight / asset:getHeight()
    for _, y in ipairs(geometry.rows) do
        for _, x in ipairs(geometry.columns) do
            g.draw(asset, x, y, 0, scaleX, scaleY)
        end
    end
end

local function defaultTiledImage(host, node, asset, geometry, style, clipState,
        paintRow)
    local g = graphics()
    if not g or not asset then return end
    local previousMin, previousMag, previousAnisotropy
    if asset.getFilter and asset.setFilter then
        previousMin, previousMag, previousAnisotropy = asset:getFilter()
        asset:setFilter(geometry.filter, geometry.filter)
    end
    local activeShader = g.getShader and g.getShader() or nil
    if activeShader then g.setShader() end
    beginClip(clipState, node, "bounds")
    if activeShader then g.setShader(activeShader) end
    setColor(style.tint)
    local ok, reason = pcall(drawTiles, g, asset, geometry)
    if activeShader then g.setShader() end
    endClip(clipState, node, "bounds")
    if activeShader then g.setShader(activeShader) end
    if previousMin then
        asset:setFilter(previousMin, previousMag, previousAnisotropy)
    end
    if not ok then error(reason, 0) end
end

-- Replays validated local shape commands beneath their scoped transforms.
local function replayCanvasCommands(g, commands)
    for _, command in ipairs(commands) do
        if command.kind == "transform" then
            g.push("all")
            g.translate(command.x, command.y)
            g.rotate(command.rotation)
            g.scale(command.scale)
            local ok, reason = pcall(replayCanvasCommands, g,
                command.commands)
            g.pop()
            if not ok then error(reason, 0) end
        else
            setColor(command.color)
            if command.kind == "fillRect" then
                g.rectangle("fill", command.x, command.y,
                    command.width, command.height,
                    command.radius, command.radius, command._segments)
            elseif command.kind == "strokeRect" then
                g.setLineWidth(command.lineWidth)
                g.rectangle("line", command.x, command.y,
                    command.width, command.height,
                    command.radius, command.radius, command._segments)
            elseif command.kind == "fillCircle" then
                g.circle("fill", command.x, command.y,
                    command.radius, command._segments)
            elseif command.kind == "strokeCircle" then
                g.setLineWidth(command.lineWidth)
                g.circle("line", command.x, command.y,
                    command.radius, command._segments)
            elseif command.kind == "fillEllipse" then
                g.ellipse("fill", command.x, command.y,
                    command.radiusX, command.radiusY, command._segments)
            else
                error("unknown validated Canvas command "
                    .. tostring(command.kind), 0)
            end
        end
    end
end

-- Clips and replays one recorded leaf while restoring state on GPU failure.
local function defaultCanvas(host, node, commands, clipState, paintRow)
    local g = graphics()
    if not g then return true end
    beginClip(clipState, node, "bounds")
    g.push("all")
    g.translate(node.layout.x, node.layout.y)
    local ok, reason = pcall(replayCanvasCommands, g, commands)
    g.pop()
    endClip(clipState, node, "bounds")
    return ok, reason
end

-- Records every visible Canvas before a frame clears or touches GPU state.
local function preflightNode(host, node, inheritedOpacity, inheritedTint,
        portalRoot, paintRow)
    if not node._containsCanvas then return nil end
    if node._portal and node ~= portalRoot then return nil end
    local session = host._interactionSession
    if session and session.claimed == "drag"
            and node.identity == session.sourceIdentity then return nil end
    local style = styleFor(host, node, inheritedOpacity or 1, inheritedTint,
        defaultScratch(node, paintRow), paintRow)
    if node.type == "Canvas" then
        local commands, inspection = Canvas.record(node.props.draw,
            node.layout.width, node.layout.height, function(color, output)
                return writeTintOpacity(
                    output, host:_color(color, "text"),
                    style.tint, style.opacity)
            end)
        inspection.arrangedBounds = {
            x = node.layout.x, y = node.layout.y, width = node.layout.width, height = node.layout.height,
        }
        node._canvasCommands = commands
        node._canvasInspection = inspection
        if inspection.status == "failed" then return inspection.error end
    end
    for _, child in ipairs(node.children) do
        local failure = preflightNode(host, child, style.opacity, style.tint,
            portalRoot, paintRow)
        if failure then return failure end
    end
end

-- Mirrors visible root-plane order so callbacks observe authored paint order.
local function preflightCanvases(host, paintRow)
    local failure = preflightNode(host, host._tree, nil, nil, nil, paintRow)
    if failure then return failure end
    local chrome = host._chrome
    local chromeAboveModal = chrome and host._modal
        and host._modal.props.allowChrome == true
    if chrome and not chromeAboveModal then
        failure = preflightNode(host, chrome, nil, nil, chrome, paintRow)
        if failure then return failure end
    end
    for _, modal in ipairs(host._modals or {}) do
        failure = preflightNode(host, modal, nil, nil, modal, paintRow)
        if failure then return failure end
    end
    if chromeAboveModal then
        failure = preflightNode(host, chrome, nil, nil, chrome, paintRow)
        if failure then return failure end
    end
    local session = host._interactionSession
    local preview = session and session.claimed == "drag"
        and session.source and session.source._dragPreview or nil
    if preview then
        return preflightNode(host, preview, nil, nil, preview, paintRow)
    end
end

local function customCall(custom, method, ...)
    if custom and custom[method] then custom[method](custom, ...) end
end

-- Gives custom painters useful arranged data without exposing the committed
-- tree, callbacks, actors, or a path back to a Canvas draw closure.
local function safeCustomValue(value, seen)
    local kind = type(value)
    if kind == "string" or kind == "number" or kind == "boolean" then
        return value
    end
    if kind ~= "table" or getmetatable(value) ~= nil then return nil end
    seen = seen or {}
    if seen[value] then return nil end
    seen[value] = true
    local copy = {}
    for key, child in pairs(value) do
        local safeKey = safeCustomValue(key, seen)
        local safeChild = safeCustomValue(child, seen)
        if safeKey ~= nil and safeChild ~= nil then copy[safeKey] = safeChild end
    end
    seen[value] = nil
    return copy
end

local function customNode(node)
    return {
        type = node.type,
        key = node.key,
        identity = node.identity,
        logicalIdentity = node.logicalIdentity,
        owner = node.owner,
        source = safeCustomValue(node.source),
        x = node.layout.x,
        y = node.layout.y,
        width = node.layout.width,
        height = node.layout.height,
        contentX = node.layout.contentX,
        contentY = node.layout.contentY,
        contentWidth = node.layout.contentWidth,
        contentHeight = node.layout.contentHeight,
        measuredWidth = node.layout.measuredWidth,
        measuredHeight = node.layout.measuredHeight,
        _resolvedFontSize = node.layout.resolvedFontSize,
        presentation = safeCustomValue(node.presentation),
        props = safeCustomValue(node.props) or {},
    }
end

local drawNode

-- Recurses without allocating one closure per primitive per frame. Shader
-- error isolation calls this same helper through pcall, preserving its exact
-- child push/pop and fallback behavior.
local function drawChildren(host, node, custom, style, clipState, portalRoot,
        paintRow)
    for _, child in ipairs(node.children) do
        drawNode(host, child, custom, style.opacity, style.tint,
            clipState, portalRoot, paintRow)
    end
end

drawNode = function(host, node, custom, inheritedOpacity, inheritedTint,
        clipState, portalRoot, paintRow)
    if node._portal and node ~= portalRoot then return end
    local session = host._interactionSession
    if session and session.claimed == "drag"
            and node.identity == session.sourceIdentity then return end
    local g = graphics()
    local presentation = node.presentation or {}
    local radialPresentation = node.type == "RadialDial"
        and Interaction.radialPresentation(node) or nil
    local radialScale = radialPresentation and radialPresentation.scale or 1
    if not custom and g then
        local pivot = node.props.pivot
        local pivotX = node.layout.x + node.layout.width
            * (pivot and pivot.x or 0.5)
        local pivotY = node.layout.y + node.layout.height
            * (pivot and pivot.y or 0.5)
        local scale = presentation.scale or 1
        g.push("all")
        g.translate(presentation.x or 0, presentation.y or 0)
        g.translate(pivotX, pivotY)
        g.rotate(presentation.rotation or 0)
        g.scale(scale * (presentation.scaleX or 1) * radialScale,
            scale * (presentation.scaleY or 1) * radialScale)
        g.translate(-pivotX, -pivotY)
    end
    local style = styleFor(host, node, inheritedOpacity or 1, inheritedTint,
        not custom and defaultScratch(node, paintRow) or nil, paintRow)
    style.transform.scale = style.transform.scale * radialScale
    local customDescriptor = custom and customNode(node) or nil
    if custom then
        customCall(custom, "box", customDescriptor, style)
    else
        defaultBox(host, node, style)
    end

    if node.type == "Canvas" then
        local commands = assert(node._canvasCommands,
            "Canvas commands were not preflighted")
        local inspection = assert(node._canvasInspection,
            "Canvas inspection was not preflighted")
        if custom then
            customCall(custom, "canvas", customDescriptor,
                Canvas.detached(commands), Canvas.detached(inspection))
        elseif inspection.status == "ready" then
            local ok, reason = defaultCanvas(
                host, node, commands, clipState, paintRow)
            if not ok then
                inspection.status = "failed"
                inspection.commandCount = 0
                inspection.transformDepth = 0
                inspection.error = tostring(reason)
                if not host._paintFailure then
                    host._paintFailure = inspection.error
                end
            end
        end
    elseif node.type == "Projectile" then
        local effectStyle = {
            color = faded(tinted(host:_color(node.props.color, "text"),
                style.tint), style.opacity),
            tint = faded(tinted(host:_color(node.props.tint, nil,
                node.props.color and host:_color(node.props.color)
                    or { 1, 1, 1, 1 }), style.tint), style.opacity),
        }
        if custom then
            customCall(custom, "projectile", customDescriptor,
                node._effect, effectStyle)
        else
            defaultProjectile(host, node, node._effect, effectStyle)
        end
    elseif node.type == "Flipbook" then
        local effectStyle = {
            tint = faded(tinted(host:_color(node.props.tint, nil,
                { 1, 1, 1, 1 }), style.tint), style.opacity),
        }
        if custom then
            customCall(custom, "flipbook", customDescriptor,
                node._effect, effectStyle)
        else
            defaultFlipbook(host, node, node._effect, effectStyle)
        end
    elseif node.type == "ParticleBurst" then
        local effectStyle = {
            color = faded(tinted(host:_color(node.props.color, "text"),
                style.tint), style.opacity),
            tint = faded(tinted(host:_color(node.props.tint, nil,
                node.props.color and host:_color(node.props.color)
                    or { 1, 1, 1, 1 }), style.tint), style.opacity),
        }
        if custom then
            customCall(custom, "particleBurst", customDescriptor,
                node._effect, effectStyle)
        else
            defaultParticleBurst(host, node, node._effect, effectStyle)
        end
    elseif node.type == "Text" or node.type == "PopupText" then
        local textStyle = textStyleFor(host, node, style, custom, paintRow)
        if custom then
            customCall(custom, "text", customDescriptor,
                node.props.text or "", textStyle)
        else
            if node.props.maxLines and g then
                beginClip(clipState, node, "bounds")
            end
            defaultText(host, node, textStyle, clipState, paintRow)
            if node.props.maxLines and g then
                endClip(clipState, node, "bounds")
            end
        end
    elseif node.type == "TiledImage" then
        local imageStyle = imageStyleFor(
            host, node, style, custom, "tiledImage", paintRow)
        local asset = host:_asset(node.props.source)
        local geometry = tiledGeometry(node, asset)
        node._tileGeometry = geometry
        if custom then
            customCall(custom, "tiledImage", customDescriptor,
                asset, geometry, imageStyle)
        else
            defaultTiledImage(host, node, asset, geometry, imageStyle,
                clipState, paintRow)
        end
    elseif node.type == "SpriteSheet" then
        local spriteStyle = imageStyleFor(
            host, node, style, custom, "spriteSheet", paintRow)
        local asset = host:_asset(node.props.source)
        local geometry = spriteSheetGeometry(node, asset)
        node._spriteSheetGeometry = geometry
        if custom then
            customCall(custom, "spriteSheet", customDescriptor,
                asset, safeCustomValue(geometry), spriteStyle)
        else
            defaultSpriteSheet(host, node, asset, geometry, spriteStyle,
                clipState, paintRow)
        end
    elseif node.type == "Image" then
        local imageStyle = imageStyleFor(
            host, node, style, custom, "image", paintRow)
        imageStyle.fit = node.props.fit or "contain"
        imageStyle.sourceRect = sourceRectFor(node, custom)
        imageStyle.mirror = node.props.mirror == true
        local asset = host:_asset(node.props.source)
        if custom then
            customCall(custom, "image", customDescriptor, asset, imageStyle)
        else
            defaultImage(host, node, asset, imageStyle, clipState, paintRow)
        end
    elseif node.type == "Icon" then
        local outline = node.props.outline
        local iconStyle, iconScratch = imageStyleFor(
            host, node, style, custom, "icon", paintRow)
        iconStyle.fit = node.props.fit or "contain"
        iconStyle.sourceRect = sourceRectFor(node, custom)
        iconStyle.mirror = node.props.mirror == true
        iconStyle.alphaMask = true
        if outline then
            local outlineStyle = iconScratch.outline
            local coldBefore = not outlineStyle and paintRow
                and collectgarbage("count") or nil
            if not outlineStyle then
                outlineStyle = {}
                iconScratch.outline = outlineStyle
            end
            iconScratch.outlineColor = writePaintColor(
                iconScratch.outlineColor,
                host:_color(outline.color, nil, ICON_OUTLINE),
                style.tint, style.opacity)
            outlineStyle.width = outline.width or 1
            outlineStyle.color = iconScratch.outlineColor
            iconStyle.outline = outlineStyle
            if coldBefore then
                recordAllocation(paintRow, "iconExtensionCalls",
                    "iconExtensionAllocatedKB", coldBefore)
            end
        else
            iconStyle.outline = nil
        end
        local asset = host:_asset(node.props.source)
        if custom then
            customCall(custom, "icon", customDescriptor, asset, iconStyle)
        else
            defaultIcon(host, node, asset, iconStyle, clipState, paintRow)
        end
    end

    local clipped = node.type == "Scroll" or node.props.clip
        or node.props.overflow == "clip"
    if clipped and not custom and g then
        beginClip(clipState, node, "content")
    end
    if node.type == "ShaderImage" then
        if custom then
            node._shaderInspection = Shader.inspect(host, node)
            customCall(custom, "shaderImage", customDescriptor,
                node._shaderInspection)
            drawChildren(host, node, custom, style, clipState, portalRoot,
                paintRow)
        else
            local previousShader = g.getShader and g.getShader() or nil
            local previousBlend, previousAlpha = g.getBlendMode()
            local active = Shader.activate(host, node)
            node._shaderInspection = Shader.inspect(host, node)
            if active then
                local ok, reason = pcall(drawChildren,
                    host, node, custom, style, clipState, portalRoot,
                    paintRow)
                if not ok then
                    -- The validated child is one paint leaf, so its unmatched
                    -- drawNode push is the only graphics frame to unwind.
                    g.pop()
                    Shader.drawFailed(host, node, reason)
                    g.setShader(previousShader)
                    g.setBlendMode(previousBlend, previousAlpha)
                    node._shaderInspection = Shader.inspect(host, node)
                    if (node.props.fallback or "plain") == "plain" then
                        drawChildren(host, node, custom, style,
                            clipState, portalRoot, paintRow)
                    end
                end
            elseif (node.props.fallback or "plain") == "plain" then
                g.setShader(previousShader)
                g.setBlendMode(previousBlend, previousAlpha)
                drawChildren(host, node, custom, style,
                    clipState, portalRoot, paintRow)
            end
        end
    else
        drawChildren(host, node, custom, style, clipState, portalRoot,
            paintRow)
    end
    if clipped and not custom and g then
        endClip(clipState, node, "content")
    end
    if node.type == "Scroll" and node.props.bar and node._scroll
            and node._scroll.extent > 0 and not custom and g then
        local scroll = node._scroll
        local ratio = scroll.viewport / math.max(scroll.viewport, scroll.content)
        local progress = scroll.offset / scroll.extent
        setColor(host:_color(nil, "textDim", { 0.65, 0.7, 0.72, 0.65 }))
        if scroll.axis == "vertical" then
            local length = math.max(16, node.layout.contentHeight * ratio)
            g.rectangle("fill", node.layout.contentX + node.layout.contentWidth - 3,
                node.layout.contentY + (node.layout.contentHeight - length) * progress,
                3, length, 1.5, 1.5)
        else
            local length = math.max(16, node.layout.contentWidth * ratio)
            g.rectangle("fill", node.layout.contentX
                    + (node.layout.contentWidth - length) * progress,
                node.layout.contentY + node.layout.contentHeight - 3,
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
    if entry.inspectionShape and entry.inspectionShape.type == "circle" then
        local circle = entry.inspectionShape
        g.circle("line", circle.center.x, circle.center.y, circle.radius)
    else
        g.rectangle("line", bounds.x, bounds.y, bounds.width, bounds.height)
    end
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
        elseif entry.canvas then
            local state = entry.canvas
            local localBounds = state.localBounds or {
                width = bounds.width, height = bounds.height,
            }
            g.print(("canvas %s / %d commands / depth %d / "
                    .. "local %.1fx%.1f / clipped"):format(
                    tostring(state.status), state.commandCount or 0,
                    state.transformDepth or 0,
                    localBounds.width or 0, localBounds.height or 0),
                bounds.x + 3, bounds.y + 2 + detailLine * lineHeight)
            detailLine = detailLine + 1
        elseif entry.spriteSheet then
            local sprite = entry.spriteSheet
            g.print(("sprite %s / frame %d/%d / %.2fs @ %.2f fps"
                    .. " / %s clock / %s / %s%s"):format(
                    tostring(sprite.status), sprite.frame or 0,
                    sprite.frameCount or 0, sprite.time or 0,
                    sprite.fps or 0, tostring(sprite.clock),
                    tostring(sprite.fit), tostring(sprite.filter),
                    sprite.mirror and " / mirrored" or ""),
                bounds.x + 3, bounds.y + 2 + detailLine * lineHeight)
            detailLine = detailLine + 1
        elseif entry.tiledImage then
            local tile = entry.tiledImage
            local phase = tile.phase or { x = 0, y = 0 }
            g.print(("tiles %s / %s / phase %.1f,%.1f / %dx%d copies"):format(
                    tostring(tile.repeatAxis), tostring(tile.clock),
                    phase.x or 0, phase.y or 0,
                    #(tile.columns or {}), #(tile.rows or {})),
                bounds.x + 3, bounds.y + 2 + detailLine * lineHeight)
            detailLine = detailLine + 1
        elseif entry.shaderImage then
            local shaderState = entry.shaderImage
            g.print(("shader %s / %s / fallback %s / blend %s"):format(
                    tostring(shaderState.token), tostring(shaderState.status),
                    tostring(shaderState.fallback), tostring(shaderState.blend)),
                bounds.x + 3, bounds.y + 2 + detailLine * lineHeight)
            detailLine = detailLine + 1
        elseif entry.radialDial then
            local dial = entry.radialDial
            g.print(("radial value %s / index %d / angle %.3f / visual %.3f"
                    .. " / track %.1f / scale %.3f%s%s"):format(
                    tostring(dial.value), dial.index, dial.angle,
                    dial.visualAngle, dial.trackRadius or 0,
                    dial.paintScale or 1,
                    dial.settling and " / settling" or "",
                    dial.reducedMotion and " / reduced" or ""),
                bounds.x + 3, bounds.y + 2 + detailLine * lineHeight)
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
        if session.swipe then
            lines[#lines + 1] = ("horizontal swipe %s%s"):format(
                tostring(session.swipePhase or "candidate"),
                session.swipeDirection
                    and (" · " .. session.swipeDirection) or "")
        end
        if session.radial then
            lines[#lines + 1] = ("radial dial %s · index %s · angle %s"):format(
                tostring(session.radialPhase or "armed"),
                tostring(session.radialPreviewIndex or "-"),
                session.radialPreviewAngle
                    and ("%.3f"):format(session.radialPreviewAngle) or "-")
        end
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
    local paintRow = paintAllocationRow(host)
    local drawBefore = paintRow and collectgarbage("count") or nil
    host._paintFailure = nil
    local preflightBefore = paintRow and collectgarbage("count") or nil
    local preflightFailure = preflightCanvases(host, paintRow)
    recordAllocation(paintRow, "preflightCalls", "preflightAllocatedKB",
        preflightBefore)
    if preflightFailure then
        error("FrogUI Canvas draw failed: " .. preflightFailure, 0)
    end
    local setupBefore = paintRow and collectgarbage("count") or nil
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
    local clipState = not custom and clipStateFor(host, paintRow) or nil
    recordAllocation(paintRow, "setupCalls", "setupAllocatedKB",
        setupBefore)
    local treeBefore = paintRow and collectgarbage("count") or nil
    drawNode(host, host._tree, custom, nil, nil, clipState, nil, paintRow)
    local chrome = host._chrome
    local chromeAboveModal = chrome and host._modal
        and host._modal.props.allowChrome == true
    if chrome and not chromeAboveModal then
        drawNode(host, chrome, custom, nil, nil, clipState, chrome, paintRow)
    end
    for _, modal in ipairs(host._modals or {}) do
        drawNode(host, modal, custom, nil, nil, clipState, modal, paintRow)
    end
    if chromeAboveModal then
        drawNode(host, chrome, custom, nil, nil, clipState, chrome, paintRow)
    end
    local session = host._interactionSession
    local preview = session and session.claimed == "drag"
        and session.source and session.source._dragPreview or nil
    if preview then
        local previewLayout = assert(preview.layout,
            "FrogUI drag preview has no committed layout")
        customCall(custom, "dragPreview", customNode(preview), {
            x = session.x,
            y = session.y,
            pointerId = session.pointerId,
            claimed = session.claimed,
            press = session.pressIdentity,
            distance = session.distance,
            payloadKind = session.payload and session.payload.kind or nil,
        })
        if not custom and g then
            g.push("all")
            g.translate(session.x - previewLayout.width / 2,
                session.y - previewLayout.height / 2)
        end
        drawNode(host, preview, custom, nil, nil,
            clipState, preview, paintRow)
        if not custom and g then g.pop() end
    end
    recordAllocation(paintRow, "treeCalls", "treeAllocatedKB", treeBefore)
    local inspectorBefore = paintRow and collectgarbage("count") or nil
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
    recordAllocation(paintRow, "inspectorCalls", "inspectorAllocatedKB",
        inspectorBefore)
    local finishBefore = paintRow and collectgarbage("count") or nil
    if not custom and g then g.pop() end
    customCall(custom, "finish")
    local failure = host._paintFailure
    host._paintFailure = nil
    recordAllocation(paintRow, "finishCalls", "finishAllocatedKB",
        finishBefore)
    recordAllocation(paintRow, "drawCalls", "drawAllocatedKB", drawBefore)
    if failure then error("FrogUI Canvas draw failed: " .. failure, 0) end
end

painter.defaults = DEFAULTS

return painter
