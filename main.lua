-- Runs the standalone test suite selected by --headless or --graphical.

local activeExample

local function requestedExample(arguments)
    for index, value in ipairs(arguments) do
        if value == "--example" then
            local name = assert(arguments[index + 1],
                "--example requires hello or gallery")
            assert(name == "hello" or name == "gallery",
                "unknown FrogUI example " .. tostring(name))
            return require("examples." .. name .. ".main")
        end
    end
end

function love.load(arguments)
    activeExample = requestedExample(arguments or arg or {})
    if activeExample then
        if activeExample.load then activeExample.load(arguments) end
        return
    end
    local Tests = require("tests.main")
    local ok, reason = xpcall(function()
        Tests.run(arguments or arg or {})
    end, debug.traceback)
    if not ok then
        io.stderr:write(reason .. "\n")
        love.event.quit(1)
        return
    end
    love.event.quit(0)
end


function love.update(dt)
    if activeExample and activeExample.update then activeExample.update(dt) end
end

function love.draw()
    if activeExample and activeExample.draw then activeExample.draw() end
end

function love.resize(width, height)
    if activeExample and activeExample.resize then
        activeExample.resize(width, height)
    end
end

for _, callback in ipairs {
    "mousepressed", "mousemoved", "mousereleased",
    "touchpressed", "touchmoved", "touchreleased",
    "keypressed", "keyreleased", "textinput", "wheelmoved",
} do
    love[callback] = function(...)
        if activeExample and activeExample[callback] then
            return activeExample[callback](...)
        end
    end
end
