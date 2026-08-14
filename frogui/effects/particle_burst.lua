-- Declares one deterministic finite particle burst owned by an EffectLayer.

local Element = require("src.frogui.element")

-- Particle generation, clock sampling, and completion live in the Host effect
-- runtime so rerenders and resizes cannot restart or reroll the keyed burst.
local ParticleBurst = Element.primitive("ParticleBurst")

return ParticleBurst
