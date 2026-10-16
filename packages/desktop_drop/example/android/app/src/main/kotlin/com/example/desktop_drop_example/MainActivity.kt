package com.example.desktop_drop_example

import android.content.pm.ApplicationInfo
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if ((applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) == 0) return
        // The fixture exists only in the debug source set, never in release APKs.
        Class.forName("com.example.desktop_drop_example.DropTestHost")
            .getMethod("register", FlutterActivity::class.java, FlutterEngine::class.java)
            .invoke(null, this, flutterEngine)
    }
}
