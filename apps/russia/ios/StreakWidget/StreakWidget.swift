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
    @ViewBuilder func background(done: Bool) -> some View {
        if done {
            StreakWidgetPalette.activeBackground
        } else {
            switch self {
            case .flame:
                ZStack {
                    Color(uiColor: .secondarySystemBackground)
                    Color.orange.opacity(0.06)
                }
            case .minimal:
                Color(uiColor: .systemBackground)
            case .record:
                Color(widgetRGB: 0x14243D)
            }
        }
    }
}

private extension Color {
    init(widgetRGB rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 255) / 255,
                  green: Double((rgb >> 8) & 255) / 255,
                  blue: Double(rgb & 255) / 255)
    }
}

struct StreakWidgetPalette {
    // AppColors.gold, also used by the full-screen streak celebration.
    static let activeBackground = Color(widgetRGB: 0xFFA53C)
    let ink: Color
    let secondaryInk: Color
    let accent: Color
    let icon: Color
    let separator: Color
    let track: Color

    init(style: StreakWidgetStyle, done: Bool) {
        if done {
            let primary = Color(widgetRGB: 0x3E250D)
            let secondary = Color(widgetRGB: 0x573516)
            ink = primary
            secondaryInk = secondary
            accent = primary
            icon = .white
            separator = secondary.opacity(0.3)
            track = secondary.opacity(0.3)
        } else {
            ink = style == .record ? .white : .primary
            secondaryInk = style == .record ? .white.opacity(0.72) : .secondary
            accent = style == .record ? Color(widgetRGB: 0xFFBA6B) : .orange
            icon = accent
            separator = style == .record ? .white.opacity(0.2) : Color.secondary.opacity(0.25)
            track = style == .record ? .white.opacity(0.15) : Color.secondary.opacity(0.15)
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
    private var palette: StreakWidgetPalette { StreakWidgetPalette(style: style, done: entry.done) }
    private var small: Bool { family == .systemSmall }
    private var large: Bool { family == .systemLarge }

    private var count: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "flame.fill")
                .resizable().scaledToFit()
                .frame(width: large ? 42 : 28, height: large ? 52 : 34)
                .foregroundStyle(palette.icon)
                .opacity(entry.current > 0 ? 1 : 0.4).accessibilityHidden(true)
            Text(entry.current, format: .number)
                .font(.system(size: large ? 64 : 40, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.4).lineLimit(1)
        }
    }

    private var metric: some View {
        VStack(alignment: style == .minimal ? .center : .leading, spacing: 4) {
            count
            Text(entry.label("currentLabel")).font(.caption).foregroundStyle(palette.secondaryInk)
                .lineLimit(2).minimumScaleFactor(0.7)
        }.accessibilityElement(children: .combine)
    }

    private var bestCount: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "trophy.fill")
                .font(.system(size: small ? 17 : 24))
                .foregroundStyle(palette.icon).accessibilityHidden(true)
            Text(entry.best, format: .number)
                .font(.system(size: small ? 19 : 30, weight: .semibold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.4)
        }
    }

    private var record: some View {
        VStack(alignment: style == .minimal ? .center : .leading, spacing: 4) {
            bestCount
            Text(entry.label("bestLabel")).font(.caption).foregroundStyle(palette.secondaryInk)
                .lineLimit(2).minimumScaleFactor(0.7)
        }.accessibilityElement(children: .combine)
    }

    private var status: some View {
        Label(entry.status, systemImage: entry.done ? "checkmark.circle.fill" : "sparkles")
            .font(.caption).foregroundStyle(palette.accent).lineLimit(2).minimumScaleFactor(0.7)
    }

    private var heading: some View {
        Text(entry.label("nameLabel")).font(.headline).foregroundStyle(palette.secondaryInk)
            .lineLimit(2).minimumScaleFactor(0.7)
    }

    private var progress: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.track)
                Capsule().fill(palette.accent).frame(width: geometry.size.width * entry.progress)
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
                Divider().overlay(palette.separator)
                record
            } else {
                HStack(spacing: 20) {
                    metric.frame(maxWidth: .infinity)
                    Divider().frame(height: 56).overlay(palette.separator)
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
                    bestCount
                    Text(entry.label("bestLabel")).font(.caption).foregroundStyle(palette.secondaryInk)
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
        .foregroundStyle(palette.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(2)
        .streakBackground(style: style, done: entry.done)
    }
}

private extension View {
    @ViewBuilder func streakBackground(style: StreakWidgetStyle, done: Bool) -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(for: .widget) { style.background(done: done) }
        } else {
            self.padding(14).background { style.background(done: done) }
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
