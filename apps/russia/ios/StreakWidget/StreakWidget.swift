import SwiftUI
import WidgetKit

private let widgetGroup = "group.ru.pdd.pddApp.streak"
private let widgetKind = "PddStudyStreak"

struct StreakEntry: TimelineEntry {
    let date: Date
    let snapshot: [String: Any]

    private var lastActive: Date? {
        guard let iso = snapshot["lastActiveDate"] as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: iso)
    }

    var current: Int {
        guard let last = lastActive,
              let yesterday = Calendar.current.date(byAdding: .day, value: -1,
                  to: Calendar.current.startOfDay(for: date)), last >= yesterday else { return 0 }
        return max(0, snapshot["current"] as? Int ?? 0)
    }
    var best: Int { max(current, snapshot["longest"] as? Int ?? 0) }
    var done: Bool { lastActive.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false }
    func label(_ key: String) -> String {
        snapshot[key] as? String ?? NSLocalizedString(key == "nameLabel" ? "streak_widget_name" : key, comment: "Home screen widget")
    }
    var status: String { label(done ? "doneLabel" : current > 0 ? "continueLabel" : "startLabel") }
}

struct StreakProvider: TimelineProvider {
    func placeholder(in context: Context) -> StreakEntry {
        StreakEntry(date: Date(), snapshot: ["current": 7, "longest": 21,
            "lastActiveDate": ISO8601DateFormatter().string(from: Date()).prefix(10).description])
    }

    private func read() -> [String: Any] {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: widgetGroup)?
                .appendingPathComponent("streak.json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return json
    }

    func getSnapshot(in context: Context, completion: @escaping (StreakEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : StreakEntry(date: Date(), snapshot: read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StreakEntry>) -> Void) {
        let now = Date()
        let snapshot = read()
        let calendar = Calendar.autoupdatingCurrent
        let midnight = calendar.startOfDay(for: now)
        // Include the grace day and expiry even if the app stays closed.
        let entries = [StreakEntry(date: now, snapshot: snapshot)] + (1...3).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: midnight).map {
                StreakEntry(date: $0, snapshot: snapshot)
            }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct StreakWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StreakEntry
    private let orange = Color.orange

    private var count: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("🔥").font(.system(size: family == .systemLarge ? 54 : 34))
                .opacity(entry.current > 0 ? 1 : 0.4).accessibilityHidden(true)
            Text(entry.current, format: .number)
                .font(.system(size: family == .systemLarge ? 72 : 44, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.4).lineLimit(1)
        }
    }

    private var record: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("🏆 \(entry.best)")
                .font(.system(size: family == .systemSmall ? 19 : 30, weight: .semibold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.4)
            Text(entry.label("bestLabel")).font(.caption).foregroundStyle(.secondary)
                .lineLimit(2).minimumScaleFactor(0.7)
        }.accessibilityElement(children: .combine)
    }

    var body: some View {
        Group {
            if family == .systemSmall {
                VStack(alignment: .leading, spacing: 4) {
                    count
                    Text(entry.label("currentLabel")).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2).minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    record
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if family == .systemLarge {
                        Text(entry.label("nameLabel"))
                            .font(.headline).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            count
                            Text(entry.label("currentLabel")).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(2).minimumScaleFactor(0.7)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        record.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if family == .systemLarge { Spacer(minLength: 0) }
                    Label(entry.status, systemImage: entry.done ? "checkmark.circle.fill" : "sparkles")
                        .font(.caption).foregroundStyle(orange).lineLimit(2).minimumScaleFactor(0.7)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(2)
        .streakBackground()
    }
}

private extension View {
    @ViewBuilder func streakBackground() -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(for: .widget) {
                Color(uiColor: .secondarySystemBackground)
                Color.orange.opacity(0.06)
            }
        } else {
            self.padding(14).background(Color(uiColor: .secondarySystemBackground))
        }
    }
}

@main
struct StudyStreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: widgetKind, provider: StreakProvider()) { entry in
            StreakWidgetView(entry: entry)
        }
        .configurationDisplayName(NSLocalizedString("streak_widget_name", comment: "Widget name"))
        .description(NSLocalizedString("streak_widget_description", comment: "Widget description"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
