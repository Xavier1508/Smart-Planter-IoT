package io.github.xavier1508.smart_planter

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.Executor

// Keep the latest state so Flutter can reconnect after an activity recreation.
internal object UpdateProgressEvents : EventChannel.StreamHandler {
    private val mainHandler = Handler(Looper.getMainLooper())
    val mainExecutor = Executor { runnable ->
        if (Looper.myLooper() == Looper.getMainLooper()) runnable.run()
        else mainHandler.post(runnable)
    }
    private var sink: EventChannel.EventSink? = null
    private var latest: Map<String, Any> = mapOf("status" to "IDLE")

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        events.success(latest)
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    fun status(): String = latest["status"] as String

    fun publish(status: String, downloaded: Long = -1, total: Long = -1) {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mainHandler.post { publish(status, downloaded, total) }
            return
        }
        latest = mapOf("status" to status, "downloaded" to downloaded, "total" to total)
        sink?.success(latest)
    }
}
