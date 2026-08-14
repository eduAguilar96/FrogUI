-- Boots the hello component tree and forwards LÖVE callbacks to one Host.

local Frog = require("frogui")
local Theme = require("examples.hello.theme")
local App = require("examples.hello.components.app")

local example = {}
local host

function example.load()
    local width, height = love.graphics.getDimensions()
    host = Frog.host {
        width = width,
        height = height,
        designWidth = 540,
        designHeight = 960,
        theme = Theme,
        feedback = {
            sound = function(cue) print("sound:", cue) end,
            haptic = function(cue) print("haptic:", cue) end,
        },
    }
    host:mount(App {})
end

function example.update(dt) host:update(dt) end
function example.draw() host:draw() end
function example.resize(width, height) host:resize(width, height) end

for _, callback in ipairs {
    "mousepressed", "mousemoved", "mousereleased",
    "touchpressed", "touchmoved", "touchreleased",
    "keypressed", "keyreleased", "textinput", "wheelmoved",
} do
    example[callback] = function(...)
        return host[callback](host, ...)
    end
end

return example
