-- Boots the compact gallery through the same one-Host callback boundary.

local Frog = require("frogui")
local Theme = require("examples.gallery.theme")
local Gallery = require("examples.gallery.components.gallery")

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
    }
    host:mount(Gallery {})
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
