-- Proves an application folder containing "frogui" is not mistaken for the
-- exact loaded framework package root by definition provenance.

local Frog = require("frogui")

return function()
    -- Keep this frame visible to debug.getinfo; a tail return would erase the
    -- application call site before FrogUI captures definition provenance.
    local description = Frog.Box { testId = "unrelated-frogui-source" }
    return description
end
