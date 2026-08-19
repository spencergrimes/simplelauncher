# SimpleLauncher

A home screen with a clock and a short list of app names. No icons, no drawer, no
search, no widgets, no wallpaper, no gestures. Paper-coloured background, one font,
one weight.

- `minSdk` 30, Kotlin, Android Views (no Compose)
- Package: `com.example.simplelauncher`

---

## Build environment

Two things here look like mistakes and are not. **Don't "fix" either.**

**There is no Kotlin Gradle plugin, and that is correct.** AGP 9.3.1 compiles
Kotlin natively — `:app:compileDebugKotlin` runs with no
`org.jetbrains.kotlin.android` declared anywhere in `build.gradle.kts` or
`libs.versions.toml`. Adding one is unnecessary and risks colliding with AGP's
built-in support.

**There is no working `java` on this machine's `PATH`.** macOS ships a
`/usr/bin/java` stub that resolves fine under `command -v` and then does nothing
but tell you to install a JRE — so any `command -v java` guard is a false
positive. The real JDK is the one bundled with Android Studio. `install.sh`
handles this by testing whether `java -version` actually *executes*, not whether
the binary exists. To build by hand:

    JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" ./gradlew :app:assembleDebug

Gradle 9.5, JBR 25 (`toolchainVersion=25`), compileSdk/targetSdk 37.

---

## The app

### Editing the app list

Everything you'd want to change lives in one file:

    app/src/main/java/com/example/simplelauncher/AppList.kt

It is an ordered list of package names. Order in the file is order on screen. The
labels shown on screen are read from `PackageManager` at runtime, so a row says
whatever the device calls that app — nothing is hardcoded. A package that isn't
installed (or has no launcher activity) is silently dropped, so a stale or wrong
entry is harmless.

To find a package name for something on the phone:

    adb shell pm list packages | grep -i maps

Two entries ship commented as caveats, and both were **confirmed absent on the
actual test device**: **Pixel Weather** (`com.google.android.apps.weather`)
doesn't exist on this Pixel 5 build — weather lives inside the Google app there
and has no launcher entry — and **Google Authenticator**
(`com.google.android.apps.authenticator2`) is never preinstalled. Neither row
renders until those apps are present, which is the "silently omit" path working
as intended, not a fault. 7 of the 9 seeded packages resolve; the home screen
shows 7 rows.

### Behavior

| Action | Result |
| --- | --- |
| Tap a row | Launches the app |
| Long-press a row | Opens that app's system App Info page |
| Back button | Nothing. `OnBackPressedCallback`, not the deprecated `onBackPressed`. |
| Home while already home | Nothing (`singleTask` + a no-op `onNewIntent`) |
| App uninstalled while backgrounded | Row disappears — the list rebuilds in `onResume` |

The clock is driven by `ACTION_TIME_TICK` rather than a polling handler, and
respects the system 12/24-hour setting.

### Package visibility

The manifest declares a top-level `<queries>` element for `MAIN` +
`LAUNCHER`. Without it, Android 11+ package-visibility filtering makes
`getLaunchIntentForPackage()` return `null` for every package and nothing would
launch. `QUERY_ALL_PACKAGES` is deliberately not used — it's the broad permission
Play restricts, and the narrow `<queries>` declaration is all this needs.

---

## Installing

    ./tools/install.sh

Builds the debug APK with the Gradle wrapper and `adb install`s it. It refuses to
run unless exactly one device is attached.

It does **not** make SimpleLauncher your default home app. It prints the command
and stops, so you can try it first:

    adb shell am start -n com.example.simplelauncher/.MainActivity

### Before it's the default, that command is the only way in

This trips everyone up once. Until you run `set-home-activity`:

- **The home button won't take you there.** A stock Pixel already has Pixel
  Launcher set as the default home app, so Android goes straight to it and never
  shows a chooser.
- **It's not in the app drawer.** The intent-filter declares `HOME` + `DEFAULT`
  but not `LAUNCHER`, so it has no drawer entry — that's what keeps a launcher
  from listing itself.
- **It's not in recents.** `excludeFromRecents="true"`.

So the moment you tap an app from SimpleLauncher, you've left it, and pressing
home brings up Pixel Launcher instead. That is the design working correctly, not
a crash. Re-run `am start` to get back, or set it as default and the home button
starts doing the right thing.

When you're happy:

    adb shell cmd package set-home-activity com.example.simplelauncher/.MainActivity

**Undo** — hand control back to the Pixel launcher:

    adb shell cmd package set-home-activity com.google.android.apps.nexuslauncher/.NexusLauncherActivity

You can also do this from the device: Settings → Apps → Default apps → Home app.
That path keeps working even if the launcher itself misbehaves, which is why
`com.android.settings` is on the protected list below.

See [Build environment](#build-environment) for the `JAVA_HOME` situation.

### Reinstalling later may drop the default-home setting

Replacing a package can clear its preferred-activity status on some Android
versions. **This has not been tested on this device.** After any `install.sh`
that isn't the first one, press Home once — if you land on Pixel Launcher, just
re-run `set-home-activity` above.

---

## Living with it day to day

### Only the listed apps are reachable

This is the thing to understand before committing to it. There is no drawer and
no search, so the rows in `AppList.kt` are your *entire* reachable surface.
Notably **Play Store is not in the default list**, so nothing installs or updates
until you deal with that.

Ways to open an unlisted app without rebuilding:

- **Settings → Apps → See all apps → tap it → Open.** Settings is in the list, so
  this always works. This is the universal escape hatch.
- **Notifications.** Tapping one opens its app normally.
- **Links from other apps** resolve normally.
- **Assistant**, if enabled, still works off the power button.

If that friction isn't the point of the exercise, add `com.android.vending` (Play
Store) and a browser to `AppList.kt`.

### Changing the list

Edit `AppList.kt`, plug in, run `./tools/install.sh`. It reinstalls over the top.
Note the default-home caveat above.

### If something goes badly wrong

A launcher that crashes on boot is the one genuinely annoying failure mode. You
cannot actually get stuck:

- **Safe mode** — hold power → long-press "Power off" → Reboot to safe mode.
  Third-party launchers are disabled and the stock one comes back.
- **Settings → Apps → Default apps → Home app** — works from the device, no
  laptop needed. This is why `com.android.settings` is on the protected list.
- **adb** — `set-home-activity` back to `nexuslauncher`, or
  `adb uninstall com.example.simplelauncher`.

Worth rebooting once while you're near the laptop, just to confirm it comes up as
home on its own.

### The debug build is fine indefinitely

Debug-signed APKs don't expire in any way that matters (the debug keystore is
valid ~30 years), nothing auto-updates, and Play Store is not involved. There is
no need to make a release build for personal use.

---

## Stripping packages

### Workflow

1. **Edit the list.** Uncomment lines in `tools/packages.txt`. Everything ships
   commented out, so a fresh checkout removes nothing.

2. **Dry run.** This is the default — it prints what it would do and changes
   nothing:

       ./tools/strip.sh

   Each package is reported as `will-remove`, `protected`, or `not-found`.

3. **Apply.** Only an explicit flag actually removes anything:

       ./tools/strip.sh --apply

   Every successful removal is appended to `tools/removed.log`.

Both scripts verify that `adb` sees exactly one device before touching anything.

### Undo

Restore everything you've stripped:

    ./tools/restore.sh

Restore one package:

    ./tools/restore.sh com.android.chrome

Under the hood that's `adb shell cmd package install-existing <pkg>`. Once
everything is back, delete `tools/removed.log` so it reflects reality.

### What "removing" actually means

`strip.sh` runs:

    adb shell pm uninstall -k --user 0 <pkg>

This uninstalls the package **for user 0 only**. The APK stays in the read-only
system partition, which is exactly why `install-existing` can bring it back. No
root, no unlocked bootloader, nothing is wiped from the device.

### Protected packages

`strip.sh` has a hardcoded `PROTECTED` array it refuses to touch under any
circumstance. If one shows up in `packages.txt`, the script prints a loud banner
and skips it:

| Package | Why |
| --- | --- |
| `com.google.android.gms` | Play services — auth, notifications, location |
| `com.android.vending` | Play Store |
| `com.google.android.gsf` | Google Services Framework — account sync |
| `com.android.phone` | Telephony process |
| `com.android.server.telecom` | Call routing |
| `com.android.systemui` | Status bar, nav bar, notification shade |
| `com.google.android.permissioncontroller` | Every runtime permission dialog |
| `com.google.android.apps.messaging` | SMS |
| `com.example.simplelauncher` | This launcher |
| `com.android.settings` | Settings — the way out of a mess |
| `com.google.android.dialer` | Phone app |

Overriding this means editing the array in `tools/strip.sh` by hand. That friction
is intentional.

### Candidates seeded in `packages.txt`

All commented out: Chrome, YouTube, YouTube Music, Google TV, Play Games, the
Google app (`quicksearchbox`), Drive, Docs/Sheets/Slides, Gmail, Calendar, Keep,
Podcasts, Meet, Digital Wellbeing, Google One.

Two worth thinking about before you uncomment:

- **`com.android.chrome`** — on some builds Chrome also provides the system
  WebView, and removing it breaks in-app browsers.
- **`com.google.android.googlequicksearchbox`** — this is the Google app,
  Assistant, Discover, *and* the weather data older Pixels rely on.

---

## ⚠️ Stripped packages come back

`pm uninstall --user 0` is not permanent:

- **OTA system updates** re-provision packages for user 0. Expect anything you
  stripped to reappear after a monthly update — re-run `./tools/strip.sh --apply`
  afterwards.
- **Factory reset** restores everything, unconditionally.
- **Adding a new user or work profile** provisions that user with the full set.
- Play Store can reinstall a stripped app if you tap install on its listing.

`tools/removed.log` is your record of what you took off, and re-running
`strip.sh --apply` after an OTA is the normal maintenance step.

One real caveat: `pm uninstall --user 0` on a package that a *system* app depends
on can leave that system app crash-looping, and the fix is `restore.sh` rather than
anything on the device UI. Strip a few packages at a time and live with the phone
for a day before removing more.

---

## Status — what has actually been verified

Test device: **Pixel 5 (`redfin`), Android 14, API 34, build UP1A.231105.001.B2.**
Note it has **no SIM**, so placing a real call has never been exercised.

Verified on hardware:

- Debug APK builds clean from scratch and installs
- Launcher starts with no `FATAL` / `AndroidRuntime` in logcat
- UI renders as intended
- Tap-to-launch works
- Long-press → App Info works
- 7 of 9 seeded packages resolve; the 2 missing ones are silently omitted
- Set as default home; the Home button now returns to it

**Not yet verified — do not assume these work:**

- Back button no-op (implemented via `OnBackPressedCallback`, never exercised on device)
- Home-while-already-home no-op
- Behavior across a reboot
- Whether reinstalling preserves the default-home setting
- The `onResume` refresh actually dropping a row after an uninstall
- Every script in `tools/` except `install.sh`. `strip.sh` and `restore.sh` were
  exercised end-to-end against a **stub `adb`** — dry run, `--apply`, the
  protected-package banner, `not-found`, trailing comments, restore-all,
  restore-single, unknown-flag rejection, and the two-device guard all behave —
  but neither has ever been pointed at a real phone. Nothing has been stripped
  from the device; `packages.txt` is still entirely commented out and
  `tools/removed.log` does not exist.

### adb gotcha worth knowing

`adb start-server` returns *before* the USB bus has been enumerated, so a cold adb
server honestly reports zero devices for a second or so. All three scripts poll
and re-read rather than trusting the first `adb devices` answer. Don't simplify
that back into a single call — it made `install.sh` fail outright.
