import SwiftUI
import WidgetKit

private let widgetGroup = "group.ru.pdd.pddApp.streak"

// Date keys are the app's Gregorian calendar days in the device's time zone.
private func dayKeyFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = .autoupdatingCurrent
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}

private struct ActivityDay: Identifiable {
    let id: String
    let weekday: String
    let spokenDate: String
    let active: Bool
    let today: Bool
}

struct StreakEntry: TimelineEntry {
    let date: Date
    let snapshot: [String: Any]

    private var lastActive: Date? {
        guard let value = snapshot["lastActiveDate"] as? String else { return nil }
        return dayKeyFormatter().date(from: value)
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
        snapshot[key] as? String ?? NSLocalizedString(key, comment: "Home screen widget")
    }

    fileprivate var week: [ActivityDay] {
        let calendar = Calendar.autoupdatingCurrent
        let keys = dayKeyFormatter()
        // Already installed widgets can still have the old snapshot until the next app launch.
        var active = Set(snapshot["activeDates"] as? [String] ?? [])
        if let last = snapshot["lastActiveDate"] as? String { active.insert(last) }
        let formatter = DateFormatter()
        formatter.locale = (snapshot["locale"] as? String).map { Locale(identifier: $0) } ?? .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "EEE"
        let spoken = DateFormatter()
        spoken.locale = formatter.locale
        spoken.dateStyle = .full

        return (-6...0).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: date) else { return nil }
            let key = keys.string(from: day)
            return ActivityDay(id: key, weekday: formatter.string(from: day), spokenDate: spoken.string(from: day),
                               active: active.contains(key), today: offset == 0)
        }
    }
}

struct StreakProvider: TimelineProvider {
    func placeholder(in context: Context) -> StreakEntry {
        let date = Date()
        let keys = dayKeyFormatter()
        let days = [-6, -4, -2, -1, 0].compactMap { offset in
            Calendar.current.date(byAdding: .day, value: offset, to: date).map { keys.string(from: $0) }
        }
        return StreakEntry(date: date, snapshot: ["current": 3, "longest": 12,
                           "lastActiveDate": keys.string(from: date), "activeDates": days])
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
        let entries = [StreakEntry(date: now, snapshot: snapshot)] + (1...7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: midnight).map {
                StreakEntry(date: $0, snapshot: snapshot)
            }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// Static outline of the in-game BurningFlame, including its cut-out tongue.
private struct CelebrationFlame: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        func curve(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ x: CGFloat, _ y: CGFloat) {
            path.addCurve(to: point(x, y), control1: point(x1, y1), control2: point(x2, y2))
        }
        path.move(to: point(50, 112))
        curve(26,112,14,95,14,77)
        curve(14,64,20,54,26,47)
        curve(26,60,31,67,37,68)
        curve(30,45,43,25,60,9)
        curve(56,32,70,38,76,52)
        curve(79,46,79,42,78,37)
        curve(90,53,94,66,92,80)
        curve(90,100,73,112,50,112)
        path.closeSubpath()
        path.move(to: point(51,104))
        curve(35,104,32,91,36,82)
        curve(38,75,43,69,48,61)
        curve(47,73,55,77,57,82)
        curve(58,78,59,76,59,74)
        curve(66,83,70,92,63,100)
        curve(60,103,56,104,51,104)
        path.closeSubpath()
        let scale = min(rect.width / 80, rect.height / 104)
        return path.applying(CGAffineTransform(translationX: rect.midX - 53 * scale,
                                               y: rect.midY - 60.5 * scale).scaledBy(x: scale, y: scale))
    }
}

private struct CelebrationBackground: View {
    let center: UnitPoint

    var body: some View {
        GeometryReader { bounds in
            let radius = max(bounds.size.width, bounds.size.height) * 0.85
            ZStack {
                Color(red: 1, green: 165 / 255, blue: 60 / 255)
                AngularGradient(stops: (0...48).map { index in
                    Gradient.Stop(color: .white.opacity(index % 4 == 1 ? 0.36 : 0),
                                  location: Double(index) / 48)
                }, center: center)
                .mask(RadialGradient(colors: [.white, .clear], center: center,
                                     startRadius: 0, endRadius: radius))
            }
        }
    }
}

struct StreakWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StreakEntry

    private var small: Bool { family == .systemSmall }
    private var large: Bool { family == .systemLarge }
    private var center: UnitPoint {
        UnitPoint(x: small || large ? 0.5 : 0.42, y: small ? 0.43 : large ? 0.38 : 0.34)
    }

    private func flame(height: CGFloat) -> some View {
        CelebrationFlame().fill(.white, style: FillStyle(eoFill: true))
            .frame(width: height * 0.78, height: height)
    }

    private var number: some View {
        Text(entry.current, format: .number)
            .font(.system(size: large ? 76 : small ? 40 : 52, weight: .heavy, design: .rounded))
            .minimumScaleFactor(0.35).lineLimit(1)
    }

    private var streak: some View {
        Group {
            if small || large {
                VStack(spacing: 2) {
                    flame(height: large ? 92 : 48).opacity(entry.done ? 1 : 0.74)
                    number
                }
            } else {
                HStack(spacing: 9) { flame(height: 46); number }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(entry.label("currentLabel")))
        .accessibilityValue(Text("\(entry.current). \(entry.label(entry.done ? "doneLabel" : entry.current > 0 ? "continueLabel" : "startLabel"))"))
    }

    private var best: some View {
        HStack(spacing: 4) {
            if #available(iOS 16.0, *) { Image(systemName: "trophy.fill") }
            else { Image(systemName: "rosette") }
            Text(entry.best, format: .number).lineLimit(1).minimumScaleFactor(0.6)
        }
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .padding(.vertical, 4).padding(.horizontal, 7)
        .background(Capsule().fill(Color.black.opacity(0.12)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(entry.label("bestLabel")))
        .accessibilityValue(Text(entry.best, format: .number))
    }

    private var week: some View {
        HStack(spacing: 0) {
            ForEach(entry.week) { day in
                VStack(spacing: 3) {
                    Text(day.weekday)
                        .font(.system(size: large ? 13 : 11, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    ZStack {
                        if day.active { flame(height: large ? 22 : 15) }
                        else { Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1.3).frame(width: 8, height: 8) }
                    }.frame(height: large ? 22 : 15)
                    Capsule().fill(.white).frame(width: 10, height: 2).opacity(day.today ? 1 : 0)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(day.spokenDate))
                .accessibilityAddTraits(day.active ? .isSelected : [])
            }
        }
        .padding(.vertical, large ? 10 : 5)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.12)))
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack { Spacer(minLength: 0); best }
            streak.frame(maxWidth: .infinity, maxHeight: .infinity)
            if !small { week }
        }
        .overlay(alignment: .bottomLeading) {
            if small && entry.done {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(.white)
        .padding(small ? 10 : large ? 16 : 10)
        .modifier(WidgetBackdrop(center: center))
    }
}

private struct WidgetBackdrop: ViewModifier {
    let center: UnitPoint

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) { CelebrationBackground(center: center) }
        } else {
            content.background(CelebrationBackground(center: center))
        }
    }
}

@main
struct StudyStreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PddStudyStreak", provider: StreakProvider()) { entry in
            StreakWidgetView(entry: entry)
        }
        .configurationDisplayName(NSLocalizedString("streak_widget_flame_name", comment: "Widget name"))
        .description(NSLocalizedString("streak_widget_flame_description", comment: "Widget description"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
