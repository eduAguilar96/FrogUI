-- Adversarial public-contract checks for positional committed refs, keyed
-- retention, candidate atomicity, runtime faulting, and F6 metadata.

local Frog = require("frogui")
local support = require("tests.support")

local check = {}

-- Requires a callback to fail with one actionable diagnostic fragment.
local function rejects(label, callback, fragment)
    local ok, err = pcall(callback)
    assert(not ok, label .. " unexpectedly succeeded")
    assert(tostring(err):find(fragment, 1, true),
        label .. " rejected for the wrong reason: " .. tostring(err))
end

-- Compares one public ref snapshot to one arranged resolved node.
local function matches(ref, node, label)
    local rect = assert(ref.current, label .. " ref did not commit")
    support.near(rect.x, node.layout.x, label .. " x")
    support.near(rect.y, node.layout.y, label .. " y")
    support.near(rect.width, node.layout.width, label .. " width")
    support.near(rect.height, node.layout.height, label .. " height")
end

-- Serializes one rectangle so failed candidates can prove byte-for-byte
-- preservation without keeping a mutable public table.
local function rectangleText(ref)
    local rect = assert(ref.current, "expected a committed ref rectangle")
    return ("%.6f:%.6f:%.6f:%.6f"):format(
        rect.x, rect.y, rect.width, rect.height)
end

local basicHandles = {}

-- Attaches one ordinary ref to an offset primitive for exact geometry checks.
local BasicRef = Frog.component("RefCheckBasic", function(props)
    local handle = Frog.useRef()
    basicHandles[#basicHandles + 1] = handle
    return Frog.Box {
        testId = "basic-ref",
        ref = handle,
        width = props.width,
        height = 35,
        offset = { x = 7, y = 9 },
        background = { 0.2, 0.4, 0.6, 1 },
    }
end)

-- Proves commit timing, retained identity, detached reads, F6 data, and clear.
local function basicLifecycle()
    local host = support.host { width = 200, height = 120 }
    local tree = support.mount(host, BasicRef { width = 60 })
    local first = assert(basicHandles[#basicHandles])
    matches(first, assert(support.find(tree, "basic-ref")), "initial ref")

    local detached = first.current
    detached.x = -1000
    assert(first.current.x ~= -1000,
        "ref.current exposed mutable committed framework state")

    local inspected
    for _, entry in ipairs(host:inspectionTree().nodes) do
        if entry.testId == "basic-ref" then inspected = entry break end
    end
    inspected = assert(inspected, "F6 omitted the ref-bearing primitive")
    assert(inspected.ref and type(inspected.ref.id) == "string",
        "F6 omitted the committed ref id")
    assert(inspected.ref.key == nil,
        "ordinary useRef unexpectedly reported a keyed identity")
    support.near(inspected.ref.current.x, first.current.x, "F6 ref x")
    support.near(inspected.ref.current.width, first.current.width,
        "F6 ref width")

    tree = support.render(host, BasicRef { width = 90 })
    local retained = assert(basicHandles[#basicHandles])
    assert(retained == first, "ordinary render replaced a retained ref handle")
    matches(first, assert(support.find(tree, "basic-ref")), "rerendered ref")
    support.near(first.current.width, 90, "rerendered committed width")

    host:resize(360, 120)
    assert(basicHandles[#basicHandles] == first,
        "resize replaced a retained ref handle")
    matches(first, assert(support.find(host:tree(), "basic-ref")),
        "resized ref")

    host:unmount()
    assert(first.current == nil, "unmount did not clear the committed ref")
end

local motionRef

-- Attaches a ref to Motion so arranged rest geometry and visual transforms are
-- distinguished by an executable public contract.
local MotionRef = Frog.component("RefCheckMotionGeometry", function()
    local handle = Frog.useRef()
    motionRef = handle
    return Frog.Motion {
        testId = "motion-ref",
        ref = handle,
        width = 40,
        height = 20,
        x = 30,
        scale = 1.5,
        Frog.Box { width = 40, height = 20 },
    }
end)

-- Proves refs expose stable arranged rest geometry, not Motion paint bounds.
local function motionRestGeometry()
    local host = support.host { width = 540, height = 960 }
    host:mount(MotionRef {})
    local node = assert(support.find(host:tree(), "motion-ref"))
    matches(motionRef, node, "Motion arranged ref")
    assert(node._visualBounds.x ~= node.layout.x
            or node._visualBounds.width ~= node.layout.width,
        "Motion geometry probe did not create a visual transform")
    assert(motionRef.current.x ~= node._visualBounds.x
            or motionRef.current.width ~= node._visualBounds.width,
        "ref unexpectedly exposed transformed Motion visual bounds")
    host:unmount()
end

local keyedSnapshots = {}

-- Attaches authored keys in independently supplied visual order.
local KeyedRefs = Frog.component("RefCheckKeyed", function(props)
    local refs = Frog.useKeyedRefs(props.keys)
    keyedSnapshots[#keyedSnapshots + 1] = refs
    local row = {
        testId = "keyed-row",
        width = 240,
        height = 40,
        gap = 10,
        align = "start",
    }
    for _, key in ipairs(props.order) do
        row[#row + 1] = Frog.Box {
            key = key,
            testId = "keyed-" .. tostring(key),
            ref = refs[key],
            width = 40,
            height = 30,
        }
    end
    return Frog.Row(row)
end)

-- Proves key retention, reorder, removal, re-add, and keyed F6 metadata.
local function keyedLifecycle()
    local host = support.host { width = 300, height = 100 }
    host:mount(KeyedRefs {
        keys = { "a", "b", "c" },
        order = { "a", "b", "c" },
    })
    local first = keyedSnapshots[#keyedSnapshots]
    local a, b, c = first.a, first.b, first.c
    assert(a and b and c, "keyed refs omitted a requested key")
    support.near(a.current.x, 0, "initial keyed a x")
    support.near(b.current.x, 50, "initial keyed b x")
    support.near(c.current.x, 100, "initial keyed c x")

    host:render(KeyedRefs {
        keys = { "c", "a" },
        order = { "c", "a" },
    })
    local reordered = keyedSnapshots[#keyedSnapshots]
    assert(reordered.a == a and reordered.c == c,
        "key reorder replaced retained handles")
    assert(b.current == nil, "removed keyed ref retained stale geometry")
    support.near(c.current.x, 0, "reordered keyed c x")
    support.near(a.current.x, 50, "reordered keyed a x")

    local inspected = host:inspectionTree().nodes
    local keyedEntry
    for _, entry in ipairs(inspected) do
        if entry.testId == "keyed-c" then keyedEntry = entry break end
    end
    keyedEntry = assert(keyedEntry, "F6 omitted a keyed ref primitive")
    assert(keyedEntry.ref and keyedEntry.ref.key == "c",
        "F6 omitted the authored ref key")
    matches(c, assert(support.find(host:tree(), "keyed-c")), "keyed F6 ref")

    host:render(KeyedRefs {
        keys = { "a", "b" },
        order = { "a", "b" },
    })
    local readded = keyedSnapshots[#keyedSnapshots]
    assert(readded.a == a, "retained keyed handle changed after another edit")
    assert(readded.b ~= b, "a removed and re-added key reused its retired handle")
    assert(c.current == nil, "second removed keyed ref retained stale geometry")
    assert(readded.b.current ~= nil, "re-added keyed ref did not commit geometry")

    local newB = readded.b
    host:unmount()
    assert(a.current == nil and newB.current == nil,
        "unmount did not clear current keyed handles")
end

local failedRef

-- Produces render-, arrange-, and resize-only failures after consuming a ref.
local FailureOwner = Frog.component("RefCheckFailureOwner", function(props)
    local handle = Frog.useRef()
    failedRef = handle
    local viewport = Frog.useViewport()
    if props.renderFailure then error("intentional ref render failure") end
    if props.resizeFailure and viewport.wide then
        error("intentional ref resize failure")
    end
    if props.arrangeFailure then
        return Frog.Scroll {
            testId = "failure-ref",
            ref = handle,
            axis = "vertical",
            width = 80,
            height = 60,
            Frog.Column { width = 80, height = "100%" },
        }
    end
    return Frog.Box {
        testId = "failure-ref",
        ref = handle,
        width = 70,
        height = 30,
    }
end)

-- Proves every failed candidate leaves both the tree and ref snapshot intact.
local function candidateAtomicity()
    local host = support.host { width = 120, height = 200 }
    host:mount(FailureOwner { resizeFailure = true })
    local handle = failedRef
    local before = rectangleText(handle)
    local tree = host:tree()
    local revision = host._arrangedRefRevision
    assert(host._publishedRefRevision == revision,
        "initial failed-candidate fixture left refs dirty")

    rejects("failed ref render", function()
        host:render(FailureOwner { renderFailure = true })
    end, "intentional ref render failure")
    assert(host:tree() == tree and failedRef == handle
            and host._arrangedRefRevision == revision
            and host._publishedRefRevision == revision,
        "failed ref render replaced committed identity")
    assert(rectangleText(handle) == before,
        "failed ref render changed committed geometry")

    rejects("failed ref arrange", function()
        host:render(FailureOwner { arrangeFailure = true })
    end, "vertical Scroll child height must be naturally measured")
    assert(host:tree() == tree and rectangleText(handle) == before
            and host._arrangedRefRevision == revision
            and host._publishedRefRevision == revision,
        "failed arrange changed committed ref/tree state")

    rejects("failed ref resize", function()
        host:resize(300, 100)
    end, "intentional ref resize failure")
    assert(host:tree() == tree and rectangleText(handle) == before
            and host._arrangedRefRevision == revision
            and host._publishedRefRevision == revision,
        "failed resize changed committed ref/tree state")
    local viewport = host:viewport()
    assert(not viewport.wide,
        "failed resize did not restore the committed viewport")
    host:render(FailureOwner { resizeFailure = true })
    assert(host:tree() ~= tree and failedRef == handle,
        "failed candidate left the Host unusable or replaced the ref handle")
    assert(host._arrangedRefRevision > revision
            and host._publishedRefRevision == host._arrangedRefRevision,
        "valid recovery did not publish one synchronized ref revision")
    assert(rectangleText(handle) == before,
        "valid recovery render changed the stable ref geometry")
    host:unmount()
end

local deferredHandles = {}
local DeferredOwner = Frog.actor("RefCheckDeferredCompactionOwner", {
    initial = "ready",
    render = function()
        return Frog.Box {
            testId = "deferred-owner",
            width = 20,
            height = 20,
        }
    end,
})
local DeferredAddress = DeferredOwner:address(
    "RefCheckDeferredCompactionAddress")
local DeferredView = DeferredOwner:view(
    "RefCheckDeferredCompactionView", function(props)
        if props.fail then error("intentional deferred view failure") end
        if props.omit then return nil end
        return Frog.Box {
            testId = "deferred-kept",
            ref = props.anchor,
            width = 30,
            height = 20,
        }
    end)
local DeferredRoot = Frog.component("RefCheckDeferredCompactionRoot",
    function(props)
        local anchor = Frog.useRef("deferred-kept")
        deferredHandles[#deferredHandles + 1] = anchor
        return Frog.Column {
            width = 100,
            height = 100,
            DeferredView {
                key = "kept",
                target = DeferredAddress,
                anchor = anchor,
            },
            DeferredView {
                key = "omitted",
                target = DeferredAddress,
                omit = true,
            },
            DeferredView {
                key = "candidate-failure",
                target = DeferredAddress,
                omit = true,
                fail = props.fail,
            },
            Frog.Text {
                key = "middle",
                testId = "deferred-middle",
                text = "middle",
            },
            DeferredOwner {
                key = "owner",
                address = DeferredAddress,
            },
        }
    end)

-- Proves deferred views compact in place without disturbing order, refs, or
-- the last committed tree when a later deferred sibling rejects its candidate.
local function deferredCompactionAtomicity()
    local function assertNoDeferredMarker(node)
        assert(node._containsDeferred == nil
                and node.__frogDeferredView == nil,
            "committed tree retained deferred-resolution bookkeeping")
        for _, child in ipairs(node.children or {}) do
            assertNoDeferredMarker(child)
        end
        if node._dragPreview then
            assertNoDeferredMarker(node._dragPreview)
        end
    end

    local host = support.host { width = 120, height = 120 }
    local tree = support.mount(host, DeferredRoot { fail = false })
    assertNoDeferredMarker(tree)
    local handle = assert(deferredHandles[#deferredHandles])
    local kept = assert(support.find(tree, "deferred-kept"))
    assert(#tree.children == 3
            and tree.children[1] == kept
            and tree.children[2].props.testId == "deferred-middle"
            and tree.children[3].props.testId == "deferred-owner",
        "deferred view compaction changed order or retained a nil view")
    matches(handle, kept, "deferred compacted ref")
    local before = rectangleText(handle)

    rejects("failed deferred compaction", function()
        host:render(DeferredRoot { fail = true })
    end, "intentional deferred view failure")
    assert(host:tree() == tree and deferredHandles[#deferredHandles] == handle,
        "failed deferred compaction replaced committed tree/ref identity")
    assert(rectangleText(handle) == before,
        "failed deferred compaction changed committed ref geometry")

    local recovered = support.render(host, DeferredRoot { fail = false })
    assertNoDeferredMarker(recovered)
    local recoveredKept = assert(support.find(recovered, "deferred-kept"))
    assert(recoveredKept.identity == kept.identity
            and deferredHandles[#deferredHandles] == handle,
        "deferred compaction recovery changed stable identity")
    matches(handle, recoveredKept, "recovered deferred compacted ref")
    host:unmount()
end

-- Proves theme rollback follows publication, not merely the presence of a
-- terminal fault: rejected candidates keep the old theme, while a tree that
-- published before an after-commit fault keeps its matching new theme.
local function themePublicationBoundary()
    local oldTheme, rejectedTheme, publishedTheme = {}, {}, {}
    local ThemeCandidate = Frog.component(
        "RefCheckThemeCandidate", function(props)
            if props.fail then error("intentional theme candidate failure") end
            return Frog.Box { testId = "old-theme-tree", width = 20, height = 20 }
        end)
    local host = support.host {
        width = 540, height = 960, theme = oldTheme, assets = {},
    }
    host:mount(ThemeCandidate {})
    rejects("unpublished theme refresh", function()
        host:refreshTheme(rejectedTheme, {}, ThemeCandidate { fail = true })
    end, "intentional theme candidate failure")
    assert(host.theme == oldTheme and support.find(host:tree(), "old-theme-tree")
            and not host:inspectionTree().fault,
        "unpublished theme candidate did not restore the last good theme")
    host:unmount()

    local ThemeCleanup = Frog.component("RefCheckThemeCleanup", function()
        Frog.useResource(function()
            return {}, function()
                error("intentional theme candidate cleanup failure")
            end
        end)
        return Frog.Box { width = 10, height = 10 }
    end)
    local ThemeRenderFailure = Frog.component(
        "RefCheckThemeRenderFailure", function()
            error("intentional theme render failure")
        end)
    local ThemeCleanupCandidate = Frog.component(
        "RefCheckThemeCleanupCandidate", function()
            return Frog.Column { ThemeCleanup {}, ThemeRenderFailure {} }
        end)
    host = support.host {
        width = 540, height = 960, theme = oldTheme, assets = {},
    }
    host:mount(ThemeCandidate {})
    rejects("faulted unpublished theme refresh", function()
        host:refreshTheme(rejectedTheme, {}, ThemeCleanupCandidate {})
    end, "intentional theme candidate cleanup failure")
    assert(host.theme == oldTheme and support.find(host:tree(), "old-theme-tree")
            and host:inspectionTree().fault,
        "faulted unpublished theme candidate did not retain old tree/theme")
    host:unmount()

    host = support.host {
        width = 540, height = 960, theme = oldTheme, assets = {},
    }
    host:mount(Frog.Button {
        testId = "theme-refresh-hover",
        width = 80,
        height = 40,
        onPress = function() end,
        onHoverChange = function(hovered)
            if not hovered then error("intentional theme publication failure") end
        end,
        Frog.Text "Hover",
    })
    local x, y = support.center(assert(
        support.find(host:tree(), "theme-refresh-hover")))
    host:pointerMove(x, y, "mouse")
    rejects("post-publication theme refresh", function()
        host:refreshTheme(publishedTheme, {}, Frog.Box {
            testId = "new-theme-tree", width = 20, height = 20,
        })
    end, "intentional theme publication failure")
    assert(host.theme == publishedTheme
            and support.find(host:tree(), "new-theme-tree"),
        "faulted theme refresh restored old theme beneath its published tree")
    assert(host:inspectionTree().fault,
        "post-publication theme refresh failure did not fault the Host")
    host:unmount()
end

local faultRef
local faultHost

-- Commits changed geometry inside an input callback that then fails.
local FaultOwner = Frog.component("RefCheckFaultOwner", function(props)
    local handle = Frog.useRef()
    faultRef = handle
    return Frog.Column {
        width = props.expanded and 180 or 100,
        height = 90,
        Frog.Box {
            testId = "fault-ref",
            ref = handle,
            width = props.expanded and 160 or 60,
            height = 30,
        },
        Frog.Button {
            testId = "fault-button",
            width = 80,
            height = 40,
            onPress = props.onPress,
            Frog.Text "Fail",
        },
    }
end)

-- Proves a callback failure faults after a nested candidate has committed.
local function callbackFault()
    faultHost = support.host { width = 540, height = 960 }
    local onPress
    onPress = function()
        faultHost:render(FaultOwner {
            expanded = true,
            onPress = onPress,
        })
        assert(faultRef.current.width == 160,
            "nested render did not publish before callback completion")
        error("intentional outer callback failure")
    end
    faultHost:mount(FaultOwner { onPress = onPress })
    local handle = faultRef
    local button = assert(support.find(faultHost:tree(),
        "fault-button"))
    local x, y = support.center(button)
    assert(faultHost:pointerDown(x, y, "mouse", 1),
        "transaction button did not capture")
    rejects("outer callback ref fault", function()
        faultHost:pointerUp(x, y, "mouse", 1)
    end, "intentional outer callback failure")
    assert(faultHost:inspectionTree().fault,
        "outer callback failure did not fault the Host")
    assert(faultRef == handle,
        "nested commit replaced the retained ref handle")
    support.near(faultRef.current.width, 160,
        "faulted callback committed ref width")
    support.near(assert(support.find(faultHost:tree(),
        "fault-ref")).layout.width, 160, "faulted callback tree width")
    rejects("faulted ref Host mutation", function()
        faultHost:render(FaultOwner {
            expanded = false,
            onPress = onPress,
        })
    end, "FrogUI Host faulted")
    faultHost:unmount()
    assert(handle.current == nil,
        "faulted Host unmount did not clear its committed ref")
    faultHost = nil
end

local lifecycleRef

-- Removes one hovered control while retaining a separately anchored surface.
local HoverLifecycle = Frog.component("RefCheckHoverLifecycle", function(props)
    local handle = Frog.useRef()
    lifecycleRef = handle
    return Frog.Column {
        width = 180,
        height = 100,
        Frog.Box {
            testId = "lifecycle-anchor",
            ref = handle,
            width = props.anchorWidth,
            height = 30,
        },
        props.showHover and Frog.Button {
            testId = "lifecycle-hover",
            width = 80,
            height = 40,
            onPress = function() end,
            onHoverChange = props.onHoverChange,
            Frog.Text "Hover",
        } or nil,
    }
end)

-- Proves removed-hover callbacks see candidate refs and a nested render wins.
local function afterCommitRefOrdering()
    local host = support.host { width = 540, height = 960 }
    local nested = false
    local onHoverChange
    onHoverChange = function(hovered)
        if hovered then return end
        assert(lifecycleRef.current.width == 90,
            "removed-hover callback observed the previous ref rectangle")
        nested = true
        host:render(HoverLifecycle {
            anchorWidth = 130,
            showHover = false,
            onHoverChange = onHoverChange,
        })
    end
    host:mount(HoverLifecycle {
        anchorWidth = 50,
        showHover = true,
        onHoverChange = onHoverChange,
    })
    local hover = assert(support.find(host:tree(), "lifecycle-hover"))
    local x, y = support.center(hover)
    host:pointerMove(x, y, "mouse")
    host:render(HoverLifecycle {
        anchorWidth = 90,
        showHover = false,
        onHoverChange = onHoverChange,
    })
    assert(nested, "removed-hover callback did not run")
    assert(assert(support.find(host:tree(), "lifecycle-anchor")).layout.width == 130,
        "outer afterCommit overwrote its nested render tree")
    assert(lifecycleRef.current.width == 130,
        "outer afterCommit overwrote its nested render ref geometry")
    host:unmount()
end

local dragLifecycleRef

-- Opens a Modal during an active drag so afterCommit cancels its old session.
local DragLifecycle = Frog.component("RefCheckDragLifecycle", function(props)
    local handle = Frog.useRef()
    dragLifecycleRef = handle
    return Frog.Overlay {
        width = 240,
        height = 140,
        Frog.Box {
            testId = "drag-lifecycle-anchor",
            ref = handle,
            width = props.anchorWidth,
            height = 30,
        },
        Frog.DragSource {
            testId = "drag-lifecycle-source",
            payload = { kind = "ref-probe" },
            preview = Frog.Box { width = 30, height = 20 },
            onDrop = function() return false end,
            onDragEnd = props.onDragEnd,
            Frog.Box { width = 80, height = 50 },
        },
        props.modal and Frog.Modal {
            dismiss = "none",
            Frog.Box { width = 100, height = 80 },
        } or nil,
    }
end)

-- Proves drag-cancel lifecycle callbacks see the new committed ref geometry.
local function dragCancelRefOrdering()
    local observed
    local host = support.host { width = 540, height = 960 }
    local onDragEnd = function(status)
        observed = { status = status, width = dragLifecycleRef.current.width }
    end
    host:mount(DragLifecycle {
        anchorWidth = 40,
        modal = false,
        onDragEnd = onDragEnd,
    })
    local source = assert(support.find(host:tree(), "drag-lifecycle-source"))
    local x, y = support.center(source)
    host:pointerDown(x, y, "touch", 1)
    host:pointerMove(x + 20, y, "touch")
    assert(host:inspectionTree().interaction.session.claimed == "drag",
        "drag lifecycle probe did not claim its source")
    host:render(DragLifecycle {
        anchorWidth = 110,
        modal = true,
        onDragEnd = onDragEnd,
    })
    assert(observed and observed.status == "cancelled",
        "modal takeover did not cancel the active drag")
    assert(observed.width == 110,
        "drag-cancel callback observed the previous ref rectangle")
    host:unmount()
end

local scrollRefSnapshots = {}

-- Mounts two anchored descendants inside one retained vertical Scroll.
local ScrollRefs = Frog.component("RefCheckScrollRefs", function(props)
    local refs = Frog.useKeyedRefs({ "tracked", "focus" })
    scrollRefSnapshots[#scrollRefSnapshots + 1] = refs
    return Frog.Overlay {
        width = 180,
        height = 160,
        align = "start",
        justify = "start",
        Frog.Scroll {
            testId = "ref-scroll",
            axis = "vertical",
            width = 120,
            height = 100,
            snapInterval = props.snap and 50 or nil,
            onScrollEnd = props.onScrollEnd,
            Frog.Column {
                width = 120,
                Frog.Box {
                    testId = "scroll-tracked",
                    ref = refs.tracked,
                    width = 120,
                    height = 40,
                },
                Frog.Box { width = 120, height = 80 },
                Frog.Button {
                    testId = "scroll-focus",
                    ref = refs.focus,
                    width = 120,
                    height = 40,
                    onPress = function() end,
                    Frog.Text "Focus",
                },
                Frog.Box { width = 120, height = 80 },
            },
        },
        props.motionClock and Frog.Motion {
            width = 10,
            height = 10,
            juice = {
                probe = {
                    recipe = Frog.withClock(props.motionClock,
                        Frog.tween { to = { x = 1 }, duration = 1 }),
                    key = "running",
                },
            },
            Frog.Box { width = 10, height = 10 },
        } or nil,
    }
end)

-- Asserts that a retained ref follows its currently arranged Scroll node.
local function matchesScrollNode(host, handle, testId, label)
    local node = assert(support.find(host:tree(), testId))
    matches(handle, node, label)
end

-- Proves wheel, touch drag, momentum, and focus reveal republish refs.
local function retainedScrollGeometry()
    local host = support.host { width = 540, height = 960 }
    host:mount(ScrollRefs {})
    local refs = scrollRefSnapshots[#scrollRefSnapshots]
    local tracked, focus = refs.tracked, refs.focus
    local initialY = tracked.current.y
    local scroll = assert(support.find(host:tree(), "ref-scroll"))
    local x, y = support.center(scroll)

    host:pointerMove(x, y, "mouse")
    host:wheelMoved(0, -1)
    assert(scrollRefSnapshots[#scrollRefSnapshots].tracked == tracked,
        "wheel input replaced a retained ref handle")
    assert(tracked.current.y < initialY,
        "wheel input did not move committed descendant geometry")
    matchesScrollNode(host, tracked, "scroll-tracked", "wheel ref")

    local beforeDrag = tracked.current.y
    host:pointerDown(x, y, "touch", 1)
    host:pointerMove(x, y - 20, "touch")
    host:pointerMove(x, y - 45, "touch")
    assert(host:inspectionTree().interaction.session.claimed == "scroll",
        "ref Scroll probe did not claim touch movement")
    assert(tracked.current.y < beforeDrag,
        "touch Scroll drag did not republish descendant refs")
    matchesScrollNode(host, tracked, "scroll-tracked", "drag ref")
    host:pointerUp(x, y - 45, "touch", 1)

    local beforeMomentum = tracked.current.y
    host:update(0.02)
    assert(tracked.current.y <= beforeMomentum,
        "Scroll momentum moved opposite its retained velocity")
    matchesScrollNode(host, tracked, "scroll-tracked", "momentum ref")
    host:unmount()

    host = support.host { width = 540, height = 960 }
    host:mount(ScrollRefs {})
    refs = scrollRefSnapshots[#scrollRefSnapshots]
    focus = refs.focus
    local beforeFocus = focus.current.y
    host:keyDown("tab", "tab", false)
    assert(host:inspectionTree().interaction.focused ~= nil,
        "Tab did not focus the Scroll descendant")
    assert(focus.current.y < beforeFocus,
        "focus reveal did not republish Scroll descendant refs")
    matchesScrollNode(host, focus, "scroll-focus", "focus reveal ref")
    host:unmount()
end

-- Proves snap publication happens before the terminal Scroll callback.
local function scrollSnapOrdering()
    local observed
    local host = support.host { width = 540, height = 960 }
    host:mount(ScrollRefs {
        snap = true,
        onScrollEnd = function(position)
            local refs = scrollRefSnapshots[#scrollRefSnapshots]
            observed = {
                position = position,
                y = refs.tracked.current.y,
                nodeY = assert(support.find(host:tree(), "scroll-tracked")).layout.y,
            }
        end,
    })
    local scroll = assert(support.find(host:tree(), "ref-scroll"))
    local x, y = support.center(scroll)
    host:pointerDown(x, y, "touch", 1)
    host:pointerMove(x, y - 72, "touch")
    host:pointerUp(x, y - 72, "touch", 1)
    assert(observed, "snapped Scroll did not invoke onScrollEnd")
    assert(observed.position % 50 == 0,
        "Scroll release did not apply its snap interval")
    support.near(observed.y, observed.nodeY,
        "snap callback committed ref ordering")
    host:unmount()
end

-- Proves a later Motion failure faults after retained Scroll work may advance.
local function scrollUpdateFault()
    local clock = Frog.clock()
    local host = support.host { width = 540, height = 960 }
    host:mount(ScrollRefs { motionClock = clock })
    local tracked = scrollRefSnapshots[#scrollRefSnapshots].tracked
    local scroll = assert(support.find(host:tree(), "ref-scroll"))
    local x, y = support.center(scroll)
    host:pointerDown(x, y, "touch", 1)
    host:pointerMove(x, y - 25, "touch")
    host:pointerUp(x, y - 25, "touch", 1)
    clock.now = function() error("intentional post-scroll Motion failure") end
    rejects("Scroll update ref fault", function()
        host:update(0.05)
    end, "intentional post-scroll Motion failure")
    clock.now = nil
    assert(host:inspectionTree().fault,
        "failed Motion update did not fault the Host")
    assert(tracked.current,
        "faulted update discarded the last published Scroll ref")
    rejects("faulted Scroll Host update", function()
        host:update(0.01)
    end, "FrogUI Host faulted")
    rejects("faulted Scroll Host input", function()
        host:pointerDown(x, y, "touch", 1)
    end, "FrogUI Host faulted")
    host:unmount()
    assert(tracked.current == nil,
        "faulted Scroll Host unmount did not clear its ref")
end

-- Gives two same-kind hooks distinct call sites for reorder detection.
local function firstOrderedRef()
    return Frog.useRef()
end

-- Gives the second same-kind hook its own distinct call site.
local function secondOrderedRef()
    return Frog.useRef()
end

local ConditionalHooks = Frog.component("RefCheckConditionalHooks", function(props)
    local first = Frog.useRef()
    if props.extra then Frog.useRef() end
    return Frog.Box { ref = first, width = 20, height = 20 }
end)

local KindHooks = Frog.component("RefCheckKindHooks", function(props)
    local handle
    if props.keyed then handle = Frog.useKeyedRefs({ "one" }).one
    else handle = Frog.useRef() end
    return Frog.Box { ref = handle, width = 20, height = 20 }
end)

local OrderedHooks = Frog.component("RefCheckOrderedHooks", function(props)
    local first, second
    if props.reverse then
        second = secondOrderedRef()
        first = firstOrderedRef()
    else
        first = firstOrderedRef()
        second = secondOrderedRef()
    end
    return Frog.Row {
        Frog.Box { ref = first, width = 20, height = 20 },
        Frog.Box { ref = second, width = 20, height = 20 },
    }
end)

-- Proves conditional, kind, and same-callback order changes fail loudly.
local function hookOrderContracts()
    local host = support.host { width = 100, height = 100 }
    host:mount(ConditionalHooks {})
    rejects("conditional hook addition", function()
        host:render(ConditionalHooks { extra = true })
    end, "changed its hook count")
    host:unmount()

    host = support.host { width = 100, height = 100 }
    host:mount(KindHooks {})
    rejects("hook kind replacement", function()
        host:render(KindHooks { keyed = true })
    end, "changed hook 1 from useRef to useKeyedRefs")
    host:unmount()

    host = support.host { width = 100, height = 100 }
    host:mount(OrderedHooks {})
    rejects("same-kind hook reorder", function()
        host:render(OrderedHooks { reverse = true })
    end, "reordered hook 1")
    host:unmount()
end

local hotReloadHandles = {}

local HotReloadOwner = Frog.component("RefCheckHotReloadOwner", function()
    local handle = Frog.useRef()
    hotReloadHandles[#hotReloadHandles + 1] = handle
    return Frog.Box { ref = handle, width = 30, height = 20 }
end)

-- Proves a replaced hot-reload callback refreshes sites but not kind/count.
local function hotReloadHookContract()
    local host = support.host { width = 100, height = 100 }
    host:mount(HotReloadOwner {})
    local retained = hotReloadHandles[#hotReloadHandles]
    HotReloadOwner.render = function()
        local handle = Frog.useRef()
        hotReloadHandles[#hotReloadHandles + 1] = handle
        return Frog.Box { ref = handle, width = 45, height = 20 }
    end
    host:render(HotReloadOwner {})
    assert(hotReloadHandles[#hotReloadHandles] == retained,
        "hot-reloaded callback replaced a compatible hook handle")
    support.near(retained.current.width, 45, "hot-reloaded ref width")

    HotReloadOwner.render = function()
        local first = Frog.useRef()
        local second = Frog.useRef()
        return Frog.Row {
            Frog.Box { ref = first, width = 20, height = 20 },
            Frog.Box { ref = second, width = 20, height = 20 },
        }
    end
    rejects("hot-reload hook count change", function()
        host:render(HotReloadOwner {})
    end, "changed its hook count")
    assert(retained.current.width == 45,
        "failed hot-reload hook edit changed committed geometry")
    host:unmount()
end

-- Proves malformed APIs and ambiguous attachments reject before commit.
local function validationContracts()
    rejects("useRef outside render", function()
        Frog.useRef()
    end, "may only run while a component, actor, or view renders")
    rejects("useKeyedRefs outside render", function()
        Frog.useKeyedRefs({ "a" })
    end, "may only run while a component, actor, or view renders")

    local function rejectsKeys(name, keys, fragment)
        local Owner = Frog.component("RefCheckBadKeys" .. name, function()
            Frog.useKeyedRefs(keys)
            return Frog.Box {}
        end)
        rejects(name, function()
            support.host { width = 100, height = 100 }:mount(Owner {})
        end, fragment)
    end
    rejectsKeys("Duplicate", { "a", "a" }, "duplicate key a")
    rejectsKeys("NonScalar", { {} }, "must be a scalar")
    rejectsKeys("Sparse", { [1] = "a", [3] = "c" }, "plain dense array")
    rejectsKeys("Named", { "a", extra = true }, "plain dense array")
    rejectsKeys("NonFinite", { math.huge }, "must be finite")

    local DuplicateAttachment = Frog.component(
        "RefCheckDuplicateAttachment", function()
            local handle = Frog.useRef()
            return Frog.Row {
                Frog.Box { ref = handle, width = 20, height = 20 },
                Frog.Box { ref = handle, width = 20, height = 20 },
            }
        end)
    rejects("duplicate ref attachment", function()
        support.host { width = 100, height = 100 }:mount(DuplicateAttachment {})
    end, "attached to more than one primitive")

    local SemanticChild = Frog.component("RefCheckSemanticChild", function()
        return Frog.Box { width = 20, height = 20 }
    end)
    local ComponentParent = Frog.component(
        "RefCheckSemanticComponentParent", function()
            local handle = Frog.useRef()
            return SemanticChild { ref = handle }
        end)
    rejects("component ref attachment", function()
        support.host { width = 100, height = 100 }:mount(ComponentParent {})
    end, "semantic component")

    local SemanticActor = Frog.actor("RefCheckSemanticActor", {
        initial = "ready",
        render = function() return Frog.Box { width = 20, height = 20 } end,
    })
    local ActorParent = Frog.component(
        "RefCheckSemanticActorParent", function()
            local handle = Frog.useRef()
            return SemanticActor { ref = handle }
        end)
    rejects("actor ref attachment", function()
        support.host { width = 100, height = 100 }:mount(ActorParent {})
    end, "semantic actor")

    local ViewAddress = SemanticActor:address("RefCheckSemanticViewAddress")
    local SemanticView = SemanticActor:view("RefCheckSemanticView", function()
        return Frog.Box { width = 20, height = 20 }
    end)
    local ViewParent = Frog.component("RefCheckSemanticViewParent", function()
        local handle = Frog.useRef()
        return Frog.Overlay {
            SemanticActor { address = ViewAddress },
            SemanticView { target = ViewAddress, ref = handle },
        }
    end)
    rejects("view ref attachment", function()
        support.host { width = 100, height = 100 }:mount(ViewParent {})
    end, "semantic view")
end

-- Proves hooks are also owned correctly by semantic actor renders.
local function actorOwnerContract()
    local actorHandles = {}
    local Owner = Frog.actor("RefCheckActorOwner", {
        initial = "ready",
        render = function()
            local handle = Frog.useRef()
            actorHandles[#actorHandles + 1] = handle
            return Frog.Box { ref = handle, width = 40, height = 25 }
        end,
    })
    local host = support.host { width = 100, height = 100 }
    host:mount(Owner {})
    local retained = actorHandles[#actorHandles]
    host:render(Owner {})
    assert(actorHandles[#actorHandles] == retained,
        "actor rerender replaced its retained hook")
    host:resize(200, 100)
    assert(actorHandles[#actorHandles] == retained,
        "actor resize replaced its retained hook")
    host:unmount()
    assert(retained.current == nil, "actor unmount did not clear its ref")
end

function check.run()
    basicLifecycle()
    motionRestGeometry()
    keyedLifecycle()
    candidateAtomicity()
    deferredCompactionAtomicity()
    themePublicationBoundary()
    callbackFault()
    afterCommitRefOrdering()
    dragCancelRefOrdering()
    retainedScrollGeometry()
    scrollSnapOrdering()
    scrollUpdateFault()
    hookOrderContracts()
    hotReloadHookContract()
    validationContracts()
    actorOwnerContract()
end

return check
