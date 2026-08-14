-- Composes the complete hello screen from a readable nested component tree.

local Frog = require("frogui")
local Counter = require("examples.hello.components.counter")

local App = Frog.component("HelloApp", function()
    local viewport = Frog.useViewport()
    return Frog.Box {
        width = "100%",
        height = "100%",
        padding = 28,
        background = "background",
        align = "center",
        justify = "center",
        Frog.Column {
            width = viewport.wide and 520 or "100%",
            gap = 18,
            align = "center",
            Frog.Text { role = "heading", "FrogUI" },
            Frog.Text {
                role = "caption",
                color = "muted",
                align = "center",
                "One Host. Small components. Explicit state.",
            },
            Counter { address = Counter.App },
            Frog.Button {
                width = 180,
                height = 48,
                onPress = function()
                    Frog.emit(Counter.ResetRequested {})
                end,
                Frog.Text { role = "body", "Reset by event" },
            },
        },
    }
end)

return App
