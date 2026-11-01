package io.github.xavier1508.smart_planter

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
