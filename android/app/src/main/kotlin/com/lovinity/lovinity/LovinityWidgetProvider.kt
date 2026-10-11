package com.lovinity.lovinity

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.TimeUnit

/**
 * Home-screen widget: next prayer, both spouses' check-ins, today's verse.
 *
 * Reads the JSON snapshot the Flutter side writes (see
 * `lib/features/widget/data/widget_snapshot.dart`). Deliberately does no
 * network and no database work of its own — a widget update runs on a tight
 * budget and can be killed mid-flight, so everything it needs is already in
 * the payload.
 */
class LovinityWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val raw = widgetData.getString("lovinity_snapshot", null)

        appWidgetIds.forEach { id ->
            val views = RemoteViews(context.packageName, R.layout.lovinity_widget)

            if (raw.isNullOrEmpty()) {
                // Before the first publish there is genuinely nothing to show.
                // Say so, rather than rendering zeros that would read as "you
                // have prayed nothing today".
                views.setTextViewText(R.id.widget_prayer, "Open Lovinity")
                views.setTextViewText(R.id.widget_counts, "")
                views.setTextViewText(R.id.widget_days, "")
                views.setTextViewText(R.id.widget_verse, "")
                appWidgetManager.updateAppWidget(id, views)
                return@forEach
            }

            try {
                val json = JSONObject(raw)
                renderInto(views, json)
            } catch (_: Exception) {
                // A malformed payload must leave a usable widget behind, never
                // a crash — an uncaught throw here shows the system's "problem
                // loading widget" tile until the next update cycle.
                views.setTextViewText(R.id.widget_prayer, "Lovinity")
                views.setTextViewText(R.id.widget_counts, "")
                views.setTextViewText(R.id.widget_days, "")
                views.setTextViewText(R.id.widget_verse, "")
            }

            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun renderInto(views: RemoteViews, json: JSONObject) {
        val ownName = json.optString("ownName", "You")
        val spouseName = json.optString("spouseName", "Your spouse")
        val ownCount = json.optInt("ownCount", 0)
        val spouseCount = json.optInt("spouseCount", 0)
        val ownTz = json.optString("ownTz", "UTC")
        val spouseTz = json.optString("spouseTz", "UTC")

        views.setTextViewText(R.id.widget_prayer, nextPrayerLabel(json))
        views.setTextViewText(
            R.id.widget_counts,
            "$ownName $ownCount/5   ·   $spouseName $spouseCount/5",
        )

        // The line that stops "0/5" being read as neglect. Only shown when the
        // two spouses are genuinely on different calendar days — for the common
        // same-zone case it would be noise.
        views.setTextViewText(R.id.widget_days, dayAttribution(ownTz, spouseTz, spouseName))

        val verse = json.optString("verseText", "")
        val reference = json.optString("verseReference", "")
        views.setTextViewText(
            R.id.widget_verse,
            when {
                verse.isEmpty() -> ""
                reference.isEmpty() -> verse
                else -> "$verse — $reference"
            },
        )
    }

    /**
     * "Asr in 1h 12m", or "Asr now" once it has arrived.
     *
     * The instant travels as UTC precisely so this can be rendered against the
     * device's current clock without the app having to guess the zone.
     */
    private fun nextPrayerLabel(json: JSONObject): String {
        val name = json.optString("nextPrayerName", "")
        val atIso = json.optString("nextPrayerAtIso", "")
        if (name.isEmpty() || atIso.isEmpty()) return "Lovinity"

        val at = parseIsoUtc(atIso) ?: return name
        val remaining = at.time - System.currentTimeMillis()
        if (remaining <= 0) return "$name now"

        val hours = TimeUnit.MILLISECONDS.toHours(remaining)
        val minutes = TimeUnit.MILLISECONDS.toMinutes(remaining) % 60
        return if (hours == 0L) "$name in ${minutes}m" else "$name in ${hours}h ${minutes}m"
    }

    /**
     * Names the days the two counts belong to, when they differ.
     *
     * Computed here rather than baked into the payload because the day rolls
     * over between publishes: the widget redraws on its own schedule, and a
     * precomputed string would go stale at midnight in either zone.
     */
    private fun dayAttribution(ownTz: String, spouseTz: String, spouseName: String): String {
        if (ownTz == spouseTz) return ""
        val now = Date()
        val ownDay = dayIn(ownTz, now)
        val spouseDay = dayIn(spouseTz, now)
        if (ownDay == spouseDay) return ""
        return "your $ownDay · $spouseName's $spouseDay"
    }

    private fun dayIn(tz: String, at: Date): String {
        val fmt = SimpleDateFormat("EEE d MMM", Locale.getDefault())
        fmt.timeZone = TimeZone.getTimeZone(tz)
        return fmt.format(at)
    }

    private fun parseIsoUtc(iso: String): Date? = try {
        val fmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        fmt.timeZone = TimeZone.getTimeZone("UTC")
        fmt.parse(iso)
    } catch (_: Exception) {
        try {
            val fallback = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
            fallback.timeZone = TimeZone.getTimeZone("UTC")
            fallback.parse(iso)
        } catch (_: Exception) {
            null
        }
    }
}
