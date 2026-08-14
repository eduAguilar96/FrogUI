-- Owns the standalone contract inventory and prints one readable gate result.

local runner = {}

local groups = {
    headless = {
        { "callable elements and keyed components", "parsingcheck" },
        { "committed refs and runtime faults", "refcheck" },
        { "resources, frames, and cleanup", "processcheck" },
        { "pointer, keyboard, and inspection", "inputcheck" },
        { "actor identity and candidate atomicity", "actoridentitycheck" },
        { "breadth-first typed events", "eventordercheck" },
        { "actor runtime fault boundaries", "runtimecontractcheck" },
        { "mobile interaction and drag lifecycle", "interactioncheck" },
        { "horizontal swipe ownership", "swipecheck" },
        { "semantic feedback ordering", "feedbackcheck" },
        { "bounded diagnostics", "diagnosticscheck" },
        { "render replay feasibility census", "renderreplaycensuscheck" },
        { "actor-local scheduling", "actorlocalcheck" },
    },
    graphical = {
        { "public API, services, viewport, and Host lifecycle", "apicheck" },
        { "nested and responsive layout with font measurement", "layoutcheck" },
        { "transient popup text", "effectcheck" },
        { "projectile and flipbook travel", "travelcheck" },
        { "deterministic particle bursts", "particleburstcheck" },
        { "tiled images and shaders", "worldcheck" },
        { "bounded Canvas drawing", "canvascheck" },
        { "default and custom painters", "paintercheck" },
        { "images and sprite sheets", "spritesheetcheck" },
        { "motion and juice", "motioncheck" },
        { "accessible radial dial", "radialdialcheck" },
        { "portrait and wide example boot", false, "tests.examplecheck" },
    },
}

local function releaseConsistency()
    local version = require("frogui.version")
    assert(version.string == require("frogui").VERSION,
        "frogui/version.lua and Frog.VERSION disagree")
    local changelog = assert(love.filesystem.read("CHANGELOG.md"),
        "CHANGELOG.md is missing")
    assert(changelog:find("## [" .. version.string .. "]", 1, true),
        "CHANGELOG.md has no entry for Frog.VERSION")
end

function runner.run(mode)
    local contracts = assert(groups[mode], "unknown FrogUI test mode")
    releaseConsistency()
    require("tests.boundarycheck").run()
    for index, entry in ipairs(contracts) do
        io.write(("[%02d/%02d] %s ... "):format(index, #contracts, entry[1]))
        local moduleName = entry[3] or "tests.contracts." .. entry[2]
        local contract = require(moduleName)
        assert(type(contract.run) == "function",
            moduleName .. " does not export run()")
        contract.run()
        print("ok")
    end
    print(("FrogUI %s contracts passed (%d)"):format(mode, #contracts))
    return true
end

return runner
