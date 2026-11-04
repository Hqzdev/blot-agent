# Chat selection and hold gestures

Reproduced: a normal 80 ms click on a chat row left the previous chat selected,
while accessibility activation could select it. The high-priority hold recognizer
was taking the pointer click. Agent and group rows now observe holds alongside
the native button click. Other message hold behavior remains unchanged.

A row-local reference gates activation while its hold menu is open, including a
native action queued before the hold. The menu's own actions explicitly clear that
environment so they remain usable. Closing the menu restores normal activation.

Validation:

- Final app build passed without warnings/errors.
- Four regression checks passed with `scripts/verify-mac-press-activation.swift`:
  ordinary activation, queued release suppression, restored activation after
  dismissal, and isolation between rows.
- After the user unlocked the Mac, end-to-end pointer checks passed: 80 ms clicks
  selected Scout, Dough and the Orders/Finance group; a 650 ms hold on Eagle Eye
  opened its menu while the group stayed selected, including a later observation
  after release. Normal selection worked again after closing the menu.

Run the regression check:

```sh
xcrun swiftc -parse-as-library -module-cache-path .build/mac-press-check/module-cache \
  apps/macos/BlotMac/Features/TeamDesign/MacTeamPressState.swift \
  scripts/verify-mac-press-activation.swift -o .build/mac-press-check/verify
.build/mac-press-check/verify
```
