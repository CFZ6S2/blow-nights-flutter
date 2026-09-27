package com.blownights.finder.finder

import android.app.AlarmManager
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Renews the BLE key while the radar runs, even with the app closed. About once an hour the service asks the app's
 * isolate (FinderNative.onRenewRequest) if the app is alive; otherwise it starts a headless Flutter engine running
 * lib/services/finder_background.dart, so the renewal logic exists only once, in Dart. Either way the result is the new
 * advertising schedule, handed to [FinderBle.setKeys].
 */
object KeyRenewal {
    private const val TAG = "KeyRenewal"
    private const val INTERVAL_MS = 60L * 60 * 1000

    /** Headless runs must finish (Firebase sign-in restore, one query, a few writes) well within this. */
    private const val MAX_RUN_MS = 90_000L

    private val main = Handler(Looper.getMainLooper())
    private var appContext: Context? = null
    private var engine: FlutterEngine? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private val alarm = AlarmManager.OnAlarmListener { run() }
    private val timeout = Runnable {
        Log.w(TAG, "renewal timed out")
        finish()
    }

    /** From ProximityService: first check shortly after the radar starts, then hourly. */
    fun start(context: Context) {
        appContext = context.applicationContext
        schedule(5L * 60 * 1000)
    }

    fun stop(context: Context) {
        context.getSystemService(AlarmManager::class.java)?.cancel(alarm)
        finish()
        appContext = null
    }

    private fun schedule(delayMs: Long) {
        val alarms = appContext?.getSystemService(AlarmManager::class.java) ?: return
        alarms.cancel(alarm)
        // Inexact wakeup alarm: no exact-alarm permission needed, and a renewal a few minutes late is harmless.
        alarms.setWindow(AlarmManager.RTC_WAKEUP, System.currentTimeMillis() + delayMs, 10L * 60 * 1000, "bn-finder-renew", alarm, main)
    }

    private fun run() {
        val context = appContext ?: return
        schedule(INTERVAL_MS)
        if (engine != null || wakeLock != null) return // previous run still going
        // The alarm only keeps the CPU awake while it's delivered; network calls need longer.
        wakeLock = context.getSystemService(PowerManager::class.java)
            ?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "blownights:finder-renew")
            ?.apply { acquire(MAX_RUN_MS) }
        main.postDelayed(timeout, MAX_RUN_MS)

        val app = FinderChannels.active
        if (app != null) {
            app.requestRenewal { keys ->
                if (keys != null) {
                    apply(keys)
                } else {
                    // App alive but couldn't (e.g. still starting): don't race it with a second engine, retry next hour.
                    finish()
                }
            }
        } else {
            runHeadless(context)
        }
    }

    private fun runHeadless(context: Context) {
        try {
            val e = FlutterEngine(context)
            engine = e
            MethodChannel(e.dartExecutor.binaryMessenger, "blownights/finder_bg").setMethodCallHandler { call, result ->
                if (call.method == "done") {
                    result.success(null)
                    val keys = FinderChannels.parseKeys(call.argument<List<Map<String, Any>>>("keys"))
                    if (keys.isNotEmpty()) apply(keys) else finish()
                } else {
                    result.notImplemented()
                }
            }
            e.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(
                    FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                    "package:blow_nights/services/finder_background.dart",
                    "finderBackgroundMain",
                ),
            )
        } catch (e: Exception) {
            Log.e(TAG, "headless renewal failed to start", e)
            finish()
        }
    }

    private fun apply(keys: List<Pair<Long, String>>) {
        FinderBle.setKeys(keys)
        finish()
    }

    private fun finish() {
        main.removeCallbacks(timeout)
        // Destroy after the reply has been delivered back to Dart.
        engine?.let { e -> main.post { e.destroy() } }
        engine = null
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }
}
