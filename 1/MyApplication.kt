package com.laxce.adl

import android.app.Application
import android.util.Log
import com.google.firebase.FirebaseApp

class MyApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        Log.d("MyApplication", "onCreate - Initializing Firebase...")
        FirebaseApp.initializeApp(this)
        Log.d("MyApplication", "Firebase initialized: ${FirebaseApp.getApps(this).isNotEmpty()}")
    }
} 
