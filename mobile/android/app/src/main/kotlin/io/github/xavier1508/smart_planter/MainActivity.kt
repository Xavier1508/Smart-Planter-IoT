package io.github.xavier1508.smart_planter

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onResume() {
        super.onResume()
        checkForTesterUpdate()
    }
}
