-- Declares one finite frame sequence with an optional contact callback.

local Element = require("src.frogui.element")

-- Flipbook frame/contact state lives in the Host effect runtime so rerenders
-- and resizes cannot restart it or replay its callbacks.
local Flipbook = Element.primitive("Flipbook")

return Flipbook
