package org.noxylva.lbjconsole.flutter

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AudioInputHandler.registerWith(flutterEngine, applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lbj/debug")
            .setMethodCallHandler { call, result ->
                if (call.method == "lastExitInfo") {
                    result.success(lastExitInfo())
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun lastExitInfo(): Map<String, Any?>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val exits = am.getHistoricalProcessExitReasons(packageName, 0, 1)
        if (exits.isEmpty()) return null
        val e = exits[0]
        return mapOf(
            "reason" to e.reason,
            "description" to e.description,
            "timestamp" to e.timestamp,
            "process" to e.processName
        )
    }
}