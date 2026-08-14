-- Selects one explicit standalone contract group from the LÖVE command line.

local Runner = require("tests.runner")

local main = {}

local function selectedMode(arguments)
    local mode
    for _, value in ipairs(arguments) do
        if value == "--headless" or value == "--graphical" then
            assert(mode == nil, "choose exactly one FrogUI test mode")
            mode = value:sub(3)
        end
    end
    assert(mode, "usage: love . --headless | love . --graphical")
    return mode
end

function main.run(arguments)
    return Runner.run(selectedMode(arguments))
end

return main
