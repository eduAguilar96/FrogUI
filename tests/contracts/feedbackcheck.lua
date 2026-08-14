-- Generic semantic-feedback checks using only injected cue logs; physical
-- audio catalogs and shipped-game parity remain consumer integration tests.

local Frog = require("frogui")
local support = require("tests.support")

local check = {}

local THEME = {
    sounds = {
        activate = "ui.activate",
        hover = "ui.hover",
        reject = "ui.reject",
        dismiss = "ui.close",
        dragGrab = "drag.grab",
        dragDrop = "drag.drop",
    },
}

-- Returns one semantic feedback provider and its ordered cue receipt list.
local function cueLog()
    local cues = {}
    return cues, {
        sound = function(cue) cues[#cues + 1] = cue end,
    }
end

-- Compares one exact feedback sequence without knowing physical sound files.
local function assertCues(actual, expected, label)
    assert(#actual == #expected,
        label .. " cue count: expected " .. #expected .. ", got " .. #actual)
    for index, cue in ipairs(expected) do
        assert(actual[index] == cue,
            label .. " cue " .. index .. ": expected " .. cue
                .. ", got " .. tostring(actual[index]))
    end
end

-- Confirms a callback/provider failure terminally faults its owning Host.
local function expectFault(host, retry, label)
    local fault = host:inspectionTree().fault
    assert(fault and fault.origin:find("Button:", 1, true),
        label .. " did not record its terminal Host fault")
    local ok, reason = pcall(retry)
    assert(not ok and tostring(reason):find("FrogUI Host faulted", 1, true),
        label .. " allowed input after its terminal Host fault")
end

-- Proves default, override, disable, reject, and callback-fault feedback.
local function buttonContract()
    local cues, feedback = cueLog()
    local throwCalls, cleanups = 0, 0
    local ButtonSoundOwner = Frog.component(
        "FeedbackCheckButtonSoundOwner", function()
            Frog.useResource(function()
                return {}, function() cleanups = cleanups + 1 end
            end)
            return Frog.Column {
                Frog.Button {
                    testId = "default-button", shortcut = "a",
                    onPress = function() end,
                    Frog.Text "Default",
                },
                Frog.Button {
                    testId = "custom-button", shortcut = "b",
                    sound = "ui.open", hoverSound = false,
                    onPress = function() end,
                    Frog.Text "Custom",
                },
                Frog.Button {
                    testId = "reject-button", shortcut = "r",
                    onCommit = function() return false, "no" end,
                    onResult = function() end,
                    Frog.Text "Reject",
                },
                Frog.Button {
                    testId = "throw-button", shortcut = "t",
                    onPress = function()
                        throwCalls = throwCalls + 1
                        error("intentional feedback callback failure")
                    end,
                    Frog.Text "Throw",
                },
            }
        end)
    local host = support.host {
        width = 540, height = 960, theme = THEME, feedback = feedback,
    }
    host:mount(ButtonSoundOwner {})

    local x, y = support.center(assert(
        support.find(host:tree(), "default-button")))
    host:pointerMove(x, y, "mouse")
    assert(host:keyDown("a", nil, false))
    assert(host:keyDown("b", nil, false))
    assert(host:keyDown("r", nil, false))
    local ok = pcall(function() host:keyDown("t", nil, false) end)
    assert(not ok and throwCalls == 1,
        "throwing Button unexpectedly succeeded or retried")
    assertCues(cues, {
        "ui.hover", "ui.activate", "ui.open", "ui.reject",
    }, "Button feedback")
    expectFault(host, function() host:keyDown("t", nil, false) end,
        "throwing Button feedback transaction")
    assert(throwCalls == 1, "faulted Button retried its callback")
    host:unmount()
    assert(cleanups == 1,
        "faulted feedback Host did not clean its resource exactly once")

    local invalid = support.host { width = 540, height = 960, theme = THEME }
    local invalidOk, invalidError = pcall(function()
        invalid:mount(Frog.Button {
            sound = true, onPress = function() end, Frog.Text "Bad",
        })
    end)
    if invalidOk then invalid:unmount() end
    assert(not invalidOk and tostring(invalidError):find(
            "non-empty cue id or false", 1, true),
        "invalid feedback override did not fail clearly")

    local themeOk, themeError = pcall(function()
        support.host { width = 540, height = 960,
            theme = { sounds = "not-a-table" } }
    end)
    assert(not themeOk and tostring(themeError):find(
            "theme.sounds must be a plain", 1, true),
        "malformed theme feedback defaults did not fail clearly")
end

-- Proves an injected platform-provider failure cannot replay its cue.
local function providerFaultContract()
    local feedbackCalls = 0
    local host = support.host {
        width = 540,
        height = 960,
        theme = THEME,
        feedback = {
            sound = function()
                feedbackCalls = feedbackCalls + 1
                error("intentional feedback provider failure")
            end,
        },
    }
    host:mount(Frog.Button {
        shortcut = "f",
        onPress = function() end,
        Frog.Text "Fault provider",
    })
    local ok, reason = pcall(function() host:keyDown("f", nil, false) end)
    assert(not ok and tostring(reason):find(
            "intentional feedback provider failure", 1, true)
            and feedbackCalls == 1,
        "feedback provider failure was hidden or replayed")
    expectFault(host, function() host:keyDown("f", nil, false) end,
        "failing feedback provider")
    assert(feedbackCalls == 1,
        "faulted feedback provider replayed its cue")
    host:unmount()
end

-- Builds a compact drag surface for accepted and rejected drop feedback.
local function DragTree(commit)
    return Frog.Row {
        width = 320,
        height = 100,
        gap = 80,
        Frog.DragSource {
            testId = "feedback-drag-source",
            payload = { kind = "feedback-probe" },
            preview = Frog.Box { width = 40, height = 30 },
            onDrop = function() return commit, commit and "ok" or "no" end,
            Frog.Box { width = 100, height = 70 },
        },
        Frog.DropTarget {
            key = "feedback-target",
            testId = "feedback-drag-target",
            accepts = "feedback-probe",
            address = { kind = "probe" },
            Frog.Box { width = 100, height = 70 },
        },
    }
end

-- Proves drag claim/result and modal dismissal share one semantic provider.
local function dragAndModalContract()
    for _, probe in ipairs({
        { commit = true, result = "drag.drop" },
        { commit = false, result = "ui.reject" },
    }) do
        local cues, feedback = cueLog()
        local host = support.host {
            width = 540, height = 960, theme = THEME, feedback = feedback,
        }
        host:mount(DragTree(probe.commit))
        local sx, sy = support.center(assert(
            support.find(host:tree(), "feedback-drag-source")))
        local tx, ty = support.center(assert(
            support.find(host:tree(), "feedback-drag-target")))
        host:pointerDown(sx, sy, "touch", 1)
        host:pointerMove(sx + 20, sy, "touch")
        host:pointerMove(tx, ty, "touch")
        host:pointerUp(tx, ty, "touch", 1)
        assertCues(cues, { "drag.grab", probe.result },
            "DragSource feedback")
        host:unmount()
    end

    local cues, feedback = cueLog()
    local host = support.host {
        width = 540, height = 960, theme = THEME, feedback = feedback,
    }
    host:mount(Frog.Modal {
        dismiss = "back",
        onDismiss = function() end,
        Frog.Box { width = 100, height = 80 },
    })
    assert(host:keyDown("escape", nil, false))
    assertCues(cues, { "ui.close" }, "Modal dismiss feedback")
    host:unmount()
end

function check.run()
    buttonContract()
    providerFaultContract()
    dragAndModalContract()
end

return check
