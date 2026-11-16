import SwiftUI
import WidgetKit

/// Must match `kWidgetAppGroupId` / `kWidgetDataKey` in
/// `lib/features/widget/domain/widget_providers.dart`, and the App Group must
/// be enabled on BOTH the Runner target and this extension. If either side
/// differs the widget reads nothing and renders its empty state forever, with
/// no error anywhere — so these are the first thing to check if it looks dead.
private let appGroupId = "group.com.lovinity.lovinity"
private let snapshotKey = "lovinity_snapshot"

struct LovinityEntry: TimelineEntry {
    let date: Date
    let snapshot: LovinitySnapshot?
}

struct LovinityProvider: TimelineProvider {
    func placeholder(in context: Context) -> LovinityEntry {
        LovinityEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (LovinityEntry) -> Void) {
        completion(
            LovinityEntry(
                date: Date(),
                snapshot: LovinitySnapshot.load(appGroupId: appGroupId, key: snapshotKey)
            )
        )
    }

    /// Refreshes on a short rolling timeline.
    ///
    /// The countdown to the next prayer has to stay honest between app
    /// launches, and WidgetKit will not let the view re-render on its own — the
    /// only way to change what is on screen is to supply entries in advance.
    /// Fifteen minutes over four hours is a compromise: fine-grained enough
    /// that "Asr in 2h 14m" is never badly wrong, coarse enough to stay inside
    /// the system's refresh budget.
    ///
    /// The check-in counts and verse deliberately are NOT extrapolated — they
    /// come only from what the app last wrote. Guessing at them would mean the
    /// widget inventing prayer counts, which is exactly the falsehood this
    /// feature must not commit.
    func getTimeline(in context: Context, completion: @escaping (Timeline<LovinityEntry>) -> Void) {
        let snapshot = LovinitySnapshot.load(appGroupId: appGroupId, key: snapshotKey)
        let now = Date()

        var entries: [LovinityEntry] = []
        for offset in stride(from: 0, to: 240, by: 15) {
            let date = Calendar.current.date(byAdding: .minute, value: offset, to: now) ?? now
            entries.append(LovinityEntry(date: date, snapshot: snapshot))
        }

        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct LovinityWidgetView: View {
    var entry: LovinityEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            guardedContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
    }

    @ViewBuilder
    private var guardedContent: some View {
        if let snapshot = entry.snapshot {
            Text(snapshot.prayerLabel(at: entry.date))
                .font(.headline)
                .lineLimit(1)

            Text("\(snapshot.ownName) \(snapshot.ownCount)/5   ·   \(snapshot.spouseName) \(snapshot.spouseCount)/5")
                .font(.subheadline)
                .lineLimit(1)

            // Only rendered when the two are genuinely on different days.
            let attribution = snapshot.dayAttribution(at: entry.date)
            if !attribution.isEmpty {
                Text(attribution)
                    .font(.caption2)
                    .opacity(0.75)
                    .lineLimit(1)
            }

            if !snapshot.verseLine.isEmpty {
                Text(snapshot.verseLine)
                    .font(.caption)
                    .opacity(0.9)
                    .lineLimit(3)
                    .padding(.top, 4)
            }
        } else {
            // No payload yet. Say so rather than rendering zeros, which would
            // read as "you have prayed nothing today".
            Text("Open Lovinity")
                .font(.headline)
            Text("Your prayer times and check-ins will appear here.")
                .font(.caption)
                .opacity(0.8)
        }
    }
}

@main
struct LovinityWidget: Widget {
    let kind: String = "LovinityWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LovinityProvider()) { entry in
            if #available(iOS 17.0, *) {
                LovinityWidgetView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                LovinityWidgetView(entry: entry)
            }
        }
        .configurationDisplayName("Lovinity")
        .description("Next prayer, both your check-ins, and today's verse.")
        .supportedFamilies([.systemMedium])
    }
}
