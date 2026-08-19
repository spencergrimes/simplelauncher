package com.example.simplelauncher

/**
 * THE ONLY FILE YOU NEED TO EDIT TO CHANGE THE HOME SCREEN.
 *
 * Order here is the order on screen. Display labels are NOT hardcoded — they are
 * resolved from PackageManager at runtime, so a row reads whatever the device calls
 * that app. The trailing comments are just a reminder of what each package is.
 *
 * Anything not installed is silently dropped from the list. Adding a bogus package
 * name is harmless; it simply never renders.
 *
 * To find a package name for something already on the phone:
 *   adb shell pm list packages | grep -i <name>
 *   adb shell cmd package resolve-activity --brief <package>
 */
object AppList {

    /**
     * Package names, resolved for a stock Pixel 5 on Android 14 (AP2A.240***).
     */
    val PACKAGES: List<String> = listOf(
        "com.google.android.dialer",              // Phone (Google Phone)
        "com.google.android.apps.messaging",      // Messages (Google Messages)
        "com.google.android.GoogleCamera",        // Camera (Pixel Camera)
        "com.google.android.apps.photos",         // Photos (Google Photos)
        "com.google.android.apps.maps",           // Maps (Google Maps)
        "com.google.android.apps.weather",        // Weather (Pixel Weather) — see note below
        "com.google.android.deskclock",           // Clock (Google Clock)
        "com.google.android.apps.authenticator2", // Authenticator (Google Authenticator)
        "com.android.settings",                   // Settings (AOSP Settings — Pixel uses this too)
    )

    // Notes on the two entries most likely to be missing on your device:
    //
    // com.google.android.apps.weather — "Pixel Weather" is a separate app that shipped
    //   with Pixel 9 / Android 14 QPR3 and was backported to older Pixels only in some
    //   builds. On a Pixel 5 that never got it, weather lives inside the Google app
    //   (com.google.android.googlequicksearchbox) and has no launcher entry of its own,
    //   so this row will just not appear. Nothing breaks. If you want a weather row on
    //   such a device, install any weather app and put its package here instead.
    //
    // com.google.android.apps.authenticator2 — Google Authenticator is not preinstalled
    //   on any Pixel. Install it from Play first or this row will not appear. (The "2"
    //   suffix is correct and historical; the current app still uses that package name.)
}
