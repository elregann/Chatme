package com.pribadi.chatme

import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters

class NostrWorker(context: Context, params: WorkerParameters) : Worker(context, params) {

    override fun doWork(): Result {
        return try {
            val intent = android.content.Intent("com.pribadi.chatme.RECONNECT")
            intent.setPackage(applicationContext.packageName)
            applicationContext.sendBroadcast(intent)
            Result.success()
        } catch (e: Exception) {
            Result.retry()
        }
    }
}