-- Runs the nested-install proof without a drawable or consumer assets.

function love.conf(t)
    t.identity = "frogui-nested-consumer-check"
    t.version = "11.5"
    t.console = true
    t.window = false
    t.modules.graphics = false
    t.modules.image = false
end
