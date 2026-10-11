import Foundation

/// The payload the Flutter app writes into the shared App Group container.
///
/// Mirrors `lib/features/widget/data/widget_snapshot.dart`. The two are joined
/// only by this JSON shape, so a field renamed on one side and not the other
/// fails silently — every property here is therefore optional with a sensible
/// default rather than a hard requirement that would blank the whole widget.
struct LovinitySnapshot: Decodable {
    var ownName: String = "You"
    var spouseName: String = "Your spouse"
    var ownCount: Int = 0
    var spouseCount: Int = 0
    var ownTz: String = "UTC"
    var spouseTz: String = "UTC"
    var nextPrayerName: String?
    var nextPrayerAtIso: String?
    var verseText: String?
    var verseReference: String?
    var latitude: Double?
    var longitude: Double?
    var calcMethod: String?
    var madhab: String?
    var updatedAt: String?

    /// Whether the two spouses are on different calendar days right now.
    ///
    /// Recomputed on every render rather than read from the payload: the day
    /// rolls over between publishes, and a precomputed answer would be stale
    /// from midnight until the app next happens to write.
    func zonesDiffer(at date: Date = Date()) -> Bool {
        guard ownTz != spouseTz else { return false }
        return dayString(tz: ownTz, at: date) != dayString(tz: spouseTz, at: date)
    }

    /// "your Thu 7 Aug · Aisha's Fri 8 Aug", or empty when they agree.
    ///
    /// This line is why both zones travel in the payload. A widget has no day
    /// toggle and no room to explain itself, so an unqualified "Aisha 0/5" at
    /// 1am her time reads as neglect rather than as a day that has barely
    /// started.
    func dayAttribution(at date: Date = Date()) -> String {
        guard zonesDiffer(at: date) else { return "" }
        let mine = dayString(tz: ownTz, at: date)
        let theirs = dayString(tz: spouseTz, at: date)
        return "your \(mine) · \(spouseName)'s \(theirs)"
    }

    /// "Asr in 1h 12m", or "Asr now" once it has arrived.
    func prayerLabel(at date: Date = Date()) -> String {
        guard let name = nextPrayerName, !name.isEmpty else { return "Lovinity" }
        guard let iso = nextPrayerAtIso, let at = Self.parseIso(iso) else { return name }

        let remaining = at.timeIntervalSince(date)
        if remaining <= 0 { return "\(name) now" }

        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        return hours == 0 ? "\(name) in \(minutes)m" : "\(name) in \(hours)h \(minutes)m"
    }

    var verseLine: String {
        guard let text = verseText, !text.isEmpty else { return "" }
        guard let ref = verseReference, !ref.isEmpty else { return text }
        return "\(text) — \(ref)"
    }

    private func dayString(tz: String, at date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE d MMM"
        fmt.timeZone = TimeZone(identifier: tz) ?? TimeZone(identifier: "UTC")
        return fmt.string(from: date)
    }

    /// Parses the Dart-side ISO-8601 UTC form, with and without milliseconds.
    static func parseIso(_ iso: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFractional.date(from: iso) { return d }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: iso)
    }

    /// Reads the snapshot from the shared App Group container.
    ///
    /// Returns nil when absent or unreadable so the widget can show a "open the
    /// app" state instead of rendering zeros, which would look like a real
    /// count of nothing prayed.
    static func load(appGroupId: String, key: String) -> LovinitySnapshot? {
        guard
            let defaults = UserDefaults(suiteName: appGroupId),
            let raw = defaults.string(forKey: key),
            let data = raw.data(using: .utf8)
        else { return nil }

        return try? JSONDecoder().decode(LovinitySnapshot.self, from: data)
    }
}
