#!/bin/bash
# Window minimizing for the Minimized Windows plugin. Called by the plugin's
# QML (never with untrusted text: every address is checked against ^0x[0-9a-f]+$).
#
#   minimize.sh minimize                     minimize the active window
#   minimize.sh restore-last                 bring back the most recently minimized window
#   minimize.sh restore <address>...         bring back these windows, in the order given
#   minimize.sh close <address>              close a minimized window (the app may ask to save)
#   minimize.sh previews                     capture a preview of every minimized window
#
# Minimized windows live on the special:minimized workspace with an
# omarchy-minimized-from-<workspace> tag, the same as Omarchy's own dock
# minimize, so the dock on floating workspaces still sees and restores them.
#
# Needs: hyprctl, jq, grim (all part of Omarchy).

set -u

PREVIEW_DIR="${XDG_RUNTIME_DIR:-/tmp}/omarchy-minimized-windows"
MINIMIZED="special:minimized"

valid_address() { [[ $1 =~ ^0x[0-9a-f]+$ ]]; }

is_minimized() {
  hyprctl clients -j | jq -e --arg a "$1" --arg w "$MINIMIZED" \
    'any(.[]; .address == $a and .workspace.name == $w)' >/dev/null
}

dispatch() { hyprctl dispatch "$1" >/dev/null; }

# Captures each minimized window by its toplevel id. This works while the
# window is hidden and isn't affected by windows on top of it. Previews of
# windows that are no longer minimized are removed.
save_previews() {
  local addr sid keep file
  mkdir -p "$PREVIEW_DIR"
  while read -r addr sid; do
    valid_address "$addr" && [[ $sid =~ ^[0-9a-f]+$ ]] || continue
    grim -T "$sid" -s 0.3 -t jpeg -q 80 "$PREVIEW_DIR/$addr.jpg" 2>/dev/null &
  done < <(hyprctl clients -j | jq -r --arg w "$MINIMIZED" '.[] | select(.workspace.name == $w) | "\(.address) \(.stableId)"')
  wait

  keep=$(hyprctl clients -j | jq -r --arg w "$MINIMIZED" '.[] | select(.workspace.name == $w) | .address')
  for file in "$PREVIEW_DIR"/*.jpg; do
    [[ -e $file ]] || continue
    grep -qxF "$(basename "$file" .jpg)" <<<"$keep" || rm -f "$file"
  done
}

clear_minimized_tags() {
  local address=$1 tag
  while read -r tag; do
    [[ $tag =~ ^omarchy-minimized-from-[0-9]+$ ]] || continue
    dispatch "hl.dsp.window.tag({ tag = \"-$tag\", window = \"address:$address\" })"
  done < <(hyprctl clients -j | jq -r --arg a "$address" '.[] | select(.address == $a) | (.tags // [])[]')
}

# Moves a minimized window onto the current workspace and focuses it.
restore_window() {
  local address=$1 current
  current=$(hyprctl activeworkspace -j | jq -r '.id')
  [[ $current =~ ^-?[0-9]+$ ]] || return 1
  clear_minimized_tags "$address"
  dispatch "hl.dsp.window.move({ workspace = \"$current\", follow = true, window = \"address:$address\" })"
  dispatch "hl.dsp.focus({ window = \"address:$address\" })"
  rm -f "$PREVIEW_DIR/$address.jpg"
}

minimize_active() {
  local address workspace
  read -r address workspace < <(hyprctl activewindow -j | jq -r '"\(.address // "") \(.workspace.id // "")"')
  valid_address "${address:-}" && [[ ${workspace:-} =~ ^[0-9]+$ ]] || return 1

  clear_minimized_tags "$address"
  dispatch "hl.dsp.window.tag({ tag = \"+omarchy-minimized-from-$workspace\", window = \"address:$address\" })"
  dispatch "hl.dsp.window.move({ workspace = \"$MINIMIZED\", follow = false, window = \"address:$address\" })"
  # Keep focus on the workspace, or the next window opened would join the
  # minimized one on the hidden workspace.
  dispatch "hl.dsp.focus({ workspace = \"$workspace\" })"
}

notify_none() {
  omarchy osd -i '󰖯' -m "${1:-No minimized windows}" >/dev/null 2>&1 &
}

case "${1:-}" in
  minimize)
    minimize_active
    ;;
  restore-last)
    # Lowest focusHistoryID = focused most recently = minimized most recently.
    address=$(hyprctl clients -j | jq -r --arg w "$MINIMIZED" '
      [.[] | select(.workspace.name == $w)] | sort_by(.focusHistoryID) | first | .address // empty')
    if valid_address "${address:-}"; then restore_window "$address"; else notify_none "${2:-}"; fi
    ;;
  restore)
    shift
    for address in "$@"; do
      valid_address "$address" && is_minimized "$address" && restore_window "$address"
    done
    ;;
  close)
    address=${2:-}
    valid_address "$address" && is_minimized "$address" || exit 1
    # A polite close, like Super+W: the app can still ask to save first.
    dispatch "hl.dsp.window.close({ window = \"address:$address\" })"
    rm -f "$PREVIEW_DIR/$address.jpg"
    # Still open a moment later: it's probably asking something, so bring it
    # back where the question can be answered.
    sleep 1
    is_minimized "$address" && restore_window "$address"
    ;;
  previews)
    save_previews
    ;;
  *)
    echo "usage: $0 minimize | restore-last | restore <address>... | close <address> | previews" >&2
    exit 2
    ;;
esac
