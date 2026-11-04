# Clear conversation behind actions

Removed the actions-menu dimming fill and the conversation header's opaque
background. The header keeps its fixed 64-point layout while the glass menu
expands over the conversation. Opening it does not add a full-width white block
or shift messages down. Only the menu itself paints a surface.

The outside-click target is completely transparent, with its explicit hit shape
on the button label and a cutout for the menu. Escape and menu actions remain
available.

Validated in the running app: no darkening, no growing white header behind the
menu, Memory action, outside-click dismissal. Build succeeded without warnings
or errors. `closed.jpg` and `open.jpg` show the visible layout.

This supersedes the earlier dimming behavior documented in `mac-actions-backdrop`.
