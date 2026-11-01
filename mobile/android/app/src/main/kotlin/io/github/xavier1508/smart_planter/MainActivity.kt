package io.github.xavier1508.smart_planter

import android.Manifest
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.SystemClock
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        NotificationHelper.createChannels(this)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "moss/update_progress")
            .setStreamHandler(UpdateProgressEvents)
        val appearance = getSharedPreferences("moss_appearance", MODE_PRIVATE)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "moss/appearance")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "read" -> result.success(mapOf(
                        "theme" to appearance.getString("theme", "system"),
                        "sky" to appearance.getString("sky", "automatic"),
                        "manualMinute" to appearance.getInt("manualMinute", 720),
                    ))
                    "write" -> {
                        val theme = call.argument<String>("theme")
                        val sky = call.argument<String>("sky")
                        val manualMinute = call.argument<Int>("manualMinute")
                        val themes = setOf("system", "light", "dark")
                        val skies = setOf("automatic", "dawn", "morning", "day", "evening", "night", "midnight", "custom")
                        if (theme == null || sky == null || manualMinute == null || theme !in themes || sky !in skies || manualMinute !in 0..1439) {
                            result.error("invalid", "Display settings are invalid.", null)
                        } else {
                            appearance.edit().putString("theme", theme).putString("sky", sky)
                                .putInt("manualMinute", manualMinute).apply()
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        val schedule = getSharedPreferences("moss_schedule", MODE_PRIVATE)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "moss/schedule")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "read" -> result.success(schedule.getString("json", "[]"))
                    "write" -> {
                        val json = call.argument<String>("json")
                        if (json == null || json.length > 32768) {
                            result.error("invalid", "Schedule is invalid.", null)
                        } else {
                            schedule.edit().putString("json", json).apply()
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        val profile = getSharedPreferences("tunas_profile", MODE_PRIVATE)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "moss/profile")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "read" -> result.success(profile.getString("json", ""))
                    "write" -> {
                        val json = call.argument<String>("json")
                        if (json == null || json.length > 65536) {
                            result.error("invalid", "Profile is invalid.", null)
                        } else {
                            profile.edit().putString("json", json).apply()
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "moss/notifications")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermission" -> {
                        if (Build.VERSION.SDK_INT >= 33 &&
                            ContextCompat.checkSelfPermission(
                                this,
                                Manifest.permission.POST_NOTIFICATIONS,
                            ) != PackageManager.PERMISSION_GRANTED
                        ) {
                            requestPermissions(
                                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                4101,
                            )
                            result.success(false)
                        } else {
                            result.success(true)
                        }
                    }
                    "show" -> {
                        val id = call.argument<Int>("id")
                        val title = call.argument<String>("title")
                        val body = call.argument<String>("body")
                        val channel = call.argument<String>("channel")
                            ?: NotificationHelper.CHANNEL_ALERTS
                        if (id == null || title == null || body == null) {
                            result.error("invalid", "Notification payload is invalid.", null)
                        } else {
                            NotificationHelper.show(this, id, title, body, channel)
                            result.success(null)
                        }
                    }
                    "schedule" -> {
                        val id = call.argument<Int>("id")
                        val title = call.argument<String>("title")
                        val body = call.argument<String>("body")
                        val channel = call.argument<String>("channel")
                            ?: NotificationHelper.CHANNEL_PREDICTIONS
                        val intervalMinutes = call.argument<Int>("intervalMinutes")
                        if (id == null || title == null || body == null ||
                            intervalMinutes == null || intervalMinutes < 30
                        ) {
                            result.error("invalid", "Schedule payload is invalid.", null)
                        } else {
                            val intent = Intent(this, NotificationReceiver::class.java).apply {
                                putExtra("id", id)
                                putExtra("title", title)
                                putExtra("body", body)
                                putExtra("channel", channel)
                            }
                            val pending = PendingIntent.getBroadcast(
                                this,
                                id,
                                intent,
                                PendingIntent.FLAG_UPDATE_CURRENT or NotificationHelper.immutableFlag(),
                            )
                            val alarm = getSystemService(ALARM_SERVICE) as AlarmManager
                            val interval = intervalMinutes * 60_000L
                            alarm.setInexactRepeating(
                                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                                SystemClock.elapsedRealtime() + interval,
                                interval,
                                pending,
                            )
                            result.success(null)
                        }
                    }
                    "update" -> {
                        val id = call.argument<Int>("id")
                        val title = call.argument<String>("title")
                        val body = call.argument<String>("body")
                        val channel = call.argument<String>("channel")
                            ?: NotificationHelper.CHANNEL_PREDICTIONS
                        if (id == null || title == null || body == null) {
                            result.error("invalid", "Notification payload is invalid.", null)
                        } else {
                            val intent = Intent(this, NotificationReceiver::class.java).apply {
                                putExtra("id", id)
                                putExtra("title", title)
                                putExtra("body", body)
                                putExtra("channel", channel)
                            }
                            // Update the extras without resetting the repeating
                            // alarm's next-fire time.
                            PendingIntent.getBroadcast(
                                this,
                                id,
                                intent,
                                PendingIntent.FLAG_UPDATE_CURRENT or NotificationHelper.immutableFlag(),
                            )
                            result.success(null)
                        }
                    }
                    "cancel" -> {
                        val id = call.argument<Int>("id")
                        if (id == null) {
                            result.error("invalid", "Notification id is invalid.", null)
                        } else {
                            val intent = Intent(this, NotificationReceiver::class.java)
                            val pending = PendingIntent.getBroadcast(
                                this,
                                id,
                                intent,
                                PendingIntent.FLAG_NO_CREATE or NotificationHelper.immutableFlag(),
                            )
                            if (pending != null) {
                                (getSystemService(ALARM_SERVICE) as AlarmManager).cancel(pending)
                                pending.cancel()
                            }
                            NotificationManagerCompat.from(this).cancel(id)
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "moss/history")
            .setMethodCallHandler { call, result ->
                val deviceId = call.argument<String>("deviceId")
                when (call.method) {
                    "append" -> {
                        val header = call.argument<String>("header")
                        val line = call.argument<String>("line")
                        if (deviceId == null || header == null || line == null) {
                            result.error("invalid", "History payload is invalid.", null)
                        } else {
                            try {
                                HistoryStore.append(this, deviceId, header, line)
                                result.success(null)
                            } catch (error: Exception) {
                                result.error("write_failed", "History write failed.", null)
                            }
                        }
                    }
                    "readTail" -> {
                        if (deviceId == null) {
                            result.error("invalid", "Device id is missing.", null)
                        } else {
                            val limit = call.argument<Int>("limit") ?: 240
                            result.success(HistoryStore.readTail(this, deviceId, limit))
                        }
                    }
                    "export" -> {
                        if (deviceId == null) {
                            result.error("invalid", "Device id is missing.", null)
                        } else {
                            try {
                                result.success(HistoryStore.export(this, deviceId))
                            } catch (error: Exception) {
                                result.error("export_failed", "History export failed.", null)
                            }
                        }
                    }
                    "clear" -> {
                        if (deviceId == null) {
                            result.error("invalid", "Device id is missing.", null)
                        } else {
                            result.success(HistoryStore.clear(this, deviceId))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "moss/build_info")
            .setMethodCallHandler { call, result ->
                if (call.method != "read") {
                    result.notImplemented()
                } else {
                    try {
                        @Suppress("DEPRECATION")
                        val info = packageManager.getPackageInfo(packageName, 0)
                        @Suppress("DEPRECATION")
                        val build = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            info.longVersionCode
                        } else {
                            info.versionCode.toLong()
                        }
                        result.success(mapOf(
                            "version" to info.versionName,
                            "build" to build,
                            "channel" to distributionChannel,
                        ))
                    } catch (error: Exception) {
                        result.error("unavailable", "Build information is unavailable.", null)
                    }
                }
            }
    }

    override fun onResume() {
        super.onResume()
        checkForTesterUpdate()
    }
}
