#!/usr/bin/env bash
#
# Undo tools/strip.sh.
#
#   ./tools/restore.sh                 restore everything in tools/removed.log
#   ./tools/restore.sh <package>       restore just that one package
#
# Uses `cmd package install-existing`, which re-enables the copy still sitting in
# the system image for user 0. It only works for packages that were removed with
# `pm uninstall -k --user 0` — i.e. exactly what strip.sh does.
#
set -euo pipefail

TOOLS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOVED_LOG="$TOOLS/removed.log"

command -v adb >/dev/null 2>&1 || {
  echo "error: adb not on PATH. Add \$ANDROID_HOME/platform-tools to your PATH." >&2
  exit 1
}

# --- exactly one device ---------------------------------------------------
# `adb start-server` returns before the USB bus has been enumerated, so a cold
# adb server honestly reports zero devices for a second or so. Poll instead of
# trusting the first answer, then re-read once things have settled.
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
  echo "error: $COUNT devices connected; refusing to guess which one." >&2
  adb devices >&2
  exit 1
fi

echo "device:  $DEVICES"

# --- what to restore ------------------------------------------------------
TARGETS=()
SINGLE=0

if [[ "$#" -gt 1 ]]; then
  echo "error: pass at most one package name." >&2
  exit 1
elif [[ "$#" -eq 1 ]]; then
  TARGETS=("$1")
  SINGLE=1
  echo "source:  argument"
else
  [[ -f "$REMOVED_LOG" ]] || {
    echo "error: $REMOVED_LOG does not exist — nothing has been stripped yet." >&2
    echo "       To restore one package anyway: $0 <package>" >&2
    exit 1
  }
  echo "source:  $REMOVED_LOG"
  # De-duplicate, preserving first-seen order, in case a package was stripped
  # and restored more than once.
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    line="${raw%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    for seen in ${TARGETS[@]+"${TARGETS[@]}"}; do
      [[ "$seen" == "$line" ]] && continue 2
    done
    TARGETS+=("$line")
  done < "$REMOVED_LOG"
fi

echo

if [[ "${#TARGETS[@]}" -eq 0 ]]; then
  echo "Nothing to restore."
  exit 0
fi

OK=0
FAILED=0
for pkg in "${TARGETS[@]}"; do
  printf 'restoring %s ... ' "$pkg"
  out="$(adb shell cmd package install-existing "$pkg" 2>&1 | tr -d '\r')"
  if [[ "$out" == *installed* || "$out" == *Success* ]]; then
    echo "ok"
    OK=$((OK + 1))
  else
    echo "FAILED: $out"
    FAILED=$((FAILED + 1))
  fi
done

echo
echo "restored $OK, failed $FAILED"

if [[ "$SINGLE" -eq 0 && "$OK" -gt 0 && "$FAILED" -eq 0 ]]; then
  echo
  echo "Everything in removed.log is back. Clear the log so it reflects reality:"
  echo "    rm $REMOVED_LOG"
fi
exit 0
