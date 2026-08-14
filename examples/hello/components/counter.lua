-- Demonstrates one small actor that reacts to both a local action and a
-- broadcast application event without moving state into the root component.

local Frog = require("frogui")

local Increment = Frog.action("HelloCounter.Increment")
local ResetRequested = Frog.event("hello.reset")

local Counter = Frog.actor("HelloCounter", {
    initial = 0,
    actions = {
        [Increment] = function(count) return count + 1 end,
    },
    reactions = {
        Frog.on(ResetRequested) { transition = Frog.go(0) },
    },
    render = function(_, count, send)
        return Frog.Column {
            gap = 14,
            align = "center",
            Frog.Text { role = "heading", tostring(count) },
            Frog.Button {
                width = 180,
                height = 56,
                background = "panel",
                border = "accent",
                borderWidth = 2,
                radius = 12,
                onPress = function() send(Increment {}) end,
                Frog.Text { role = "body", "Add one" },
            },
        }
    end,
})

Counter.App = Counter:address("hello-counter")
Counter.ResetRequested = ResetRequested

return Counter
