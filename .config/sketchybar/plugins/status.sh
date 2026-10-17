#!/usr/bin/env bash
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
plugin_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
appearance="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/desktop/appearance.sh"
if [[ -r $appearance ]]; then
  # shellcheck source=/dev/null
  source "$appearance"
fi
case "${SENDER:-}" in
  mouse.entered) sketchybar --set "$NAME" background.drawing=on background.color="${UI_HOVER:-0xff29313b}" ;;
  mouse.exited) sketchybar --set "$NAME" background.drawing=off ;;
esac
if [[ ${SENDER:-} == mouse.entered || ${SENDER:-} == mouse.clicked ]]; then
  menu_index=''
  case "${NAME:-}" in
    apple) menu_index=0 ;;
    front_app) menu_index=1 ;;
    app_menu.*) menu_index=$(( ${NAME#app_menu.} + 2 )) ;;
  esac
  if [[ -n $menu_index ]]; then
    python3 -B "$plugin_dir/controls.py" cancel all
    exec "${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/desktop/desktop-edge" --app-menu "$menu_index"
  fi
fi
case "${SENDER:-}" in
  mouse.entered)
    exec python3 -B "$plugin_dir/controls.py" hover "$NAME"
    ;;
  mouse.exited)
    exec python3 -B "$plugin_dir/controls.py" leave "$NAME"
    ;;
  mouse.clicked)
    exec python3 -B "$plugin_dir/controls.py" click "$NAME"
    ;;
  mouse.scrolled)
    exec python3 -B "$plugin_dir/controls.py" scroll "$NAME"
    ;;
esac
case "${NAME:-}" in
  weather)
    exec python3 -B "$plugin_dir/weather.py"
    ;;
  hover_guard)
    if [[ ${SENDER:-} == desktop_concealed ]]; then
      exec python3 -B "$plugin_dir/controls.py" cancel all
    fi
    exec python3 -B "$plugin_dir/controls.py" warm all
    ;;
  cpu)
    exec python3 -B "$plugin_dir/metrics.py"
    ;;
  wifi|bluetooth)
    exec python3 -B "$plugin_dir/controls.py" refresh "$NAME"
    ;;
  front_app)
    sketchybar --set "$NAME" label="${INFO:-Workstation}" \
      icon.background.image="app.${INFO:-Finder}"
    ;;
  clock)
    sketchybar --set "$NAME" label="$(/bin/date '+%-I:%M %p')"
    ;;
  battery)
    charge="$(pmset -g batt | sed -nE 's/.*[[:space:]]([0-9]+%);.*/\1/p')"
    sketchybar --set "$NAME" label="${charge:-AC}"
    ;;
  volume)
    volume="${INFO:-}"
    if [[ -z $volume || ! $volume =~ ^[0-9]+([.][0-9]+)?$ ]]; then
      volume="$(osascript -e 'output volume of (get volume settings)')"
    fi
    sketchybar --set "$NAME" label="${volume%%.*}%"
    ;;
esac
