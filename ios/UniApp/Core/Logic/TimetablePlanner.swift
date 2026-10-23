import Foundation

struct TimetablePlanner: Sendable {
    let timetable: Timetable
    var group: String?
    var parityFlipped = false
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(identifier: "Europe/Sofia") ?? .current
        return calendar
    }()

    static func base(_ group: String?) -> String? {
        guard let group else { return nil }
        let digits = group.prefix { $0.isNumber }
        return digits.isEmpty ? nil : String(digits)
    }

    static func defaultGroup(for student: Student?, in timetable: Timetable) -> String? {
        guard let base = base(student?.group) else { return nil }
        let matches = timetable.groups.filter { Self.base($0) == base }
        if matches.count == 1 { return matches[0] }
        return matches.isEmpty ? nil : base
    }

    var subgroups: [String] {
        guard let base = Self.base(group) else { return [] }
        return timetable.groups.filter { Self.base($0) == base && $0 != base }
    }

    var needsSubgroup: Bool {
        guard let group else { return false }
        return Self.base(group) == group && !subgroups.isEmpty
    }

    func includes(_ lesson: TimetableLesson) -> Bool {
        guard let group, !lesson.groups.isEmpty else { return true }
        guard let base = Self.base(group) else { return lesson.groups.contains(group) }
        if group == base {
            return lesson.groups.contains { Self.base($0) == base }
        }
        return lesson.groups.contains(group) || lesson.groups.contains(base)
    }

    func dayIndex(_ date: Date) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }

    func parity(on date: Date) -> WeekParity {
        let start = weekOneDate ?? date
        let first = calendar.dateInterval(of: .weekOfYear, for: start)?.start ?? start
        let current = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        let days = calendar.dateComponents([.day], from: first, to: current).day ?? 0
        let weeks = Int((Double(days) / 7).rounded(.down))
        let parity: WeekParity = weeks.isMultiple(of: 2) ? .odd : .even
        return parityFlipped ? parity.other : parity
    }

    func weekNumber(on date: Date) -> Int? {
        guard let start = weekOneDate else { return nil }
        let first = calendar.dateInterval(of: .weekOfYear, for: start)?.start ?? start
        let current = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        let days = calendar.dateComponents([.day], from: first, to: current).day ?? 0
        return Int((Double(days) / 7).rounded(.down)) + 1
    }

    private var weekOneDate: Date? {
        guard let weekOne = timetable.weekOne else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: weekOne)
    }

    func lessons(day: Int, parity: WeekParity) -> [TimetableLesson] {
        timetable.lessons
            .filter { $0.day == day && ($0.week == nil || $0.week == parity) && includes($0) }
            .sorted { ($0.startMinutes, $0.endMinutes, $0.groups.first ?? "") < ($1.startMinutes, $1.endMinutes, $1.groups.first ?? "") }
    }

    var days: [Int] {
        let used = Set(timetable.lessons.filter(includes).map(\.day))
        return Array(0...(used.contains(5) || used.contains(6) ? max(used.max() ?? 4, 5) : 4))
    }

    struct Moment: Sendable, Equatable {
        var current: TimetableLesson?
        var next: TimetableLesson?
        var nextDate: Date?
    }

    func moment(at date: Date) -> Moment {
        let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let today = lessons(day: dayIndex(date), parity: parity(on: date))
        let current = today.first { $0.startMinutes <= minutes && minutes < $0.endMinutes }
        if let next = today.first(where: { $0.startMinutes > minutes }) {
            return Moment(current: current, next: next, nextDate: date)
        }
        for offset in 1...14 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)) else { continue }
            if let first = lessons(day: dayIndex(day), parity: parity(on: day)).first {
                return Moment(current: current, next: first, nextDate: day)
            }
        }
        return Moment(current: current, next: nil, nextDate: nil)
    }

    func date(_ day: Date, at minutes: Int) -> Date {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day) ?? day
    }
}
