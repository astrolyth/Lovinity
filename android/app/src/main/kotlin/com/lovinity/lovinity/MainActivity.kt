package com.lovinity.lovinity

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Delivers text shared from other apps (ACTION_SEND, text/plain) to Dart over
 * the "lovinity/share" channel. A cold-start share is held until Dart pulls it
 * with getInitialShare; later shares are pushed with onShare.
 *
 * The activity is launchMode="singleTask" (AndroidManifest.xml): while it
 * exists, every share is routed to this same instance through onNewIntent,
 * so there is only ever one FlutterEngine (and one Dart isolate touching the
 * per-account databases and key vault).
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var initialShare: Map<String, String?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        initialShare = sharePayload(intent)
        // Same-process recreation (e.g. rotation) re-reads this same Intent
        // object, so reset its action once the share is held. A relaunch after
        // process death is covered separately in sharePayload.
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

    // singleTask delivers every re-launch of the running activity here: a
    // share pushes onShare; anything else (launcher icon, notification tap)
    // only updates the current intent for the Flutter embedding.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val payload = sharePayload(intent) ?: return
        intent.action = Intent.ACTION_MAIN
        channel?.invokeMethod("onShare", payload)
    }

    private fun sharePayload(intent: Intent?): Map<String, String?>? {
        if (intent?.action != Intent.ACTION_SEND) return null
        // Relaunched from Recents (e.g. after process death): the system hands
        // back the original ACTION_SEND intent, which is a stale share, not a
        // new one.
        if ((intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) return null
        if (intent.type?.startsWith("text/") != true) return null
        // CharSequence, not String: apps may share styled text (a Spanned),
        // which getStringExtra returns as null.
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString() ?: return null
        val subject = intent.getCharSequenceExtra(Intent.EXTRA_SUBJECT)?.toString()
        return mapOf("text" to text, "subject" to subject)
    }
}
