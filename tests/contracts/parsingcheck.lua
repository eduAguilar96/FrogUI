-- Public-contract checks for callable tags, child normalization and keyed
-- reconciliation. No runtime internals are imported here.

local Frog = require("frogui")
local support = require("tests.support")
local FroguiFeatureProbe = require("tests.frogui_feature.probe")

local check = {}

-- Draws one keyed item used to prove component parsing and reorder identity.
local Item = Frog.component("ParsingCheckItem", function(props)
    return Frog.Box {
        testId = "item-" .. props.item.id,
        Frog.Text(props.item.label),
    }
end)

-- Supplies the first component type for the same-key type-swap check.
local SwapA = Frog.component("ParsingSwapA", function()
    return Frog.Box { testId = "swap-node" }
end)

-- Supplies the replacement component type for the same-key type-swap check.
local SwapB = Frog.component("ParsingSwapB", function()
    return Frog.Box { testId = "swap-node" }
end)

-- Maps domain items to keyed child component descriptions.
local List = Frog.component("ParsingCheckList", function(props)
    return Frog.Column {
        testId = "parsed-list",
        false,
        Frog.each(props.items, function(item)
            return Item { key = item.id, item = item }
        end),
        nil,
    }
end)

-- Non-card example for the generic silhouette primitive: application code
-- composes an ordinary status label without a custom painter or icon widget.
local ConnectionStatus = Frog.component("ParsingConnectionStatus", function(props)
    return Frog.Row {
        gap = 4,
        Frog.Icon {
            testId = "connection-icon",
            width = 18,
            height = 18,
            source = props.icon,
            tint = "text",
            mirror = props.mirror,
            outline = { width = 1, color = "panel" },
        },
        Frog.Text {
            testId = "connection-label",
            outlineWidth = 1,
            outlineColor = "panel",
            props.label,
        },
    }
end)

-- Owns several primitive leaves so the public tree can prove one component
-- definition source is shared across rebuilds instead of recaptured per leaf.
local ProvenanceProbe = Frog.component("ParsingProvenanceProbe", function()
    return Frog.Column {
        testId = "provenance-root",
        Frog.Box {
            testId = "provenance-box",
            Frog.Text { testId = "provenance-text", "Shared source" },
        },
    }
end)

local function rejects(label, fn, fragment)
    local ok, err = pcall(fn)
    assert(not ok, label .. " unexpectedly succeeded")
    assert(not fragment or tostring(err):find(fragment, 1, true),
        label .. " rejected for the wrong reason: " .. tostring(err))
end

-- Keeps every public primitive attached to one spaced LuaLS props contract.
local function publicPrimitiveDocumentation()
    local source = assert(love.filesystem.read("frogui/init.lua"),
        "could not read FrogUI's public API module")
    local contracts = {
        { "Box", "---@type fun(input?: FrogBoxProps):FrogUIElementDescription" },
        { "Row", "---@type fun(input?: FrogRowProps):FrogUIElementDescription" },
        { "Column", "---@type fun(input?: FrogColumnProps):FrogUIElementDescription" },
        { "Overlay", "---@type fun(input?: FrogOverlayProps):FrogUIElementDescription" },
        { "Text", "---@type fun(input:FrogTextProps|string|number):FrogUIElementDescription" },
        { "Image", "---@type fun(input:FrogImageProps):FrogUIElementDescription" },
        { "SpriteSheet", "---@type fun(input:FrogSpriteSheetProps):FrogUIElementDescription" },
        { "Icon", "---@type fun(input:FrogIconProps):FrogUIElementDescription" },
        { "Button", "---@type fun(input?: FrogButtonProps):FrogUIElementDescription" },
        { "Motion", "---@type fun(input?: FrogMotionProps):FrogUIElementDescription" },
        { "Pressable", "---@type fun(input:FrogPressableProps):FrogUIElementDescription" },
        { "Scroll", "---@type fun(input:FrogScrollProps):FrogUIElementDescription" },
        { "Chrome", "---@type fun(input:FrogChromeProps):FrogUIElementDescription" },
        { "Modal", "---@type fun(input:FrogModalProps):FrogUIElementDescription" },
        { "DragSource", "---@type fun(input:FrogDragSourceProps):FrogUIElementDescription" },
        { "DropTarget", "---@type fun(input:FrogDropTargetProps):FrogUIElementDescription" },
    }
    for index, contract in ipairs(contracts) do
        local assignment = "Frog." .. contract[1] .. " = Element.primitive(\""
            .. contract[1] .. "\")"
        local block = contract[2] .. "\n" .. assignment
        local first, last = source:find(block, 1, true)
        assert(first,
            "Frog." .. contract[1] .. " lost its adjacent LuaLS contract")
        if index < #contracts then
            assert(source:sub(last + 1, last + 5):find("\n\n---", 1, true),
                "Frog." .. contract[1]
                    .. " must be separated from the next primitive")
        end
    end
end

local function painterSmoke()
    local calls = { box = 0, text = 0, image = 0, icon = 0, inspector = 0 }
    local painter = {}
    function painter:begin(viewport)
        assert(viewport.width == 540 and viewport.height == 960,
            "painter received the wrong virtual viewport")
        calls.begin = (calls.begin or 0) + 1
    end
    function painter:box(node)
        assert(node.width >= 0 and node.height >= 0,
            "painter received unresolved bounds")
        calls.box = calls.box + 1
    end
    function painter:text(_, value, style)
        assert(value == "Paint", "Text painter received the wrong value")
        assert(style.outlineWidth == 2
                and style.outlineColor[1] == 0.05,
            "Text painter lost its resolved outline descriptor")
        calls.text = calls.text + 1
    end
    function painter:image(node, asset, style)
        assert(asset == nil, "missing test asset unexpectedly resolved")
        assert(node.width > 0 and node.height > 0 and style.fit == "cover",
            "Image painter lost resolved cover geometry")
        calls.image = calls.image + 1
    end
    function painter:icon(node, asset, style)
        assert(asset == nil, "missing test icon unexpectedly resolved")
        assert(node.width > 0 and node.height > 0
                and style.fit == "contain"
                and style.alphaMask == true
                and style.mirror == true,
            "Icon painter lost its generic silhouette descriptor")
        assert(style.outline and style.outline.width == 1.5
                and style.outline.color[1] == 0.05,
            "Icon painter lost its resolved outline descriptor")
        calls.icon = calls.icon + 1
    end
    function painter:inspector(entry)
        assert(entry.source and entry.bounds,
            "inspector painter received incomplete entry")
        calls.inspector = calls.inspector + 1
    end
    function painter:finish() calls.finish = (calls.finish or 0) + 1 end

    local host = support.host {
        width = 540,
        height = 960,
        painter = painter,
        assets = {
            ["missing-test-asset"] =
                "tests/fixtures/__frogui_intentionally_missing__.png",
        },
    }
    host:mount(Frog.Overlay {
        Frog.Box { testId = "paint-box", background = "panel" },
        Frog.Text {
            testId = "paint-text",
            outlineWidth = 2,
            outlineColor = { 0.05, 0.06, 0.07, 1 },
            "Paint",
        },
        Frog.Image {
            testId = "paint-image",
            source = "missing-test-asset",
            fit = "cover",
        },
        Frog.Icon {
            testId = "paint-icon",
            source = "missing-test-asset",
            fit = "contain",
            mirror = true,
            outline = {
                width = 1.5,
                color = { 0.05, 0.06, 0.07, 1 },
            },
        },
    })
    host:setInspectorVisible(true)
    host:draw()
    host:unmount()
    assert(calls.begin == 1 and calls.finish == 1,
        "painter frame hooks did not bracket exactly one draw")
    assert(calls.box >= 5 and calls.text == 1 and calls.image == 1
            and calls.icon == 1,
        "Box/Text/Image/Icon did not use the shared painter")
    assert(calls.inspector == calls.box,
        "F6 did not paint the exact committed primitive tree")
end

-- Proves semantic-owner provenance remains readable and referentially stable
-- through an ordinary rebuild while every leaf shares the same source object.
local function componentProvenance()
    local host = support.host { width = 100, height = 100 }
    local tree = support.mount(host, ProvenanceProbe {})
    local source = assert(tree.source,
        "component root omitted definition provenance")
    local box = assert(support.find(tree, "provenance-box"))
    local label = assert(support.find(tree, "provenance-text"))
    assert(source.path:find("tests/contracts/parsingcheck.lua", 1, true)
            and type(source.line) == "number" and source.line > 0,
        "component definition provenance omitted its readable file:line")
    assert(box.source == source and label.source == source,
        "component leaves did not share definition provenance")

    tree = support.render(host, ProvenanceProbe {})
    assert(tree.source == source
            and assert(support.find(tree, "provenance-box")).source == source
            and assert(support.find(tree, "provenance-text")).source == source,
        "component rebuild recaptured or replaced definition provenance")
    host:unmount()

    host = support.host()
    tree = support.mount(host, FroguiFeatureProbe())
    source = assert(tree.source,
        "application path containing frogui lost provenance")
    assert(source.path:find("tests/frogui_feature/probe.lua", 1, true),
        "an unrelated application folder containing frogui was excluded: "
            .. tostring(source.path))
    host:unmount()
end

-- Locks the allocation-light descriptor normalizer to the existing public
-- syntax, including sparse order, Text shorthand, and typed sibling keys.
local function descriptorNormalization()
    local shorthand = Frog.Text(42)
    local sparseText = Frog.Text { [5] = "After holes" }
    assert(shorthand.props.text == "42"
            and #shorthand.children == 0
            and sparseText.props.text == "After holes",
        "Text shorthand changed during descriptor normalization")

    local ordered = Frog.Column {
        [1000000] = Frog.Text { testId = "sparse-last", "Last" },
        [2] = Frog.Text { testId = "sparse-first", "First" },
    }
    assert(ordered.children[1].props.testId == "sparse-first"
            and ordered.children[2].props.testId == "sparse-last",
        "sparse numeric children lost sorted order")

    local typedKeys = Frog.Row {
        Frog.Box { key = 1 },
        Frog.Box { key = "1" },
    }
    assert(#typedKeys.children == 2,
        "numeric and string sibling keys stopped being distinct")

    rejects("non-Text scalar input", function()
        Frog.Box("invalid")
    end, "props table")
    rejects("multiple Text shorthand values", function()
        Frog.Text { "one", "two" }
    end, "accepts text")
    rejects("Text element child", function()
        Frog.Text { Frog.Box {} }
    end, "accepts text")
    rejects("unsupported sibling key type", function()
        Frog.Row { Frog.Box { key = true } }
    end, "keys must be strings or numbers")
end

-- Proves the constructor detaches authored input once, then the resolved node
-- reuses the framework-owned descriptor props without a second copy.
local function descriptorPropsOwnership()
    local input = {
        testId = "descriptor-props-owner",
        width = 30,
        height = 20,
    }
    local description = Frog.Box(input)
    input.width = 90
    input.testId = "mutated-author-input"

    local host = support.host { width = 100, height = 100 }
    local node = support.mount(host, description)
    assert(node.props == description.props,
        "resolved primitive copied its framework-owned descriptor props")
    assert(node.props.width == 30
            and node.props.testId == "descriptor-props-owner",
        "descriptor props retained mutable authored input")

    local rebuilt = support.render(host, description)
    assert(rebuilt.props == description.props and rebuilt.props == node.props,
        "descriptor props identity changed across an ordinary rebuild")
    host:unmount()

    local childrenHost = support.host { width = 100, height = 100 }
    local childrenTree = support.mount(childrenHost, Frog.Row {
        Frog.Text { testId = "empty-children-a", "A" },
        Frog.Text { testId = "empty-children-b", "B" },
    })
    local first = assert(support.find(childrenTree, "empty-children-a"))
    local second = assert(support.find(childrenTree, "empty-children-b"))
    assert(first.children == second.children and #first.children == 0,
        "childless primitives did not share the read-only empty collection")
    assert(childrenTree.children ~= first.children,
        "container reused the childless collection for authored children")
    childrenHost:unmount()
end

-- Proves retained-description validation is scoped to one Host presentation
-- catalog and a rejected theme candidate restores the last-good cache.
local function retainedDescriptorValidation()
    local theme = {
        colors = {
            ["cached-only"] = { 0.2, 0.4, 0.6, 1 },
        },
    }
    local description = Frog.Text {
        color = "cached-only",
        "Retained",
    }
    local host = support.host {
        width = 100,
        height = 100,
        theme = theme,
    }
    host:mount(description)
    host:render(description)

    rejects("retained descriptor under replacement theme", function()
        host:refreshTheme({
            colors = {
                replacement = { 0.8, 0.7, 0.6, 1 },
            },
        }, {}, description)
    end, "unknown FrogUI color token cached-only")

    assert(host.theme == theme,
        "rejected theme refresh did not restore descriptor validation catalog")
    assert(support.render(host, description).props.color == "cached-only",
        "last-good descriptor validation cache did not survive rejection")
    host:unmount()
end

local function paintStateSmoke()
    local buttonStyle, textStyle
    local painter = {}
    function painter:box(node, style)
        if node.props.testId == "selected-button" then buttonStyle = style end
    end
    function painter:text(node, _, style)
        if node.props.testId == "selected-label" then textStyle = style end
    end

    local host = support.host {
        width = 100,
        height = 100,
        painter = painter,
        theme = {
            colors = {
                border = { 0.8, 0.7, 0.6, 0.6 },
                text = { 1, 1, 1, 1 },
                selected = { 0.2, 0.4, 0.6, 0.8 },
            },
            controls = { button = { selected = "selected" } },
        },
    }
    host:mount(Frog.Box {
        opacity = 0.5,
        Frog.Button {
            testId = "selected-button",
            opacity = 0.5,
            selected = true,
            border = "border",
            Frog.Text { testId = "selected-label", "Selected" },
        },
    })
    host:draw()
    host:unmount()

    buttonStyle = assert(buttonStyle, "selected Button was not painted")
    textStyle = assert(textStyle, "selected Button label was not painted")
    support.near(buttonStyle.opacity, 0.25, "cumulative subtree opacity")
    support.near(buttonStyle.background[1], 0.2,
        "selected semantic background red")
    support.near(buttonStyle.background[4], 0.2,
        "selected semantic background alpha")
    support.near(buttonStyle.border[4], 0.15,
        "Button border alpha applied exactly once")
    support.near(textStyle.color[4], 0.25,
        "child text inherited cumulative opacity")
end

-- Proves one Button can retain its authored fill while choosing explicit
-- hover/pressed fills and borders without an application painter.
local function localButtonStateStyle()
    local styles = {}
    local painter = {}
    function painter:box(node, style)
        if node.props.testId == "local-state-button" then
            styles[#styles + 1] = style
        end
    end
    local host = support.host {
        width = 540, height = 960, painter = painter,
        theme = { colors = {
            base = { 0.1, 0.2, 0.3, 1 },
            baseBorder = { 0.2, 0.3, 0.4, 1 },
            hot = { 0.4, 0.5, 0.6, 1 },
            hotBorder = { 0.8, 0.7, 0.2, 1 },
            selectedFill = { 0.3, 0.7, 0.4, 1 },
            selectedBorder = { 0.9, 0.8, 0.3, 1 },
            text = { 1, 1, 1, 1 },
        } },
    }
    host:mount(Frog.Button {
        testId = "local-state-button", width = 120, height = 40,
        background = "base", border = "baseBorder", borderWidth = 2,
        hoverBackground = "hot", hoverBorder = "hotBorder",
        pressedBackground = "hot", pressedBorder = "hotBorder",
        onPress = function() end, Frog.Text "Styled",
    })
    host:draw()
    local button = assert(support.find(host:tree(), "local-state-button"))
    local x, y = support.center(button)
    host:pointerMove(x, y, "mouse")
    host:draw()
    host:pointerDown(x, y, "mouse", 1)
    host:draw()
    assert(styles[1].background[1] == 0.1
            and styles[1].border[1] == 0.2
            and styles[1].borderWidth == 2,
        "Button base state ignored its local paint tokens")
    for index = 2, 3 do
        assert(styles[index].background[1] == 0.4
                and styles[index].border[1] == 0.8,
            "Button hover/pressed state ignored its local paint tokens")
    end
    host:pointerUp(x, y, "mouse", 1)
    host:unmount()

    styles = {}
    host = support.host {
        width = 540, height = 960, painter = painter,
        theme = { colors = {
            base = { 0.1, 0.2, 0.3, 1 },
            baseBorder = { 0.2, 0.3, 0.4, 1 },
            hot = { 0.4, 0.5, 0.6, 1 },
            hotBorder = { 0.8, 0.7, 0.2, 1 },
            selectedFill = { 0.3, 0.7, 0.4, 1 },
            selectedBorder = { 0.9, 0.8, 0.3, 1 },
            text = { 1, 1, 1, 1 },
        } },
    }
    host:mount(Frog.Button {
        testId = "local-state-button", width = 120, height = 40,
        selected = true,
        background = "base", border = "baseBorder",
        hoverBackground = "hot", hoverBorder = "hotBorder",
        pressedBackground = "hot", pressedBorder = "hotBorder",
        selectedBackground = "selectedFill",
        selectedBorder = "selectedBorder",
        onPress = function() end, Frog.Text "Selected",
    })
    host:draw()
    button = assert(support.find(host:tree(), "local-state-button"))
    x, y = support.center(button)
    host:pointerMove(x, y, "mouse")
    host:draw()
    host:pointerDown(x, y, "mouse", 1)
    host:draw()
    for index = 1, 2 do
        assert(styles[index].background[1] == 0.3
                and styles[index].border[1] == 0.9,
            "selected Button did not outrank base/hover paint")
    end
    assert(styles[3].background[1] == 0.4
            and styles[3].border[1] == 0.8,
        "pressed Button did not outrank selected paint")
    host:pointerUp(x, y, "mouse", 1)
    host:unmount()
end

function check.run()
    publicPrimitiveDocumentation()
    componentProvenance()
    descriptorNormalization()
    descriptorPropsOwnership()
    retainedDescriptorValidation()
    local first = { id = "first", label = "First" }
    local second = { id = "second", label = "Second" }
    local host = support.host { width = 540, height = 960 }
    local tree = support.mount(host, List { items = { first, second } })
    local firstNode = assert(support.find(tree, "item-first"))
    local secondNode = assert(support.find(tree, "item-second"))
    assert(firstNode.identity ~= secondNode.identity,
        "different keyed children shared identity")
    assert(#assert(support.find(tree, "parsed-list")).children == 2,
        "nil/false children were not ignored")

    local firstIdentity, secondIdentity = firstNode.identity, secondNode.identity
    tree = support.render(host, List { items = { second, first } })
    assert(assert(support.find(tree, "item-first")).identity == firstIdentity,
        "first keyed child lost identity after reorder")
    assert(assert(support.find(tree, "item-second")).identity == secondIdentity,
        "second keyed child lost identity after reorder")
    host:unmount()

    local sparseHost = support.host { width = 100, height = 100 }
    local sparse = support.mount(sparseHost, Frog.Column {
        [2] = Frog.Text { testId = "after-hole", "Still present" },
    })
    assert(support.find(sparse, "after-hole"),
        "a nil child hole truncated a later numeric child")
    sparseHost:unmount()

    local statusHost = support.host {
        width = 100,
        height = 100,
        theme = { colors = {
            text = { 1, 1, 1, 1 },
            panel = { 0.1, 0.1, 0.1, 1 },
        } },
        assets = {
            connection = "tests/fixtures/__frogui_intentionally_missing__.png",
        },
    }
    tree = support.mount(statusHost, ConnectionStatus {
        icon = "connection",
        label = "Online",
        mirror = false,
    })
    assert(assert(support.find(tree, "connection-icon")).type == "Icon"
            and support.find(tree, "connection-label"),
        "ordinary status component did not parse Frog.Icon and outlined Text")
    statusHost:unmount()

    painterSmoke()
    paintStateSmoke()
    localButtonStateStyle()

    local swapHost = support.host { width = 100, height = 100 }
    tree = support.mount(swapHost, Frog.Row { SwapA { key = "same" } })
    local swapIdentity = assert(support.find(tree, "swap-node")).identity
    tree = support.render(swapHost, Frog.Row { SwapB { key = "same" } })
    assert(assert(support.find(tree, "swap-node")).identity ~= swapIdentity,
        "same key preserved identity across component types")
    swapIdentity = assert(support.find(tree, "swap-node")).identity
    tree = support.render(swapHost, Frog.Row {
        Frog.Text { key = "same", testId = "swap-node", "Changed" },
    })
    assert(assert(support.find(tree, "swap-node")).identity ~= swapIdentity,
        "same key preserved identity across primitive types")
    swapHost:unmount()

    local rollbackHost = support.host { width = 100, height = 100 }
    tree = support.mount(rollbackHost, Frog.Text { testId = "rollback", "Committed" })
    local committedIdentity = tree.identity
    rejects("failed render", function()
        rollbackHost:render(Frog.Box {
            Frog.Text "One", Frog.Text "Two",
        })
    end, "one child")
    tree = support.render(rollbackHost)
    assert(tree.identity == committedIdentity
            and tree.props.text == "Committed",
        "failed render did not restore the previous committed descriptor")
    rollbackHost:unmount()

    rejects("duplicate sibling key", function()
        local duplicateHost = support.host { width = 100, height = 100 }
        duplicateHost:mount(Frog.Row {
            Frog.Box { key = "same" },
            Frog.Box { key = "same" },
        })
    end, "duplicate")
    rejects("Frog.each missing key", function()
        Frog.each({ first }, function(item)
            return Frog.Box { testId = item.id }
        end)
    end, "key")
    rejects("Frog.each duplicate key", function()
        Frog.each({ first, second }, function(item)
            return Frog.Box { key = "same", testId = item.id }
        end)
    end, "key")
    rejects("Frog.each sparse input", function()
        Frog.each({ [1] = first, [3] = second }, function(item)
            return Frog.Box { key = item.id }
        end)
    end, "dense")
    rejects("fractional numeric child index", function()
        Frog.Column { [1.5] = Frog.Text "Invalid" }
    end, "numeric")
    rejects("non-positive numeric child index", function()
        Frog.Column { [0] = Frog.Text "Invalid" }
    end, "numeric")
    rejects("unknown primitive prop", function()
        support.host { width = 100, height = 100 }:mount(
            Frog.Box { paddding = 8 })
    end, "paddding")
    rejects("unknown semantic color", function()
        support.host { width = 100, height = 100,
            theme = { colors = {} } }:mount(
            Frog.Box { background = "not-a-color" })
    end, "color")
    rejects("malformed direct color", function()
        support.host { width = 100, height = 100 }:mount(
            Frog.Box { background = { 0.2, "bad", 0.4, 1 } })
    end, "channel")
    rejects("malformed resolved color token", function()
        support.host {
            width = 100,
            height = 100,
            theme = { colors = { broken = { 0.2, "bad", 0.4, 1 } } },
        }:mount(Frog.Box { background = "broken" })
    end, "channel")
    rejects("unknown asset token", function()
        support.host { width = 100, height = 100, assets = {} }:mount(
            Frog.Image { source = "not-an-asset" })
    end, "asset")
    rejects("unknown Icon asset token", function()
        support.host { width = 100, height = 100, assets = {} }:mount(
            Frog.Icon { source = "not-an-asset" })
    end, "asset")
    rejects("malformed direct asset", function()
        support.host { width = 100, height = 100 }:mount(Frog.Image {
            source = { getWidth = function() return 10 end },
        })
    end, "asset")
    rejects("malformed declared asset", function()
        support.host {
            width = 100,
            height = 100,
            assets = {
                broken = { getWidth = function() return 10 end },
            },
        }:mount(Frog.Image { source = "broken" })
    end, "asset")
    rejects("malformed Icon mirror", function()
        support.host {
            width = 100,
            height = 100,
            assets = { icon = "missing.png" },
        }:mount(Frog.Icon { source = "icon", mirror = "yes" })
    end, "mirror")
    rejects("malformed Icon outline", function()
        support.host {
            width = 100,
            height = 100,
            assets = { icon = "missing.png" },
        }:mount(Frog.Icon {
            source = "icon",
            outline = { width = -1, color = { 0, 0, 0, 1 } },
        })
    end, "outline width")
    local cropAsset = {
        getWidth = function() return 100 end,
        getHeight = function() return 80 end,
    }
    local cropHost = support.host { width = 100, height = 100 }
    cropHost:mount(Frog.Column { align = "start",
        Frog.Image {
            testId = "cropped-image", source = cropAsset,
            sourceRect = { x = 10, y = 12, width = 20, height = 40 },
        },
    })
    local cropped = assert(support.find(cropHost:tree(), "cropped-image"))
    assert(cropped.layout.width == 20 and cropped.layout.height == 40,
        "Image sourceRect did not own intrinsic crop dimensions")
    cropHost:unmount()
    local missingCrop = support.host { width = 100, height = 100,
        assets = { missing = "tests/fixtures/__frogui_missing_crop__.png" } }
    missingCrop:mount(Frog.Column { align = "start",
        Frog.Image { testId = "missing-crop", source = "missing",
            sourceRect = { x = 0, y = 0, width = 23, height = 31 } },
    })
    local missing = assert(support.find(missingCrop:tree(), "missing-crop"))
    assert(missing.layout.width == 23 and missing.layout.height == 31,
        "missing cropped asset lost deterministic intrinsic dimensions")
    missingCrop:unmount()
    rejects("out-of-bounds Image sourceRect", function()
        support.host { width = 100, height = 100 }:mount(Frog.Image {
            source = cropAsset,
            sourceRect = { x = 90, y = 0, width = 20, height = 10 },
        })
    end, "stay inside")
    rejects("incomplete Icon sourceRect", function()
        support.host { width = 100, height = 100 }:mount(Frog.Icon {
            source = cropAsset,
            sourceRect = { x = 0, y = 0, width = 10 },
        })
    end, "width and height")
    rejects("unknown Icon outline field", function()
        support.host {
            width = 100,
            height = 100,
            assets = { icon = "missing.png" },
        }:mount(Frog.Icon {
            source = "icon",
            outline = { thickness = 1 },
        })
    end, "thickness")
    rejects("negative Text outline", function()
        support.host { width = 100, height = 100 }:mount(Frog.Text {
            outlineWidth = -1,
            "Outlined",
        })
    end, "outlineWidth")
    rejects("zero Text fontScale", function()
        support.host { width = 100, height = 100 }:mount(Frog.Text {
            fontScale = 0,
            "Tiny",
        })
    end, "fontScale must be positive")
    rejects("malformed Text fontScale", function()
        support.host { width = 100, height = 100 }:mount(Frog.Text {
            fontScale = "large",
            "Large",
        })
    end, "fontScale must be finite")
    rejects("malformed theme fontFile", function()
        support.host {
            width = 100,
            height = 100,
            theme = { fontFile = false },
        }
    end, "fontFile")

    local leafProps = {
        { name = "padding", value = 1 },
        { name = "clip", value = true },
        { name = "overflow", value = "clip" },
    }
    for _, case in ipairs(leafProps) do
        rejects("Text leaf " .. case.name, function()
            local props = { text = "Leaf" }
            props[case.name] = case.value
            support.host { width = 100, height = 100 }:mount(Frog.Text(props))
        end, case.name)
        rejects("Image leaf " .. case.name, function()
            local props = { source = "leaf" }
            props[case.name] = case.value
            support.host {
                width = 100,
                height = 100,
                assets = {
                    leaf = "tests/fixtures/__frogui_intentionally_missing__.png",
                },
            }:mount(Frog.Image(props))
        end, case.name)
        rejects("Icon leaf " .. case.name, function()
            local props = { source = "leaf" }
            props[case.name] = case.value
            support.host {
                width = 100,
                height = 100,
                assets = {
                    leaf = "tests/fixtures/__frogui_intentionally_missing__.png",
                },
            }:mount(Frog.Icon(props))
        end, case.name)
    end
    rejects("Box with two children", function()
        support.host { width = 100, height = 100 }:mount(
            Frog.Box { Frog.Text "One", Frog.Text "Two" })
    end, "one child")
    rejects("Button with two children", function()
        support.host { width = 100, height = 100 }:mount(
            Frog.Button { Frog.Text "One", Frog.Text "Two" })
    end, "one child")
    rejects("Image with a child", function()
        support.host { width = 100, height = 100 }:mount(
            Frog.Image { Frog.Text "Invalid" })
    end, "children")
    rejects("Icon with a child", function()
        support.host {
            width = 100,
            height = 100,
            assets = { icon = "missing.png" },
        }:mount(Frog.Icon { source = "icon", Frog.Text "Invalid" })
    end, "children")
end

return check
