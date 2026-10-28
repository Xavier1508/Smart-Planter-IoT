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
        FirebaseAppDistribution.getInstance()
            .updateIfNewReleaseAvailable()
            .addOnCompleteListener { checkInProgress = false }
            .addOnFailureListener { error ->
                Log.w("MossUpdates", "Update check unavailable (${error.javaClass.simpleName}).")
            }
    } catch (error: IllegalStateException) {
        checkInProgress = false
        Log.w("MossUpdates", "Firebase is not configured for this tester build.")
    }
}
