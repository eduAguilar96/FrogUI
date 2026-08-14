-- Presents a compact, responsive sampling of ordinary FrogUI composition.

local Frog = require("frogui")

local ToggleDetails = Frog.action("Gallery.ToggleDetails")

-- Owns the optional details modal rather than leaking its state into App.
local Details = Frog.actor("GalleryDetails", {
    initial = "closed",
    actions = {
        [ToggleDetails] = { closed = "open", open = "closed" },
    },
    render = function(_, state, send)
        if state == "closed" then return nil end
        local close = function() send(ToggleDetails {}) end
        return Frog.Modal {
            dismiss = "both",
            onDismiss = close,
            background = "scrim",
            align = "center",
            justify = "center",
            Frog.Box {
                width = 340,
                height = 220,
                padding = 24,
                background = "panelRaised",
                border = "accent",
                borderWidth = 2,
                radius = 18,
                Frog.Column {
                    gap = 18,
                    align = "center",
                    Frog.Text { role = "heading", "A real Modal" },
                    Frog.Text {
                        role = "caption",
                        color = "muted",
                        align = "center",
                        "Focus, dismissal, and input isolation belong to the primitive.",
                    },
                    Frog.Button {
                        width = 120,
                        height = 44,
                        onPress = close,
                        Frog.Text "Close",
                    },
                },
            },
        }
    end,
})

Details.App = Details:address("gallery-details")

-- Draws one named sample card used by both portrait and wide layouts.
local function SampleCard(title, body, color)
    return Frog.Box {
        width = 230,
        height = 128,
        padding = 16,
        background = "panel",
        border = color,
        borderWidth = 2,
        radius = 14,
        Frog.Column {
            gap = 8,
            Frog.Text { role = "body", color = color, title },
            Frog.Text { role = "caption", color = "muted", body },
        },
    }
end

local Gallery = Frog.component("PrimitiveGallery", function()
    local viewport = Frog.useViewport()
    local samples = {
        SampleCard("Components", "Small named render owners compose primitives.", "accent"),
        SampleCard("Actors", "Semantic state changes through typed actions.", "warm"),
        SampleCard("Layout", "The same tree responds to virtual viewport shape.", "accent"),
    }
    local cards
    if viewport.wide then
        cards = Frog.Row { gap = 14, unpack(samples) }
    else
        cards = Frog.Column { gap = 14, unpack(samples) }
    end
    return Frog.Overlay {
        width = "100%",
        height = "100%",
        Frog.Box {
            width = "100%",
            height = "100%",
            padding = 28,
            background = "background",
            align = "center",
            justify = "center",
            Frog.Column {
                gap = 20,
                align = "center",
                Frog.Text { role = "heading", "FrogUI gallery" },
                cards,
                Frog.Button {
                    width = 190,
                    height = 50,
                    onPress = function()
                        Frog.send(Details.App, ToggleDetails {})
                    end,
                    Frog.Text "Open details",
                },
            },
        },
        Details { address = Details.App },
    }
end)

return Gallery
