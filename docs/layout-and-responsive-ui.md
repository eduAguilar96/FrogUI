# Layout and responsive UI

FrogUI uses a virtual design viewport with fit-then-extend scaling. Every Host
declares positive `designWidth` and `designHeight`. Physical dimensions are an
explicit pair or the LÖVE drawable sampled once at construction. Resizes update
the virtual width, height, scale, and wide state atomically.

Inside a render owner, `Frog.useViewport()` returns detached virtual dimensions,
`wide`, `scale`, and safe insets. Use it to choose a readable portrait or wide
tree:

```lua
local viewport = Frog.useViewport()
return viewport.wide
    and Frog.Row { LeftPanel {}, RightPanel {} }
    or Frog.Column { LeftPanel {}, RightPanel {} }
```

Row and Column support fixed/natural dimensions, percentages, `grow`, gap,
padding, alignment, and main-axis justification. Overlay gives every child the
same region. Motion offsets and transforms never move siblings or negotiate
layout.

Refs expose exact committed primitive rectangles for effects and other
presentation links. They are not a layout query system: ordinary geometry
remains visible in the component tree.
