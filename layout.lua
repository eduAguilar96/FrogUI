-- Pure two-pass measurement and arrangement for resolved FrogUI primitives.
-- It owns box allocation only; components and input remain Host concerns.

local layout = {}

-- Default padding is read-only layout data. Fresh candidate nodes may share
-- this private record because no layout path mutates normalized padding.
local ZERO_PADDING = { left = 0, right = 0, top = 0, bottom = 0 }

local function recordAllocation(probe, callsField, kbField, before, created)
    local after = collectgarbage("count")
    if created then probe[callsField] = probe[callsField] + created end
    probe[kbField] = probe[kbField] + after - before
end

local function recordTextHelper(probe, callsField, kbField, before)
    local allocatedKB = collectgarbage("count") - before
    probe.pipelineLayoutTextHelperCreated =
        probe.pipelineLayoutTextHelperCreated + 1
    probe.pipelineLayoutTextHelperAllocatedKB =
        probe.pipelineLayoutTextHelperAllocatedKB + allocatedKB
    probe[callsField] = probe[callsField] + 1
    probe[kbField] = probe[kbField] + allocatedKB
end

local function sessionProbe(session)
    return session and session._allocationProbe or nil
end

local function recordPaddingAllocation(probe, before, kind)
    local allocatedKB = collectgarbage("count") - before
    probe.pipelineLayoutPaddingCreated =
        probe.pipelineLayoutPaddingCreated + 1
    probe.pipelineLayoutPaddingAllocatedKB =
        probe.pipelineLayoutPaddingAllocatedKB + allocatedKB
    if kind == "zero" then
        probe.pipelineLayoutZeroPaddingCreated =
            probe.pipelineLayoutZeroPaddingCreated + 1
        probe.pipelineLayoutZeroPaddingAllocatedKB =
            probe.pipelineLayoutZeroPaddingAllocatedKB + allocatedKB
    elseif kind == "uniform" then
        probe.pipelineLayoutUniformPaddingCreated =
            probe.pipelineLayoutUniformPaddingCreated + 1
        probe.pipelineLayoutUniformPaddingAllocatedKB =
            probe.pipelineLayoutUniformPaddingAllocatedKB + allocatedKB
    else
        probe.pipelineLayoutSidedPaddingCreated =
            probe.pipelineLayoutSidedPaddingCreated + 1
        probe.pipelineLayoutSidedPaddingAllocatedKB =
            probe.pipelineLayoutSidedPaddingAllocatedKB + allocatedKB
    end
end

local function clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

local function resolveSize(value, available, probe)
    if not probe then
        if type(value) == "number" then return math.max(0, value) end
        if type(value) == "string" then
            local number = value:match("^([%d%.]+)%%$")
            assert(number, "FrogUI size must be a number or percentage")
            return math.max(0, available * tonumber(number) / 100)
        end
        assert(value == nil,
            "FrogUI size must be a number, percentage, or nil")
        return nil
    end
    if type(value) == "number" then
        probe.pipelineLayoutSizeNumberCalls =
            probe.pipelineLayoutSizeNumberCalls + 1
        return math.max(0, value)
    end
    if type(value) == "string" then
        local before = collectgarbage("count")
        local number = value:match("^([%d%.]+)%%$")
        assert(number, "FrogUI size must be a number or percentage")
        local result = math.max(0, available * tonumber(number) / 100)
        probe.pipelineLayoutSizePercentCalls =
            probe.pipelineLayoutSizePercentCalls + 1
        probe.pipelineLayoutSizePercentAllocatedKB =
            probe.pipelineLayoutSizePercentAllocatedKB
                + collectgarbage("count") - before
        return result
    end
    assert(value == nil, "FrogUI size must be a number, percentage, or nil")
    probe.pipelineLayoutSizeNilCalls =
        probe.pipelineLayoutSizeNilCalls + 1
    return nil
end

local function padding(value, probe)
    if value == nil or value == 0 then
        if probe then
            probe.pipelineLayoutPaddingNormalizations =
                probe.pipelineLayoutPaddingNormalizations + 1
            probe.pipelineLayoutZeroPaddingAliases =
                probe.pipelineLayoutZeroPaddingAliases + 1
        end
        return ZERO_PADDING
    end
    local before = probe and collectgarbage("count") or nil
    local kind = type(value) == "number" and "uniform" or "sided"
    if type(value) == "number" then
        local result = {
            left = value, right = value, top = value, bottom = value,
        }
        if probe then
            probe.pipelineLayoutPaddingNormalizations =
                probe.pipelineLayoutPaddingNormalizations + 1
            recordPaddingAllocation(probe, before, kind)
        end
        return result
    end
    assert(type(value) == "table", "padding must be a number or side table")
    local result = {
        left = value.left or 0,
        right = value.right or 0,
        top = value.top or 0,
        bottom = value.bottom or 0,
    }
    if probe then
        probe.pipelineLayoutPaddingNormalizations =
            probe.pipelineLayoutPaddingNormalizations + 1
        recordPaddingAllocation(probe, before, kind)
    end
    return result
end

-- Resolves authored padding once for one fresh candidate node. Measurement
-- constraints may change within a pass; padding cannot, so later measurement
-- and arrangement entries reuse the exact normalized record.
local function nodePadding(node, probe)
    if node._padding then
        if probe then
            probe.pipelineLayoutPaddingReuseHits =
                probe.pipelineLayoutPaddingReuseHits + 1
        end
        return node._padding
    end
    local result = padding(node.props.padding, probe)
    node._padding = result
    return result
end

local function explicit(node, maxWidth, maxHeight, probe)
    return resolveSize(node.props.width, maxWidth, probe),
        resolveSize(node.props.height, maxHeight, probe)
end

-- Production text measurement stays free of allocation-probe branches. The
-- instrumented twin below runs only inside the exclusive Battle harness.
local function textSizeFast(node, maxWidth, maxHeight, host)
    local text = tostring(node.props.text or "")
    local size = host:_fontSize(node.props.role) * (node.props.fontScale or 1)
    local minimum = (host.theme.fontSizes or {}).minimum or 8
    local font, width, height, lineCount
    local function measureAt(candidateSize)
        local candidateFont = host:_font(node.props.role, candidateSize)
        local candidateWidth, candidateHeight, lines
        if candidateFont and candidateFont.getWidth
                and candidateFont.getHeight then
            candidateWidth, candidateHeight = candidateFont:getWidth(text),
                candidateFont:getHeight()
            lines = 1
            if node.props.wrap and maxWidth < math.huge
                    and candidateFont.getWrap then
                local wrappedWidth, wrappedLines = candidateFont:getWrap(text,
                    math.max(1, maxWidth))
                candidateWidth = math.min(maxWidth, wrappedWidth)
                lines = math.max(1, #wrappedLines)
                candidateHeight = candidateHeight * lines
            end
        else
            candidateWidth, candidateHeight = #text * candidateSize * 0.55,
                candidateSize * 1.2
            lines = 1
            if node.props.wrap and maxWidth < math.huge
                    and candidateWidth > maxWidth then
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
        local lineHeight = font and font.getHeight and font:getHeight()
            or size * 1.2
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
        local lineHeight = font and font.getHeight and font:getHeight()
            or size * 1.2
        height = math.min(height, lineHeight * node.props.maxLines)
    end
    return width, height
end

local function textSize(node, maxWidth, maxHeight, host, probe)
    if not probe then
        return textSizeFast(node, maxWidth, maxHeight, host)
    end
    local setupBefore = collectgarbage("count")
    local text = tostring(node.props.text or "")
    local size = host:_fontSize(node.props.role) * (node.props.fontScale or 1)
    local minimum = (host.theme.fontSizes or {}).minimum or 8
    local font, width, height, lineCount
    recordAllocation(probe, "pipelineLayoutTextSetupCalls",
        "pipelineLayoutTextSetupAllocatedKB", setupBefore, 1)
    local helperBefore = collectgarbage("count")
    local function measureAt(candidateSize)
        local before = probe and collectgarbage("count") or nil
        local candidateFont = host:_font(node.props.role, candidateSize)
        if probe then
            recordAllocation(probe, "pipelineLayoutTextFontCalls",
                "pipelineLayoutTextFontAllocatedKB", before, 1)
        end
        local candidateWidth, candidateHeight, lines
        if candidateFont and candidateFont.getWidth and candidateFont.getHeight then
            before = probe and collectgarbage("count") or nil
            candidateWidth, candidateHeight = candidateFont:getWidth(text),
                candidateFont:getHeight()
            if probe then
                recordAllocation(probe, "pipelineLayoutTextMetricCalls",
                    "pipelineLayoutTextMetricAllocatedKB", before, 1)
            end
            lines = 1
            if node.props.wrap and maxWidth < math.huge and candidateFont.getWrap then
                before = probe and collectgarbage("count") or nil
                local wrappedWidth, wrappedLines = candidateFont:getWrap(text,
                    math.max(1, maxWidth))
                if probe then
                    recordAllocation(probe, "pipelineLayoutTextWrapCalls",
                        "pipelineLayoutTextWrapAllocatedKB", before, 1)
                end
                candidateWidth = math.min(maxWidth, wrappedWidth)
                lines = math.max(1, #wrappedLines)
                candidateHeight = candidateHeight * lines
            end
        else
            before = probe and collectgarbage("count") or nil
            candidateWidth, candidateHeight = #text * candidateSize * 0.55, candidateSize * 1.2
            lines = 1
            if node.props.wrap and maxWidth < math.huge and candidateWidth > maxWidth then
                lines = math.ceil(candidateWidth / math.max(1, maxWidth))
                candidateHeight = candidateHeight * lines
                candidateWidth = maxWidth
            end
            if probe then
                recordAllocation(probe, "pipelineLayoutTextFallbackCalls",
                    "pipelineLayoutTextFallbackAllocatedKB", before, 1)
            end
        end
        return candidateFont, candidateWidth, candidateHeight, lines
    end
    recordTextHelper(probe, "pipelineLayoutTextMeasureHelperCreated",
        "pipelineLayoutTextMeasureHelperAllocatedKB", helperBefore)
    font, width, height, lineCount = measureAt(size)
    helperBefore = collectgarbage("count")
    local function visibleHeight()
        if not node.props.maxLines then return height end
        local lineHeight
        if font and font.getHeight then
            local before = probe and collectgarbage("count") or nil
            lineHeight = font:getHeight()
            if probe then
                recordAllocation(probe, "pipelineLayoutTextMaxLineCalls",
                    "pipelineLayoutTextMaxLineAllocatedKB", before, 1)
            end
        else
            lineHeight = size * 1.2
        end
        return math.min(height, lineHeight * node.props.maxLines)
    end
    recordTextHelper(probe, "pipelineLayoutTextVisibleHelperCreated",
        "pipelineLayoutTextVisibleHelperAllocatedKB", helperBefore)
    if node.props.fitDown then
        if probe then
            probe.pipelineLayoutTextFitDownCalls =
                probe.pipelineLayoutTextFitDownCalls + 1
        end
        while size > minimum and (width > maxWidth
                or visibleHeight() > maxHeight
                or node.props.maxLines and lineCount > node.props.maxLines) do
            if probe then
                probe.pipelineLayoutTextFitIterations =
                    probe.pipelineLayoutTextFitIterations + 1
            end
            size = size - 1
            font, width, height, lineCount = measureAt(size)
        end
    end
    node._resolvedFont = font
    node._resolvedFontSize = size
    if node.props.maxLines then
        local lineHeight
        if font and font.getHeight then
            local before = probe and collectgarbage("count") or nil
            lineHeight = font:getHeight()
            if probe then
                recordAllocation(probe, "pipelineLayoutTextMaxLineCalls",
                    "pipelineLayoutTextMaxLineAllocatedKB", before, 1)
            end
        else
            lineHeight = size * 1.2
        end
        height = math.min(height, lineHeight * node.props.maxLines)
    end
    return width, height
end

local function imageSize(node, host)
    local rect = node.props.sourceRect
    if rect then return rect.width, rect.height end
    local image = host:_asset(node.props.source)
    if image and image.getWidth and image.getHeight then
        if node.type == "SpriteSheet" then
            return image:getWidth() / node.props.frameCount, image:getHeight()
        end
        return image:getWidth(), image:getHeight()
    end
    return 48, 48
end

local function wrappedLines(node, availableWidth, probe)
    local before = probe and collectgarbage("count") or nil
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
    if probe then
        recordAllocation(probe, "pipelineLayoutWrappedLinesCalls",
            "pipelineLayoutWrappedLinesAllocatedKB", before, 1)
    end
    return lines
end

local function measure(node, maxWidth, maxHeight, host, session)
    local allocationProbe = sessionProbe(session)
    if allocationProbe then
        allocationProbe.pipelineLayoutMeasureNodes =
            allocationProbe.pipelineLayoutMeasureNodes + 1
    end
    maxWidth = math.max(0, maxWidth or math.huge)
    maxHeight = math.max(0, maxHeight or math.huge)
    if session and node._measureSession == session
            and node._measureMaxWidth == maxWidth
            and node._measureMaxHeight == maxHeight
            and node._measurePortalLayout == (node._portalLayout == true) then
        -- The immediately preceding completed measurement left its padding,
        -- resolved font/axes, and dimensions on this fresh candidate node.
        if allocationProbe then
            allocationProbe.pipelineLayoutMeasureReuseHits =
                allocationProbe.pipelineLayoutMeasureReuseHits + 1
        end
        return node.measuredWidth, node.measuredHeight
    end
    local pad = nodePadding(node, allocationProbe)
    local width, height = explicit(node, maxWidth, maxHeight, allocationProbe)
    local innerMaxWidth = math.max(0, (width or maxWidth) - pad.left - pad.right)
    local innerMaxHeight = math.max(0, (height or maxHeight) - pad.top - pad.bottom)
    local naturalWidth, naturalHeight = 0, 0

    if (node.type == "Modal" or node.type == "Chrome")
            and not node._portalLayout then
        naturalWidth, naturalHeight = 0, 0
    elseif node.type == "Text" or node.type == "PopupText" then
        local before = allocationProbe and collectgarbage("count") or nil
        naturalWidth, naturalHeight = textSize(node, innerMaxWidth,
            innerMaxHeight, host, allocationProbe)
        if allocationProbe then
            recordAllocation(allocationProbe, "pipelineLayoutTextCalls",
                "pipelineLayoutTextAllocatedKB", before, 1)
        end
    elseif node.type == "Image" or node.type == "SpriteSheet"
            or node.type == "TiledImage"
            or node.type == "Icon" then
        local before = allocationProbe and collectgarbage("count") or nil
        naturalWidth, naturalHeight = imageSize(node, host)
        if allocationProbe then
            recordAllocation(allocationProbe, "pipelineLayoutImageCalls",
                "pipelineLayoutImageAllocatedKB", before, 1)
        end
    elseif node.type == "Canvas" then
        -- Canvas is explicit-size; drawing cannot participate in measurement.
        naturalWidth, naturalHeight = 0, 0
    elseif node.type == "Row" or node.type == "Column" then
        local gap = node.props.gap or 0
        assert(type(gap) == "number" and gap >= 0, "gap must be non-negative")
        local main, cross = 0, 0
        for index, child in ipairs(node.children) do
            measure(child, innerMaxWidth, innerMaxHeight, host, session)
            local childMain = node.type == "Row" and child.measuredWidth or child.measuredHeight
            local childCross = node.type == "Row" and child.measuredHeight or child.measuredWidth
            if index > 1 then main = main + gap end
            main = main + childMain
            cross = math.max(cross, childCross)
        end
        if node.type == "Row" and node.props.wrap then
            local lines = wrappedLines(node, innerMaxWidth, allocationProbe)
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
            measure(child, innerMaxWidth, innerMaxHeight, host, session)
            naturalWidth = math.max(naturalWidth, child.measuredWidth)
            naturalHeight = math.max(naturalHeight, child.measuredHeight)
        end
    elseif node.type == "EffectLayer" then
        for _, child in ipairs(node.children) do
            if child.type == "PopupText" then
                measure(child, innerMaxWidth, innerMaxHeight, host, session)
                local at = child.props.at
                naturalWidth = math.max(naturalWidth,
                    at.x + child.measuredWidth / 2)
                naturalHeight = math.max(naturalHeight,
                    at.y + child.measuredHeight / 2)
            end
        end
    elseif node.type == "RadialDial" then
        local largestWidth, largestHeight = 0, 0
        for _, child in ipairs(node.children) do
            measure(child, innerMaxWidth, innerMaxHeight, host, session)
            largestWidth = math.max(largestWidth, child.measuredWidth)
            largestHeight = math.max(largestHeight, child.measuredHeight)
        end
        local radius = node.props.trackRadius
            or math.max(largestWidth, largestHeight)
        naturalWidth = radius * 2 + largestWidth
        naturalHeight = radius * 2 + largestHeight
    elseif node.type == "Scroll" then
        local child = node.children[1]
        if child then
            local childMaxWidth = node.props.axis == "horizontal"
                and math.huge or innerMaxWidth
            local childMaxHeight = node.props.axis == "vertical"
                and math.huge or innerMaxHeight
            measure(child, childMaxWidth, childMaxHeight, host, session)
            naturalWidth, naturalHeight = child.measuredWidth, child.measuredHeight
        end
    else -- One-child wrappers: Box, Button, Pressable, HorizontalSwipe,
         -- DragSource, and DropTarget.
        local child = node.children[1]
        if child then
            measure(child, innerMaxWidth, innerMaxHeight, host, session)
            naturalWidth, naturalHeight = child.measuredWidth, child.measuredHeight
        end
    end

    local derivedWidth, derivedHeight = false, false
    if node.type == "SpriteSheet" and naturalWidth > 0 and naturalHeight > 0 then
        if width ~= nil and height == nil then
            local contentWidth = math.max(0, width - pad.left - pad.right)
            height = contentWidth * naturalHeight / naturalWidth
                + pad.top + pad.bottom
            derivedHeight = true
        elseif height ~= nil and width == nil then
            local contentHeight = math.max(0, height - pad.top - pad.bottom)
            width = contentHeight * naturalWidth / naturalHeight
                + pad.left + pad.right
            derivedWidth = true
        end
    end
    width = width or naturalWidth + pad.left + pad.right
    height = height or naturalHeight + pad.top + pad.bottom
    -- A derived SpriteSheet axis is the implicit authored partner of the
    -- explicit axis. Preserve it like childBox preserves an explicit size, so
    -- a centered overflow-visible figure cannot be silently distorted by its
    -- parent's measurement ceiling.
    node._derivedWidth = derivedWidth and width or nil
    node._derivedHeight = derivedHeight and height or nil
    node.measuredWidth = node._derivedWidth or clamp(width, 0, maxWidth)
    node.measuredHeight = node._derivedHeight or clamp(height, 0, maxHeight)
    if session then
        node._measureSession = session
        node._measureMaxWidth = maxWidth
        node._measureMaxHeight = maxHeight
        node._measurePortalLayout = node._portalLayout == true
    end
    return node.measuredWidth, node.measuredHeight
end

-- Places every keyed dial option around the Host-owned visual angle. Children
-- move along the track but keep their own upright paint orientation.
local function arrangeRadialDial(node, host, session)
    local allocationProbe = sessionProbe(session)
    local dial = assert(node._radialDial, "unprepared Frog.RadialDial")
    local centerX = node.contentX + node.contentWidth / 2
    local centerY = node.contentY + node.contentHeight / 2
    local maximum = math.min(node.width, node.height) / 2
    local before = allocationProbe and collectgarbage("count") or nil
    local measured = {}
    if allocationProbe then
        recordAllocation(allocationProbe,
            "pipelineLayoutRadialScratchCreated",
            "pipelineLayoutRadialScratchAllocatedKB", before, 1)
    end
    local largestHalfDiagonal = 0
    for index, child in ipairs(node.children) do
        measure(child, node.contentWidth, node.contentHeight, host, session)
        local width = resolveSize(child.props.width, node.contentWidth,
            allocationProbe)
            or child.measuredWidth
        local height = resolveSize(child.props.height, node.contentHeight,
            allocationProbe)
            or child.measuredHeight
        before = allocationProbe and collectgarbage("count") or nil
        measured[index] = { width = width, height = height }
        if allocationProbe then
            recordAllocation(allocationProbe,
                "pipelineLayoutRadialScratchCreated",
                "pipelineLayoutRadialScratchAllocatedKB", before, 1)
        end
        largestHalfDiagonal = math.max(largestHalfDiagonal,
            math.sqrt((width / 2) ^ 2 + (height / 2) ^ 2))
    end
    local trackRadius = node.props.trackRadius
        or math.max(0, math.min(node.contentWidth, node.contentHeight) / 2
            - largestHalfDiagonal)
    local containedMaximum = math.min(
        maximum,
        math.min(node.contentWidth, node.contentHeight) / 2
            - largestHalfDiagonal)
    assert(trackRadius > 0 and trackRadius <= containedMaximum,
        "RadialDial trackRadius must keep every option child inside the"
            .. " arranged circular surface")
    dial.trackRadius = trackRadius
    before = allocationProbe and collectgarbage("count") or nil
    local geometry = { string.format("%.17g", trackRadius) }
    for index, size in ipairs(measured) do
        geometry[#geometry + 1] = type(node.children[index].key)
            .. ":" .. tostring(node.children[index].key)
        geometry[#geometry + 1] = string.format("%.17g", size.width)
        geometry[#geometry + 1] = string.format("%.17g", size.height)
    end
    dial.geometrySignature = table.concat(geometry, ":")
    if allocationProbe then
        recordAllocation(allocationProbe,
            "pipelineLayoutRadialScratchCreated",
            "pipelineLayoutRadialScratchAllocatedKB", before, 1)
    end
    local angle = dial.previewAngle or dial.angle
    local step = math.pi * 2 / #node.children
    for index, child in ipairs(node.children) do
        local childAngle = angle + (index - 1) * step - math.pi / 2
        local size = measured[index]
        layout.arrange(child,
            centerX + math.cos(childAngle) * trackRadius - size.width / 2,
            centerY + math.sin(childAngle) * trackRadius - size.height / 2,
            size.width, size.height, host, session)
    end
end

-- Retained dial motion is outside candidate reconciliation and never receives
-- a measurement session.
function layout.arrangeRadialDial(node, host)
    return arrangeRadialDial(node, host, nil)
end

local function alignedStart(align, start, available, size)
    if align == "center" then return start + (available - size) / 2 end
    if align == "end" then return start + available - size end
    return start
end

local function arrangeWrappedRow(node, host, session)
    local allocationProbe = sessionProbe(session)
    local gap = node.props.gap or 0
    for _, child in ipairs(node.children) do
        measure(child, node.contentWidth, node.contentHeight, host, session)
    end
    local lines = wrappedLines(node, node.contentWidth, allocationProbe)
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
        local before = allocationProbe and collectgarbage("count") or nil
        local allocations = {}
        if allocationProbe then
            recordAllocation(allocationProbe,
                "pipelineLayoutWrappedAllocationCreated",
                "pipelineLayoutWrappedAllocationAllocatedKB", before, 1)
        end
        local arrangedHeight = 0
        for index, child in ipairs(line.children) do
            local grow = child.props.grow or 0
            local width = grow > 0 and remaining * grow / totalGrow
                or child.measuredWidth
            measure(child, width, node.contentHeight, host, session)
            allocations[index] = width
            arrangedHeight = math.max(arrangedHeight, child.measuredHeight)
        end
        line.height = arrangedHeight
        for index, child in ipairs(line.children) do
            local width = allocations[index]
            local height = child.measuredHeight
            local align = node.props.align or "stretch"
            if align == "stretch" and child.props.height == nil
                    and child._derivedHeight == nil then
                height = line.height
            end
            local childY = alignedStart(align, y, line.height, height)
            layout.arrange(child, x, childY, width, height, host, session)
            x = x + width + actualGap
        end
        y = y + line.height + gap
    end
end

local function arrangeFlow(node, horizontal, host, session)
    local children = node.children
    local gap = node.props.gap or 0
    local contentMain = horizontal and node.contentWidth or node.contentHeight
    local contentCross = horizontal and node.contentHeight or node.contentWidth
    local fixed, totalGrow = 0, 0
    for _, child in ipairs(children) do
        if horizontal then measure(child, contentMain, contentCross, host, session)
        else measure(child, contentCross, contentMain, host, session) end
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
        if horizontal then measure(child, main, contentCross, host, session)
        else measure(child, contentCross, main, host, session) end
        local cross = horizontal and child.measuredHeight or child.measuredWidth
        local align = node.props.align or "stretch"
        if align == "stretch"
                and (horizontal and child.props.height == nil
                    and child._derivedHeight == nil
                or not horizontal and child.props.width == nil
                    and child._derivedWidth == nil) then
            cross = contentCross
        end
        local crossStart = alignedStart(align,
            horizontal and node.contentY or node.contentX, contentCross, cross)
        if horizontal then
            layout.arrange(child, cursor, crossStart, main, cross, host, session)
        else
            layout.arrange(child, crossStart, cursor, cross, main, host, session)
        end
        cursor = cursor + main + actualGap
    end
end

local function childBox(node, child, host, session)
    local allocationProbe = sessionProbe(session)
    measure(child, node.contentWidth, node.contentHeight, host, session)
    local width = resolveSize(child.props.width, node.contentWidth,
        allocationProbe) or child.measuredWidth
    local height = resolveSize(child.props.height, node.contentHeight,
        allocationProbe) or child.measuredHeight
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
    if align == "stretch" and child.props.width == nil
            and child._derivedWidth == nil then
        width = node.contentWidth
    end
    if justify == "stretch" and child.props.height == nil
            and child._derivedHeight == nil then
        height = node.contentHeight
    end
    local x = alignedStart(align, node.contentX, node.contentWidth, width)
    local y = alignedStart(justify, node.contentY, node.contentHeight, height)
    layout.arrange(child, x, y, width, height, host, session)
end

-- Repositions one retained Scroll child after layout, wheel input, or
-- momentum without asking application components to rerender.
local function arrangeScroll(node, host, session)
    local allocationProbe = sessionProbe(session)
    local child = node.children[1]
    local scroll = node._scroll
    if not child or not scroll then return end
    local vertical = scroll.axis == "vertical"
    if vertical then
        assert(type(child.props.height) ~= "string",
            "vertical Scroll child height must be naturally measured")
        measure(child, node.contentWidth, math.huge, host, session)
        local width = resolveSize(child.props.width, node.contentWidth,
            allocationProbe)
            or math.max(node.contentWidth, child.measuredWidth)
        local height = child.measuredHeight
        scroll.viewport, scroll.content = node.contentHeight, height
        scroll.extent = math.max(0, height - node.contentHeight)
        scroll.offset = clamp(scroll.offset or 0, 0, scroll.extent)
        layout.arrange(child, node.contentX, node.contentY - scroll.offset,
            width, height, host, session)
    else
        assert(type(child.props.width) ~= "string",
            "horizontal Scroll child width must be naturally measured")
        measure(child, math.huge, node.contentHeight, host, session)
        local width = child.measuredWidth
        local height = resolveSize(child.props.height, node.contentHeight,
            allocationProbe)
            or math.max(node.contentHeight, child.measuredHeight)
        scroll.viewport, scroll.content = node.contentWidth, width
        scroll.extent = math.max(0, width - node.contentWidth)
        scroll.offset = clamp(scroll.offset or 0, 0, scroll.extent)
        layout.arrange(child, node.contentX - scroll.offset, node.contentY,
            width, height, host, session)
    end
    scroll.node = node
end

-- Retained wheel/touch/momentum movement measures normally; candidate reuse
-- cannot survive into this public arrangement boundary.
function layout.arrangeScroll(node, host)
    return arrangeScroll(node, host, nil)
end

function layout.arrange(node, x, y, width, height, host, session)
    local allocationProbe = sessionProbe(session)
    if allocationProbe then
        allocationProbe.pipelineLayoutArrangeNodes =
            allocationProbe.pipelineLayoutArrangeNodes + 1
    end
    -- Measuring a descendant under its final allocation can change state that
    -- contributed to this ancestor's natural size. Retire the node's own
    -- last-entry stamp before arranging it; descendant stamps remain eligible
    -- until their own arrange begins. This avoids a dependency graph while
    -- making every exact reuse local to the still-valid traversal prefix.
    node._measureSession = nil
    node._measureMaxWidth = nil
    node._measureMaxHeight = nil
    node._measurePortalLayout = nil
    local offset = node.props.offset
    if offset then
        x = x + (offset.x or 0)
        y = y + (offset.y or 0)
    end
    node.x, node.y = x, y
    node.width, node.height = math.max(0, width), math.max(0, height)
    local pad = nodePadding(node, allocationProbe)
    node.contentX = x + pad.left
    node.contentY = y + pad.top
    node.contentWidth = math.max(0, width - pad.left - pad.right)
    node.contentHeight = math.max(0, height - pad.top - pad.bottom)

    if (node.type == "Modal" or node.type == "Chrome")
            and not node._portalLayout then return end

    if node.type == "Row" and node.props.wrap then
        if allocationProbe then
            allocationProbe.pipelineLayoutWrappedRowNodes =
                allocationProbe.pipelineLayoutWrappedRowNodes + 1
        end
        arrangeWrappedRow(node, host, session)
    elseif node.type == "Row" then
        if allocationProbe then
            allocationProbe.pipelineLayoutFlowNodes =
                allocationProbe.pipelineLayoutFlowNodes + 1
        end
        arrangeFlow(node, true, host, session)
    elseif node.type == "Column" then
        if allocationProbe then
            allocationProbe.pipelineLayoutFlowNodes =
                allocationProbe.pipelineLayoutFlowNodes + 1
        end
        arrangeFlow(node, false, host, session)
    elseif node.type == "Overlay" then
        if allocationProbe then
            allocationProbe.pipelineLayoutOverlayNodes =
                allocationProbe.pipelineLayoutOverlayNodes + 1
        end
        for _, child in ipairs(node.children) do
            childBox(node, child, host, session)
        end
    elseif node.type == "EffectLayer" then
        if allocationProbe then
            allocationProbe.pipelineLayoutEffectLayerNodes =
                allocationProbe.pipelineLayoutEffectLayerNodes + 1
        end
        for _, child in ipairs(node.children) do
            if child.type == "PopupText" then
                measure(child, node.contentWidth, node.contentHeight, host, session)
                local width = resolveSize(child.props.width,
                    node.contentWidth, allocationProbe)
                    or child.measuredWidth
                local height = resolveSize(child.props.height,
                    node.contentHeight, allocationProbe)
                    or child.measuredHeight
                local at = child.props.at
                layout.arrange(child,
                    node.contentX + at.x - width / 2,
                    node.contentY + at.y - height / 2,
                    width, height, host, session)
            elseif child.type == "Canvas" then
                local width = assert(resolveSize(child.props.width,
                    node.contentWidth, allocationProbe),
                    "Canvas needs an explicit EffectLayer width")
                local height = assert(resolveSize(child.props.height,
                    node.contentHeight, allocationProbe),
                    "Canvas needs an explicit EffectLayer height")
                layout.arrange(child, node.contentX, node.contentY,
                    width, height, host, session)
            else
                layout.arrange(child, node.contentX, node.contentY,
                    node.contentWidth, node.contentHeight, host, session)
                local before = allocationProbe
                    and collectgarbage("count") or nil
                child._effectLayerRect = {
                    x = node.contentX,
                    y = node.contentY,
                    width = node.contentWidth,
                    height = node.contentHeight,
                }
                if allocationProbe then
                    recordAllocation(allocationProbe,
                        "pipelineLayoutEffectRectCreated",
                        "pipelineLayoutEffectRectAllocatedKB", before, 1)
                end
            end
        end
    elseif node.type == "RadialDial" then
        if allocationProbe then
            allocationProbe.pipelineLayoutRadialNodes =
                allocationProbe.pipelineLayoutRadialNodes + 1
        end
        arrangeRadialDial(node, host, session)
    elseif node.type == "Scroll" then
        if allocationProbe then
            allocationProbe.pipelineLayoutScrollNodes =
                allocationProbe.pipelineLayoutScrollNodes + 1
        end
        arrangeScroll(node, host, session)
    elseif node.children[1] then
        if allocationProbe then
            allocationProbe.pipelineLayoutWrapperNodes =
                allocationProbe.pipelineLayoutWrapperNodes + 1
        end
        childBox(node, node.children[1], host, session)
    end
end

local function arrangePortal(node, width, height, host, session)
    local allocationProbe = sessionProbe(session)
    if allocationProbe then
        allocationProbe.pipelineLayoutPortalNodes =
            allocationProbe.pipelineLayoutPortalNodes + 1
    end
    node._portal, node._portalLayout = true, true
    nodePadding(node, allocationProbe)
    layout.arrange(node, 0, 0, width, height, host, session)
    node._portalLayout = nil
end

local function prepareDetached(node, maxWidth, maxHeight, host, session)
    local allocationProbe = sessionProbe(session)
    if allocationProbe then
        allocationProbe.pipelineLayoutDetachedNodes =
            allocationProbe.pipelineLayoutDetachedNodes + 1
    end
    measure(node, maxWidth, maxHeight, host, session)
    local width = resolveSize(node.props.width, maxWidth, allocationProbe)
        or node.measuredWidth
    local height = resolveSize(node.props.height, maxHeight, allocationProbe)
        or node.measuredHeight
    layout.arrange(node, 0, 0, width, height, host, session)
    for _, child in ipairs(node.children or {}) do
        if child._dragPreview then
            prepareDetached(child._dragPreview,
                maxWidth, maxHeight, host, session)
        end
    end
end

local function preparePlanes(node, width, height, host, session)
    if node.type == "Modal" or node.type == "Chrome" then
        arrangePortal(node, width, height, host, session)
    end
    if node._dragPreview then
        prepareDetached(node._dragPreview, width, height, host, session)
    end
    for _, child in ipairs(node.children or {}) do
        preparePlanes(child, width, height, host, session)
    end
end

function layout.run(root, width, height, host, allocationProbe)
    -- One opaque token scopes last-entry reuse to this fresh candidate, exact
    -- normalized constraints, and portal mode. Public retained arrangement
    -- supplies no token, so Scroll/RadialDial updates always perform ordinary
    -- measurement and clear any obsolete candidate stamp while arranging.
    local before = allocationProbe and collectgarbage("count") or nil
    local session = { _allocationProbe = allocationProbe }
    if allocationProbe then
        recordAllocation(allocationProbe, "pipelineLayoutSessionCreated",
            "pipelineLayoutSessionAllocatedKB", before, 1)
    end
    before = allocationProbe and collectgarbage("count") or nil
    measure(root, width, height, host, session)
    if allocationProbe then
        recordAllocation(allocationProbe, "pipelineLayoutMeasurePhaseCalls",
            "pipelineLayoutMeasurePhaseAllocatedKB", before, 1)
    end
    local arrangedWidth = resolveSize(root.props.width, width, allocationProbe)
        or width
    local arrangedHeight = resolveSize(root.props.height, height,
        allocationProbe) or height
    before = allocationProbe and collectgarbage("count") or nil
    layout.arrange(root, 0, 0, arrangedWidth, arrangedHeight, host, session)
    if allocationProbe then
        recordAllocation(allocationProbe, "pipelineLayoutArrangePhaseCalls",
            "pipelineLayoutArrangePhaseAllocatedKB", before, 1)
    end
    before = allocationProbe and collectgarbage("count") or nil
    preparePlanes(root, width, height, host, session)
    if allocationProbe then
        recordAllocation(allocationProbe, "pipelineLayoutPlanesPhaseCalls",
            "pipelineLayoutPlanesPhaseAllocatedKB", before, 1)
    end
    return root
end

return layout
