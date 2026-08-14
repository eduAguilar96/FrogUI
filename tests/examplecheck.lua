-- Boots each shipped example with the default painter at portrait and wide
-- dimensions so documentation never points at an unexecutable application.

local Frog = require("frogui")

local check = {}

local examples = {
    {
        name = "hello",
        component = require("examples.hello.components.app"),
        theme = require("examples.hello.theme"),
    },
    {
        name = "gallery",
        component = require("examples.gallery.components.gallery"),
        theme = require("examples.gallery.theme"),
    },
}

function check.run()
    for _, example in ipairs(examples) do
        local host = Frog.host {
            width = 540,
            height = 960,
            designWidth = 540,
            designHeight = 960,
            theme = example.theme,
        }
        host:mount(example.component {})
        host:update(1 / 60)
        host:draw()
        host:resize(960, 540)
        assert(host:viewport().wide,
            example.name .. " did not enter its wide composition")
        host:update(1 / 60)
        host:draw()
        host:unmount()
    end
    return true
end

return check
