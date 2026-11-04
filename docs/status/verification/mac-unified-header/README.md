# Unified header row

Window controls, sidebar controls, chat actions, the horizontal agent/avatar title
and inspector toggle share a centerline 32 points below the window top. The header
occupies 64 points. Traffic lights begin 24 points from the left, and the inspector
divider is removed. Expanding chat actions overlays the conversation without
changing the header row height; outside-click dismissal remains functional.

AppKit's standard-window-button factory supplies native controls. Their host
dispatches close/minimize/full-screen to the actual window; Option-green performs
Zoom. The original titlebar controls are hidden while this host is installed and
restored on teardown. The host survives navigation into settings, and blank header
backgrounds retain WindowDragGesture. No custom-drawn traffic lights are used.

Validation: final build passed without warnings or errors. Verified visual
alignment, both sidebar toggles, actions/backdrop/Escape, creation menu, settings
round trip, and native Option-green Zoom/restore. Window controls remain present
after these layout changes. `aligned.jpg` shows the final main window.
