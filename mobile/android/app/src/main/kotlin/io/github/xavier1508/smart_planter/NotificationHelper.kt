package io.github.xavier1508.smart_planter

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

/**
 * Small native notification surface for Tunas. The plant data itself stays in
 * the Flutter app; this helper only renders alerts and the repeating summary.
 */
object NotificationHelper {
    const val CHANNEL_ALERTS = "tunas_alerts"
    const val CHANNEL_PREDICTIONS = "tunas_predictions"

    fun createChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ALERTS,
                "Peringatan tanaman",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Air penampung rendah dan kondisi yang perlu perhatian."
            },
        )
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_PREDICTIONS,
                "Prediksi tanaman",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "Ringkasan prediksi kondisi tanaman secara berkala."
            },
        )
    }

    fun canNotify(context: Context): Boolean =
        Build.VERSION.SDK_INT < 33 ||
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED

    fun show(context: Context, id: Int, title: String, body: String, channel: String) {
        if (!canNotify(context)) return
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val contentIntent = launch?.let {
            PendingIntent.getActivity(
                context,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag(),
            )
        }
        val priority = if (channel == CHANNEL_ALERTS) {
            NotificationCompat.PRIORITY_HIGH
        } else {
            NotificationCompat.PRIORITY_DEFAULT
        }
        val builder = NotificationCompat.Builder(context, channel)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(priority)
            .setAutoCancel(true)
        if (contentIntent != null) builder.setContentIntent(contentIntent)
        try {
            NotificationManagerCompat.from(context).notify(id, builder.build())
        } catch (_: SecurityException) {
            // Permission was revoked between the check and notify.
        }
    }

    fun immutableFlag(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE
        } else {
            0
        }
}
