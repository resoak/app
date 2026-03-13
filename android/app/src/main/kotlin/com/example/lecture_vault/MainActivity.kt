package com.example.lecture_vault

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.util.Log

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "native_libs")
            .setMethodCallHandler { call, result ->
                if (call.method == "getNativeLibDir") {
                    val dir = applicationInfo.nativeLibraryDir
                    Log.d("MAIN", "nativeLibDir: $dir")
                    result.success(dir)
                } else {
                    result.notImplemented()
                }
            }
    }
}