# Components and primitives

Primitives are FrogUI's framework-owned leaves and containers. Components are
small consumer-owned render functions that compose those primitives.

```lua
local Notice = Frog.component("Notice", function(props)
    return Frog.Box {
        padding = 12,
        background = "panel",
        Frog.Text(props.message),
    }
end)
```

Use Box for one child, Row/Column for flow, and Overlay for shared geometry and
paint order. Text, Image, Icon, SpriteSheet, TiledImage, ShaderImage, and Canvas
paint content. Button, TextInput, Pressable, HorizontalSwipe, RadialDial,
Scroll, DragSource, and DropTarget own interaction. Chrome and Modal own root
portals and input isolation. Motion and EffectLayer change presentation without
becoming domain state.

Component props are ordinary explicit tables. Children are ordered table
entries; false and nil are ignored. Use `Frog.each` for dense collections and
give every generated or reordered description a stable semantic `key`.

Descriptions and props are read-only after construction. A component does not
cache nodes or trigger its own render. Its actor, root props, or viewport change
causes semantic reconciliation; smooth paint samples clocks without rebuilding
component state every frame.
