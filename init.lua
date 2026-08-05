-- Public FrogUI vocabulary. Application code imports this one module to define
-- primitives, components, actors, messages, and the single Host.

local Element = require("src.frogui.element")
local Host = require("src.frogui.host")
local Message = require("src.frogui.message")
local Clock = require("src.frogui.clock")
local Juice = require("src.frogui.juice")
local Interaction = require("src.frogui.interaction")

---@alias FrogUISize number|string
---Logical pixels or a percentage such as `"100%"`.

---@alias FrogUIRGBA number[]|{r:number,g:number,b:number,a?:number}
---@alias FrogUIColor string|FrogUIRGBA
---A semantic theme token or numeric RGBA color.

---@alias FrogUIOverflow 'clip'|'visible'
---@alias FrogUIAlign 'start'|'center'|'end'|'stretch'
---@alias FrogUIBoxJustify 'start'|'center'|'end'|'stretch'
---@alias FrogUIFlowJustify 'start'|'center'|'end'|'space-between'
---@alias FrogUITextAlign 'left'|'center'|'right'|'start'|'end'
---@alias FrogUIImageFit 'contain'|'cover'|'stretch'
---@alias FrogUIScrollAxis 'vertical'|'horizontal'
---@alias FrogUIModalDismiss 'back'|'outside'|'both'|'none'
---@alias FrogUIButtonResultStatus 'committed'|'rejected'
---@alias FrogUIDragStatus 'committed'|'rejected'|'cancelled'
---@alias FrogUISoundCue string|false
---A semantic cue id, or `false` to disable that primitive's default sound.

---@alias FrogUIRefKey string|number|boolean
---A stable authored key retained by `Frog.useKeyedRefs`.

---@class FrogUIRect
---@field x number Committed arranged left edge in logical viewport pixels.
---@field y number Committed arranged top edge in logical viewport pixels.
---@field width number Committed arranged width in logical viewport pixels.
---@field height number Committed arranged height in logical viewport pixels.

---@class FrogUIRef
---@field current? FrogUIRect Read-only property returning a detached rectangle copy, or nil while unattached/unmounted; mutating the copy never changes FrogUI.
---A stable handle created by a render hook and attached to one primitive.

---@class FrogUIOffset
---@field x? number Horizontal logical-pixel offset applied after layout.
---@field y? number Vertical logical-pixel offset applied after layout.

---@class FrogUIPaddingSides
---@field left? number
---@field right? number
---@field top? number
---@field bottom? number

---@alias FrogUIPadding number|FrogUIPaddingSides

---@class FrogUIJuiceBinding
---@field recipe table Declarative recipe returned by Frog.tween/spring/etc.
---@field key? string|number|boolean Replay identity; a changed key restarts it.
--- Exactly-once terminal follow-up after a finite recipe settles and the Host
--- update commits. Key replacement, restart, or unmount cancels stale work;
--- reduced motion defers completion until the next update.
---@field onComplete? fun()

---@class FrogUIActorDefinition
---@field initial any|fun(props:table):any Initial plain actor state.
---@field actions? table Typed action reducers or scalar transition maps.
---@field reactions? table[] Typed event reactions.
--- Exactly-once terminal cleanup with final props/state after this actor mount
--- leaves the committed tree. It cannot message, render, or route input.
---@field unmount? fun(props:table,state:any)
---@field render fun(props:table,state:any,send:fun(record:table)):FrogUIElementDescription?

---@class FrogUIElementDescription
---@field __frogDescriptor true
---@field props table
---@field children FrogUIElementDescription[]

---@class FrogUIBaseProps
---@field key? string|number Stable identity among reordered siblings.
---@field ref? FrogUIRef Exact primitive rectangle published after arrange commits.
---@field width? FrogUISize Explicit width; otherwise measure naturally.
---@field height? FrogUISize Explicit height; otherwise measure naturally.
---@field grow? number Non-negative share of remaining Row/Column space.
---@field opacity? number Static opacity from 0 through 1.
---@field testId? string Readable development/test identity shown by F6.
---@field juice? table<string, table|FrogUIJuiceBinding> Named recipes.
---@field reactions? table[] Typed element reactions that play named juice.

---@class FrogUIElementProps:FrogUIBaseProps
---@field offset? FrogUIOffset Translation that does not move later siblings.

---@class FrogBoxProps:FrogUIElementProps
---@field padding? FrogUIPadding Inner space around its child.
---@field background? FrogUIColor
---@field border? FrogUIColor
---@field borderWidth? number Non-negative border thickness.
---@field radius? number Non-negative corner radius.
---@field clip? boolean Clip descendants to this box.
---@field overflow? FrogUIOverflow Explicit clipping policy.
---@field align? FrogUIAlign Horizontal placement of the child.
---@field justify? FrogUIBoxJustify Vertical placement of the child.
---@field [integer] FrogUIElementDescription Zero or one child.

---@class FrogRowProps:FrogUIElementProps
---@field padding? FrogUIPadding
---@field background? FrogUIColor
---@field border? FrogUIColor
---@field borderWidth? number
---@field radius? number
---@field clip? boolean
---@field overflow? FrogUIOverflow
---@field gap? number Non-negative horizontal gap between children.
---@field align? FrogUIAlign Vertical/cross-axis child placement.
---@field justify? FrogUIFlowJustify Horizontal/main-axis distribution.
---@field wrap? boolean Wrap children onto additional rows.
---@field [integer] FrogUIElementDescription Any number of children.

---@class FrogColumnProps:FrogUIElementProps
---@field padding? FrogUIPadding
---@field background? FrogUIColor
---@field border? FrogUIColor
---@field borderWidth? number
---@field radius? number
---@field clip? boolean
---@field overflow? FrogUIOverflow
---@field gap? number Non-negative vertical gap between children.
---@field align? FrogUIAlign Horizontal/cross-axis child placement.
---@field justify? FrogUIFlowJustify Vertical/main-axis distribution.
---@field [integer] FrogUIElementDescription Any number of children.

---@class FrogOverlayProps:FrogUIElementProps
---@field padding? FrogUIPadding
---@field background? FrogUIColor
---@field border? FrogUIColor
---@field borderWidth? number
---@field radius? number
---@field clip? boolean
---@field overflow? FrogUIOverflow
---@field align? FrogUIAlign Horizontal placement shared by every child.
---@field justify? FrogUIBoxJustify Vertical placement shared by every child.
---@field [integer] FrogUIElementDescription Children paint back-to-front.

---@class FrogTextProps:FrogUIElementProps
---@field text? string Text content; a lone positional string/number is shorthand.
---@field role? string Semantic theme font role; defaults to `body`.
---@field fontScale? number Positive local multiplier for the current role size.
---@field color? FrogUIColor
---@field wrap? boolean Wrap within the resolved width.
---@field maxLines? integer Positive visible-line cap, normally paired with wrap.
---@field align? FrogUITextAlign Horizontal alignment inside the text box.
---@field fitDown? boolean Shrink until bounds/line cap fit; never grow.
---@field outlineWidth? number Non-negative outline thickness.
---@field outlineColor? FrogUIColor
---@field [integer] string|number At most one readable text shorthand.

---@alias FrogUIAssetSource string|userdata|table
---An application asset token or image-like object with width/height methods.

---@class FrogUIImageSourceRect
---@field x number Left source pixel; must be inside the source asset.
---@field y number Top source pixel; must be inside the source asset.
---@field width number Positive source-pixel width.
---@field height number Positive source-pixel height.

---@class FrogImageProps:FrogUIElementProps
---@field source FrogUIAssetSource Required authored image source.
--- Optional source-pixel crop; sizing and fit use the cropped dimensions.
---@field sourceRect? FrogUIImageSourceRect
---@field fit? FrogUIImageFit Sizing policy; defaults to `contain`.
---@field tint? FrogUIColor Optional multiplicative tint.

---@class FrogIconOutline
---@field width? number Non-negative outline thickness.
---@field color? FrogUIColor

---@class FrogIconProps:FrogUIElementProps
---@field source FrogUIAssetSource Required alpha-silhouette source.
--- Optional source-pixel crop; sizing and fit use the cropped dimensions.
---@field sourceRect? FrogUIImageSourceRect
---@field fit? FrogUIImageFit Sizing policy; defaults to `contain`.
---@field tint? FrogUIColor Recolors from the source alpha.
---@field mirror? boolean Mirror horizontally.
---@field outline? FrogIconOutline

---@class FrogButtonProps:FrogUIElementProps
---@field padding? FrogUIPadding
---@field background? FrogUIColor
---@field border? FrogUIColor
---@field borderWidth? number
---@field radius? number
---@field hoverBackground? FrogUIColor
---@field hoverBorder? FrogUIColor
---@field pressedBackground? FrogUIColor
---@field pressedBorder? FrogUIColor
---@field focusedBackground? FrogUIColor
---@field focusedBorder? FrogUIColor
---@field selectedBackground? FrogUIColor
---@field selectedBorder? FrogUIColor
---@field align? FrogUIAlign Horizontal placement of the child.
---@field justify? FrogUIBoxJustify Vertical placement of the child.
---@field onPress? fun() Reversible UI callback.
---@field onLongPress? fun() Pointer hold callback after the Host threshold.
---@field onHoverChange? fun(hovered:boolean) Mouse enter/leave callback.
---@field onCommit? fun():boolean, any One irreversible domain call.
---@field onResult? fun(status:FrogUIButtonResultStatus, detail:any)
---@field sound? FrogUISoundCue Activation/commit cue; defaults to theme `activate`.
---@field rejectSound? FrogUISoundCue Rejected-commit cue; defaults to theme `reject`.
---@field hoverSound? FrogUISoundCue Mouse-entry cue; defaults to theme `hover`.
---@field disabled? boolean Disable focus and activation.
---@field selected? boolean Paint the retained selected/toggled state.
---@field shortcut? string|string[] Keyboard shortcut or ordered alternatives.
---@field [integer] FrogUIElementDescription Zero or one child.

---@class FrogMotionSpring
---@field frequency? number Positive oscillation frequency.
---@field damping? number Positive damping ratio.

---@alias FrogMotionSpringChoice string|FrogMotionSpring
---Built-ins are `gentle`, `snappy`, and `bouncy`; themes may add names.

---@class FrogMotionNumberTarget
---@field target number
---@field spring? FrogMotionSpringChoice

---@class FrogMotionColorTarget
---@field target FrogUIRGBA
---@field spring? FrogMotionSpringChoice

---@class FrogMotionProps:FrogUIElementProps
---@field x? number|FrogMotionNumberTarget Horizontal paint/input translation.
---@field y? number|FrogMotionNumberTarget Vertical paint/input translation.
---@field rotation? number|FrogMotionNumberTarget Radians around element center.
---@field scale? number|FrogMotionNumberTarget Non-negative center scale.
---@field opacity? number|FrogMotionNumberTarget Value from 0 through 1.
---@field tint? FrogUIRGBA|FrogMotionColorTarget Numeric multiplicative tint.
---@field [integer] FrogUIElementDescription Zero or one stable-layout child.

---@class FrogPressableProps:FrogUIElementProps
---@field onPress? fun() Pointer tap callback.
---@field onLongPress? fun() Pointer hold callback after the Host threshold.
---@field onHoverChange? fun(hovered:boolean) Mouse enter/leave callback.
---@field sound? FrogUISoundCue Tap/hold cue; defaults to theme `activate`.
---@field hoverSound? FrogUISoundCue Mouse-entry cue; defaults to theme `hover`.
---@field [integer] FrogUIElementDescription Exactly one child.

---@class FrogScrollProps:FrogUIElementProps
---@field axis FrogUIScrollAxis Required retained scrolling axis.
---@field bar? boolean Show the built-in touch-sized scrollbar.
--- Requested logical offset. When present, reconciliation moves directly to
--- this position; omit it for ordinary retained free scrolling.
---@field scrollPosition? number
--- Positive logical-pixel interval used to snap a completed touch gesture.
---@field snapInterval? number
--- Called once after a claimed touch gesture settles, with its final offset.
---@field onScrollEnd? fun(position:number)
---@field [integer] FrogUIElementDescription Exactly one content child.

---@class FrogModalProps:FrogUIBaseProps
---@field dismiss? FrogUIModalDismiss Defaults to `back`.
---@field onDismiss? fun() Required unless dismiss is `none`.
---@field dismissSound? FrogUISoundCue Dismiss cue; defaults to theme `dismiss`.
---@field allowChrome? boolean Paint and route the one root Chrome above this Modal while it is topmost. Defaults to false.
---@field padding? FrogUIPadding
---@field background? FrogUIColor Root-plane background/scrim.
---@field align? FrogUIAlign Horizontal placement of the modal child.
---@field justify? FrogUIBoxJustify Vertical placement of the modal child.
---@field [integer] FrogUIElementDescription Exactly one child.

---@class FrogChromeProps:FrogUIBaseProps
---@field padding? FrogUIPadding
---@field background? FrogUIColor Root-plane background; usually omitted.
---@field align? FrogUIAlign Horizontal placement of the chrome child.
---@field justify? FrogUIBoxJustify Vertical placement of the chrome child.
---@field [integer] FrogUIElementDescription Exactly one persistent chrome child.

---@class FrogDragPayload
---@field kind string Required non-empty type matched by DropTarget.accepts.

---@class FrogDropMatch
---@field key string|number Stable target identity.
---@field address table Plain application-owned destination address.

---@class FrogDragSourceProps:FrogUIElementProps
---@field payload FrogDragPayload Plain finite acyclic drag value.
---@field preview FrogUIElementDescription Static root-plane preview.
---@field onDrop fun(payload:FrogDragPayload, target:FrogDropMatch):boolean, any
---@field onDragStart? fun(payload:FrogDragPayload)
---@field onDragEnd? fun(status:FrogUIDragStatus, detail:any)
---@field grabSound? FrogUISoundCue Drag-claim cue; defaults to theme `dragGrab`.
---@field dropSound? FrogUISoundCue Committed-drop cue; defaults to theme `dragDrop`.
---@field rejectSound? FrogUISoundCue Rejected-drop cue; defaults to theme `reject`.
---@field [integer] FrogUIElementDescription Exactly one visible source child.

---@class FrogDropTargetProps:FrogUIElementProps
---@field key string|number Required stable target identity.
---@field accepts string Required payload kind.
---@field address table Plain finite acyclic application destination.
---@field [integer] FrogUIElementDescription Exactly one visible target child.

local Frog = {}

-- Primitives are FrogUI's built-in layout/paint vocabulary. Calling one
-- creates a description; the Host later measures, paints, and routes it.
--- Paints and pads one rectangular region around zero or one child.
---
--- `align` moves the child horizontally. `justify` moves it vertically.
---@type fun(input?: FrogBoxProps):FrogUIElementDescription
Frog.Box = Element.primitive("Box")

--- Flows children from left to right, optionally wrapping onto more rows.
---
--- `justify` distributes horizontally; `align` places children vertically.
---@type fun(input?: FrogRowProps):FrogUIElementDescription
Frog.Row = Element.primitive("Row")

--- Flows children from top to bottom.
---
--- `justify` distributes vertically; `align` places children horizontally.
---@type fun(input?: FrogColumnProps):FrogUIElementDescription
Frog.Column = Element.primitive("Column")

--- Gives every child the same region and paints them in listed order.
---
--- `align` is horizontal and `justify` is vertical for every child.
---@type fun(input?: FrogOverlayProps):FrogUIElementDescription
Frog.Overlay = Element.primitive("Overlay")

--- Draws one text leaf. `role` selects a semantic theme size; `fontScale`
--- changes only this use while preserving responsive role changes. `fitDown`
--- may shrink that requested size to fit explicit bounds. Hover this symbol or
--- command-click it in LuaLS for the complete `FrogTextProps` contract.
---@type fun(input:FrogTextProps|string|number):FrogUIElementDescription
Frog.Text = Element.primitive("Text")

--- Draws an authored image without replacing its RGB colors.
---
--- `fit` accepts `contain`, `cover`, or `stretch`.
---@type fun(input:FrogImageProps):FrogUIElementDescription
Frog.Image = Element.primitive("Image")

--- Draws and recolors an alpha-silhouette asset.
---
--- Use this for icons; use Image when authored RGB colors must survive.
---@type fun(input:FrogIconProps):FrogUIElementDescription
Frog.Icon = Element.primitive("Icon")

--- Owns focus, shortcuts, tap/hold, disabled/selected state, and interaction paint.
---
--- `align` moves its child horizontally; `justify` moves it vertically. Mouse
--- hover, pointer press, and keyboard focus each have explicit paint tokens.
--- `sound`, `rejectSound`, and `hoverSound` override semantic theme defaults;
--- pass `false` to silence one interaction without changing its behavior.
---@type fun(input?: FrogButtonProps):FrogUIElementDescription
Frog.Button = Element.primitive("Button")

--- Animates one child's paint and input transform without changing layout.
---
--- Scalar targets snap; `{ target, spring }` targets reconcile smoothly.
---@type fun(input?: FrogMotionProps):FrogUIElementDescription
Frog.Motion = Element.primitive("Motion")

--- Adds pointer tap, hold, and mouse-hover behavior to exactly one child.
---
--- Supply at least one callback; keyboard-visible actions use Button. Sound
--- overrides follow Button and accept `false` to suppress a theme default.
---@type fun(input:FrogPressableProps):FrogUIElementDescription
Frog.Pressable = Element.primitive("Pressable")

--- Retains clipped wheel/touch scrolling along one required axis.
---
--- `axis` is `vertical` or `horizontal`; gesture arbitration is Host-owned.
---@type fun(input:FrogScrollProps):FrogUIElementDescription
Frog.Scroll = Element.primitive("Scroll")

--- Root-hosts the application's one persistent navigation/chrome surface.
---
--- Chrome paints above the base tree and below isolated Modals. A top Modal
--- may set `allowChrome = true` to keep this same surface visible and usable;
--- a later ordinary Modal covers and isolates it again.
---@type fun(input:FrogChromeProps):FrogUIElementDescription
Frog.Chrome = Element.primitive("Chrome")

--- Root-hosts one focus/input-isolated surface above the application tree.
---
--- `dismiss` is `back`, `outside`, `both`, or `none`; `dismissSound` overrides
--- the semantic theme cue for either keyboard or pointer dismissal. Multiple
--- Modals paint in source order; only the last receives input, and closing it
--- restores focus to the previous layer. `allowChrome` opts only the current
--- top Modal into sharing input with the one root Frog.Chrome portal.
---@type fun(input:FrogModalProps):FrogUIElementDescription
Frog.Modal = Element.primitive("Modal")

--- Owns a typed drag payload, static preview, and one domain drop callback.
---
--- The Host supplies the deepest matching DropTarget to `onDrop`. Grab,
--- committed-drop, and rejected-drop sounds have separate semantic overrides.
---@type fun(input:FrogDragSourceProps):FrogUIElementDescription
Frog.DragSource = Element.primitive("DragSource")

--- Advertises one typed, stable application destination to drag sources.
---
--- `accepts` must equal the source payload's `kind`.
---@type fun(input:FrogDropTargetProps):FrogUIElementDescription
Frog.DropTarget = Element.primitive("DropTarget")

-- component(name, render) defines a reusable stateless application concept.
-- Calling the returned token also creates a description; during Host render,
-- its render(props) function expands that description into primitives and
-- other components. See src/frogui/README.md for the complete reading model.
Frog.component = Element.component
Frog.each = Element.each
--- Defines one state owner with typed actions, reactions, and visible output.
---
--- Optional `unmount(props, state)` runs exactly once after this mounted actor
--- leaves a committed tree, using that mount's final props and state. It is a
--- terminal domain-cleanup boundary: it may not send messages, rerender, or
--- route input. Failed candidate renders, retained keys, and resize do not
--- clean up the live mount.
---@type fun(name:string, definition:FrogUIActorDefinition):table
Frog.actor = Message.actor
Frog.action = Message.action
Frog.event = Message.event
Frog.on = Message.on
Frog.go = Message.go
Frog.prop = Message.prop
Frog.oneOf = Message.oneOf
Frog.send = Host.send
Frog.emit = Host.emit
Frog.events = Interaction.events

-- Juice recipes are inert data. Named element bindings and typed event
-- reactions decide when the Host plays them.
Frog.tween = Juice.tween
Frog.spring = Juice.spring
Frog.shake = Juice.shake
Frog.sound = Juice.sound
Frog.haptic = Juice.haptic
Frog.delay = Juice.delay
Frog.sequence = Juice.sequence
Frog.parallel = Juice.parallel
Frog.loop = Juice.loop
Frog.withClock = Juice.withClock
Frog.play = Juice.play
Frog.clock = Clock.new

function Frog.host(options)
    return Host.new(options)
end

function Frog.useViewport()
    return Host.currentViewport()
end

--- Creates one stable geometry handle in the current component, actor, or
--- addressed-view render owner. Attach it with `ref = handle` on exactly one
--- primitive, never to a semantic component/actor/view descriptor.
--- `handle.current` publishes after a successful tree commit and after a
--- Host-owned retained rearrangement such as Scroll; failed transactions keep
--- the previous rectangle. It is nil before attachment or after
--- removal/unmount. Every read returns a detached copy, so mutating that
--- rectangle never changes FrogUI.
---
--- Hooks are positional and unconditional: keep each call on its own line and
--- never place it behind a branch. A structural hook edit during hot reload
--- preserves the last good tree; restart the gallery after that edit.
---@return FrogUIRef
Frog.useRef = Host.useRef

--- Creates a readable key-to-ref table for a dense array of stable scalar
--- authored keys. Retained keys keep their handle through reorder and resize;
--- removed keys clear their former handle, and newly added keys get new ones.
---
--- This is one positional hook regardless of key count. Attach every returned
--- handle that needs geometry to one exact primitive via its `ref` prop.
---@param keys FrogUIRefKey[]
---@return table<FrogUIRefKey, FrogUIRef>
Frog.useKeyedRefs = Host.useKeyedRefs

return Frog
