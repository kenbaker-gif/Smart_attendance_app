package com.example.smart_attendance_app

import android.os.Bundle
import android.webkit.WebView
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val webView = WebView(this)
        webView.settings.domStorageEnabled = true
        webView.settings.javaScriptEnabled = true
    }
}