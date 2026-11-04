# Toolbar creation menu

The plus control expands into a rounded rectangular Liquid Glass block with
vertical Agent and Group rows, matching the chat actions menu. The surface grows
from 32×32 to 192×128 points with its top-left corner fixed at the toolbar button.
The native toolbar retains a constant layout throughout the animation.

SwiftUI owns presentation and animation state. A small NSViewRepresentable anchors
a child panel because the native toolbar clips content extending below its height.
The panel has no window chrome and supports keyboard focus and accessibility.
Reduce Motion bypasses the expansion animation.

Verified in the running app:

- Menu appears at the plus control, with vertical action rows.
- Escape and clicking outside dismiss the menu; it can be reopened.
- Agent opens the New Agent editor and Group opens the New Group editor.
  Both were cancelled without creating records.
- Final build passed without warnings or errors.

`expanded.jpg` shows the completed menu in the running app.
