package com.blownights.finder.finder

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.content.Intent
import android.content.pm.PackageManager
import android.nfc.NfcAdapter
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Bridge for lib/services/finder_native.dart.
 * Method channel "blownights/finder": state, requestPermissions, enableBluetooth, start, setKeys, stop, setInvite;
 * the other way, renewKeys (KeyRenewal asks the app's isolate to renew the BLE key).
 * Event channel "blownights/finder/events": {type: peer, id, rssi, t} | {type: advertise_failed|scan_failed, code}.
 */
class FinderChannels(private val activity: Activity, messenger: BinaryMessenger) {

    private var pendingPermissions: MethodChannel.Result? = null
    private val methods = MethodChannel(messenger, "blownights/finder")

    init {
        active = this
        methods.setMethodCallHandler { call, result ->
            when (call.method) {
                "state" -> result.success(state())
                "requestPermissions" -> requestPermissions(result)
                "enableBluetooth" -> {
                    try {
                        @Suppress("DEPRECATION")
                        activity.startActivityForResult(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE), 0)
                        result.success(true)
                    } catch (e: SecurityException) {
                        result.success(false)
                    }
                }
                "start" -> {
                    val keys = parseKeys(call.argument<List<Map<String, Any>>>("keys"))
                    if (keys.isEmpty() || !hasPermissions()) {
                        result.success(false)
                    } else {
                        ProximityService.start(
                            activity.applicationContext, keys,
                            call.argument<String>("title") ?: "Blow Nights",
                            call.argument<String>("text") ?: "",
                        )
                        result.success(true)
                    }
                }
                "setKeys" -> {
                    FinderBle.setKeys(parseKeys(call.argument<List<Map<String, Any>>>("keys")))
                    result.success(null)
                }
                "stop" -> {
                    ProximityService.stop(activity.applicationContext)
                    result.success(null)
                }
                "setInvite" -> {
                    InviteHceService.payload = call.argument<String>("payload")
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, "blownights/finder/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                FinderBle.listener = FinderBle.Listener {
                    // The service outlives the activity; a sink from a destroyed engine must not crash it.
                    try {
                        events.success(it)
                    } catch (_: Exception) {
                    }
                }
            }

            override fun onCancel(arguments: Any?) {
                FinderBle.listener = null
            }
        })
    }

    /**
     * Asks the app's isolate to renew the BLE key (FinderNative.onRenewRequest). [done] gets the new schedule, or null
     * if the app couldn't (not signed in, no handler yet, error). Main thread only.
     */
    fun requestRenewal(done: (List<Pair<Long, String>>?) -> Unit) {
        methods.invokeMethod("renewKeys", null, object : MethodChannel.Result {
            @Suppress("UNCHECKED_CAST")
            override fun success(result: Any?) = done((result as? List<Map<String, Any>>)?.let(::parseKeys))
            override fun error(code: String, message: String?, details: Any?) = done(null)
            override fun notImplemented() = done(null)
        })
    }

    /** From MainActivity.cleanUpFlutterEngine: the app's engine is going away. */
    fun detach() {
        if (active === this) active = null
    }

    private fun state(): Map<String, Any?> {
        val pm = activity.packageManager
        val adapter = FinderBle.adapter(activity)
        val ble = pm.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE) && adapter != null
        return mapOf(
            "ble" to ble,
            "advertise" to (ble && adapter?.isMultipleAdvertisementSupported == true),
            "enabled" to (adapter?.isEnabled == true),
            "permissions" to hasPermissions(),
            "running" to FinderBle.running,
            "hce" to pm.hasSystemFeature(PackageManager.FEATURE_NFC_HOST_CARD_EMULATION),
            "nfcOn" to (NfcAdapter.getDefaultAdapter(activity)?.isEnabled == true),
        )
    }

    private fun required(): Array<String> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        arrayOf(
            Manifest.permission.BLUETOOTH_SCAN,
            Manifest.permission.BLUETOOTH_ADVERTISE,
            Manifest.permission.BLUETOOTH_CONNECT,
        )
    } else {
        // Before Android 12 a BLE scan only returns results with location permission.
        arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
    }

    private fun hasPermissions() =
        required().all { activity.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }

    private fun requestPermissions(result: MethodChannel.Result) {
        if (hasPermissions()) {
            result.success(true)
            return
        }
        pendingPermissions?.success(false)
        pendingPermissions = result
        val ask = required().toMutableList()
        // The ongoing notification is optional: denying it doesn't block the finder.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) ask += Manifest.permission.POST_NOTIFICATIONS
        activity.requestPermissions(ask.toTypedArray(), PERMISSION_REQUEST)
    }

    /** Forwarded from MainActivity.onRequestPermissionsResult. */
    fun onPermissionsResult(requestCode: Int): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        pendingPermissions?.success(hasPermissions())
        pendingPermissions = null
        return true
    }

    companion object {
        private const val PERMISSION_REQUEST = 4712

        /** Bridge of the app engine currently alive, if any (the radar service outlives it). */
        @Volatile var active: FinderChannels? = null
            private set

        /** [{k, from}] from lib/services/finder_native.dart → (fromMs, key). */
        fun parseKeys(raw: List<Map<String, Any>>?): List<Pair<Long, String>> =
            raw.orEmpty().mapNotNull { m ->
                val k = m["k"] as? String
                val from = (m["from"] as? Number)?.toLong()
                if (k.isNullOrBlank() || from == null) null else from to k
            }
    }
}
