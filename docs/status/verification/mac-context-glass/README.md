# Glass chat and message menus

`MacTeamPressMenu` now uses one rounded, interactive Liquid Glass surface with a
clear presentation background instead of an opaque panel fill. Chat actions and
message reactions/actions share this modifier, including own and agent messages.
Native popover positioning, dismissal, long-press motion and haptics are retained.

Validation: macOS build passed without warnings or errors; chat actions opened;
right-click on an agent message showed all six reactions and three actions;
Reply displayed the composer reply preview and was cancelled; holding an own
message opened the same menu. Screenshots are in `chat-menu.jpg` and
`message-menu.jpg`. No messages or reactions were added during verification.
