package io.github.xavier1508.smart_planter

import android.os.SystemClock
import android.util.Log
import com.google.firebase.appdistribution.FirebaseAppDistribution

internal const val distributionChannel = "beta"

private const val checkIntervalMs = 15 * 60 * 1000L
private var lastCheckMs: Long? = null
private var checkInProgress = false

// Firebase prompts the tester to sign in and approve an available APK update.
// Checking is deliberately throttled when the activity repeatedly resumes.
internal fun checkForTesterUpdate() {
    val now = SystemClock.elapsedRealtime()
    val lastCheck = lastCheckMs
    if (checkInProgress || (lastCheck != null && now - lastCheck < checkIntervalMs)) return
    lastCheckMs = now
    try {
        checkInProgress = true
        UpdateProgressEvents.publish("CHECKING")
        FirebaseAppDistribution.getInstance()
            .updateIfNewReleaseAvailable()
            .addOnProgressListener(UpdateProgressEvents.mainExecutor) { progress ->
                UpdateProgressEvents.publish(
                    progress.updateStatus.name,
                    progress.apkBytesDownloaded,
                    progress.apkFileTotalBytes,
                )
            }
            .addOnCompleteListener { task ->
                checkInProgress = false
                val status = UpdateProgressEvents.status()
                if (task.isCanceled && status in setOf("CHECKING", "PENDING", "DOWNLOADING", "DOWNLOADED")) {
                    UpdateProgressEvents.publish(if (status == "DOWNLOADED") "INSTALL_CANCELED" else "UPDATE_CANCELED")
                } else if (!task.isSuccessful && status in setOf("CHECKING", "PENDING", "DOWNLOADING", "DOWNLOADED")) {
                    val failure = when (status) {
                        "DOWNLOADING" -> "DOWNLOAD_FAILED"
                        "DOWNLOADED" -> "UPDATE_FAILED"
                        else -> "NEW_RELEASE_CHECK_FAILED"
                    }
                    UpdateProgressEvents.publish(failure)
                } else if (task.isSuccessful && status in setOf("CHECKING", "PENDING")) {
                    // UpdateTask returns Void; a null result does not prove that
                    // no update exists. Only a Firebase status can say that.
                    UpdateProgressEvents.publish("IDLE")
                }
            }
            .addOnFailureListener { error ->
                Log.w("MossUpdates", "Update check unavailable (${error.javaClass.simpleName}).")
            }
    } catch (error: IllegalStateException) {
        checkInProgress = false
        UpdateProgressEvents.publish("NEW_RELEASE_CHECK_FAILED")
        Log.w("MossUpdates", "Firebase is not configured for this tester build.")
    }
}
