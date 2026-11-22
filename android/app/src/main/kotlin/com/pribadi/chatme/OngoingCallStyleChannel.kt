package com.pribadi.chatme

import android.app.Notification
import android.app.PendingIntent
import android.app.Person
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationManagerCompat
import com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Restyles the active-call notification with Android's own CallStyle so the
 * system can show its regular call chip. The plugin's foreground service still
 * owns the notification lifecycle; this object only replaces the notification
 * with the same id after the call becomes active.
 */
object OngoingCallStyleChannel {
    private const val CHANNEL_NAME = "com.chatme.app/ongoing_call_style"
    private const val APPLY = "applyCallStyle"
    private const val CLEAR = "clearCallStyle"

    private const val KEY_CHANNEL_ID = "channelId"
    private const val KEY_NOTIFICATION_ID = "notificationId"
    private const val KEY_TITLE = "title"
    private const val KEY_PEER_PUBKEY = "peerPubkey"
    private const val KEY_STARTED_AT = "startedAtMs"
    private const val KEY_ACCENT_ARGB = "accentArgb"
    private const val KEY_END_ACTION = "endActionId"

    // Mirrors flutter_local_notifications' broadcast contract so END_CALL_ACTION
    // keeps flowing through the same Dart handler as the plugin's own action.
    private const val ACTION_TAPPED =
        "com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver.ACTION_TAPPED"
    private const val EXTRA_NOTIFICATION_ID = "notificationId"
    private const val EXTRA_ACTION_ID = "actionId"
    private const val EXTRA_CANCEL_NOTIFICATION = "cancelNotification"
    private const val EXTRA_PAYLOAD = "payload"
    private const val ACTION_SELECT_NOTIFICATION = "SELECT_NOTIFICATION"

    fun register(engine: FlutterEngine, context: Context) {
        val appContext = context.applicationContext
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    APPLY -> result.success(apply(appContext, call.arguments))
                    CLEAR -> {
                        clear(appContext, call.arguments)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun apply(context: Context, args: Any?): Boolean {
        // CallStyle is a platform style from Android 12. Older versions keep
        // the plugin's original MessagingStyle notification untouched.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return false

        val map = args as? Map<*, *> ?: return false
        val channelId = map[KEY_CHANNEL_ID] as? String ?: return false
        val notificationId = (map[KEY_NOTIFICATION_ID] as? Number)?.toInt() ?: return false
        val title = map[KEY_TITLE] as? String ?: return false
        val peerPubkey = map[KEY_PEER_PUBKEY] as? String ?: ""
        val startedAtMs = (map[KEY_STARTED_AT] as? Number)?.toLong() ?: return false
        val accentArgb = (map[KEY_ACCENT_ARGB] as? Number)?.toInt() ?: return false
        val endActionId = map[KEY_END_ACTION] as? String ?: return false
        if (title.isBlank() || startedAtMs <= 0L || notificationId == 0) return false

        return try {
            val person = Person.Builder()
                .setName(title)
                .setImportant(true)
                .apply { if (peerPubkey.isNotEmpty()) setKey(peerPubkey) }
                .build()

            val hangUpIntent = Intent(context, ActionBroadcastReceiver::class.java).apply {
                action = ACTION_TAPPED
                putExtra(EXTRA_NOTIFICATION_ID, notificationId)
                putExtra(EXTRA_ACTION_ID, endActionId)
                putExtra(EXTRA_CANCEL_NOTIFICATION, false)
                putExtra(EXTRA_PAYLOAD, peerPubkey)
            }
            val hangUpPendingIntent = PendingIntent.getBroadcast(
                context,
                notificationId * 16,
                hangUpIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

            val launchIntent = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
                ?.apply {
                    action = ACTION_SELECT_NOTIFICATION
                    putExtra(EXTRA_NOTIFICATION_ID, notificationId)
                    putExtra(EXTRA_PAYLOAD, peerPubkey)
                }
                ?: return false
            val contentIntent = PendingIntent.getActivity(
                context,
                notificationId,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

            val notification = Notification.Builder(context, channelId)
                .setSmallIcon(R.drawable.ic_stat_call)
                .setContentTitle(title)
                .setContentIntent(contentIntent)
                .setOngoing(true)
                .setAutoCancel(false)
                .setOnlyAlertOnce(true)
                .setShowWhen(true)
                .setUsesChronometer(true)
                .setWhen(startedAtMs)
                .setCategory(Notification.CATEGORY_CALL)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setColor(accentArgb)
                .setStyle(Notification.CallStyle.forOngoingCall(person, hangUpPendingIntent))
                .build()

            NotificationManagerCompat.from(context).notify(notificationId, notification)
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun clear(context: Context, args: Any?) {
        val map = args as? Map<*, *> ?: return
        val notificationId = (map[KEY_NOTIFICATION_ID] as? Number)?.toInt() ?: return
        try {
            NotificationManagerCompat.from(context).cancel(notificationId)
        } catch (_: Exception) {
        }
    }
}
