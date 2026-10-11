package com.lovinity.lovinity

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Delivers text shared from other apps (ACTION_SEND, text/plain) to Dart over
 * the "lovinity/share" channel. A cold-start share is held until Dart pulls it
 * with getInitialShare; later shares are pushed with onShare.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var initialShare: Map<String, String?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        initialShare = sharePayload(intent)
        // Consume it so a process restore doesn't redeliver the same share.
        if (initialShare != null) intent.action = Intent.ACTION_MAIN
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lovinity/share").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialShare" -> {
                        result.success(initialShare)
                        initialShare = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val payload = sharePayload(intent) ?: return
        intent.action = Intent.ACTION_MAIN
        channel?.invokeMethod("onShare", payload)
    }

    private fun sharePayload(intent: Intent?): Map<String, String?>? {
        if (intent?.action != Intent.ACTION_SEND) return null
        if (intent.type?.startsWith("text/") != true) return null
        val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return null
        return mapOf("text" to text, "subject" to intent.getStringExtra(Intent.EXTRA_SUBJECT))
    }
}
