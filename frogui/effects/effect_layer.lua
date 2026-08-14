-- Defines the ordered, input-transparent surface that owns transient effects.

local Element = require("frogui.element")

-- Paints effect children in source order without participating in pointer or
-- keyboard input. Keep it as the last child of the visual surface it decorates.
local EffectLayer = Element.primitive("EffectLayer")

return EffectLayer
