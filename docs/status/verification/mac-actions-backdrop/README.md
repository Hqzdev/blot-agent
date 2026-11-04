# Chat actions backdrop

Opening the header actions menu fades in an 18% black workspace backdrop. A
rounded cutout follows the menu's layout anchor, preserving its appearance and
pointer interaction. Clicking outside or pressing Escape closes the menu.
Selecting an action, opening a sheet, changing conversations or opening settings
clears the expanded state. The backdrop uses the existing Reduce Motion-aware
animation modifier.

Validated in the running app: backdrop/menu appearance, selecting Memory through
the cutout, outside-click dismissal, Escape dismissal, reopening and restoration
of the Overview inspector. No demo records were changed. Build passed without
warnings or errors. `expanded.jpg` and `closed.jpg` show both states.
