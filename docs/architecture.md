# Architecture

FrogUI has four deliberately narrow layers:

1. descriptions: immutable primitive/component calls;
2. semantic owners: components, actors, messages, hooks, and resources;
3. Host runtime: validation, reconciliation, layout, input, effects, and
   atomic commit;
4. painter: the default LÖVE renderer.

The Host renders semantic owners only when explicit input changes them. Smooth
motion, clocks, effects, shaders, and sprite sheets sample during update/draw
without recomputing application components every frame. Layout rebuilds a
primitive tree when semantic descriptions or viewport geometry change.

Actor state and delivered messages are detached plain data. Refs publish only
committed geometry. Candidate work cannot leak partial state; runtime faults are
terminal because mutable external effects cannot be generically rewound.

FrogUI is presentation infrastructure. It does not own simulation, persistence,
scene authority, networking, audio catalogs, or content. Those layers provide
explicit data and callbacks to small consumer components.
