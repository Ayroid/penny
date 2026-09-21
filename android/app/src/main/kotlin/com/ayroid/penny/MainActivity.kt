package com.ayroid.penny

import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// A FragmentActivity because the system's biometric prompt is a fragment —
// local_auth cannot show it from a plain Activity.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // With the app lock on, the recent-apps switcher shows no picture of
        // the ledger. Android 13+ can blank just that; older phones only have
        // FLAG_SECURE, which blocks screenshots as well.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "penny/privacy")
            .setMethodCallHandler { call, result ->
                if (call.method != "hideInRecents") return@setMethodCallHandler result.notImplemented()
                val hide = call.arguments as Boolean
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    setRecentsScreenshotEnabled(!hide)
                } else if (hide) {
                    window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                } else {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                }
                result.success(null)
            }
    }
}
