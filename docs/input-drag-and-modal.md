# Input, drag, and modal

Use Button for keyboard-visible actions and Pressable only for deliberately
pointer-only surfaces. Touch does not synthesize hover. Focus, disabled and
selected paint, shortcuts, tap, hold, rejection, and semantic sounds belong to
the owning primitive.

DragSource owns one plain payload and a static preview. DropTarget advertises a
matching `accepts` kind and stable application address. The Host resolves the
deepest eligible target and reports committed, rejected, or cancelled terminal
status. Domain validation and persistence remain in the consumer callback.

Scroll, HorizontalSwipe, RadialDial, presses, and drag participate in explicit
gesture arbitration. Once a gesture claims a pointer, ownership does not jump
to another primitive. RadialDial treats small angular touch jitter as a tap;
the left and right halves step backward and forward until a deliberate turn
crosses its code-owned drag boundary.

Modal creates a root input-isolated surface. `dismiss` is `back`, `outside`,
`both`, or `none`; only the top modal receives input. Closing restores focus to
the previous layer. Chrome is one persistent root portal below modals; a modal
may explicitly allow that same portal rather than constructing a duplicate HUD.
