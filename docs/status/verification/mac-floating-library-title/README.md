# Floating page title

Library pages now show a noninteractive Liquid Glass capsule centered above their
content. The title shares font and padding with the agent-name control, but is a
Text heading, has no action, and does not intercept pointer events. The opaque
header strip was removed for these pages; content scrolls behind the capsule.
Initial scroll content margins keep the first section clear of the title.
Conversation headers retain their existing profile action and background.

Validated: build succeeded without warnings/errors, marketplace title appeared as
a heading, clicking it opened no sheet or popover, and scrolling left it fixed
with page content visible underneath. Screenshots show the top and scrolled page.
