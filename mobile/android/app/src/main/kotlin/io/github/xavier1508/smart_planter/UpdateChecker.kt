package io.github.xavier1508.smart_planter

internal const val distributionChannel = "local"

// Local-only builds do not contain any distribution or cloud SDK.
internal fun checkForTesterUpdate() = Unit
