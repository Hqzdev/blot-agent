# Header button sizing

Sidebar and plus controls now use the same 36×36-point circle as the actions and
inspector buttons. Increased the leading cluster's trailing inset by 8 points to
move it left. The creation menu's collapsed surface and anchor match the new size.

Added a shared `moreVertical` glyph with three solid dots and explicit ink color
for the chat actions control. The regular horizontal glyph remains available for
other contexts.

Build and whitespace checks passed. Verified the final header visually in
`header.jpg`, and opened/closed the plus and actions menus in the running app.
