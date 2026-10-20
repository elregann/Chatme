package com.pribadi.chatme.chatme_shortcuts

import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import androidx.core.app.Person
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Registers the "chatme_shortcuts" channel on every FlutterEngine, including
 * the background engine used by FCM, so conversation shortcuts can be created
 * while the app is closed.
 */
class ChatmeShortcutsPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "chatme_shortcuts")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        if (call.method != "pushShortcut") {
            result.notImplemented()
            return
        }

        val id = call.argument<String>("id")
        val name = call.argument<String>("name")
        val avatarBytes = call.argument<ByteArray>("avatarBytes")

        if (id == null || name == null) {
            result.error("INVALID_ARGS", "ID and name are required", null)
            return
        }

        try {
            createConversationShortcut(appContext, id, name, avatarBytes)
            result.success(true)
        } catch (e: Exception) {
            result.error("SHORTCUT_FAILED", e.message, null)
        }
    }

    private fun createConversationShortcut(
        context: Context,
        id: String,
        name: String,
        avatarBytes: ByteArray?
    ) {
        val personBuilder = Person.Builder()
            .setName(name)
            .setKey(id)

        if (avatarBytes != null) {
            val bitmap = BitmapFactory.decodeByteArray(avatarBytes, 0, avatarBytes.size)
            if (bitmap != null) {
                personBuilder.setIcon(IconCompat.createWithBitmap(bitmap))
            }
        }
        val person = personBuilder.build()

        // Same target and extras as the shortcut built in MainActivity.
        val intent = Intent().apply {
            setClassName(context.packageName, "com.pribadi.chatme.MainActivity")
            action = Intent.ACTION_VIEW
            putExtra("pubkey", id)
        }

        val shortcutId = "chat_shortcut_$id"

        // Drop the stale label so Android does not keep an old name.
        ShortcutManagerCompat.removeDynamicShortcuts(context, listOf(shortcutId))

        val shortcut = ShortcutInfoCompat.Builder(context, shortcutId)
            .setShortLabel(name)
            .setLongLabel(name)
            .setPerson(person)
            .setIntent(intent)
            .setLongLived(true)
            .build()

        ShortcutManagerCompat.pushDynamicShortcut(context, shortcut)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}