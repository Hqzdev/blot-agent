# Full-height settings sidebar

Removed the workspace-wide 64-point top spacer from settings. The sidebar now
draws its background to the top edge and reserves only 44 points inside that
background for native window controls. Its header, search and navigation move up
20 points; the main settings content moves up 64 points. Removed the vertical
sidebar divider. The empty top 24 points retain window dragging.

Build passed without warnings/errors and `git diff --check` passed. After the user
unlocked the Mac, the running UI confirmed that the sidebar reaches the top edge,
the navigation and main content are higher, and the vertical divider is absent.
`settings-verified.jpg` shows the final layout. The settings header returns to the
conversation when clicked. Chat selection and holding were verified separately.
