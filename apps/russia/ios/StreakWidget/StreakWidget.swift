import SwiftUI
import WidgetKit

private let widgetGroup = "group.ru.pdd.pddApp.streak"
enum StreakWidgetStyle: String {
    // Preserve the original kind for already placed widgets.
    case flame = "PddStudyStreak"
    case minimal = "PddStudyStreakMinimal"
    case record = "PddStudyStreakRecord"

    var resourceName: String {
        switch self {
        case .flame: return "flame"
        case .minimal: return "minimal"
        case .record: return "record"
        }
    }
    var ink: Color { self == .record ? .white : .primary }
    var secondaryInk: Color { self == .record ? .white.opacity(0.72) : .secondary }
    var accent: Color { self == .record ? Color(red: 1, green: 0.73, blue: 0.42) : .orange }

    @ViewBuilder var background: some View {
        switch self {
        case .flame:
            ZStack {
                Color(uiColor: .secondarySystemBackground)
                Color.orange.opacity(0.06)
            }
        case .minimal:
            Color(uiColor: .systemBackground)
        case .record:
            Color(red: 0.08, green: 0.14, blue: 0.24)
        }
    }
}

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
    var progress: Double { best > 0 ? min(1, max(0, Double(current) / Double(best))) : 0 }
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
    let style: StreakWidgetStyle
    private var small: Bool { family == .systemSmall }
    private var large: Bool { family == .systemLarge }

    private var count: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("🔥").font(.system(size: large ? 48 : style == .minimal ? 26 : 32))
                .opacity(entry.current > 0 ? 1 : 0.4).accessibilityHidden(true)
            Text(entry.current, format: .number)
                .font(.system(size: large ? 64 : 40, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.4).lineLimit(1)
        }
    }

    private var metric: some View {
        VStack(alignment: style == .minimal ? .center : .leading, spacing: 4) {
            count
            Text(entry.label("currentLabel")).font(.caption).foregroundStyle(style.secondaryInk)
                .lineLimit(2).minimumScaleFactor(0.7)
        }.accessibilityElement(children: .combine)
    }

    private var record: some View {
        VStack(alignment: style == .minimal ? .center : .leading, spacing: 4) {
            Text("🏆 \(entry.best)")
                .font(.system(size: small ? 19 : 30, weight: .semibold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.4)
            Text(entry.label("bestLabel")).font(.caption).foregroundStyle(style.secondaryInk)
                .lineLimit(2).minimumScaleFactor(0.7)
        }.accessibilityElement(children: .combine)
    }

    private var status: some View {
        Label(entry.status, systemImage: entry.done ? "checkmark.circle.fill" : "sparkles")
            .font(.caption).foregroundStyle(style.accent).lineLimit(2).minimumScaleFactor(0.7)
    }

    private var heading: some View {
        Text(entry.label("nameLabel")).font(.headline).foregroundStyle(style.secondaryInk)
            .lineLimit(2).minimumScaleFactor(0.7)
    }

    private var progress: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule().fill(style.accent).frame(width: geometry.size.width * entry.progress)
            }
        }.frame(height: large ? 8 : 5)
            .accessibilityElement()
            .accessibilityLabel(Text(entry.label("bestLabel")))
            .accessibilityValue(Text(entry.progress, format: .percent.precision(.fractionLength(0))))
    }

    @ViewBuilder private var flameLayout: some View {
        if small {
            VStack(alignment: .leading, spacing: 4) {
                metric
                Spacer(minLength: 4)
                record
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if large { heading; Spacer(minLength: 0) }
                HStack(spacing: 20) {
                    metric.frame(maxWidth: .infinity, alignment: .leading)
                    record.frame(maxWidth: .infinity, alignment: .leading)
                }
                if large { Spacer(minLength: 0) }
                status
            }
        }
    }

    @ViewBuilder private var minimalLayout: some View {
        VStack(spacing: small ? 6 : 12) {
            if large { heading }
            Spacer(minLength: 0)
            if small {
                metric
                Divider()
                record
            } else {
                HStack(spacing: 20) {
                    metric.frame(maxWidth: .infinity)
                    Divider().frame(height: 56)
                    record.frame(maxWidth: .infinity)
                }
            }
            Spacer(minLength: 0)
            if !small { status }
        }
    }

    @ViewBuilder private var recordLayout: some View {
        VStack(alignment: .leading, spacing: small ? 6 : 12) {
            if large { heading; Spacer(minLength: 0) }
            if small {
                metric
                Spacer(minLength: 0)
                progress
                HStack(spacing: 8) {
                    Text("🏆 \(entry.best)").font(.system(size: 18, weight: .semibold, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.4)
                    Text(entry.label("bestLabel")).font(.caption).foregroundStyle(style.secondaryInk)
                        .lineLimit(2).minimumScaleFactor(0.7)
                }.accessibilityElement(children: .combine)
            } else {
                HStack(spacing: 20) {
                    metric.frame(maxWidth: .infinity, alignment: .leading)
                    record.frame(maxWidth: .infinity, alignment: .leading)
                }
                progress
                if large { Spacer(minLength: 0) }
                status
            }
        }
    }

    var body: some View {
        Group {
            switch style {
            case .flame: flameLayout
            case .minimal: minimalLayout
            case .record: recordLayout
            }
        }
        .foregroundStyle(style.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(2)
        .streakBackground(style: style)
    }
}

private extension View {
    @ViewBuilder func streakBackground(style: StreakWidgetStyle) -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(for: .widget) { style.background }
        } else {
            self.padding(14).background { style.background }
        }
    }
}

struct StudyStreakWidget: Widget {
    let style: StreakWidgetStyle

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: style.rawValue, provider: StreakProvider()) { entry in
            StreakWidgetView(entry: entry, style: style)
        }
        .configurationDisplayName(NSLocalizedString("streak_widget_\(style.resourceName)_name", comment: "Widget name"))
        .description(NSLocalizedString("streak_widget_\(style.resourceName)_description", comment: "Widget description"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct StudyStreakWidgets: WidgetBundle {
    var body: some Widget {
        StudyStreakWidget(style: .flame)
        StudyStreakWidget(style: .minimal)
        StudyStreakWidget(style: .record)
    }
}
