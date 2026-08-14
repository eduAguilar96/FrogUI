-- Configures the standalone test launcher. Graphical contracts use a hidden
-- drawable; headless contracts disable the window and graphics module.

local function hasArgument(name)
    for _, value in ipairs(arg or {}) do
        if value == name then return true end
    end
    return false
end

local function hasExample()
    for index, value in ipairs(arg or {}) do
        if value == "--example" and type(arg[index + 1]) == "string" then
            return true
        end
    end
    return false
end

function love.conf(t)
    t.identity = "frogui-tests"
    t.version = "11.5"
    t.console = true
    t.window.title = "FrogUI contracts"
    t.window.width = 540
    t.window.height = 960
    t.window.visible = hasExample()
    if hasArgument("--headless") then
        t.window = false
        t.modules.graphics = false
        t.modules.image = false
    end
end
