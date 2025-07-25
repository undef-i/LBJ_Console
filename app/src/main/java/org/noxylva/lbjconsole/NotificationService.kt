package org.noxylva.lbjconsole

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.json.JSONObject
import org.noxylva.lbjconsole.model.TrainRecord

class NotificationService(private val context: Context) {
    companion object {
        const val TAG = "NotificationService"
        const val CHANNEL_ID = "lbj_messages"
        const val CHANNEL_NAME = "LBJ Messages"
        const val NOTIFICATION_ID_BASE = 2000
        const val PREFS_NAME = "notification_settings"
        const val KEY_ENABLED = "notifications_enabled"
    }

    private val notificationManager = NotificationManagerCompat.from(context)
    private val prefs: SharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private var notificationIdCounter = NOTIFICATION_ID_BASE

    init {
        createNotificationChannel()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Real-time LBJ train message notifications"
                enableVibration(true)
                setShowBadge(true)
            }

            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
            Log.d(TAG, "Notification channel created")
        }
    }

    fun isNotificationEnabled(): Boolean {
        return prefs.getBoolean(KEY_ENABLED, false)
    }

    fun setNotificationEnabled(enabled: Boolean) {
        prefs.edit().putBoolean(KEY_ENABLED, enabled).apply()
        Log.d(TAG, "Notification enabled set to: $enabled")
    }

    private fun isValidValue(value: String): Boolean {
        val trimmed = value.trim()
        return trimmed.isNotEmpty() &&
               trimmed != "NUL" &&
               trimmed != "<NUL>" &&
               trimmed != "NA" &&
               trimmed != "<NA>" &&
               !trimmed.all { it == '*' }
    }

    fun showTrainNotification(trainRecord: TrainRecord) {
        if (!isNotificationEnabled()) {
            Log.d(TAG, "Notifications disabled, skipping")
            return
        }

        try {
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }

            val pendingIntent = PendingIntent.getActivity(
                context,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val directionText = when (trainRecord.direction) {
                1 -> "下行"
                3 -> "上行"
                else -> "未知"
            }

            val trainDisplay = if (isValidValue(trainRecord.lbjClass) && isValidValue(trainRecord.train)) {
                "${trainRecord.lbjClass.trim()}${trainRecord.train.trim()}"
            } else if (isValidValue(trainRecord.lbjClass)) {
                trainRecord.lbjClass.trim()
            } else if (isValidValue(trainRecord.train)) {
                trainRecord.train.trim()
            } else "列车"

            val title = trainDisplay
            val content = buildString {
                append(directionText)
                if (isValidValue(trainRecord.route)) {
                    append("\n线路: ${trainRecord.route.trim()}")
                }
                if (isValidValue(trainRecord.speed)) {
                    append("\n速度: ${trainRecord.speed.trim()} km/h")
                }
                if (isValidValue(trainRecord.position)) {
                    append("\n位置: ${trainRecord.position.trim()} km")
                }
            }

            val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(title)
                .setContentText(content)
                .setStyle(NotificationCompat.BigTextStyle().bigText(content))
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .setWhen(trainRecord.timestamp.time)
                .build()

            val notificationId = notificationIdCounter++
            if (notificationIdCounter > NOTIFICATION_ID_BASE + 1000) {
                notificationIdCounter = NOTIFICATION_ID_BASE
            }

            notificationManager.notify(notificationId, notification)
            Log.d(TAG, "Notification sent for train: ${trainRecord.train}")

        } catch (e: Exception) {
            Log.e(TAG, "Failed to show notification: ${e.message}", e)
        }
    }

    fun showTrainNotification(jsonData: JSONObject) {
        if (!isNotificationEnabled()) {
            Log.d(TAG, "Notifications disabled, skipping")
            return
        }

        try {
            val trainRecord = TrainRecord(jsonData)
            showTrainNotification(trainRecord)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create TrainRecord from JSON: ${e.message}", e)
        }
    }

    fun hasNotificationPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            notificationManager.areNotificationsEnabled()
        } else {
            notificationManager.areNotificationsEnabled()
        }
    }
}