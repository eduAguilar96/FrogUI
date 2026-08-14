-- Owns semantic shader compilation, explicit uniforms, and safe fallback state.

local Clock = require("frogui.clock")

local shader = {}

local EFFECT_RECOLOR_TOKEN = "__frogui-effect-recolor"
local EFFECT_RECOLOR_SOURCE = [[
    extern vec3 target;
    extern float hotCore;
    extern float hotCoreExp;

    vec4 effect(vec4 color, Image texture, vec2 textureCoordinates,
            vec2 screenCoordinates) {
        vec4 pixel = Texel(texture, textureCoordinates);
        float value = max(pixel.r, max(pixel.g, pixel.b));
        vec3 recolored = target * value;
        float core = pow(value, hotCoreExp) * hotCore;
        return vec4(mix(recolored, vec3(1.0), core), pixel.a) * color;
    }
]]

local function graphics()
    return love and love.graphics or nil
end

-- Returns the current physical render-target size for full-field shaders.
local function pixelTargetSize()
    local g = graphics()
    if not g then return nil end
    local canvas = g.getCanvas and g.getCanvas() or nil
    if canvas then
        if canvas.getPixelDimensions then
            return { canvas:getPixelDimensions() }
        end
        return { canvas:getDimensions() }
    end
    if g.getPixelDimensions then return { g.getPixelDimensions() } end
    return { g.getDimensions() }
end

-- Converts a documented uniform value into the payload sent to LÖVE.
local function resolveUniform(value)
    if Clock.isClock(value) then return value:now() end
    if type(value) ~= "table" then return value end
    local copy = {}
    for index, amount in ipairs(value) do copy[index] = amount end
    return copy
end

-- Records one failure per semantic token and emits one actionable diagnostic.
local function fail(host, token, reason)
    host._shaderFailures = host._shaderFailures or {}
    if host._shaderFailures[token] == nil then
        host._shaderFailures[token] = tostring(reason)
        print("[frogui shader] " .. token .. " unavailable: "
            .. tostring(reason))
    end
    host._shaderCache = host._shaderCache or {}
    host._shaderCache[token] = false
end

-- Compiles one theme-owned source lazily and caches success or failure.
local function compiled(host, token)
    host._shaderCache = host._shaderCache or {}
    local cached = host._shaderCache[token]
    if cached ~= nil then return cached or nil end
    local g = graphics()
    if not g or not g.newShader then return nil end
    local source = assert((host.theme.shaders or {})[token],
        "unknown FrogUI shader token " .. tostring(token))
    local ok, result = pcall(g.newShader, source)
    if not ok then
        fail(host, token, result)
        return nil
    end
    host._shaderCache[token] = result
    return result
end

-- Compiles FrogUI's one generic effect-art recolor program independently
-- from application shader tokens. Failure falls back to ordinary tint.
local function compiledEffectRecolor(host)
    if host._effectRecolorShader ~= nil then
        return host._effectRecolorShader or nil
    end
    local g = graphics()
    if not g or not g.newShader then return nil end
    local ok, result = pcall(g.newShader, EFFECT_RECOLOR_SOURCE)
    if not ok then
        fail(host, EFFECT_RECOLOR_TOKEN, result)
        host._effectRecolorShader = false
        return nil
    end
    host._effectRecolorShader = result
    return result
end

-- Sends one already-validated effect recipe without allocating a per-draw
-- closure around the protected GPU boundary.
local function sendEffectRecolor(program, target, hotCore, hotCoreExp, g)
    program:send("target", target)
    program:send("hotCore", hotCore or 0)
    program:send("hotCoreExp", hotCoreExp or 2.5)
    g.setShader(program)
end

-- Sends one uniform only when the compiled program declares its name.
local function sendUniform(program, name, value)
    if program.hasUniform and not program:hasUniform(name) then
        error("shader does not declare uniform " .. name, 0)
    end
    program:send(name, resolveUniform(value))
end

-- Sends standard viewport uniforms when the authored shader asks for them.
local function sendStandardUniforms(host, program)
    if program.hasUniform and program:hasUniform("frogViewportPixels") then
        sendUniform(program, "frogViewportPixels", pixelTargetSize())
    end
    if program.hasUniform and program:hasUniform("frogViewportLogical") then
        local viewport = host:viewport()
        sendUniform(program, "frogViewportLogical",
            { viewport.width, viewport.height })
    end
end

-- Activates one compiled shader and all currently sampled uniform values.
function shader.activate(host, node)
    local token = node.props.shader
    local program = compiled(host, token)
    if not program then return false end
    local g = graphics()
    local ok, reason = pcall(function()
        sendStandardUniforms(host, program)
        for name, value in pairs(node.props.uniforms or {}) do
            sendUniform(program, name, value)
        end
        if node.props.blend == "add" then
            g.setBlendMode("add", "alphamultiply")
        end
        g.setShader(program)
    end)
    if not ok then
        fail(host, token, reason)
        return false
    end
    return true
end

-- Activates brightness-preserving hue replacement for one effect asset.
-- `target` is already resolved from the application's semantic color table.
function shader.activateEffectRecolor(host, target, hotCore, hotCoreExp)
    local program = compiledEffectRecolor(host)
    if not program then return false end
    local targetScratch = host._effectRecolorTarget
    if not targetScratch then
        targetScratch = {}
        host._effectRecolorTarget = targetScratch
    end
    targetScratch[1] = target[1] or target.r
    targetScratch[2] = target[2] or target.g
    targetScratch[3] = target[3] or target.b
    local ok, reason = pcall(sendEffectRecolor, program, targetScratch,
        hotCore, hotCoreExp, graphics())
    if not ok then
        fail(host, EFFECT_RECOLOR_TOKEN, reason)
        host._effectRecolorShader = false
        return false
    end
    return true
end

-- Marks a draw-time GPU failure so later frames use the authored fallback.
function shader.drawFailed(host, node, reason)
    fail(host, node.props.shader, reason)
end

-- Resolves clock uniforms for custom painters and F6 without exposing clocks.
function shader.uniforms(node)
    local values = {}
    for name, value in pairs(node.props.uniforms or {}) do
        values[name] = resolveUniform(value)
    end
    return values
end

-- Reports compilation/fallback state without forcing eager compilation.
function shader.inspect(host, node)
    local token = node.props.shader
    local cached = host._shaderCache and host._shaderCache[token]
    local status = cached == false and "failed"
        or cached ~= nil and "active" or "pending"
    return {
        token = token,
        status = status,
        error = host._shaderFailures and host._shaderFailures[token] or nil,
        fallback = node.props.fallback or "plain",
        blend = node.props.blend or "alpha",
        uniforms = shader.uniforms(node),
    }
end

-- Drops GPU programs after a theme reload or Host teardown.
function shader.clear(host)
    host._shaderCache = {}
    host._shaderFailures = {}
    host._effectRecolorShader = nil
    host._effectRecolorTarget = nil
end

return shader
