package com.pribadi.chatme

import android.content.Context
import android.content.Intent
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Bundle
import android.os.Looper
import android.os.PowerManager
import android.os.StatFs
import android.provider.Settings
import androidx.work.*
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

class MainActivity: FlutterActivity() {
    private val BATTERY_CHANNEL = "com.chatme.app/battery"
    private val TASK_CHANNEL = "com.chatme.app/task"
    private val STORAGE_CHANNEL = "com.chatme.app/storage"
    private val AES_CHANNEL = "com.chatme.app/aes"
    private val SHORTCUT_CHANNEL = "com.chatme.app/shortcut"

    // Pubkey from a tapped launcher shortcut, handed to Dart exactly once.
    private var pendingShortcutPubkey: String? = null

    companion object {
        // Must match the extra ChatmeShortcutsPlugin puts on the intent.
        private const val EXTRA_SHORTCUT_PUBKEY = "pubkey"
        private var retainedEngine: FlutterEngine? = null
        private var attachedActivity: MainActivity? = null
        @Volatile private var callActive = false

        // One worker for the whole process: a file is sealed chunk by chunk, in
        // order, and the platform thread stays free while it happens.
        private val aesExecutor = Executors.newSingleThreadExecutor()
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine? = retainedEngine

    override fun shouldDestroyEngineWithHost(): Boolean = !callActive

    override fun onDestroy() {
        if (attachedActivity === this) attachedActivity = null
        if (callActive) retainedEngine = flutterEngine
        super.onDestroy()
    }

    private fun releaseRetainedEngineIfIdle() {
        Handler(Looper.getMainLooper()).postDelayed({
            val engine = retainedEngine
            if (!callActive && attachedActivity == null && engine != null) {
                retainedEngine = null
                engine.destroy()
            }
        }, 1500)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Read the shortcut before super: the retained engine can resume and ask
        // for it right away. A recreation (rotation, process restore) keeps the
        // saved state, so an old tap is not replayed.
        if (savedInstanceState == null) captureShortcutIntent(intent)
        super.onCreate(savedInstanceState)
        val tappedOngoing = intent?.action == "SELECT_NOTIFICATION" &&
                intent?.getIntExtra("notificationId", -1) == 888889
        if (tappedOngoing && callActive) {
            flutterEngine?.dartExecutor?.binaryMessenger?.let {
                MethodChannel(it, TASK_CHANNEL).invokeMethod("openActiveCall", null)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // singleTop: a shortcut tapped while the activity is alive arrives here.
        // Dart looks for it on the next resume.
        captureShortcutIntent(intent)
    }

    private fun captureShortcutIntent(intent: Intent?) {
        if (intent == null) return
        // Opening from Recents reuses the old intent; it is not a new tap.
        if ((intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) return
        val pubkey = intent.getStringExtra(EXTRA_SHORTCUT_PUBKEY) ?: return
        if (pubkey.isEmpty()) return
        pendingShortcutPubkey = pubkey
        // Consumed, so an activity recreation cannot open the chat again.
        intent.removeExtra(EXTRA_SHORTCUT_PUBKEY)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        if (flutterEngine === retainedEngine) {
            retainedEngine = null
        } else {
            super.configureFlutterEngine(flutterEngine)
        }
        attachedActivity = this

        // Battery Optimization Channel
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
            } else if (call.method == "isIgnoringBatteryOptimization") {
                val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
                result.success(
                    Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
                        powerManager.isIgnoringBatteryOptimizations(packageName)
                )
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TASK_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "moveToBack" -> {
                    moveTaskToBack(true)
                    result.success(true)
                }
                "setCallActive" -> {
                    callActive = (call.arguments as? Boolean) ?: false
                    if (!callActive) {
                        releaseRetainedEngineIfIdle()
                        try {
                            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                audioManager.clearCommunicationDevice()
                            }
                            @Suppress("DEPRECATION")
                            audioManager.isSpeakerphoneOn = false
                        } catch (_: Exception) {}
                    }
                    result.success(true)
                }
                "setSpeakerphone" -> {
                    val enabled = (call.arguments as? Boolean) ?: false
                    try {
                        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        if (enabled && audioManager.mode != AudioManager.MODE_IN_COMMUNICATION) {
                            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            if (enabled) {
                                val devices = audioManager.availableCommunicationDevices
                                val speakerDevice = devices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
                                if (speakerDevice != null) {
                                    audioManager.setCommunicationDevice(speakerDevice)
                                } else {
                                    @Suppress("DEPRECATION")
                                    audioManager.isSpeakerphoneOn = true
                                }
                            } else {
                                audioManager.clearCommunicationDevice()
                            }
                        } else {
                            @Suppress("DEPRECATION")
                            audioManager.isSpeakerphoneOn = enabled
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("AUDIO_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Storage Channel: how much room is left for a video download.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORAGE_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "freeBytes") {
                try {
                    val stat = StatFs(filesDir.absolutePath)
                    result.success(stat.availableBytes)
                } catch (e: Exception) {
                    result.error("STORAGE_ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }

        // AES Channel: AES-GCM for one chunk of a streamed file. The cipher runs
        // on a worker, so a video is encrypted without stalling the screen.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AES_CHANNEL).setMethodCallHandler { call, result ->
            val encrypt = when (call.method) {
                "seal" -> true
                "open" -> false
                else -> {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
            }
            val args = call.arguments as? Map<*, *>
            val key = args?.get("key") as? ByteArray
            val nonce = args?.get("nonce") as? ByteArray
            val aad = args?.get("aad") as? ByteArray
            val data = args?.get("data") as? ByteArray
            if (key == null || nonce == null || aad == null || data == null) {
                result.error("AES_ARGUMENTS", "key, nonce, aad and data are required", null)
                return@setMethodCallHandler
            }
            aesExecutor.execute {
                try {
                    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                    cipher.init(
                        if (encrypt) Cipher.ENCRYPT_MODE else Cipher.DECRYPT_MODE,
                        SecretKeySpec(key, "AES"),
                        GCMParameterSpec(128, nonce)
                    )
                    cipher.updateAAD(aad)
                    val out = cipher.doFinal(data)
                    Handler(Looper.getMainLooper()).post { result.success(out) }
                } catch (e: Exception) {
                    Handler(Looper.getMainLooper()).post {
                        result.error("AES_ERROR", e.message, null)
                    }
                }
            }
        }

        // Shortcut Channel: the contact of a tapped launcher shortcut. The value
        // is cleared here, so the Dart side can check on every resume safely.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHORTCUT_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getLaunchChat") {
                val pubkey = pendingShortcutPubkey
                pendingShortcutPubkey = null
                result.success(pubkey)
            } else {
                result.notImplemented()
            }
        }

        scheduleNostrWorker()
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