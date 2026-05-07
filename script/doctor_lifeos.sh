#!/bin/bash
set -euo pipefail

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

ROOT_DIR="$(cd "$(/usr/bin/dirname "${BASH_SOURCE[0]}")/.." && /bin/pwd)"
APP_NAME="LifeOS"
BUNDLE_ID="local.codex.lifeos"
ROOT_APP_BUNDLE="$ROOT_DIR/LifeOS.app"
STORE="$HOME/Library/Application Support/LifeOSData.store"
FAILURES=0

pass() {
  echo "PASS: $1"
}

fail() {
  echo "FAIL: $1" >&2
  FAILURES=$((FAILURES + 1))
}

check_equals() {
  local label="$1"
  local actual="$2"
  local expected="$3"

  if [[ "$actual" == "$expected" ]]; then
    pass "$label = $actual"
  else
    fail "$label expected $expected, got $actual"
  fi
}

if [[ -d "$ROOT_APP_BUNDLE" ]]; then
  pass "root app exists at $ROOT_APP_BUNDLE"
else
  fail "root app missing at $ROOT_APP_BUNDLE"
fi

for old_entry in "$ROOT_DIR/Life OS.app" "$ROOT_DIR/Life OS Stop.app"; do
  if [[ -e "$old_entry" ]]; then
    fail "old app entry still exists: $old_entry"
  else
    pass "old app entry absent: $old_entry"
  fi
done

if [[ -f "$ROOT_APP_BUNDLE/Contents/Info.plist" ]]; then
  actual_bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$ROOT_APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true)"
  check_equals "bundle id" "$actual_bundle_id" "$BUNDLE_ID"

  keep_windows="$(/usr/libexec/PlistBuddy -c 'Print :NSQuitAlwaysKeepsWindows' "$ROOT_APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true)"
  check_equals "NSQuitAlwaysKeepsWindows" "$keep_windows" "false"
else
  fail "root app Info.plist missing"
fi

if "$ROOT_DIR/script/repair_lifeos_store.sh" --check "$STORE" >/tmp/lifeos_store_check.log 2>&1; then
  pass "SwiftData store has no invalid references"
else
  fail "SwiftData store check failed: $(/bin/cat /tmp/lifeos_store_check.log)"
fi

process_count="$(pgrep -x "$APP_NAME" 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
check_equals "process count" "$process_count" "1"

if [[ "$process_count" == "1" ]]; then
  /usr/bin/osascript <<OSA >/dev/null 2>&1 || true
tell application id "$BUNDLE_ID"
  reopen
  activate
end tell
delay 0.5
tell application "System Events"
  tell process "$APP_NAME"
    set frontmost to true
    if (count windows) > 0 then perform action "AXRaise" of window 1
  end tell
end tell
OSA
fi

window_count="$(/usr/bin/osascript -e "tell application \"System Events\" to tell process \"$APP_NAME\" to count windows" 2>/dev/null || echo "0")"
check_equals "window count" "$window_count" "1"

frontmost="$(/usr/bin/osascript -e 'tell application "System Events" to name of first application process whose frontmost is true' 2>/dev/null || echo "")"
check_equals "frontmost app" "$frontmost" "$APP_NAME"

if [[ "$FAILURES" -gt 0 ]]; then
  echo "LifeOS doctor failed with $FAILURES issue(s)." >&2
  exit 1
fi

echo "LifeOS doctor passed."
