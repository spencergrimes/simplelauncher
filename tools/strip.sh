#!/usr/bin/env bash
#
# Remove the packages listed in tools/packages.txt from user 0 of the connected
# device.
#
#   ./tools/strip.sh            dry run — prints what it WOULD do, touches nothing
#   ./tools/strip.sh --apply    actually runs the uninstalls
#
# Uses `pm uninstall -k --user 0`, which removes the package for the current user
# but leaves the APK in the system image, so tools/restore.sh can bring it back.
# Everything successfully removed is appended to tools/removed.log.
#
set -euo pipefail

TOOLS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_FILE="$TOOLS/packages.txt"
REMOVED_LOG="$TOOLS/removed.log"

# --------------------------------------------------------------------------
# Packages this script will never remove, no matter what packages.txt says.
# Pulling any of these bricks something you cannot get back without a reflash:
# Play Services and Play Store (auth, notifications, most app installs), GSF
# (account sync), the dialer/telecom stack (phone calls), SystemUI (status bar,
# nav bar, notification shade — the phone becomes unusable), the permission
# controller (every runtime permission dialog), SMS, and this launcher itself.
# --------------------------------------------------------------------------
PROTECTED=(
  com.google.android.gms                     # Google Play services
  com.android.vending                        # Google Play Store
  com.google.android.gsf                     # Google Services Framework
  com.android.phone                          # telephony / phone process
  com.android.server.telecom                 # call routing
  com.android.systemui                       # status bar, nav bar, shade
  com.google.android.permissioncontroller    # runtime permission UI
  com.google.android.apps.messaging          # Messages (SMS)
  com.example.simplelauncher                 # this launcher
  com.android.settings                       # Settings — the way out of a mess
  com.google.android.dialer                  # Phone app
)

APPLY=0
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "error: unknown argument '$arg' (only --apply is supported)" >&2; exit 1 ;;
  esac
done

command -v adb >/dev/null 2>&1 || {
  echo "error: adb not on PATH. Add \$ANDROID_HOME/platform-tools to your PATH." >&2
  exit 1
}
[[ -f "$PACKAGES_FILE" ]] || { echo "error: $PACKAGES_FILE not found." >&2; exit 1; }

# --- exactly one device ---------------------------------------------------
# `adb start-server` returns before the USB bus has been enumerated, so a cold
# adb server honestly reports zero devices for a second or so. Poll instead of
# trusting the first answer, then re-read once things have settled — mistaking a
# two-device setup for a one-device setup would uninstall from the wrong phone.
detect_devices() {
  local i found
  adb start-server >/dev/null 2>&1 || true
  for i in $(seq 1 20); do
    found="$(adb devices | awk 'NR>1 && $2=="device" {print $1}')"
    if [[ -n "$found" ]]; then
      sleep 0.5
      adb devices | awk 'NR>1 && $2=="device" {print $1}'
      return 0
    fi
    sleep 0.5
  done
  return 1
}

DEVICES="$(detect_devices || true)"
COUNT="$(printf '%s\n' "$DEVICES" | grep -c . || true)"

if [[ "$COUNT" -eq 0 ]]; then
  echo "error: no device. Plug in the phone and enable USB debugging." >&2
  adb devices >&2
  exit 1
elif [[ "$COUNT" -gt 1 ]]; then
  echo "error: $COUNT devices connected. Uninstalling from the wrong phone is not" >&2
  echo "       something you can undo casually — refusing to guess." >&2
  adb devices >&2
  exit 1
fi

is_protected() {
  local candidate="$1" p
  for p in "${PROTECTED[@]}"; do
    [[ "$candidate" == "$p" ]] && return 0
  done
  return 1
}

# --- read packages.txt ----------------------------------------------------
# Strip comments (whole-line and trailing) and surrounding whitespace.
WANTED=()
while IFS= read -r raw || [[ -n "$raw" ]]; do
  line="${raw%%#*}"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [[ -z "$line" ]] && continue
  WANTED+=("$line")
done < "$PACKAGES_FILE"

echo "device:   $DEVICES"
echo "list:     $PACKAGES_FILE"
if [[ "$APPLY" -eq 1 ]]; then
  echo "mode:     APPLY — packages will actually be removed"
else
  echo "mode:     DRY RUN — nothing will be changed (pass --apply to do it for real)"
fi
echo

if [[ "${#WANTED[@]}" -eq 0 ]]; then
  echo "Nothing uncommented in packages.txt. Nothing to do."
  exit 0
fi

# --- protected check, loudly ---------------------------------------------
BLOCKED=()
for pkg in "${WANTED[@]}"; do
  is_protected "$pkg" && BLOCKED+=("$pkg")
done

if [[ "${#BLOCKED[@]}" -gt 0 ]]; then
  echo "########################################################################"
  echo "##  WARNING: PROTECTED PACKAGES LISTED IN packages.txt                ##"
  echo "########################################################################"
  for pkg in "${BLOCKED[@]}"; do
    echo "##  REFUSING TO REMOVE: $pkg"
  done
  echo "##"
  echo "##  These are on the hardcoded PROTECTED list in this script because"
  echo "##  removing them breaks calls, notifications, the status bar, app"
  echo "##  installs, or this launcher itself. They will be SKIPPED."
  echo "##"
  echo "##  Take them out of packages.txt. If you genuinely mean it, you will"
  echo "##  have to edit the PROTECTED array in $0 by hand — that friction is"
  echo "##  the entire point."
  echo "########################################################################"
  echo
fi

# --- installed check ------------------------------------------------------
INSTALLED="$(adb shell pm list packages --user 0 2>/dev/null | sed 's/^package://' | tr -d '\r')"

is_installed() {
  printf '%s\n' "$INSTALLED" | grep -qx "$1"
}

TARGETS=()
for pkg in "${WANTED[@]}"; do
  if is_protected "$pkg"; then
    printf '  %-12s %s\n' "protected" "$pkg"
  elif ! is_installed "$pkg"; then
    printf '  %-12s %s\n' "not-found" "$pkg"
  else
    printf '  %-12s %s\n' "will-remove" "$pkg"
    TARGETS+=("$pkg")
  fi
done
echo

if [[ "${#TARGETS[@]}" -eq 0 ]]; then
  echo "Nothing to remove."
  exit 0
fi

if [[ "$APPLY" -eq 0 ]]; then
  echo "Dry run: ${#TARGETS[@]} package(s) would be removed. Re-run with --apply."
  exit 0
fi

# --- do it ----------------------------------------------------------------
OK=0
FAILED=0
for pkg in "${TARGETS[@]}"; do
  printf 'removing %s ... ' "$pkg"
  out="$(adb shell pm uninstall -k --user 0 "$pkg" 2>&1 | tr -d '\r')"
  if [[ "$out" == *Success* ]]; then
    echo "ok"
    printf '%s\n' "$pkg" >> "$REMOVED_LOG"
    OK=$((OK + 1))
  else
    echo "FAILED: $out"
    FAILED=$((FAILED + 1))
  fi
done

echo
echo "removed $OK, failed $FAILED"
[[ "$OK" -gt 0 ]] && echo "logged to $REMOVED_LOG — undo with ./tools/restore.sh"
exit 0
