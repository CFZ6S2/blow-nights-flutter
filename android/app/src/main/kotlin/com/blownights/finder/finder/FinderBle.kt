package com.blownights.finder.finder

import android.app.AlarmManager
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.os.SystemClock
import android.util.Log
import java.util.UUID

/**
 * BLE layer of the friend finder, ported from the Kotlin prototype (C:\dev\blowapp) with its three bugs fixed:
 * - the service UUID must be valid hex (the prototype's "BN000001-FIND-…" threw on class load);
 * - a legacy advertisement is 31 bytes: flags (3) + 128-bit service data with the 8-byte id (26) = 29.
 *   The prototype also added the UUID list (18) and TX power (3) → ADVERTISE_FAILED_DATA_TOO_LARGE;
 * - results arrive in onScanResult only when reportDelay is 0 (the prototype set a delay, so they went to
 *   onBatchScanResults, which it never overrode). Both callbacks are handled here anyway.
 * The advertised id rotates every 15 minutes (see [BleIdRotation]) so a passive scanner can't follow a phone. Each
 * rotation starts a new advertising set, which also gets a new random address: id and address change together, so
 * one can't be used to link the other across a rotation.
 */
object FinderBle {
    private const val TAG = "FinderBle"

    val SERVICE_UUID: ParcelUuid = ParcelUuid(UUID.fromString("b1a57e1f-2d6c-4f0a-9e57-6e1a3b7c0f5d"))
    const val ID_LENGTH = 8

    /** Same peer is reported to Dart at most this often; RSSI is smoothed on the Dart side. */
    private const val PEER_THROTTLE_MS = 500L

    fun interface Listener {
        fun onEvent(event: Map<String, Any?>)
    }

    @Volatile var listener: Listener? = null
    @Volatile var running = false
        private set

    private val main = Handler(Looper.getMainLooper())
    private val lastEmit = HashMap<String, Long>()
    private var advertiseCallback: AdvertiseCallback? = null
    private var scanCallback: ScanCallback? = null
    private var appContext: Context? = null

    /** (fromMs, key), sorted: the install's advertising schedule from lib/services/ble_identity.dart. */
    @Volatile private var keys: List<Pair<Long, String>> = emptyList()
    private var advertisedId = ""
    @Volatile private var advertisedPeriod = Long.MIN_VALUE
    @Volatile private var ownIds: Set<String> = emptySet()
    private val rotate = Runnable { rotateIfDue() }
    private val rotateAlarm = AlarmManager.OnAlarmListener { rotateIfDue() }

    fun adapter(context: Context): BluetoothAdapter? =
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    private fun emit(event: Map<String, Any?>) = main.post { listener?.onEvent(event) }

    /** [keys]: (fromMs, key) schedule; the id on air is derived from the key in force for each period. */
    @Synchronized
    fun start(context: Context, keys: List<Pair<Long, String>>): Boolean {
        stop(context)
        if (keys.isEmpty()) return false
        val adapter = adapter(context) ?: return false
        if (!adapter.isEnabled) return false
        this.keys = keys.sortedBy { it.first }
        appContext = context.applicationContext
        try {
            advertise(adapter, System.currentTimeMillis())
            if (!startScan(context, filtered = true)) return false
        } catch (e: SecurityException) {
            Log.e(TAG, "missing Bluetooth permission", e)
            stop(context)
            return false
        }
        running = true
        return true
    }

    /** Replaces the schedule of a running finder (a renewed key was published); re-advertises only if the id changes. */
    @Synchronized
    fun setKeys(newKeys: List<Pair<Long, String>>) {
        if (newKeys.isEmpty()) return
        keys = newKeys.sortedBy { it.first }
        if (!running) return
        val now = System.currentTimeMillis()
        val adapter = appContext?.let(::adapter) ?: return
        try {
            if (idFor(BleIdRotation.period(now)) != advertisedId) advertise(adapter, now) else updateOwnIds(advertisedPeriod)
        } catch (e: SecurityException) {
            Log.e(TAG, "missing Bluetooth permission", e)
        }
    }

    /** Key in force for [period]: the last one whose fromMs is not after the period start (the first one before that). */
    private fun keyFor(period: Long): String {
        val start = period * BleIdRotation.PERIOD_MS
        var key = keys.first().second
        for ((from, k) in keys) if (from <= start) key = k
        return key
    }

    private fun idFor(period: Long) = BleIdRotation.idFor(keyFor(period), period)

    /** Our own possible ids around [period] (same window friends accept), so the scanner never reports this phone. */
    private fun updateOwnIds(period: Long) {
        ownIds = (-2L..2L).flatMap { d -> keys.map { BleIdRotation.idFor(it.second, period + d) } }.toSet()
    }

    /** (Re)starts advertising with the current period's id and schedules the next rotation. */
    private fun advertise(adapter: BluetoothAdapter, nowMs: Long) {
        val advertiser = adapter.bluetoothLeAdvertiser
        advertiseCallback?.let { advertiser?.stopAdvertising(it) }
        advertiseCallback = null
        val period = BleIdRotation.period(nowMs)
        advertisedPeriod = period
        advertisedId = idFor(period)
        updateOwnIds(period)
        scheduleRotation(nowMs)

        if (advertiser == null) {
            emit(mapOf("type" to "advertise_failed", "code" to -1))
            return
        }
        val cb = object : AdvertiseCallback() {
            override fun onStartFailure(errorCode: Int) {
                Log.e(TAG, "advertise failed: $errorCode")
                emit(mapOf("type" to "advertise_failed", "code" to errorCode))
            }
        }
        advertiser.startAdvertising(
            AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_BALANCED)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
                .setConnectable(false)
                .setTimeout(0)
                .build(),
            AdvertiseData.Builder()
                .setIncludeDeviceName(false)
                .setIncludeTxPowerLevel(false)
                .addServiceData(SERVICE_UUID, advertisedId.toByteArray(Charsets.US_ASCII))
                .build(),
            cb,
        )
        advertiseCallback = cb
    }

    @Synchronized
    private fun rotateIfDue() {
        if (!running) return
        val now = System.currentTimeMillis()
        val adapter = appContext?.let(::adapter) ?: return
        try {
            if (BleIdRotation.period(now) != advertisedPeriod) advertise(adapter, now) else scheduleRotation(now)
        } catch (e: SecurityException) {
            Log.e(TAG, "missing Bluetooth permission", e)
        }
    }

    /**
     * Handler time stops while the CPU sleeps, so the Handler alone could rotate many minutes late with the screen off.
     * The alarm wakes the phone (inexact window: no exact-alarm permission needed); scan results also check in [handle].
     */
    private fun scheduleRotation(nowMs: Long) {
        val next = BleIdRotation.nextRotationMs(nowMs)
        main.removeCallbacks(rotate)
        main.postDelayed(rotate, next - nowMs + 1_000)
        val alarms = appContext?.getSystemService(AlarmManager::class.java) ?: return
        alarms.cancel(rotateAlarm)
        alarms.setWindow(AlarmManager.RTC_WAKEUP, next, 60_000, "bn-finder-rotate", rotateAlarm, main)
    }

    /**
     * A filter is required: Android pauses unfiltered scans while the screen is off. Some controllers reject an
     * empty service-data filter in hardware; then scan unfiltered (screen-on only) and filter in [handle].
     */
    private fun startScan(context: Context, filtered: Boolean): Boolean {
        val scanner = adapter(context)?.bluetoothLeScanner ?: return false
        val cb = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) = handle(result)
            override fun onBatchScanResults(results: MutableList<ScanResult>) = results.forEach(::handle)
            override fun onScanFailed(errorCode: Int) {
                Log.e(TAG, "scan failed (filtered=$filtered): $errorCode")
                if (filtered && errorCode != ScanCallback.SCAN_FAILED_ALREADY_STARTED) {
                    main.post {
                        synchronized(this@FinderBle) {
                            if (scanCallback === this) {
                                scanCallback = null
                                try {
                                    startScan(context, filtered = false)
                                } catch (e: SecurityException) {
                                    Log.e(TAG, "missing Bluetooth permission", e)
                                }
                            }
                        }
                    }
                } else {
                    emit(mapOf("type" to "scan_failed", "code" to errorCode))
                }
            }
        }
        scanner.startScan(
            if (filtered) listOf(ScanFilter.Builder().setServiceData(SERVICE_UUID, ByteArray(0)).build()) else null,
            ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_BALANCED)
                .setReportDelay(0)
                .build(),
            cb,
        )
        scanCallback = cb
        return true
    }

    private fun handle(result: ScanResult) {
        val bytes = result.scanRecord?.getServiceData(SERVICE_UUID) ?: return
        if (BleIdRotation.period(System.currentTimeMillis()) != advertisedPeriod) main.post(rotate)
        val id = String(bytes, Charsets.US_ASCII).trimEnd('\u0000')
        if (id.length != ID_LENGTH || id in ownIds) return
        val now = SystemClock.elapsedRealtime()
        synchronized(lastEmit) {
            if (now - (lastEmit[id] ?: 0L) < PEER_THROTTLE_MS) return
            lastEmit[id] = now
        }
        emit(mapOf("type" to "peer", "id" to id, "rssi" to result.rssi, "t" to System.currentTimeMillis()))
    }

    @Synchronized
    fun stop(context: Context) {
        main.removeCallbacks(rotate)
        context.getSystemService(AlarmManager::class.java)?.cancel(rotateAlarm)
        val adapter = adapter(context)
        try {
            advertiseCallback?.let { adapter?.bluetoothLeAdvertiser?.stopAdvertising(it) }
            scanCallback?.let { adapter?.bluetoothLeScanner?.stopScan(it) }
        } catch (e: Exception) {
            // Adapter turned off or permission revoked: nothing left to stop.
            Log.w(TAG, "stop: ${e.message}")
        }
        advertiseCallback = null
        scanCallback = null
        synchronized(lastEmit) { lastEmit.clear() }
        running = false
    }
}
