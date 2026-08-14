-- Pins the release payload and rejects legacy/consumer namespaces before any
-- archive or consumer is allowed to call this revision standalone.

local check = {}

local RUNTIME_FILES = {
    "frogui/actor_local.lua",
    "frogui/canvas.lua",
    "frogui/clock.lua",
    "frogui/diagnostic_comparison.lua",
    "frogui/diagnostics.lua",
    "frogui/effects/effect_layer.lua",
    "frogui/effects/flipbook.lua",
    "frogui/effects/particle_burst.lua",
    "frogui/effects/popup_text.lua",
    "frogui/effects/projectile.lua",
    "frogui/effects/runtime.lua",
    "frogui/element.lua",
    "frogui/host.lua",
    "frogui/init.lua",
    "frogui/interaction.lua",
    "frogui/juice.lua",
    "frogui/layout.lua",
    "frogui/message.lua",
    "frogui/motion.lua",
    "frogui/painter.lua",
    "frogui/ref.lua",
    "frogui/render_replay_oracle.lua",
    "frogui/shader.lua",
    "frogui/version.lua",
    "frogui/viewport.lua",
}

local TEST_FILES = {
    "tests/boundarycheck.lua",
    "tests/contracts/actoridentitycheck.lua",
    "tests/contracts/actorlocalcheck.lua",
    "tests/contracts/apicheck.lua",
    "tests/contracts/canvascheck.lua",
    "tests/contracts/diagnosticscheck.lua",
    "tests/contracts/effectcheck.lua",
    "tests/contracts/eventordercheck.lua",
    "tests/contracts/feedbackcheck.lua",
    "tests/contracts/inputcheck.lua",
    "tests/contracts/interactioncheck.lua",
    "tests/contracts/layoutcheck.lua",
    "tests/contracts/motioncheck.lua",
    "tests/contracts/paintercheck.lua",
    "tests/contracts/parsingcheck.lua",
    "tests/contracts/particleburstcheck.lua",
    "tests/contracts/processcheck.lua",
    "tests/contracts/radialdialcheck.lua",
    "tests/contracts/refcheck.lua",
    "tests/contracts/renderreplaycensuscheck.lua",
    "tests/contracts/runtimecontractcheck.lua",
    "tests/contracts/spritesheetcheck.lua",
    "tests/contracts/swipecheck.lua",
    "tests/contracts/travelcheck.lua",
    "tests/contracts/worldcheck.lua",
    "tests/examplecheck.lua",
    "tests/frogui_feature/probe.lua",
    "tests/main.lua",
    "tests/nested_consumer/conf.lua",
    "tests/nested_consumer/frogui_feature/probe.lua",
    "tests/nested_consumer/main.lua",
    "tests/runner.lua",
    "tests/support.lua",
}

local FORBIDDEN_REFERENCES = {
    { "legacy source directory", "src" .. "/frogui" },
    { "legacy module namespace", "src" .. ".frogui" },
    { "consumer game namespace", "src" .. ".game" },
    { "consumer presentation namespace", "src" .. ".presentation" },
    { "consumer UI namespace", "src" .. ".ui" },
    { "old consumer tool path", "tools" .. "/frogui" },
    { "source consumer name", "Dice" .. "mancy" },
}

local function collectLuaFiles(root, output)
    for _, name in ipairs(love.filesystem.getDirectoryItems(root)) do
        local path = root .. "/" .. name
        local info = assert(love.filesystem.getInfo(path))
        if info.type == "directory" then
            collectLuaFiles(path, output)
        elseif info.type == "file" and path:sub(-4) == ".lua" then
            output[#output + 1] = path
        end
    end
end

local function exactInventory(root, expected, label)
    local actual = {}
    collectLuaFiles(root, actual)
    table.sort(actual)
    table.sort(expected)
    assert(#actual == #expected,
        "standalone " .. label .. " inventory changed without release review")
    for index, expectedPath in ipairs(expected) do
        assert(actual[index] == expectedPath,
            label .. " inventory mismatch: expected " .. expectedPath
                .. ", found " .. tostring(actual[index]))
    end
end

local function scanTextDirectory(root, callback)
    for _, name in ipairs(love.filesystem.getDirectoryItems(root)) do
        local path = root .. "/" .. name
        local info = assert(love.filesystem.getInfo(path))
        if info.type == "directory" then
            scanTextDirectory(path, callback)
        elseif info.type == "file"
                and (path:sub(-4) == ".lua"
                    or path:sub(-3) == ".md"
                    or path:sub(-4) == ".yml"
                    or path:sub(-5) == ".json") then
            callback(path, assert(love.filesystem.read(path)))
        end
    end
end

local function fullPayloadBoundary()
    local function inspect(path, source)
        for _, forbidden in ipairs(FORBIDDEN_REFERENCES) do
            assert(not source:find(forbidden[2], 1, true),
                path .. " retains " .. forbidden[1])
        end
    end
    for _, root in ipairs { "frogui", "tests", "examples", "docs" } do
        scanTextDirectory(root, inspect)
    end
    for _, path in ipairs {
        "README.md", "STYLE.md", "CHANGELOG.md", "main.lua", "conf.lua",
        ".luarc.json", ".github/workflows/check.yml",
    } do
        inspect(path, assert(love.filesystem.read(path)))
    end
end

local function namespaceBoundary()
    -- The literal legacy namespace is intentionally present only in this
    -- release-boundary assertion and the compatibility guide.
    local legacy = "src" .. ".frogui"
    for _, path in ipairs(RUNTIME_FILES) do
        local source = assert(love.filesystem.read(path))
        assert(not source:find(legacy, 1, true),
            path .. " retains the legacy embedded namespace")
        for moduleName in source:gmatch("require%s*%(%s*['\"]([^'\"]+)['\"]%s*%)") do
            assert(moduleName == "frogui"
                    or moduleName:sub(1, 7) == "frogui.",
                path .. " imports non-FrogUI module " .. moduleName)
        end
    end
    assert(package.loaded[legacy] == nil,
        "legacy and standalone module identities are both loaded")
end

function check.run()
    exactInventory("frogui", RUNTIME_FILES, "runtime")
    exactInventory("tests", TEST_FILES, "test")
    namespaceBoundary()
    fullPayloadBoundary()
    return true
end

return check
