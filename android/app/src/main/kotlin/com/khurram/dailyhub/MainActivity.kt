package com.khurram.dailyhub

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// local_auth (biometric unlock for the vault) requires a FragmentActivity.
// Leaving this as the default FlutterActivity causes a runtime crash the
// moment the fingerprint prompt is shown, so it must stay as written.
class MainActivity : FlutterFragmentActivity() {

    private val channel = "com.khurram.dailyhub/widget"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // Dart has just written fresh data; redraw the home-screen widget.
                    "refresh" -> {
                        DailyHubWidgetProvider.refreshAll(applicationContext)
                        result.success(null)
                    }
                    // Lets Dart know the app was opened from the widget's + button.
                    "launchRoute" -> result.success(intent?.getStringExtra("dailyhub_route"))
                    else -> result.notImplemented()
                }
            }
    }
}
