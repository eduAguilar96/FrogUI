# Actors, actions, and events

An actor owns one semantic state machine and its visible output. `Frog.action`
defines a command accepted by an actor; `Frog.event` defines an observed fact.

Actions are sent to an exact mounted address. Events are emitted to a snapshot
of matching mounted reactions in committed tree order. Nested messages join a
bounded breadth-first queue, so recipients never observe recursive or
history-dependent delivery.

Reducers return replacement state; they do not mutate the delivered record or
perform drawing. Actor state must remain plain, acyclic data. External mutable
processes belong in `useResource`, not actor state.

Use declarative `Frog.go`, `Frog.prop`, and `Frog.oneOf` for compact state
transitions. Use a function when a transition genuinely computes semantic
state. `unmount(props, state)` is a terminal cleanup boundary for a capability
owned by that exact actor mount; it cannot send, emit, or render.

Simulation and persistence remain outside FrogUI. A connected consumer calls
its authoritative domain method, then sends or emits the resulting fact for
presentation. The UI never recomputes game rules.
