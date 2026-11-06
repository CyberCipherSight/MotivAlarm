package com.cybersight.alarmforaction

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onPause() {
        // Includes the native Preview Alarm activity and Android Settings.
        NativeVideoView.setHostResumed(false)
        super.onPause()
    }

    override fun onResume() {
        super.onResume()
        NativeVideoView.setHostResumed(true)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "motivalarm/native")
            .setMethodCallHandler(AlarmMethodChannel(this))
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "motivalarm/native_video_view",
            NativeVideoViewFactory(flutterEngine.dartExecutor.binaryMessenger)
        )
    }
}
