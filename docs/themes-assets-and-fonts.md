# Themes, assets, and fonts

A theme maps semantic meaning to presentation. FrogUI reads validated colors,
font roles, optional `fontFile`, breakpoint ratio, shaders, control states,
sound defaults, and motion spring presets. Other top-level namespaces remain
available to consumer components.

Components name colors and fonts semantically. Use a theme role when all uses
should change together and `Text.fontScale` for deliberate local emphasis.
`fitDown` may reduce text to explicit bounds; it never grows beyond the chosen
role.

The asset service maps semantic ids to non-empty LÖVE paths or already-loaded
image objects. Components never depend on consumer filenames. Image preserves
RGB, Icon treats art as an alpha mask, and missing declared effect art uses the
documented fallback where supported.

Shader source belongs to `theme.shaders`. ShaderImage receives only a semantic
token, explicit uniforms, blend mode, and fallback. Asset, font, theme, and
feedback validation runs during Host construction or refresh so typos fail near
their owner.
