-- Deterministic public-contract checks for nesting, flow allocation and the
-- aspect-derived portrait/wide composition.

local Frog = require("frogui")
local Layout = require("frogui.layout")
local support = require("tests.support")

local check = {}

local function rejects(label, element, fragment)
    local ok, err = pcall(function()
        support.host { width = 100, height = 100 }:mount(element)
    end)
    assert(not ok, label .. " unexpectedly succeeded")
    assert(tostring(err):find(fragment, 1, true),
        label .. " rejected for the wrong reason: " .. tostring(err))
end

-- Switches between Row and Column so the check can prove viewport composition.
local Responsive = Frog.component("LayoutCheckResponsive", function()
    local viewport = Frog.useViewport()
    local Flow = viewport.wide and Frog.Row or Frog.Column
    return Flow {
        testId = "responsive",
        width = 300,
        height = 200,
        gap = 10,
        align = "stretch",
        Frog.Box { key = "a", testId = "responsive-a", grow = 1 },
        Frog.Box { key = "b", testId = "responsive-b", grow = 1 },
    }
end)

-- Throws at one width to prove a failed resize preserves the committed tree.
local ResizeGuard = Frog.component("LayoutCheckResizeGuard", function(props)
    local viewport = Frog.useViewport()
    if viewport.wide then error("intentional wide render refusal") end
    return Frog.Button {
        width = 100,
        height = 44,
        testId = "resize-guard",
        onPress = props.onPress,
        Frog.Text "Stable",
    }
end)

local function nestedLayout()
    local host = support.host { width = 540, height = 960 }
    local tree = support.mount(host, Frog.Column {
        testId = "layout-root",
        padding = 10,
        gap = 5,
        align = "stretch",
        Frog.Box { testId = "fixed", height = 100 },
        Frog.Row {
            testId = "row", height = 40, gap = 10, align = "stretch",
            Frog.Box { testId = "row-fixed", width = 50 },
            Frog.Box { testId = "row-grow", grow = 1 },
        },
        Frog.Overlay {
            testId = "overlay", height = 30,
            Frog.Box { testId = "overlay-back" },
            Frog.Box { testId = "overlay-front", width = 20, height = 10 },
        },
    })
    local root = assert(support.find(tree, "layout-root"))
    local fixed = assert(support.find(tree, "fixed"))
    local row = assert(support.find(tree, "row"))
    local rowFixed = assert(support.find(tree, "row-fixed"))
    local rowGrow = assert(support.find(tree, "row-grow"))
    local overlay = assert(support.find(tree, "overlay"))
    local back = assert(support.find(tree, "overlay-back"))

    support.near(root.layout.width, 540, "root width")
    support.near(root.layout.height, 960, "root height")
    support.near(fixed.layout.x, 10, "nested padding x")
    support.near(fixed.layout.y, 10, "nested padding y")
    support.near(fixed.layout.width, 520, "stretched child width")
    support.near(row.layout.y, 115, "column gap placement")
    support.near(rowFixed.layout.width, 50, "fixed row allocation")
    support.near(rowGrow.layout.width, 460, "growing row allocation")
    support.near(rowGrow.layout.x, rowFixed.layout.x + 60, "row gap placement")
    support.near(overlay.layout.y, 160, "overlay flow placement")
    support.near(back.layout.x, overlay.layout.x, "overlay shared x")
    support.near(back.layout.y, overlay.layout.y, "overlay shared y")
    support.near(back.layout.width, overlay.layout.width, "overlay shared width")
    support.near(back.layout.height, overlay.layout.height, "overlay shared height")
    host:unmount()
end

-- Proves default padding shares one private read-only record while authored
-- padding keeps exact uniform/per-side geometry. An unchanged committed branch
-- may retain the whole immutable layout record across candidates.
local function paddingNormalizationOwnership()
    local function description()
        return Frog.Overlay {
            width = 180,
            height = 80,
            align = "start",
            justify = "start",
            Frog.Row {
                width = 180,
                height = 40,
                align = "start",
                Frog.Box {
                    testId = "padding-default-a",
                    width = 20,
                    height = 20,
                },
                Frog.Box {
                    testId = "padding-default-b",
                    width = 20,
                    height = 20,
                    padding = 0,
                },
                Frog.Box {
                    testId = "padding-uniform",
                    width = 20,
                    height = 20,
                    padding = 3,
                },
                Frog.Box {
                    testId = "padding-sided",
                    width = 20,
                    height = 20,
                    padding = { left = 1, right = 2, top = 3, bottom = 4 },
                },
            },
            Frog.Modal {
                testId = "padding-portal",
                dismiss = "none",
                Frog.Box { width = 10, height = 10 },
            },
        }
    end

    local host = support.host { width = 180, height = 80 }
    local tree = support.mount(host, description())
    local defaultA = assert(support.find(tree, "padding-default-a"))
    local defaultB = assert(support.find(tree, "padding-default-b"))
    local portal = assert(support.find(tree, "padding-portal"))
    local uniform = assert(support.find(tree, "padding-uniform"))
    local sided = assert(support.find(tree, "padding-sided"))
    local sharedZero = defaultA.layout.padding
    local firstUniformLayout = uniform.layout
    local firstSidedLayout = sided.layout
    local firstUniform = uniform.layout.padding
    local firstSided = sided.layout.padding

    assert(sharedZero == defaultB.layout.padding
            and sharedZero == portal.layout.padding
            and sharedZero.left == 0 and sharedZero.right == 0
            and sharedZero.top == 0 and sharedZero.bottom == 0,
        "default padding did not retain one zero record across a portal")
    assert(firstUniform ~= sharedZero and firstSided ~= sharedZero
            and firstUniform.left == 3 and firstUniform.right == 3
            and firstUniform.top == 3 and firstUniform.bottom == 3
            and firstSided.left == 1 and firstSided.right == 2
            and firstSided.top == 3 and firstSided.bottom == 4,
        "authored padding lost private normalized sides")
    support.near(uniform.layout.contentX, uniform.layout.x + 3,
        "uniform padding content x")
    support.near(uniform.layout.contentHeight, 14,
        "uniform padding content height")
    support.near(sided.layout.contentX, sided.layout.x + 1,
        "sided padding content x")
    support.near(sided.layout.contentHeight, 13,
        "sided padding content height")

    tree = support.render(host, description())
    defaultA = assert(support.find(tree, "padding-default-a"))
    uniform = assert(support.find(tree, "padding-uniform"))
    sided = assert(support.find(tree, "padding-sided"))
    assert(defaultA.layout.padding == sharedZero
            and uniform.layout == firstUniformLayout
            and sided.layout == firstSidedLayout
            and uniform.layout.padding == firstUniform
            and sided.layout.padding == firstSided,
        "unchanged branch did not retain its immutable layout result")

    local committed = tree
    local ok = pcall(function()
        host:render(Frog.Column {
            padding = 99,
            Frog.Row { gap = -1 },
        })
    end)
    assert(not ok and host:tree() == committed
            and sharedZero.left == 0 and sharedZero.right == 0
            and sharedZero.top == 0 and sharedZero.bottom == 0,
        "failed candidate changed committed or shared padding")
    host:unmount()
end

local function responsiveLayout()
    local host = support.host { width = 540, height = 960 }
    local tree = support.mount(host, Responsive {})
    local a = assert(support.find(tree, "responsive-a"))
    local b = assert(support.find(tree, "responsive-b"))
    assert(b.layout.y > a.layout.y and b.layout.x == a.layout.x,
        "portrait viewport did not choose Column composition")
    local aIdentity, bIdentity = a.identity, b.identity

    host:resize(960, 540)
    tree = host:tree()
    a = assert(support.find(tree, "responsive-a"))
    b = assert(support.find(tree, "responsive-b"))
    assert(b.layout.x > a.layout.x and b.layout.y == a.layout.y,
        "wide viewport did not choose Row composition")
    assert(a.identity == aIdentity and b.identity == bIdentity,
        "responsive component discarded keyed child identity")
    host:unmount()
end

local function rowWrapLayout()
    local host = support.host { width = 120, height = 50 }
    local tree = support.mount(host, Frog.Row {
        width = 120,
        height = 50,
        gap = 10,
        wrap = true,
        align = "start",
        Frog.Box { testId = "wrap-a", width = 50, height = 20 },
        Frog.Box { testId = "wrap-b", width = 50, height = 20 },
        Frog.Box { testId = "wrap-c", width = 50, height = 20 },
    })
    local a = assert(support.find(tree, "wrap-a"))
    local b = assert(support.find(tree, "wrap-b"))
    local c = assert(support.find(tree, "wrap-c"))
    support.near(a.layout.x, 0, "wrap first x")
    support.near(b.layout.x, 60, "wrap second x")
    support.near(c.layout.x, 0, "wrap next-line x")
    support.near(c.layout.y, 30, "wrap next-line y")
    host:unmount()
end

local function controlledOffsetLayout()
    local host = support.host { width = 200, height = 80 }
    local tree = support.mount(host, Frog.Row {
        width = 200,
        height = 80,
        align = "start",
        Frog.Box { testId = "offset-before", width = 40, height = 40 },
        Frog.Box {
            testId = "offset-owner",
            width = 40,
            height = 40,
            offset = { x = 25, y = 7 },
            Frog.Box { testId = "offset-child", width = 10, height = 10 },
        },
        Frog.Box { testId = "offset-after", width = 40, height = 40 },
    })
    local before = assert(support.find(tree, "offset-before"))
    local owner = assert(support.find(tree, "offset-owner"))
    local child = assert(support.find(tree, "offset-child"))
    local after = assert(support.find(tree, "offset-after"))
    support.near(before.layout.x, 0, "offset preceding flow position")
    support.near(owner.layout.x, 65, "offset committed x")
    support.near(owner.layout.y, 7, "offset committed y")
    support.near(child.layout.x, 65, "offset translated descendant x")
    support.near(child.layout.y, 7, "offset translated descendant y")
    support.near(after.layout.x, 80, "offset did not affect following flow")

    local inspected
    for _, entry in ipairs(host:inspectionTree().nodes) do
        if entry.testId == "offset-owner" then inspected = entry break end
    end
    inspected = assert(inspected, "offset node missing from F6 tree")
    support.near(inspected.bounds.x, owner.layout.x, "offset F6 x")
    support.near(inspected.bounds.y, owner.layout.y, "offset F6 y")
    host:unmount()
end

-- Proves the editor-documented align/justify vocabulary and axis meanings.
local function alignmentVocabulary()
    local host = support.host { width = 100, height = 100 }
    local tree = support.mount(host, Frog.Overlay {
        width = 100,
        height = 100,
        align = "center",
        justify = "center",
        Frog.Button {
            testId = "centered-control",
            width = 20,
            height = 20,
            Frog.Text "X",
        },
    })
    local control = assert(support.find(tree, "centered-control"))
    support.near(control.layout.x, 40, "Overlay center align")
    support.near(control.layout.y, 40, "Overlay center justify")
    host:unmount()

    host = support.host { width = 100, height = 20 }
    tree = support.mount(host, Frog.Row {
        width = 100,
        height = 20,
        justify = "space-between",
        Frog.Box { testId = "spread-left", width = 20, height = 20 },
        Frog.Box { testId = "spread-right", width = 20, height = 20 },
    })
    support.near(assert(support.find(tree, "spread-left")).layout.x, 0,
        "Row space-between start")
    support.near(assert(support.find(tree, "spread-right")).layout.x, 80,
        "Row space-between end")
    host:unmount()
end

local function textLayoutContracts()
    local records = {}
    local painter = {}
    function painter:text(node, value, style)
        records[node.props.testId] = {
            node = node,
            value = value,
            font = style.font,
        }
    end
    local host = support.host {
        width = 200,
        height = 300,
        painter = painter,
        theme = {
            fonts = { body = 28 },
            fontSizes = { minimum = 8 },
        },
    }
    host:mount(Frog.Column {
        width = 200,
        height = 300,
        align = "start",
        gap = 10,
        Frog.Text {
            width = 50,
            height = 16,
            fitDown = true,
            testId = "fit-both",
            "FrogUI",
        },
        Frog.Text {
            width = 60,
            wrap = true,
            maxLines = 2,
            testId = "max-lines",
            "one two three four five six seven eight",
        },
        Frog.Text {
            role = "body",
            fontScale = 1.5,
            testId = "local-font-scale",
            "Emphasis",
        },
    })
    host:draw()
    host:unmount()

    local fitted = assert(records["fit-both"], "fitDown Text was not painted")
    assert(fitted.font and fitted.font.getWidth and fitted.font.getHeight,
        "fitDown Text did not resolve a measurable font")
    assert(fitted.font:getWidth(fitted.value) <= fitted.node.width + 0.001,
        "fitDown did not respect explicit width")
    assert(fitted.font:getHeight() <= fitted.node.height + 0.001,
        "fitDown did not respect explicit height")

    local limited = assert(records["max-lines"], "maxLines Text was not painted")
    local lineHeight = assert(limited.font):getHeight()
    assert(limited.node.height <= lineHeight * 2 + 0.001,
        "maxLines did not cap measured Text height")
    assert(limited.node.height > lineHeight,
        "maxLines story did not exercise wrapped text")

    local scaled = assert(records["local-font-scale"],
        "fontScale Text was not painted")
    support.near(scaled.node._resolvedFontSize, 42,
        "fontScale did not multiply the current semantic role")

    -- Headless tools use the deterministic text fallback when LÖVE cannot
    -- provide a font. Exercise its wrapping, line cap and fit-down directly so
    -- the production and fallback branches cannot drift unnoticed.
    local fallbackHost = {
        theme = { fontSizes = { minimum = 8 } },
    }
    function fallbackHost:_fontSize()
        return 20
    end
    function fallbackHost:_font()
        return nil
    end
    local fallbackWrapped = {
        type = "Text",
        props = {
            text = "abcdefghij",
            wrap = true,
            maxLines = 2,
        },
        children = {},
    }
    Layout.run(fallbackWrapped, 30, 200, fallbackHost)
    support.near(fallbackWrapped.layout.measuredWidth, 30,
        "fallback wrapped Text width")
    support.near(fallbackWrapped.layout.measuredHeight, 48,
        "fallback maxLines height")
    assert(fallbackWrapped.layout.resolvedFont == nil,
        "fallback Text unexpectedly resolved a real font")

    local fallbackFitted = {
        type = "Text",
        props = {
            text = "abcd",
            fitDown = true,
        },
        children = {},
    }
    Layout.run(fallbackFitted, 20, 200, fallbackHost)
    support.near(fallbackFitted.layout.resolvedFontSize, 9,
        "fallback fitDown size")
    assert(fallbackFitted.layout.measuredWidth <= 20,
        "fallback fitDown did not respect available width")

    local allocated
    local allocationPainter = {}
    function allocationPainter:text(node, value, style)
        if node.props.testId == "grow-fit" then
            allocated = { node = node, value = value, font = style.font }
        end
    end
    host = support.host {
        width = 200,
        height = 100,
        painter = allocationPainter,
        theme = {
            fonts = { body = 28 },
            fontSizes = { minimum = 8 },
        },
    }
    host:mount(Frog.Row {
        width = 200,
        height = 100,
        align = "start",
        Frog.Box { width = 150, height = 20 },
        Frog.Text {
            grow = 1,
            fitDown = true,
            testId = "grow-fit",
            "FrogUI",
        },
    })
    host:draw()
    host:unmount()
    allocated = assert(allocated, "grow-allocated fitDown Text was not painted")
    assert(allocated.node.width == 50,
        "grow fitDown story did not receive its narrow allocation")
    assert(assert(allocated.font):getWidth(allocated.value)
            <= allocated.node.width + 0.001,
        "fitDown did not remeasure after grow allocation")
end

local function nestedWrapRemeasure()
    local host = support.host { width = 200, height = 200 }
    local tree = support.mount(host, Frog.Row {
        width = 200,
        height = 200,
        align = "start",
        Frog.Box { width = 150, height = 10 },
        Frog.Box {
            grow = 1,
            testId = "narrow-wrap-owner",
            Frog.Row {
                testId = "narrow-wrap",
                gap = 5,
                wrap = true,
                Frog.Box { testId = "narrow-a", width = 40, height = 20 },
                Frog.Box { testId = "narrow-b", width = 40, height = 20 },
                Frog.Box { testId = "narrow-c", width = 40, height = 20 },
            },
        },
    })
    local owner = assert(support.find(tree, "narrow-wrap-owner"))
    local wrapped = assert(support.find(tree, "narrow-wrap"))
    local third = assert(support.find(tree, "narrow-c"))
    support.near(owner.layout.width, 50, "nested wrap narrow allocation")
    support.near(owner.layout.height, 70, "nested wrap owner remeasured height")
    support.near(wrapped.layout.height, 70, "nested wrapped Row remeasured height")
    support.near(third.layout.y, 50, "nested wrapped third-line y")
    host:unmount()
end

local function countedAsset(width, height)
    local asset = { widthCalls = 0, heightCalls = 0 }
    function asset:getWidth()
        self.widthCalls = self.widthCalls + 1
        return width
    end
    function asset:getHeight()
        self.heightCalls = self.heightCalls + 1
        return height
    end
    return asset
end

-- Counts actual natural-size work, rather than requests. The exact Overlay
-- repeat performs one read; grow performs that read plus one genuinely
-- different allocation constraint.
local function duplicateMeasurementProof()
    local exact = countedAsset(20, 10)
    local host = support.host { width = 100, height = 100 }
    host:mount(Frog.Overlay {
        width = 100,
        height = 100,
        align = "start",
        justify = "start",
        Frog.Image { source = exact, width = 20, height = 10 },
    })
    host:unmount()

    local changed = countedAsset(20, 10)
    host = support.host { width = 100, height = 100 }
    host:mount(Frog.Row {
        width = 100,
        height = 100,
        align = "start",
        Frog.Box { width = 40, height = 10 },
        Frog.Image {
            source = changed,
            grow = 1,
            height = 10,
        },
    })
    host:unmount()
    assert(exact.widthCalls == 1 and exact.heightCalls == 1,
        "exact-constraint repeat re-ran natural image measurement")
    assert(changed.widthCalls == 2 and changed.heightCalls == 2,
        "changed grow constraint incorrectly reused natural image measurement")
end

-- Proves the finished candidate retains no valid session stamp and that the
-- public retained layout entry points never participate in candidate reuse.
local function measurementReuseBoundaries()
    local nestedAsset = countedAsset(20, 10)
    local portalAsset = countedAsset(14, 9)
    local previewAsset = countedAsset(12, 8)
    local host = support.host { width = 160, height = 120 }
    local tree = support.mount(host, Frog.Overlay {
        width = 160,
        height = 120,
        Frog.Box {
            testId = "cache-ancestor",
            width = 80,
            height = 60,
            padding = 5,
            Frog.Image {
                testId = "cache-descendant",
                source = nestedAsset,
                width = 20,
                height = 10,
            },
        },
        Frog.Modal {
            testId = "cache-portal",
            dismiss = "none",
            Frog.Image {
                testId = "cache-portal-child",
                source = portalAsset,
                width = 14,
                height = 9,
            },
        },
        Frog.DragSource {
            testId = "cache-drag-source",
            payload = { kind = "cache-proof" },
            preview = Frog.Image {
                testId = "cache-drag-preview",
                source = previewAsset,
                width = 12,
                height = 8,
            },
            onDrop = function() return true end,
            Frog.Box { width = 30, height = 20 },
        },
    })
    local ancestor = assert(support.find(tree, "cache-ancestor"))
    local descendant = assert(support.find(tree, "cache-descendant"))
    local portalChild = assert(support.find(tree, "cache-portal-child"))
    local source = assert(support.find(tree, "cache-drag-source"))
    local function assertNoStamp(node)
        assert(node.layout.measureSession == nil,
            "arrangement left a stale measurement stamp on "
                .. tostring(node.props.testId or node.type))
        if node._dragPreview then assertNoStamp(node._dragPreview) end
        for _, child in ipairs(node.children or {}) do assertNoStamp(child) end
    end
    assertNoStamp(tree)
    support.near(ancestor.layout.contentWidth, 70,
        "measurement reuse preserved resolved padding")
    support.near(descendant.layout.width, 20,
        "measurement reuse preserved descendant dimensions")
    assert(support.find(tree, "cache-portal")
            and portalChild.layout.width == 14 and portalChild.layout.height == 9
            and portalAsset.widthCalls == 1
            and portalAsset.heightCalls == 1
            and source._dragPreview.layout.width == 12
            and source._dragPreview.layout.height == 8
            and previewAsset.widthCalls == 1
            and previewAsset.heightCalls == 1,
        "portal or detached drag-preview layout bypassed measurement")
    host:unmount()

    local scrollAsset = countedAsset(20, 80)
    host = support.host { width = 100, height = 50 }
    tree = support.mount(host, Frog.Scroll {
        testId = "cache-scroll",
        width = 100,
        height = 50,
        axis = "vertical",
        Frog.Image { source = scrollAsset, width = 20, height = 80 },
    })
    local scroll = assert(support.find(tree, "cache-scroll"))
    local scrollWidthReads = scrollAsset.widthCalls
    local scrollHeightReads = scrollAsset.heightCalls
    Layout.arrangeScroll(scroll, host)
    assert(scrollAsset.widthCalls == scrollWidthReads + 1
            and scrollAsset.heightCalls == scrollHeightReads + 1,
        "public retained Scroll arrangement reused candidate measurement")
    host:unmount()

    local dialAsset = countedAsset(10, 10)
    host = support.host { width = 100, height = 100 }
    tree = support.mount(host, Frog.RadialDial {
        testId = "cache-radial",
        width = 100,
        height = 100,
        trackRadius = 20,
        value = 1,
        values = { 1, 2 },
        onChange = function() end,
        Frog.Image {
            key = "one", source = dialAsset, width = 10, height = 10,
        },
        Frog.Image {
            key = "two", source = dialAsset, width = 10, height = 10,
        },
    })
    local dial = assert(support.find(tree, "cache-radial"))
    local dialWidthReads = dialAsset.widthCalls
    local dialHeightReads = dialAsset.heightCalls
    Layout.arrangeRadialDial(dial, host)
    assert(dialAsset.widthCalls == dialWidthReads + 2
            and dialAsset.heightCalls == dialHeightReads + 2,
        "public retained RadialDial arrangement reused candidate measurement")
    host:unmount()
end

local function resizeRollback()
    local presses = 0
    local host = support.host { width = 540, height = 960 }
    local tree = support.mount(host, ResizeGuard {
        onPress = function() presses = presses + 1 end,
    })
    local beforeTree = tree
    local beforeViewport = host:viewport()
    local ok, err = pcall(host.resize, host, 960, 540)
    assert(not ok and tostring(err):find("intentional wide render refusal", 1, true),
        "responsive resize did not exercise failed render rollback")
    local afterViewport = host:viewport()
    assert(host:tree() == beforeTree,
        "failed responsive resize replaced the committed tree")
    support.near(afterViewport.width, beforeViewport.width,
        "failed resize virtual width rollback")
    support.near(afterViewport.height, beforeViewport.height,
        "failed resize virtual height rollback")
    support.near(afterViewport.scale, beforeViewport.scale,
        "failed resize input-transform rollback")
    local button = assert(support.find(host:tree(), "resize-guard"))
    local x, y = support.center(button)
    host:pointerDown(x, y, "mouse", 1)
    host:pointerUp(x, y, "mouse", 1)
    assert(presses == 1,
        "failed resize left pointer input on the rejected transform")
    host:unmount()
end

-- Proves incremental layout owns immutable results, rejects shifted geometry,
-- and preserves the full-rebuild boundaries that can change hidden inputs.
local function incrementalLayoutOwnership()
    local function assertNoReuseMarkers(node)
        assert(node._layoutReusableFrom == nil
                and node._layoutReusableNodes == nil
                and node._layoutReuseFrom == nil
                and node._layoutReuseNodeCount == nil
                and node._layoutMeasureReuseFrom == nil
                and node._layoutShared == nil
                and node._layoutReused == nil,
            "committed tree retained incremental-layout bookkeeping")
        for _, child in ipairs(node.children or {}) do
            assertNoReuseMarkers(child)
        end
        if node._dragPreview then assertNoReuseMarkers(node._dragPreview) end
    end

    local function row(firstWidth, label)
        return Frog.Row {
            width = 140,
            height = 40,
            align = "start",
            Frog.Box {
                key = "first", testId = "incremental-first",
                width = firstWidth, height = 20,
            },
            Frog.Text {
                key = "second", testId = "incremental-second",
                width = 60, height = 20, label,
            },
        }
    end

    local host = support.host { width = 140, height = 40 }
    local tree = support.mount(host, row(20, "same"))
    local rootLayout = tree.layout
    local firstLayout = assert(support.find(
        tree, "incremental-first")).layout
    local second = assert(support.find(tree, "incremental-second"))
    local secondLayout, secondX = second.layout, second.layout.x

    tree = support.render(host, row(20, "same"))
    assert(tree.layout == rootLayout
            and support.find(tree, "incremental-first").layout == firstLayout
            and support.find(tree, "incremental-second").layout == secondLayout,
        "stable tree did not retain its exact immutable layout records")
    assertNoReuseMarkers(tree)

    local retained = Frog.Row {
        width = 140,
        height = 40,
        Frog.Box { width = 20, height = 20 },
    }
    host:unmount()
    host = support.host { width = 140, height = 40 }
    tree = support.mount(host, retained)
    rootLayout = tree.layout
    local retainedChildLayout = tree.children[1].layout
    tree = support.render(host, retained)
    assert(tree.props == retained.props
            and tree.layout == rootLayout
            and tree.children[1].layout == retainedChildLayout,
        "retained description lost its props or incremental layout records")
    assertNoReuseMarkers(tree)

    tree = support.render(host, row(40, "same"))
    second = assert(support.find(tree, "incremental-second"))
    assert(second.layout ~= secondLayout and second.layout.x == secondX + 20,
        "shifted sibling reused stale committed geometry")
    assertNoReuseMarkers(tree)
    local shiftedLayout = second.layout

    tree = support.render(host, row(40, "changed text"))
    second = assert(support.find(tree, "incremental-second"))
    assert(second.layout ~= shiftedLayout,
        "changed Text input retained an obsolete layout result")

    local beforeResize = tree.layout
    host:resize(200, 80)
    assert(host:tree().layout ~= beforeResize,
        "resize crossed the full-layout invalidation boundary")
    local beforeRefresh = host:tree().layout
    host:refreshTheme(host.theme, host.assets, row(40, "changed text"))
    assert(host:tree().layout ~= beforeRefresh,
        "theme/asset refresh reused a pre-refresh layout result")
    host:unmount()

    local function portalTree()
        return Frog.Overlay {
            width = 140, height = 80,
            Frog.Box {
                key = "plain", testId = "incremental-plain",
                width = 20, height = 20,
            },
            Frog.Modal {
                key = "modal", testId = "incremental-modal",
                dismiss = "none",
                Frog.Box { width = 20, height = 20 },
            },
        }
    end
    host = support.host { width = 140, height = 80 }
    tree = support.mount(host, portalTree())
    local plainLayout = assert(support.find(
        tree, "incremental-plain")).layout
    local modalLayout = assert(support.find(
        tree, "incremental-modal")).layout
    tree = support.render(host, portalTree())
    assert(support.find(tree, "incremental-plain").layout == plainLayout,
        "ordinary sibling beside a portal lost incremental layout")
    assert(support.find(tree, "incremental-modal").layout ~= modalLayout,
        "Modal crossed the incremental-layout barrier")
    assertNoReuseMarkers(tree)

    local committed, committedLayout = tree, tree.layout
    local ok = pcall(function()
        host:render(Frog.Row { gap = -1, Frog.Box { width = 10 } })
    end)
    assert(not ok and host:tree() == committed
            and host:tree().layout == committedLayout,
        "failed candidate mutated the committed layout result")
    host:unmount()
end

function check.run()
    nestedLayout()
    paddingNormalizationOwnership()
    responsiveLayout()
    rowWrapLayout()
    controlledOffsetLayout()
    alignmentVocabulary()
    textLayoutContracts()
    nestedWrapRemeasure()
    duplicateMeasurementProof()
    measurementReuseBoundaries()
    resizeRollback()
    incrementalLayoutOwnership()
    rejects("negative width", Frog.Box { width = -1 }, "width")
    rejects("non-finite width", Frog.Box { width = 0 / 0 }, "width")
    rejects("negative padding", Frog.Box { padding = -1 }, "padding")
    rejects("non-finite grow", Frog.Row {
        Frog.Box { grow = math.huge },
    }, "grow")
    rejects("Column wrap", Frog.Column { wrap = true }, "Row only")
    rejects("Overlay flow-only justify", Frog.Overlay {
        justify = "space-between",
    }, "unsupported")
    rejects("Row box-only justify", Frog.Row {
        justify = "stretch",
    }, "unsupported")
    rejects("unknown align value", Frog.Box {
        align = "middle",
    }, "unsupported")
    rejects("malformed offset", Frog.Box { offset = 4 }, "offset")
    rejects("unknown offset axis", Frog.Box {
        offset = { z = 4 },
    }, "offset axis")
    rejects("non-finite offset", Frog.Box {
        offset = { x = math.huge },
    }, "offset x")
end

return check
