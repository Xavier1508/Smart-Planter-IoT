package io.github.xavier1508.smart_planter

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Alarm receiver for the repeating prediction summary. It reads the last
 * prediction stored in the PendingIntent extras, so it works when the Flutter
 * isolate is not running.
 */
class NotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        NotificationHelper.createChannels(context)
        val id = intent.getIntExtra("id", 4102)
        val title = intent.getStringExtra("title") ?: "Tunas"
        val body = intent.getStringExtra("body")
            ?: "Buka Tunas untuk melihat kondisi tanaman."
        val channel = intent.getStringExtra("channel")
            ?: NotificationHelper.CHANNEL_PREDICTIONS
        NotificationHelper.show(context, id, title, body, channel)
    }
}
