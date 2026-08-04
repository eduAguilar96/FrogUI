-- Pure two-pass measurement and arrangement for resolved FrogUI primitives.
-- It owns box allocation only; components and input remain Host concerns.

local layout = {}

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

local function resolveSize(value, available)
    if type(value) == "number" then return math.max(0, value) end
    if type(value) == "string" then
        local number = value:match("^([%d%.]+)%%$")
        assert(number, "FrogUI size must be a number or percentage")
        return math.max(0, available * tonumber(number) / 100)
    end
    assert(value == nil, "FrogUI size must be a number, percentage, or nil")
    return nil
end

local function padding(value)
    if value == nil then value = 0 end
    if type(value) == "number" then
        return { left = value, right = value, top = value, bottom = value }
    end
    assert(type(value) == "table", "padding must be a number or side table")
    return {
        left = value.left or 0,
        right = value.right or 0,
        top = value.top or 0,
        bottom = value.bottom or 0,
    }
end

local function explicit(node, maxWidth, maxHeight)
    return resolveSize(node.props.width, maxWidth), resolveSize(node.props.height, maxHeight)
end

local function textSize(node, maxWidth, maxHeight, host)
    local text = tostring(node.props.text or "")
    local size = host:_fontSize(node.props.role) * (node.props.fontScale or 1)
    local minimum = (host.theme.fontSizes or {}).minimum or 8
    local font, width, height, lineCount
    local function measureAt(candidateSize)
        local candidateFont = host:_font(node.props.role, candidateSize)
        local candidateWidth, candidateHeight, lines
        if candidateFont and candidateFont.getWidth and candidateFont.getHeight then
            candidateWidth, candidateHeight = candidateFont:getWidth(text), candidateFont:getHeight()
            lines = 1
            if node.props.wrap and maxWidth < math.huge and candidateFont.getWrap then
                local wrappedWidth, wrappedLines = candidateFont:getWrap(text, math.max(1, maxWidth))
                candidateWidth = math.min(maxWidth, wrappedWidth)
                lines = math.max(1, #wrappedLines)
                candidateHeight = candidateHeight * lines
            end
        else
            candidateWidth, candidateHeight = #text * candidateSize * 0.55, candidateSize * 1.2
            lines = 1
            if node.props.wrap and maxWidth < math.huge and candidateWidth > maxWidth then
                lines = math.ceil(candidateWidth / math.max(1, maxWidth))
                candidateHeight = candidateHeight * lines
                candidateWidth = maxWidth
            end
        end
        return candidateFont, candidateWidth, candidateHeight, lines
    end
    font, width, height, lineCount = measureAt(size)
    local function visibleHeight()
        if not node.props.maxLines then return height end
        local lineHeight = font and font.getHeight and font:getHeight() or size * 1.2
        return math.min(height, lineHeight * node.props.maxLines)
    end
    if node.props.fitDown then
        while size > minimum and (width > maxWidth
                or visibleHeight() > maxHeight
                or node.props.maxLines and lineCount > node.props.maxLines) do
            size = size - 1
            font, width, height, lineCount = measureAt(size)
        end
    end
    node._resolvedFont = font
    node._resolvedFontSize = size
    if node.props.maxLines then
        local lineHeight = font and font.getHeight and font:getHeight() or size * 1.2
        height = math.min(height, lineHeight * node.props.maxLines)
    end
    return width, height
end

local function imageSize(node, host)
    local image = host:_asset(node.props.source)
    if image and image.getWidth and image.getHeight then
        return image:getWidth(), image:getHeight()
    end
    return 48, 48
end

local function wrappedLines(node, availableWidth)
    local gap = node.props.gap or 0
    local lines = {}
    local line = { children = {}, width = 0, height = 0 }
    for _, child in ipairs(node.children) do
        local childWidth = child.measuredWidth
        local nextWidth = childWidth
        if #line.children > 0 then nextWidth = line.width + gap + childWidth end
        if #line.children > 0 and nextWidth > availableWidth then
            lines[#lines + 1] = line
            line = { children = {}, width = 0, height = 0 }
            nextWidth = childWidth
        end
        line.children[#line.children + 1] = child
        line.width = nextWidth
        line.height = math.max(line.height, child.measuredHeight)
    end
    if #line.children > 0 then lines[#lines + 1] = line end
    return lines
end

local function measure(node, maxWidth, maxHeight, host)
    maxWidth = math.max(0, maxWidth or math.huge)
    maxHeight = math.max(0, maxHeight or math.huge)
    local pad = padding(node.props.padding)
    node._padding = pad
    local width, height = explicit(node, maxWidth, maxHeight)
    local innerMaxWidth = math.max(0, (width or maxWidth) - pad.left - pad.right)
    local innerMaxHeight = math.max(0, (height or maxHeight) - pad.top - pad.bottom)
    local naturalWidth, naturalHeight = 0, 0

    if node.type == "Modal" and not node._portalLayout then
        naturalWidth, naturalHeight = 0, 0
    elseif node.type == "Text" then
        naturalWidth, naturalHeight = textSize(node, innerMaxWidth, innerMaxHeight, host)
    elseif node.type == "Image" or node.type == "Icon" then
        naturalWidth, naturalHeight = imageSize(node, host)
    elseif node.type == "Row" or node.type == "Column" then
        local gap = node.props.gap or 0
        assert(type(gap) == "number" and gap >= 0, "gap must be non-negative")
        local main, cross = 0, 0
        for index, child in ipairs(node.children) do
            measure(child, innerMaxWidth, innerMaxHeight, host)
            local childMain = node.type == "Row" and child.measuredWidth or child.measuredHeight
            local childCross = node.type == "Row" and child.measuredHeight or child.measuredWidth
            if index > 1 then main = main + gap end
            main = main + childMain
            cross = math.max(cross, childCross)
        end
        if node.type == "Row" and node.props.wrap then
            local lines = wrappedLines(node, innerMaxWidth)
            naturalWidth, naturalHeight = 0, 0
            for index, line in ipairs(lines) do
                naturalWidth = math.max(naturalWidth, line.width)
                if index > 1 then naturalHeight = naturalHeight + gap end
                naturalHeight = naturalHeight + line.height
            end
        elseif node.type == "Row" then
            naturalWidth, naturalHeight = main, cross
        else
            naturalWidth, naturalHeight = cross, main
        end
    elseif node.type == "Overlay" then
        for _, child in ipairs(node.children) do
            measure(child, innerMaxWidth, innerMaxHeight, host)
            naturalWidth = math.max(naturalWidth, child.measuredWidth)
            naturalHeight = math.max(naturalHeight, child.measuredHeight)
        end
    elseif node.type == "Scroll" then
        local child = node.children[1]
        if child then
            local childMaxWidth = node.props.axis == "horizontal"
                and math.huge or innerMaxWidth
            local childMaxHeight = node.props.axis == "vertical"
                and math.huge or innerMaxHeight
            measure(child, childMaxWidth, childMaxHeight, host)
            naturalWidth, naturalHeight = child.measuredWidth, child.measuredHeight
        end
    else -- Box, Button, Pressable, DragSource, and DropTarget
        local child = node.children[1]
        if child then
            measure(child, innerMaxWidth, innerMaxHeight, host)
            naturalWidth, naturalHeight = child.measuredWidth, child.measuredHeight
        end
    end

    width = width or naturalWidth + pad.left + pad.right
    height = height or naturalHeight + pad.top + pad.bottom
    node.measuredWidth = clamp(width, 0, maxWidth)
    node.measuredHeight = clamp(height, 0, maxHeight)
    return node.measuredWidth, node.measuredHeight
end

local function alignedStart(align, start, available, size)
    if align == "center" then return start + (available - size) / 2 end
    if align == "end" then return start + available - size end
    return start
end

local function arrangeWrappedRow(node, host)
    local gap = node.props.gap or 0
    for _, child in ipairs(node.children) do
        measure(child, node.contentWidth, node.contentHeight, host)
    end
    local lines = wrappedLines(node, node.contentWidth)
    local y = node.contentY
    for _, line in ipairs(lines) do
        local fixed, totalGrow = 0, 0
        for _, child in ipairs(line.children) do
            local grow = child.props.grow or 0
            if grow > 0 then totalGrow = totalGrow + grow
            else fixed = fixed + child.measuredWidth end
        end
        local gapTotal = math.max(0, #line.children - 1) * gap
        local remaining = math.max(0, node.contentWidth - fixed - gapTotal)
        local used = fixed + gapTotal + (totalGrow > 0 and remaining or 0)
        local spare = math.max(0, node.contentWidth - used)
        local justify = node.props.justify or "start"
        local offset, actualGap = 0, gap
        if totalGrow == 0 then
            if justify == "center" then offset = spare / 2
            elseif justify == "end" then offset = spare
            elseif justify == "space-between" and #line.children > 1 then
                actualGap = gap + spare / (#line.children - 1)
            end
        end
        local x = node.contentX + offset
        local allocations = {}
        local arrangedHeight = 0
        for index, child in ipairs(line.children) do
            local grow = child.props.grow or 0
            local width = grow > 0 and remaining * grow / totalGrow
                or child.measuredWidth
            measure(child, width, node.contentHeight, host)
            allocations[index] = width
            arrangedHeight = math.max(arrangedHeight, child.measuredHeight)
        end
        line.height = arrangedHeight
        for index, child in ipairs(line.children) do
            local width = allocations[index]
            local height = child.measuredHeight
            local align = node.props.align or "stretch"
            if align == "stretch" and child.props.height == nil then
                height = line.height
            end
            local childY = alignedStart(align, y, line.height, height)
            layout.arrange(child, x, childY, width, height, host)
            x = x + width + actualGap
        end
        y = y + line.height + gap
    end
end

local function arrangeFlow(node, horizontal, host)
    local children = node.children
    local gap = node.props.gap or 0
    local contentMain = horizontal and node.contentWidth or node.contentHeight
    local contentCross = horizontal and node.contentHeight or node.contentWidth
    local fixed, totalGrow = 0, 0
    for _, child in ipairs(children) do
        if horizontal then measure(child, contentMain, contentCross, host)
        else measure(child, contentCross, contentMain, host) end
        local grow = child.props.grow or 0
        assert(type(grow) == "number" and grow >= 0, "grow must be non-negative")
        if grow > 0 then totalGrow = totalGrow + grow
        else fixed = fixed + (horizontal and child.measuredWidth or child.measuredHeight) end
    end
    local gapTotal = math.max(0, #children - 1) * gap
    local remaining = math.max(0, contentMain - fixed - gapTotal)
    local used = fixed + gapTotal + (totalGrow > 0 and remaining or 0)
    local justify = node.props.justify or "start"
    local offset, actualGap = 0, gap
    if totalGrow == 0 then
        local spare = math.max(0, contentMain - used)
        if justify == "center" then offset = spare / 2
        elseif justify == "end" then offset = spare
        elseif justify == "space-between" and #children > 1 then
            actualGap = gap + spare / (#children - 1)
        end
    end

    local cursor = (horizontal and node.contentX or node.contentY) + offset
    for _, child in ipairs(children) do
        local grow = child.props.grow or 0
        local main = grow > 0 and remaining * grow / totalGrow
            or (horizontal and child.measuredWidth or child.measuredHeight)
        if horizontal then measure(child, main, contentCross, host)
        else measure(child, contentCross, main, host) end
        local cross = horizontal and child.measuredHeight or child.measuredWidth
        local align = node.props.align or "stretch"
        if align == "stretch" and (horizontal and child.props.height == nil
                or not horizontal and child.props.width == nil) then
            cross = contentCross
        end
        local crossStart = alignedStart(align,
            horizontal and node.contentY or node.contentX, contentCross, cross)
        if horizontal then
            layout.arrange(child, cursor, crossStart, main, cross, host)
        else
            layout.arrange(child, crossStart, cursor, cross, main, host)
        end
        cursor = cursor + main + actualGap
    end
end

local function childBox(node, child, host)
    measure(child, node.contentWidth, node.contentHeight, host)
    local width = resolveSize(child.props.width, node.contentWidth) or child.measuredWidth
    local height = resolveSize(child.props.height, node.contentHeight) or child.measuredHeight
    local align = node.props.align
    local justify = node.props.justify
    if node.type == "Overlay" then
        align, justify = align or "stretch", justify or "stretch"
    elseif node.type == "Modal" then
        align, justify = align or "center", justify or "center"
    elseif node.type == "Button" then
        align, justify = align or "center", justify or "center"
    else
        align, justify = align or "stretch", justify or "stretch"
    end
    if align == "stretch" and child.props.width == nil then width = node.contentWidth end
    if justify == "stretch" and child.props.height == nil then height = node.contentHeight end
    local x = alignedStart(align, node.contentX, node.contentWidth, width)
    local y = alignedStart(justify, node.contentY, node.contentHeight, height)
    layout.arrange(child, x, y, width, height, host)
end

-- Repositions one retained Scroll child after layout, wheel input, or
-- momentum without asking application components to rerender.
function layout.arrangeScroll(node, host)
    local child = node.children[1]
    local scroll = node._scroll
    if not child or not scroll then return end
    local vertical = scroll.axis == "vertical"
    if vertical then
        assert(type(child.props.height) ~= "string",
            "vertical Scroll child height must be naturally measured")
        measure(child, node.contentWidth, math.huge, host)
        local width = resolveSize(child.props.width, node.contentWidth)
            or math.max(node.contentWidth, child.measuredWidth)
        local height = child.measuredHeight
        scroll.viewport, scroll.content = node.contentHeight, height
        scroll.extent = math.max(0, height - node.contentHeight)
        scroll.offset = clamp(scroll.offset or 0, 0, scroll.extent)
        layout.arrange(child, node.contentX, node.contentY - scroll.offset,
            width, height, host)
    else
        assert(type(child.props.width) ~= "string",
            "horizontal Scroll child width must be naturally measured")
        measure(child, math.huge, node.contentHeight, host)
        local width = child.measuredWidth
        local height = resolveSize(child.props.height, node.contentHeight)
            or math.max(node.contentHeight, child.measuredHeight)
        scroll.viewport, scroll.content = node.contentWidth, width
        scroll.extent = math.max(0, width - node.contentWidth)
        scroll.offset = clamp(scroll.offset or 0, 0, scroll.extent)
        layout.arrange(child, node.contentX - scroll.offset, node.contentY,
            width, height, host)
    end
    scroll.node = node
end

function layout.arrange(node, x, y, width, height, host)
    local offset = node.props.offset
    if offset then
        x = x + (offset.x or 0)
        y = y + (offset.y or 0)
    end
    node.x, node.y = x, y
    node.width, node.height = math.max(0, width), math.max(0, height)
    local pad = node._padding or padding(node.props.padding)
    node.contentX = x + pad.left
    node.contentY = y + pad.top
    node.contentWidth = math.max(0, width - pad.left - pad.right)
    node.contentHeight = math.max(0, height - pad.top - pad.bottom)

    if node.type == "Modal" and not node._portalLayout then return end

    if node.type == "Row" and node.props.wrap then
        arrangeWrappedRow(node, host)
    elseif node.type == "Row" then
        arrangeFlow(node, true, host)
    elseif node.type == "Column" then
        arrangeFlow(node, false, host)
    elseif node.type == "Overlay" then
        for _, child in ipairs(node.children) do childBox(node, child, host) end
    elseif node.type == "Scroll" then
        layout.arrangeScroll(node, host)
    elseif node.children[1] then
        childBox(node, node.children[1], host)
    end
end

local function arrangePortal(node, width, height, host)
    node._portal, node._portalLayout = true, true
    node._padding = padding(node.props.padding)
    layout.arrange(node, 0, 0, width, height, host)
    node._portalLayout = nil
end

local function prepareDetached(node, maxWidth, maxHeight, host)
    measure(node, maxWidth, maxHeight, host)
    local width = resolveSize(node.props.width, maxWidth) or node.measuredWidth
    local height = resolveSize(node.props.height, maxHeight) or node.measuredHeight
    layout.arrange(node, 0, 0, width, height, host)
    for _, child in ipairs(node.children or {}) do
        if child._dragPreview then
            prepareDetached(child._dragPreview, maxWidth, maxHeight, host)
        end
    end
end

local function preparePlanes(node, width, height, host)
    if node.type == "Modal" then arrangePortal(node, width, height, host) end
    if node._dragPreview then
        prepareDetached(node._dragPreview, width, height, host)
    end
    for _, child in ipairs(node.children or {}) do
        preparePlanes(child, width, height, host)
    end
end

function layout.run(root, width, height, host)
    measure(root, width, height, host)
    local arrangedWidth = resolveSize(root.props.width, width) or width
    local arrangedHeight = resolveSize(root.props.height, height) or height
    layout.arrange(root, 0, 0, arrangedWidth, arrangedHeight, host)
    preparePlanes(root, width, height, host)
    return root
end

return layout
