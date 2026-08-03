-- Public FrogUI vocabulary. Application code imports this one module to define
-- primitives, components, actors, messages, and the single Host.

local Element = require("src.frogui.element")
local Host = require("src.frogui.host")
local Message = require("src.frogui.message")
local Clock = require("src.frogui.clock")
local Juice = require("src.frogui.juice")

local Frog = {}

-- Primitives are FrogUI's built-in layout/paint vocabulary. Calling one
-- creates a description; the Host later measures, paints, and routes it.
Frog.Box = Element.primitive("Box")
Frog.Row = Element.primitive("Row")
Frog.Column = Element.primitive("Column")
Frog.Overlay = Element.primitive("Overlay")
Frog.Text = Element.primitive("Text")
Frog.Image = Element.primitive("Image")
Frog.Icon = Element.primitive("Icon")
Frog.Button = Element.primitive("Button")
Frog.Motion = Element.primitive("Motion")

-- component(name, render) defines a reusable stateless application concept.
-- Calling the returned token also creates a description; during Host render,
-- its render(props) function expands that description into primitives and
-- other components. See src/frogui/README.md for the complete reading model.
Frog.component = Element.component
Frog.each = Element.each
Frog.actor = Message.actor
Frog.action = Message.action
Frog.event = Message.event
Frog.on = Message.on
Frog.go = Message.go
Frog.prop = Message.prop
Frog.oneOf = Message.oneOf
Frog.send = Host.send
Frog.emit = Host.emit

-- Juice recipes are inert data. Named element bindings and typed event
-- reactions decide when the Host plays them.
Frog.tween = Juice.tween
Frog.spring = Juice.spring
Frog.shake = Juice.shake
Frog.sound = Juice.sound
Frog.haptic = Juice.haptic
Frog.delay = Juice.delay
Frog.sequence = Juice.sequence
Frog.parallel = Juice.parallel
Frog.loop = Juice.loop
Frog.withClock = Juice.withClock
Frog.play = Juice.play
Frog.clock = Clock.new

function Frog.host(options)
    return Host.new(options)
end

function Frog.useViewport()
    return Host.currentViewport()
end

return Frog
