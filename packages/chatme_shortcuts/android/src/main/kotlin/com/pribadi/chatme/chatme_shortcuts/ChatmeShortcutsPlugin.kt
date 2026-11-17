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
        val icon = avatarBytes?.let { bytes ->
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                ?.let { IconCompat.createWithBitmap(it) }
        }

        val personBuilder = Person.Builder()
            .setName(name)
            .setKey(id)
        icon?.let { personBuilder.setIcon(it) }
        val person = personBuilder.build()

        // Launches MainActivity with the pubkey of the contact to open.
        val intent = Intent().apply {
            setClassName(context.packageName, "com.pribadi.chatme.MainActivity")
            action = Intent.ACTION_VIEW
            putExtra("pubkey", id)
        }

        val shortcutId = "chat_shortcut_$id"

        // Drop the stale label so Android does not keep an old name.
        ShortcutManagerCompat.removeDynamicShortcuts(context, listOf(shortcutId))

        val shortcutBuilder = ShortcutInfoCompat.Builder(context, shortcutId)
            .setShortLabel(name)
            .setLongLabel(name)
            .setPerson(person)
            .setIntent(intent)
            .setLongLived(true)

        // The launcher renders the shortcut icon from here; the Person icon is
        // not used by every launcher (e.g. Pixel), so set both.
        icon?.let { shortcutBuilder.setIcon(it) }

        ShortcutManagerCompat.pushDynamicShortcut(context, shortcutBuilder.build())
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}