-- Defines an application component in a path containing "frogui" while
-- remaining outside the exact vendor/frogui/frogui package root.

local Frog = require("frogui")

local Probe = Frog.component("NestedConsumerProbe", function()
    return Frog.Box { testId = "nested-consumer-probe" }
end)

return Probe
