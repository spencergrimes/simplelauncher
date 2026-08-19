package com.example.simplelauncher

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.text.format.DateFormat
import android.view.LayoutInflater
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.OnBackPressedCallback
import androidx.activity.SystemBarStyle
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import java.util.Date

class MainActivity : AppCompatActivity() {

    private lateinit var clockView: TextView
    private lateinit var dateView: TextView
    private lateinit var listContainer: LinearLayout

    /**
     * ACTION_TIME_TICK fires once a minute and cannot be declared in the manifest, so
     * the clock is driven by a registered receiver rather than a polling handler.
     */
    private val timeReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) = renderClock()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // The background is always light, so pin dark system-bar icons rather than
        // letting them follow the system day/night setting.
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT),
        )
        setContentView(R.layout.activity_main)

        clockView = findViewById(R.id.clock)
        dateView = findViewById(R.id.date)
        listContainer = findViewById(R.id.app_list)

        val root = findViewById<android.view.View>(R.id.main)
        ViewCompat.setOnApplyWindowInsetsListener(root) { v, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            v.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            insets
        }

        // Back does nothing at all. onBackPressed() is deprecated on API 33+, so this
        // is an always-enabled callback that simply swallows the event.
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() = Unit
        })
    }

    /** Home pressed while already home. singleTask routes it here; do nothing. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        renderClock()
        // Rebuild every time so apps uninstalled while we were backgrounded disappear
        // without needing a restart.
        renderAppList()
        ContextCompat.registerReceiver(
            this,
            timeReceiver,
            IntentFilter().apply {
                addAction(Intent.ACTION_TIME_TICK)
                addAction(Intent.ACTION_TIME_CHANGED)
                addAction(Intent.ACTION_TIMEZONE_CHANGED)
            },
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
    }

    override fun onPause() {
        super.onPause()
        unregisterReceiver(timeReceiver)
    }

    private fun renderClock() {
        val now = Date()
        val timePattern = if (DateFormat.is24HourFormat(this)) "H:mm" else "h:mm"
        clockView.text = DateFormat.format(timePattern, now)
        dateView.text = DateFormat.format("EEEE, MMMM d", now)
    }

    private fun renderAppList() {
        listContainer.removeAllViews()
        val inflater = LayoutInflater.from(this)

        for (pkg in AppList.PACKAGES) {
            // A null launch intent means "not installed, or installed with no launcher
            // activity". Either way there is nothing to show — skip the row.
            val launchIntent = packageManager.getLaunchIntentForPackage(pkg) ?: continue

            val label = try {
                packageManager.getApplicationLabel(
                    packageManager.getApplicationInfo(pkg, 0)
                ).toString()
            } catch (_: Exception) {
                continue
            }

            val row = inflater.inflate(R.layout.row_app, listContainer, false) as TextView
            row.text = label
            row.setOnClickListener { launch(launchIntent) }
            row.setOnLongClickListener {
                openAppInfo(pkg)
                true
            }
            listContainer.addView(row)
        }
    }

    private fun launch(intent: Intent) {
        try {
            startActivity(intent)
        } catch (_: Exception) {
            // Uninstalled or disabled between rendering and tapping. Nothing useful to
            // say about it, and a launcher that crashes is unusable.
        }
    }

    private fun openAppInfo(pkg: String) {
        try {
            startActivity(
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                    .setData(Uri.fromParts("package", pkg, null))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        } catch (_: Exception) {
        }
    }
}
