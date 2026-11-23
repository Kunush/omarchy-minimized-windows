# Minimized Windows

An Omarchy shell plugin that adds a proper minimize to Hyprland: minimize any
window on any layout, then bring windows back from a row of floating glass
cards along the bottom of the screen, each with a live preview.

## Features

- **Minimize anywhere**: works on tiled and floating workspaces, not just where
  the dock is shown.
- **Live previews**: each card shows what the window looks like right now,
  captured when the row opens, even though the window is hidden.
- **Restore several in a row**: click a card to bring that window back; the
  row stays open so you can click the next one.
- **Restore all**: one button brings every minimized window back.
- **Close from the card**: the ✕ in a card's corner closes that app. Apps can
  still ask to save first; if one does, it is brought back so you can answer.
- **Follows your theme**: uses the same colors as Omarchy's dock and popups,
  with see-through glass cards.
- **Dock compatible**: uses the same hidden workspace and tags as Omarchy's
  own minimize, so the dock on floating workspaces still sees these windows.

## Requirements

Omarchy with the Quattro shell (`omarchy-shell`). It uses `hyprctl`, `jq` and
`grim`, which Omarchy already includes.

## Install

```bash
omarchy plugin add https://github.com/Kunush/omarchy-minimized-windows --enable
```

## Keyboard shortcuts

Plugins can't add Hyprland shortcuts themselves, so add these to
`~/.config/hypr/bindings.lua` (pick other keys if you like):

```lua
-- Minimize the active window
o.rebind("SUPER + M", "Minimize window", "omarchy-shell kunush.minimized-windows minimize")
-- Bring back the most recently minimized window
o.bind("SUPER + ALT + M", "Restore minimized window", "omarchy-shell kunush.minimized-windows restoreLast")
-- Show the minimized windows
o.bind("SUPER + CTRL + M", "Minimized windows", { panel = "kunush.minimized-windows" })
```

Hyprland reloads the file on save.

## Using the row

| Action | Mouse | Keyboard |
|---|---|---|
| Bring a window back | Click its card | ← → then Enter |
| Bring all back | **Restore all** | Ctrl+A |
| Close an app | ✕ on its card | Delete |
| Scroll | Mouse wheel | ← → |
| Close the row | Click outside | Esc |

## Optional: blur behind the cards

The cards are see-through. For Omarchy's "glassy" blur behind them, add this to
`~/.config/hypr/looknfeel.lua`:

```lua
hl.layer_rule({
  match = { namespace = "^minimized-windows$" },
  blur = true,
  ignore_alpha = 0.3,
  no_anim = true,
})
```

## Shell commands

```bash
omarchy-shell shell toggle kunush.minimized-windows        # show/hide the row
omarchy-shell kunush.minimized-windows minimize            # minimize the active window
omarchy-shell kunush.minimized-windows restoreLast         # restore the most recent one
```

## How it works and what it touches

- Minimized windows are moved to Hyprland's `special:minimized` workspace and
  tagged with the workspace they came from.
- Previews are small JPEGs in `$XDG_RUNTIME_DIR/omarchy-minimized-windows/`
  (memory-backed, cleared on logout). Previews of windows that are no longer
  minimized are deleted automatically.
- The plugin runs its bundled `minimize.sh` with `bash`. It only passes window
  addresses it read from `hyprctl` and checked against `^0x[0-9a-f]+$`.
- No network access, no elevated privileges, no background services.

## Remove

```bash
omarchy plugin remove kunush.minimized-windows
```

Then delete the shortcut lines (and the blur rule) you added. Any windows still
minimized stay on the hidden workspace; bring them back first, or move them
with Hyprland.

## License

MIT
