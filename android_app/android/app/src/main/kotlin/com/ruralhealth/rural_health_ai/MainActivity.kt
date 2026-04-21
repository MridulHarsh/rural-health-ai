package com.ruralhealth.rural_health_ai

import android.content.pm.ApplicationInfo
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // FLAG_SECURE prevents screenshots, screen recording, and hides the
        // window from the Android recent-apps thumbnail. This app renders
        // patient PII (names, conditions, vitals) throughout — a screenshot
        // leak is the most realistic non-physical data exfiltration path on
        // a shared rural-clinic device. Applied in non-debuggable builds only
        // so hackathon demo videos can still be recorded from a debug APK.
        val isDebuggable = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (!isDebuggable) {
            window.setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE,
            )
        }
    }
}
