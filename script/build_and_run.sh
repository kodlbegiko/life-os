#!/bin/bash
set -euo pipefail

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

MODE="${1:-run}"
APP_NAME="LifeOS"
PROJECT_NAME="LifeOS.xcodeproj"
SCHEME_NAME="LifeOS"
BUNDLE_ID="local.codex.lifeos"
ROOT_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/.." && /bin/pwd)"
XCODE_DIR="/Applications/Xcode.app/Contents/Developer"
DERIVED_DATA="$ROOT_DIR/dist/DerivedData"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
ROOT_APP_BUNDLE="$ROOT_DIR/LifeOS.app"
TMP_ERR="$(/usr/bin/mktemp)"
trap 'rm -f "$TMP_ERR"' EXIT
DESTINATION_ARGS=()

if [[ ! -d "$XCODE_DIR" ]]; then
  echo "Xcode.app not found at /Applications/Xcode.app." >&2
  exit 1
fi

export DEVELOPER_DIR="$XCODE_DIR"

if [[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" == "1" ]]; then
  DESTINATION_ARGS=(-destination "platform=macOS,arch=arm64")
fi

if ! xcodebuild -version >"$TMP_ERR" 2>&1; then
  if grep -qi "license" "$TMP_ERR"; then
    echo "Xcode is installed but the license is not accepted yet." >&2
    echo "Run: sudo xcodebuild -license accept" >&2
    echo "Then: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  else
    cat "$TMP_ERR" >&2
  fi
  exit 1
fi

ensure_root_app_bundle() {
  if [[ -L "$ROOT_APP_BUNDLE" ]]; then
    /bin/rm -f "$ROOT_APP_BUNDLE"
  elif [[ -e "$ROOT_APP_BUNDLE" ]]; then
    /bin/rm -rf "$ROOT_APP_BUNDLE"
  fi

  /usr/bin/ditto "$APP_BUNDLE" "$ROOT_APP_BUNDLE"
  /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted "$ROOT_APP_BUNDLE" >/dev/null 2>&1 || true
}

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

xcodebuild \
  -project "$ROOT_DIR/$PROJECT_NAME" \
  -scheme "$SCHEME_NAME" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  "${DESTINATION_ARGS[@]}" \
  build

ensure_root_app_bundle

open_app() {
  if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    /usr/bin/osascript <<OSA >/dev/null 2>&1 || true
tell application id "$BUNDLE_ID"
  reopen
  activate
end tell
OSA
  else
    /usr/bin/open "$ROOT_APP_BUNDLE"
  fi
}

wait_for_process() {
  local attempts="${1:-20}"
  local delay="${2:-0.25}"

  for ((i = 0; i < attempts; i++)); do
    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
      return 0
    fi
    sleep "$delay"
  done

  return 1
}

activate_app() {
  /usr/bin/osascript <<OSA >/dev/null 2>&1 || true
tell application id "$BUNDLE_ID"
  reopen
  activate
end tell
delay 0.2
tell application "System Events"
  tell process "$APP_NAME"
    set frontmost to true
    if (count windows) > 0 then perform action "AXRaise" of window 1
  end tell
end tell
OSA
}

launch_and_focus() {
  open_app
  wait_for_process
  activate_app
}

verify_app_state() {
  local process_count
  local window_count
  local frontmost

  process_count="$(pgrep -x "$APP_NAME" 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
  window_count="$(/usr/bin/osascript -e "tell application \"System Events\" to tell process \"$APP_NAME\" to count windows" 2>/dev/null || echo "0")"
  frontmost="$(/usr/bin/osascript -e 'tell application "System Events" to name of first application process whose frontmost is true' 2>/dev/null || echo "")"

  echo "process=$process_count"
  echo "windows=$window_count"
  echo "front=$frontmost"

  [[ "$process_count" == "1" && "$window_count" == "1" && "$frontmost" == "$APP_NAME" ]]
}

case "$MODE" in
  run)
    launch_and_focus
    ;;
  --debug|debug)
    lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    ;;
  --logs|logs)
    launch_and_focus
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    launch_and_focus
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    launch_and_focus
    verify_app_state
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
