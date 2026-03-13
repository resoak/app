package com.example.lecture_vault

import android.app.Application
import android.util.Log

class App : Application() {
    override fun onCreate() {
        try {
            val libDir = applicationInfo.nativeLibraryDir
            System.load("$libDir/libonnxruntime.so")
            Log.d("APP", "onnxruntime loaded from: $libDir")
        } catch (e: Exception) {
            Log.e("APP", "onnxruntime load FAILED: ${e.message}")
        }
        super.onCreate()
    }
}