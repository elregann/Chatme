package com.pribadi.chatme

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Bundle
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import androidx.work.*
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.TimeUnit

class MainActivity: FlutterActivity() {
    private val BATTERY_CHANNEL = "com.chatme.app/battery"
    private val TASK_CHANNEL = "com.chatme.app/task"

    companion object {
        private var retainedEngine: FlutterEngine? = null
        private var attachedActivity: MainActivity? = null
        @Volatile private var callActive = false
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
        super.onCreate(savedInstanceState)
        val tappedOngoing = intent?.action == "SELECT_NOTIFICATION" &&
                intent?.getIntExtra("notificationId", -1) == 888889
        if (tappedOngoing && callActive) {
            flutterEngine?.dartExecutor?.binaryMessenger?.let {
                MethodChannel(it, TASK_CHANNEL).invokeMethod("openActiveCall", null)
            }
        }
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
                    if (!callActive) releaseRetainedEngineIfIdle()
                    result.success(true)
                }
                else -> result.notImplemented()
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