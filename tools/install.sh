#!/usr/bin/env bash
#
# Build the debug APK and push it to the connected device.
#
# This does NOT make SimpleLauncher your default home app. It prints the command
# to do that and stops, so you can launch it by hand first and confirm it works.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PKG="com.example.simplelauncher"
ACTIVITY="$PKG/.MainActivity"
APK="app/build/outputs/apk/debug/app-debug.apk"

# There is no real `java` on the PATH on this machine; Android Studio's bundled
# JBR is the toolchain Gradle expects. Respect an already-set JAVA_HOME if there
# is one.
#
# Note this tests that java actually RUNS, not that the binary exists: macOS ships
# a /usr/bin/java stub that resolves fine under `command -v` and then does nothing
# but tell you to go install a JRE.
if [[ -z "${JAVA_HOME:-}" ]] && ! java -version >/dev/null 2>&1; then
  STUDIO_JBR="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
  if [[ -x "$STUDIO_JBR/bin/java" ]]; then
    export JAVA_HOME="$STUDIO_JBR"
  else
    echo "error: no java found. Install a JDK or set JAVA_HOME." >&2
    exit 1
  fi
fi

command -v adb >/dev/null 2>&1 || {
  echo "error: adb not on PATH. Add \$ANDROID_HOME/platform-tools to your PATH." >&2
  exit 1
}

# --- exactly one device ---------------------------------------------------
# `adb start-server` returns before the USB bus has been enumerated, so a cold
# adb server honestly reports zero devices for a second or so. Poll instead of
# trusting the first answer, then re-read once things have settled so a second
# device that enumerates slowly still gets noticed.
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
echo

# --- build ----------------------------------------------------------------
echo "==> building debug APK"
./gradlew :app:assembleDebug

[[ -f "$APK" ]] || { echo "error: expected APK at $APK but it is not there." >&2; exit 1; }

# --- install --------------------------------------------------------------
echo
echo "==> installing $APK"
# -r reinstall over an existing copy, -t allow test/debug builds
adb install -r -t "$APK"

cat <<EOF

==> installed: $PKG

Launch it by hand and poke at it:

    adb shell am start -n $ACTIVITY

Note that this is the ONLY way in until you set it as the default home app.
Pressing home will not get you there: if the device already has a default home
app (a stock Pixel does), Android goes straight to it without offering a
chooser. And SimpleLauncher has no LAUNCHER category and sets
excludeFromRecents, so it is in neither the app drawer nor recents — by design.

So: expect to leave it the moment you open any app from it. Re-run the command
above to get back while you are still testing.

When you are happy with it, make it the default home app yourself:

    adb shell cmd package set-home-activity $ACTIVITY

To hand control back to the stock Pixel launcher:

    adb shell cmd package set-home-activity com.google.android.apps.nexuslauncher/.NexusLauncherActivity

EOF
