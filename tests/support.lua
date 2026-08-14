-- Small tree-search/assertion and generated-fixture helpers shared by
-- FrogUI's focused checks.

local support = {}

-- Creates an ordinary framework-test Host with the suite's explicit virtual
-- canvas policy. Constructor/viewport contract checks should call Frog.host
-- directly so omitted or malformed dimensions remain observable.
function support.host(options)
    options = options or {}
    local resolved = {}
    for key, value in pairs(options) do resolved[key] = value end
    resolved.designWidth = resolved.designWidth or 540
    resolved.designHeight = resolved.designHeight or 960
    local region = resolved.viewport
    local regionOwnsSize = region
        and (region.width ~= nil or region.height ~= nil)
    if not regionOwnsSize then
        resolved.width = resolved.width or 540
        resolved.height = resolved.height or 960
    end
    return require("frogui").host(resolved)
end

-- Focused checks may inspect the mutable committed node graph. These helpers
-- keep that internal seam out of FrogUI's public mount/render return contract.
function support.mount(host, description)
    host:mount(description)
    return host:tree()
end

function support.render(host, description)
    host:render(description)
    return host:tree()
end

-- Creates a tiny in-memory image so framework checks never borrow game art.
function support.generatedImage(width, height, color)
    width = width or 2
    height = height or 2
    color = color or { 1, 1, 1, 1 }
    local data = love.image.newImageData(width, height)
    for x = 0, width - 1 do
        for y = 0, height - 1 do
            data:setPixel(x, y, unpack(color))
        end
    end
    return love.graphics.newImage(data)
end

function support.near(actual, expected, label)
    assert(math.abs(actual - expected) < 0.001,
        (label or "value") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual))
end

function support.find(node, testId)
    if not node then return nil end
    if node.testId == testId
            or node.props and node.props.testId == testId then
        return node
    end
    for _, child in ipairs(node.children or {}) do
        local found = support.find(child, testId)
        if found then return found end
    end
end

-- Returns the first resolved Text node whose complete value matches text.
function support.findText(node, text)
    if not node then return nil end
    if node.type == "Text" and node.props.text == text then return node end
    for _, child in ipairs(node.children or {}) do
        local found = support.findText(child, text)
        if found then return found end
    end
end

function support.collect(node, predicate, out)
    out = out or {}
    if not node then return out end
    if predicate(node) then out[#out + 1] = node end
    for _, child in ipairs(node.children or {}) do
        support.collect(child, predicate, out)
    end
    return out
end

function support.center(node)
    local box = node.layout or node
    local x = box.x or box.left
    local y = box.y or box.top
    local w = box.w or box.width
    local h = box.h or box.height
    assert(x and y and w and h, "resolved node has no rectangle")
    return x + w / 2, y + h / 2
end

return support
