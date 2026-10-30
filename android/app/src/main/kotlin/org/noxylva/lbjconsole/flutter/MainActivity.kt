package org.noxylva.lbjconsole.flutter

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AudioInputHandler.registerWith(flutterEngine, applicationContext)
        UsbSdrHandler.registerWith(flutterEngine, applicationContext)
        UsbSdrHandler.handleIntent(intent)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lbj/debug")
            .setMethodCallHandler { call, result ->
                if (call.method == "lastExitInfo") {
                    result.success(lastExitInfo())
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        UsbSdrHandler.handleIntent(intent)
    }

    private fun lastExitInfo(): Map<String, Any?>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val exits = am.getHistoricalProcessExitReasons(packageName, 0, 1)
        if (exits.isEmpty()) return null
        val e = exits[0]
        val trace = try {
            e.traceInputStream?.let { stream ->
                val bytes = stream.readBytes()
                String(bytes, 0, minOf(bytes.size, 16384), Charsets.UTF_8)
            }
        } catch (_: Exception) {
            null
        }
        return mapOf(
            "reason" to e.reason,
            "description" to e.description,
            "timestamp" to e.timestamp,
            "process" to e.processName,
            "trace" to trace
        )
    }
}