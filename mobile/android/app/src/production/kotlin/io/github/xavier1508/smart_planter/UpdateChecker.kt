package io.github.xavier1508.smart_planter

internal const val distributionChannel = "production"

// Google Play/production builds do not contain the App Distribution SDK.
internal fun checkForTesterUpdate() = Unit
