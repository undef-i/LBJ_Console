package org.noxylva.lbjconsole

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import kotlinx.coroutines.runBlocking
import org.noxylva.lbjconsole.database.AppSettingsRepository
import org.noxylva.lbjconsole.database.TrainDatabase
import android.os.Build
import android.util.Log
import android.view.View
import android.widget.RemoteViews
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
    private val appSettingsRepository = AppSettingsRepository(context)
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
        return runBlocking {
            appSettingsRepository.getSettings().notificationEnabled
        }
    }

    fun setNotificationEnabled(enabled: Boolean) {
        runBlocking {
            appSettingsRepository.updateNotificationEnabled(enabled)
        }
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
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            )

            val remoteViews = RemoteViews(context.packageName, R.layout.notification_train_record)
            val trainDisplay = if (isValidValue(trainRecord.lbjClass) && isValidValue(trainRecord.train)) {
                "${trainRecord.lbjClass.trim()}${trainRecord.train.trim()}"
            } else if (isValidValue(trainRecord.lbjClass)) {
                trainRecord.lbjClass.trim()
            } else if (isValidValue(trainRecord.train)) {
                trainRecord.train.trim()
            } else "列车"
            remoteViews.setTextViewText(R.id.notification_train_number, trainDisplay)
            
            val directionText = when (trainRecord.direction) {
                1 -> "下"
                3 -> "上"
                else -> ""
            }
            if (directionText.isNotEmpty()) {
                remoteViews.setTextViewText(R.id.notification_direction, directionText)
                remoteViews.setViewVisibility(R.id.notification_direction, View.VISIBLE)
            } else {
                remoteViews.setViewVisibility(R.id.notification_direction, View.GONE)
            }
            
            val locoInfo = when {
                isValidValue(trainRecord.locoType) && isValidValue(trainRecord.loco) -> {
                    val shortLoco = if (trainRecord.loco.length > 5) {
                        trainRecord.loco.takeLast(5)
                    } else {
                        trainRecord.loco
                    }
                    "${trainRecord.locoType}-${shortLoco}"
                }
                isValidValue(trainRecord.locoType) -> trainRecord.locoType
                isValidValue(trainRecord.loco) -> trainRecord.loco
                else -> ""
            }
            if (locoInfo.isNotEmpty()) {
                remoteViews.setTextViewText(R.id.notification_loco_info, locoInfo)
                remoteViews.setViewVisibility(R.id.notification_loco_info, View.VISIBLE)
            } else {
                remoteViews.setViewVisibility(R.id.notification_loco_info, View.GONE)
            }
            
            if (isValidValue(trainRecord.route)) {
                remoteViews.setTextViewText(R.id.notification_route, trainRecord.route.trim())
                remoteViews.setViewVisibility(R.id.notification_route, View.VISIBLE)
            } else {
                remoteViews.setViewVisibility(R.id.notification_route, View.GONE)
            }
            
            if (isValidValue(trainRecord.position)) {
                remoteViews.setTextViewText(R.id.notification_position, "${trainRecord.position.trim().removeSuffix(".")}K")
                remoteViews.setViewVisibility(R.id.notification_position, View.VISIBLE)
            } else {
                remoteViews.setViewVisibility(R.id.notification_position, View.GONE)
            }
            
            if (isValidValue(trainRecord.speed)) {
                remoteViews.setTextViewText(R.id.notification_speed, "${trainRecord.speed.trim()} km/h")
                remoteViews.setViewVisibility(R.id.notification_speed, View.VISIBLE)
            } else {
                remoteViews.setViewVisibility(R.id.notification_speed, View.GONE)
            }
            
            remoteViews.setOnClickPendingIntent(R.id.notification_train_number, pendingIntent)

            val summaryParts = mutableListOf<String>()
            
            val routeAndDirection = when {
                isValidValue(trainRecord.route) && directionText.isNotEmpty() -> "${trainRecord.route.trim()}${directionText}行"
                isValidValue(trainRecord.route) -> trainRecord.route.trim()
                directionText.isNotEmpty() -> "${directionText}行"
                else -> null
            }
            
            routeAndDirection?.let { summaryParts.add(it) }
            if (locoInfo.isNotEmpty()) summaryParts.add(locoInfo)
            
            val summaryText = summaryParts.joinToString(" • ")

            val notification = NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(trainDisplay)
                .setContentText(summaryText)
                .setCustomContentView(remoteViews)
                .setCustomBigContentView(remoteViews)
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
            Log.d(TAG, "Custom notification sent for train: ${trainRecord.train}")

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