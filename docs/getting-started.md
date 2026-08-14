# Getting started

Install FrogUI at a pinned revision, add the dependency root to `package.path`,
and import only `require("frogui")`. There is no generated view language,
adapter layer, or alternate namespace.

Start with one `App` component and one Host. The Host requires explicit
`designWidth` and `designHeight`; pass physical dimensions or let it sample the
current LÖVE drawable at construction. Forward LÖVE callbacks directly.

Build the first screen from Box, Row, Column, Overlay, Text, and Button. Extract
a component when the visible concept is reused or easier to understand by
name. Add an actor only when that concept owns semantic state.

Run `love . --example hello` for the smallest complete application and
`love . --example gallery` for responsive composition and a modal. Hover or
command-click a `Frog.*` symbol in a LuaLS editor to see accepted props.

Before committing a framework or consumer integration change, run both
standalone suites and the consumer's own layout, input, and device gates.
