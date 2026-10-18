# Mobile contract (roadmap item 4)

Binding decisions for touch play. Desktop behaviour is unchanged: every touch path is reached
only when `Settings.touch()` is true.

## Detection

`Settings.touch()` = `Touch.detect(UserInputService.TouchEnabled, UserInputService.KeyboardEnabled,
Settings.get().controls)`: touch when the device has a touch screen and no keyboard, unless the
`controls` setting overrides (`auto | touch | desktop`; Settings panel, "Controls"). Studio's
device emulator keeps a keyboard, so pick `touch` there.

Default quality on a touch device is 1 (figure budget, no near tier, fewer smoke parts: the
existing quality-1 paths in Figures/Effects/Props/Lighting; nothing new there).

## Gestures (`src/client/Touch.luau`, pure; `Input` and `Camera` drive it)

One finger, from its first position: moved more than `DRAG_PX` (12) before `HOLD_S` (0.35 s)
= **drag**; still for `HOLD_S` = **hold**; moving after a hold = **hold-drag**; released before
either = **tap**. Two fingers cancel the one-finger gesture: pinch zooms (height), twist rotates
yaw (`UserInputService.TouchPinch/TouchRotate`). Taps on the GUI never reach the field.

| Gesture | On | Battle | Deployment |
| --- | --- | --- | --- |
| tap | own unit | toggle in selection (first tap selects) | select |
| tap | enemy / ghost | engage with the selection (Charge/Move/Attack-move if armed) | – |
| tap | ground | clear selection; armed order goes here | clear |
| drag | ground | pan the camera | pan |
| drag | own unit | pan | re-place the unit |
| hold | selected own unit | radial order wheel | – |
| hold | unselected own unit | select it and open the wheel | – |
| hold | ground, selection | anchor; release = move there | – |
| hold-drag | ground, selection | line placement along the drag, facing its left (as desktop right-drag) | – |
| hold-drag | own unit | – | set its facing |
| hold | ground, no selection | ping (co-op) | ping (co-op) |
| double tap | unit card | centre the camera on it (same as desktop double-click) | – |

Order wheel (`UI/OrderWheel`): eight brass plaques on a gilt ring around the finger: Move,
Attack-move, Charge, Hold, Square, Line, Column, Retreat. Slide onto a plaque and lift to pick.
Move / Attack-move / Charge arm the order; the next tap on the field gives the point or target.
The rest are sent at once through the HUD's command runner.

## UI scale (`Touch.scale`, applied by `Kit.screen` as a UIScale on every screen)

Desktop 1. Touch: short side under 600 px (phones) 1.5, otherwise (tablets) 1.15. 30 px
plaques then meet the 44 px tap target. Code that compares `AbsoluteSize` against offsets
divides by `Kit.scale()`.

Touch HUD: minimap top-left under the bar, ticker beside it, player list collapsible, Help in
the pause menu, Settings / Menu / Select all and the command panel grouped bottom-right, no
inspector (the card and its tooltip carry the numbers), card bar scrolls by finger. Panels
(Settings, Deployment) scroll inside a frame sized to the viewport.

## Tests

`tests/touch.spec.luau`: gesture phases by time and distance, detection and the scale function.
