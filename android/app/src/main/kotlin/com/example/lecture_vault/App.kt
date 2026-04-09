package com.example.lecture_vault

import android.app.Application
import android.util.Log

class App : Application() {
    override fun onCreate() {
        super.onCreate()

        // Defer native STT runtime loading until the recognizer is actually used.
        Log.d("APP", "Application started")
    }
}
