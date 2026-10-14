package com.pribadi.chatme

import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.Person
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import androidx.work.*
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.TimeUnit

class MainActivity: FlutterActivity() {
    private val BATTERY_CHANNEL = "com.chatme.app/battery"
    private val SHORTCUT_CHANNEL = "chatme_shortcuts"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. Battery Optimization Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BATTERY_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "requestIgnoreBatteryOptimization") {
                val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                val packageName = packageName

                if (!powerManager.isIgnoringBatteryOptimizations(packageName)) {
                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                    intent.data = Uri.parse("package:$packageName")
                    startActivity(intent)
                    result.success(true)
                } else {
                    result.success(false)
                }
            } else {
                result.notImplemented()
            }
        }

        // 2. Dynamic Shortcuts Channel for Conversation UI
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHORTCUT_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "pushShortcut") {
                val id = call.argument<String>("id")
                val name = call.argument<String>("name")
                val avatarBytes = call.argument<ByteArray>("avatarBytes")

                if (id != null && name != null) {
                    createConversationShortcut(id, name, avatarBytes)
                    result.success(true)
                } else {
                    result.error("INVALID_ARGS", "ID and name are required", null)
                }
            } else {
                result.notImplemented()
            }
        }

        scheduleNostrWorker()
    }

    private fun createConversationShortcut(id: String, name: String, avatarBytes: ByteArray?) {
        // Build Person object for the notification avatar
        val personBuilder = Person.Builder()
            .setName(name)
            .setKey(id)

        if (avatarBytes != null) {
            val bitmap = BitmapFactory.decodeByteArray(avatarBytes, 0, avatarBytes.size)
            personBuilder.setIcon(IconCompat.createWithBitmap(bitmap))
        }
        val person = personBuilder.build()

        // Required dummy intent for Android shortcut integration
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            putExtra("pubkey", id)
        }

        // Build and configure the shortcut
        val shortcut = ShortcutInfoCompat.Builder(context, "chat_shortcut_$id")
            .setShortLabel(name)
            .setLongLabel(name)
            .setPerson(person)
            .setIntent(intent)
            .setLongLived(true) // Mandatory requirement for Android Conversation UI
            .build()

        ShortcutManagerCompat.pushDynamicShortcut(context, shortcut)
    }

    private fun scheduleNostrWorker() {
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()

        val workRequest = PeriodicWorkRequestBuilder<NostrWorker>(15, TimeUnit.MINUTES)
            .setConstraints(constraints)
            .build()

        WorkManager.getInstance(applicationContext).enqueueUniquePeriodicWork(
            "nostr_reconnect",
            ExistingPeriodicWorkPolicy.KEEP,
            workRequest
        )
    }
}