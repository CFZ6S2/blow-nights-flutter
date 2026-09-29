package com.blownights.finder

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import com.blownights.finder.finder.FinderChannels
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var finder: FinderChannels? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        finder = FinderChannels(this, flutterEngine.dartExecutor.binaryMessenger)
        // The door scanner sends the user here after the camera permission was denied.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "blownights/system").setMethodCallHandler { call, result ->
            if (call.method == "openAppSettings") {
                startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null)))
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // The radar service may keep running; it must stop asking this engine to renew keys.
        finder?.detach()
        finder = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (finder?.onPermissionsResult(requestCode) != true) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }
}
