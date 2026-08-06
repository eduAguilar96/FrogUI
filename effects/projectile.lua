-- Declares one finite source-to-target effect owned by an EffectLayer.

local Element = require("src.frogui.element")

-- Projectile lifecycle, ref resolution, and resize reprojection live in the
-- Host effect runtime; this token is the complete readable authoring surface.
local Projectile = Element.primitive("Projectile")

return Projectile
