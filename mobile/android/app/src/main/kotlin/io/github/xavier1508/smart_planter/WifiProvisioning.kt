package io.github.xavier1508.smart_planter

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Local-only Wi-Fi provisioning. Android requires a system consent dialog for
 * WifiNetworkSpecifier; the app cannot silently force or lock Wi-Fi. Once the
 * user approves, the process is bound to the Moss network only.
 */
class WifiProvisioning(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    companion object {
        private const val CHANNEL = "moss/wifi_provisioning"
        private const val PERMISSION_REQUEST = 7401
        private const val MOSS_SSID = "Moss"
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val context: Context = activity.applicationContext
    private val connectivity =
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val main = Handler(Looper.getMainLooper())

    private var callback: ConnectivityManager.NetworkCallback? = null
    private var network: Network? = null
    private var pending: MethodChannel.Result? = null
    private var pendingSsid = MOSS_SSID
    private var pendingPassword = ""
    private var pendingTimeout = 45000
    private var connectCompleted = false

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "connect" -> requestConnect(call, result)
            "release" -> {
                release()
                result.success(null)
            }
            "currentSsid" -> result.success(currentSsid())
            else -> result.notImplemented()
        }
    }

    private fun requestConnect(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error(
                "unsupported_android",
                "Android 10 or newer is required for in-app Wi-Fi setup.",
                null,
            )
            return
        }
        val ssid = call.argument<String>("ssid") ?: MOSS_SSID
        val password = call.argument<String>("password") ?: ""
        val timeout = call.argument<Int>("timeoutMs") ?: 45000
        if (ssid != MOSS_SSID) {
            result.error("invalid_ssid", "Only the Moss setup AP is allowed.", null)
            return
        }
        if (!hasPermission()) {
            pending = result
            pendingSsid = ssid
            pendingPassword = password
            pendingTimeout = timeout
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(requiredPermission()),
                PERMISSION_REQUEST,
            )
            return
        }
        startConnect(ssid, password, timeout, result)
    }

    fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (requestCode != PERMISSION_REQUEST) return
        val result = pending ?: return
        pending = null
        if (hasPermission()) {
            startConnect(pendingSsid, pendingPassword, pendingTimeout, result)
        } else {
            result.error(
                "permission_denied",
                "Wi-Fi permission is required to connect to Moss.",
                null,
            )
        }
    }

    private fun requiredPermission(): String =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.NEARBY_WIFI_DEVICES
        } else {
            Manifest.permission.ACCESS_FINE_LOCATION
        }

    private fun hasPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        return ContextCompat.checkSelfPermission(context, requiredPermission()) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun startConnect(
        ssid: String,
        password: String,
        timeout: Int,
        result: MethodChannel.Result,
    ) {
        release()
        connectCompleted = false
        val specifierBuilder = WifiNetworkSpecifier.Builder().setSsid(ssid)
        if (password.isNotEmpty()) {
            specifierBuilder.setWpa2Passphrase(password)
        }
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .setNetworkSpecifier(specifierBuilder.build())
            .build()
        val networkCallback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(available: Network) {
                network = available
                // Bind the whole process so Dart's TCP socket uses the approved
                // Moss network instead of a stale entry or mobile data.
                connectivity.bindProcessToNetwork(available)
                if (!connectCompleted) {
                    connectCompleted = true
                    main.post { result.success(true) }
                }
            }

            override fun onUnavailable() {
                network = null
                connectivity.bindProcessToNetwork(null)
                if (!connectCompleted) {
                    connectCompleted = true
                    main.post {
                        result.error(
                            "ap_unavailable",
                            "Moss AP was not approved or is not reachable.",
                            null,
                        )
                    }
                }
            }

            override fun onLost(lost: Network) {
                if (network == lost) {
                    network = null
                    connectivity.bindProcessToNetwork(null)
                }
            }
        }
        callback = networkCallback
        try {
            connectivity.requestNetwork(request, networkCallback, timeout)
        } catch (error: Exception) {
            release()
            if (!connectCompleted) {
                connectCompleted = true
                result.error("connect_failed", error.message, null)
            }
        }
    }

    private fun release() {
        connectivity.bindProcessToNetwork(null)
        val active = callback ?: return
        callback = null
        network = null
        try {
            connectivity.unregisterNetworkCallback(active)
        } catch (_: Exception) {
            // Already released or the system rejected the callback.
        }
    }

    private fun currentSsid(): String? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            !hasPermission()
        ) {
            return null
        }
        val wifi = context.getSystemService(Context.WIFI_SERVICE) as WifiManager
        @Suppress("DEPRECATION")
        val raw = wifi.connectionInfo?.ssid ?: return null
        val ssid = raw.trim('"')
        return ssid.takeIf {
            it.isNotEmpty() && !it.contains("unknown", ignoreCase = true)
        }
    }
}
