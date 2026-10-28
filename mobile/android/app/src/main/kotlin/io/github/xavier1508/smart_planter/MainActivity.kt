package io.github.xavier1508.smart_planter

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
