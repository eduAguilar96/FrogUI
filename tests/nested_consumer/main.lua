-- Proves one consumer loads only the public namespace from a nested vendor
-- checkout and retains its own readable definition provenance.

package.path = table.concat({
    "vendor/frogui/?.lua",
    "vendor/frogui/?/init.lua",
    package.path,
}, ";")

local Frog = require("frogui")
local Probe = require("frogui_feature.probe")

function love.load()
    local host = Frog.host {
        width = 540,
        height = 960,
        designWidth = 540,
        designHeight = 960,
    }
    host:mount(Probe {})
    -- This fixture intentionally uses the internal test seam. Consumers do not
    -- receive the mutable committed tree from mount/render.
    local tree = assert(host:tree())
    assert(tree.source
            and tree.source.path:find("frogui_feature/probe.lua", 1, true),
        "nested install hid application provenance")
    assert(package.loaded.frogui == Frog,
        "public root namespace did not load exactly once")
    assert(package.loaded["src" .. ".frogui"] == nil,
        "legacy embedded namespace also loaded")
    host:unmount()
    print("FrogUI nested consumer OK: " .. Frog.VERSION)
    love.event.quit(0)
end
