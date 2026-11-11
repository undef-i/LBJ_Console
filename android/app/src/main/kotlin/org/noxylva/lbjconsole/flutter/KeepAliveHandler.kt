package org.noxylva.lbjconsole.flutter

import android.app.ActivityManager
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

object KeepAliveWatchdog {
    const val ACTION = "org.noxylva.lbjconsole.flutter.WATCHDOG"
    const val SERVICE_CLASS = "id.flutter.flutter_background_service.BackgroundService"
    private const val PREFS = "keepalive"
    private const val KEY_ENABLED = "watchdogEnabled"
    private const val INTERVAL_MS = 15 * 60 * 1000L

    fun isEnabled(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_ENABLED, false)

    fun setEnabled(context: Context, enabled: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(KEY_ENABLED, enabled).apply()
        if (enabled) arm(context) else cancel(context)
    }

    fun arm(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.setAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            System.currentTimeMillis() + INTERVAL_MS,
            pendingIntent(context),
        )
    }

    fun cancel(context: Context) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(pendingIntent(context))
    }

    private fun pendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, KeepAliveReceiver::class.java).setAction(ACTION)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getBroadcast(context, 0, intent, flags)
    }

    fun startServiceIfEnabled(context: Context) {
        if (!isEnabled(context)) return
        if (isServiceRunning(context)) return
        val intent = Intent().setClassName(context.packageName, SERVICE_CLASS)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        } catch (_: Exception) {
        }
    }

    @Suppress("DEPRECATION")
    fun isServiceRunning(context: Context): Boolean {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return try {
            am.getRunningServices(Int.MAX_VALUE)
                .any { it.service.className == SERVICE_CLASS }
        } catch (_: Exception) {
            false
        }
    }
}

object KeepAliveHandler {
    private var wakeLock: PowerManager.WakeLock? = null

    fun registerWith(flutterEngine: FlutterEngine, context: Context) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "org.noxylva.lbjconsole/keepalive",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquireWakeLock" -> result.success(acquireWakeLock(context))
                "releaseWakeLock" -> result.success(releaseWakeLock())
                "isIgnoringBatteryOptimizations" ->
                    result.success(isIgnoringBatteryOptimizations(context))
                "requestIgnoreBatteryOptimizations" ->
                    result.success(requestIgnoreBatteryOptimizations(context))
                "setWatchdogEnabled" -> {
                    KeepAliveWatchdog.setEnabled(
                        context,
                        call.arguments as? Boolean ?: false,
                    )
                    result.success(true)
                }
                "isWatchdogEnabled" -> result.success(KeepAliveWatchdog.isEnabled(context))
                else -> result.notImplemented()
            }
        }
    }

    private fun acquireWakeLock(context: Context): Boolean {
        if (wakeLock?.isHeld == true) return true
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "LBJConsole:reception",
        ).apply {
            setReferenceCounted(false)
            acquire()
        }
        return true
    }

    private fun releaseWakeLock(): Boolean {
        if (wakeLock?.isHeld == true) {
            wakeLock?.release()
        }
        wakeLock = null
        return true
    }

    private fun isIgnoringBatteryOptimizations(context: Context): Boolean {
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(context.packageName)
    }

    private fun requestIgnoreBatteryOptimizations(context: Context): Boolean {
        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:${context.packageName}")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return startActivity(context, intent)
    }

    private fun startActivity(context: Context, intent: Intent): Boolean {
        return try {
            context.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }
}
