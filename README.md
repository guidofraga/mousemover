# Mouse Mover

A lightweight native macOS menu-bar utility that periodically flicks the mouse cursor by two pixels and returns it to its original position.

## Run

```sh
swift run
```

To install it as a normal app that can be launched from Spotlight or Raycast:

```sh
make install
```

This builds `MouseMover.app` into `/Applications` and opens it. After that, launch **Mouse Mover** directly from Spotlight or Raycast; Terminal does not need to remain open.

It remembers whether it was on when you last quit and restores that state at launch (it starts on the very first run), so the first time you run it, allow Mouse Mover in **System Settings > Privacy & Security > Accessibility**. Use the menu-bar cursor icon to turn it on or off, flick once right away with **Flick Now**, choose the flick interval (presets or a custom value in seconds), and choose when it should automatically turn off. While it is off, picking a **Turn Off After** option also turns it on with that setting.

On macOS 13 and later, turn on **Launch at Login** to have Mouse Mover start by itself when you log in. If Accessibility permission is revoked while it is running, Mouse Mover turns itself off, marks the status line as needing permission, and reopens the Accessibility pane. After you grant permission, the status clears the next time you open the menu.

The app stores its interval and automatic shutoff setting in standard macOS user defaults. It does not require a background service or network access.

## How "Turn Off After" works

The auto-shutoff countdown is plain wall-clock time from the moment you turn it on: 30 minutes means the app turns off after exactly 30 real minutes, whether you were active or not. It does not wait for you to go idle and does not reset when you use the Mac. Changing the duration while running restarts the countdown; changing the flick interval does not. Setting the duration while off turns it on.

## Notes

- Rebuilding and reinstalling the app (`make install`) gives it a new ad-hoc code signature, which may cause macOS to ask you to re-grant the Accessibility permission after an update.
- `make uninstall` removes the app from `/Applications`.
