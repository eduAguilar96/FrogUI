# Host and LÖVE

One mounted Host owns the committed UI tree, viewport, renderer, actors,
messages, refs, resources, input, feedback queue, and diagnostics. Constructing
a second Host is allowed; mounting it before the first unmounts fails loudly.

`host:mount(description)` publishes the first tree. `host:render(description)`
reconciles a new root description. Both return nothing: consumers cannot retain
or mutate committed nodes. Candidate render, layout, resize, and theme-refresh
failures keep the last committed tree. Runtime update/input/feedback failures
fault the Host; inspect or draw it for diagnosis, then unmount and replace it.

Call `update(dt)` and `draw()` from the matching LÖVE callbacks. Forward resize,
mouse, touch, keyboard, text, and wheel callbacks. Coordinates are converted
from the physical drawable to FrogUI's virtual viewport.

Host services are explicit:

- `theme`: validated semantic framework namespaces plus consumer namespaces;
- `assets`: semantic ids to paths or loaded image objects;
- `feedback`: optional `sound(cue)` and `haptic(cue)` callbacks;
- `reducedMotion`: a boolean visual-accessibility policy;
- `painter`: an experimental internal protocol, not a 0.x guarantee.

See `frogui/init.lua` for the complete `FrogUIHost` LuaLS surface and lifecycle
contracts.
