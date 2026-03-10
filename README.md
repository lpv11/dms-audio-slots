# dms-audio-slots

Daemon plugin for **Dank Material Shell** that provides IPC controls for:

- Cycling between saved output audio devices
- Cycling between saved input audio devices
- Toggling mute for the focused app

No bar widget is required.

## Features

- Runs as a DMS `daemon` plugin
- Save up to 4 output slots and 4 input slots
- `Disabled` option per slot
- IPC commands for output/input/app-mute
- Configurable notifications:
  - DMS toast
  - `notify-send`
  - Hyprland `hyprctl notify`
- Focused-app mute supports compositor metadata from DMS and PID-based matching for better app detection

## IPC Commands

```bash
dms ipc audioOutputs toggle
dms ipc audioInputs toggle
dms ipc audioAppMute toggle
```

## Manual Installation

```bash
git clone https://github.com/lpv11/dms-audio-slots.git ~/.config/DankMaterialShell/plugins/dms-audio-slots
```

In Settings -> Plugins click Scan, then enable the plugin.
Restart dms with `dms restart` or from DMS power menu if it does not load.

## Settings

- **Output slot 1/2/3/4**: Saved output devices for cycling
- **Input slot 1/2/3/4**: Saved input devices for cycling
- **Notification backend**:
  - `DMS toast`
  - `Desktop notify-send`
  - `Hyprland (hyprctl notify)`

## Notes

- The plugin is daemon-only and does not need bar placement.
- App-mute behavior depends on available app/window metadata and PulseAudio stream metadata.
- If a selected slot device is currently unavailable, it is skipped.

## Settings screenshot

![Alt text](https://github.com/lpv11/dms-audio-slots/blob/main/screenshot.png?raw=true&v=20260310 "")
