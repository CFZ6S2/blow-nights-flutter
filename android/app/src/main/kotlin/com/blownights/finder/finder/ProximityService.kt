package com.blownights.finder.finder

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import com.blownights.finder.MainActivity

/**
 * Foreground service so friends keep detecting each other with the screen off or the app in background.
 * The BLE work itself lives in [FinderBle]; this only owns the lifecycle and the ongoing notification.
 */
class ProximityService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val keyNames = intent?.getStringArrayExtra(EXTRA_KEYS)
        val keyFroms = intent?.getLongArrayExtra(EXTRA_KEY_FROMS)
        if (keyNames.isNullOrEmpty() || keyFroms == null || keyFroms.size != keyNames.size) {
            // Restarted by the system after being killed: we no longer know which keys to advertise from.
            stopSelf()
            return START_NOT_STICKY
        }
        val notification = buildNotification(
            intent.getStringExtra(EXTRA_TITLE) ?: "Blow Nights",
            intent.getStringExtra(EXTRA_TEXT) ?: "",
        )
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            // Android 14+ refuses a connectedDevice FGS without a granted Bluetooth permission.
            Log.e(TAG, "startForeground failed", e)
            stopSelf()
            return START_NOT_STICKY
        }
        if (FinderBle.start(this, keyFroms.zip(keyNames))) KeyRenewal.start(this) else stopSelf()
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        KeyRenewal.stop(this)
        FinderBle.stop(this)
        super.onDestroy()
    }

    private fun buildNotification(title: String, text: String): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, title, NotificationManager.IMPORTANCE_LOW).apply { setShowBadge(false) },
            )
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return builder
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setContentIntent(open)
            .setOngoing(true)
            .build()
    }

    companion object {
        private const val TAG = "ProximityService"
        private const val CHANNEL_ID = "finder_proximity"
        private const val NOTIFICATION_ID = 4711
        private const val EXTRA_KEYS = "keys"
        private const val EXTRA_KEY_FROMS = "keyFroms"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_TEXT = "text"

        fun start(context: Context, keys: List<Pair<Long, String>>, title: String, text: String) {
            val intent = Intent(context, ProximityService::class.java)
                .putExtra(EXTRA_KEYS, keys.map { it.second }.toTypedArray())
                .putExtra(EXTRA_KEY_FROMS, keys.map { it.first }.toLongArray())
                .putExtra(EXTRA_TITLE, title)
                .putExtra(EXTRA_TEXT, text)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(intent)
            else context.startService(intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, ProximityService::class.java))
        }
    }
}
