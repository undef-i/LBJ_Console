package org.noxylva.lbjconsole.flutter

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class KeepAliveReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED -> {
                if (KeepAliveWatchdog.isEnabled(context)) {
                    KeepAliveWatchdog.arm(context)
                    KeepAliveWatchdog.startServiceIfEnabled(context)
                }
            }
            KeepAliveWatchdog.ACTION -> {
                if (KeepAliveWatchdog.isEnabled(context)) {
                    KeepAliveWatchdog.startServiceIfEnabled(context)
                    KeepAliveWatchdog.arm(context)
                }
            }
        }
    }
}
