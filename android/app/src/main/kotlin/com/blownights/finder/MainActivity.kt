package com.blownights.finder

import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import com.blownights.finder.finder.FinderChannels
import com.blownights.finder.pass.PassHceService
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
        // Ticket or drink handed to a scanner by NFC (pass/PassHceService.kt, lib/services/nfc_pass.dart).
        val pass = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "blownights/nfc_pass")
        pass.setMethodCallHandler { call, result ->
            if (call.method == "setPayload") {
                PassHceService.payload = call.argument<String>("payload")
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
        val main = Handler(Looper.getMainLooper())
        PassHceService.onHandedOver = { main.post { pass.invokeMethod("handedOver", null) } }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // The radar service may keep running; it must stop asking this engine to renew keys.
        finder?.detach()
        finder = null
        // No screen is left to show a ticket or drink: stop answering scanners.
        PassHceService.onHandedOver = null
        PassHceService.payload = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (finder?.onPermissionsResult(requestCode) != true) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }
}
