import Foundation

enum LessonKind: String, Codable, Sendable {
    case lecture
    case lab
    case seminar
}

enum WeekParity: String, Codable, Sendable, CaseIterable, Identifiable {
    case odd
    case even

    var id: String { rawValue }

    var other: WeekParity { self == .odd ? .even : .odd }
}

struct TimetableLesson: Codable, Hashable, Sendable, Identifiable {
    var day: Int
    var start: String
    var end: String
    var groups: [String]
    var subject: String
    var kind: String?
    var room: String?
    var week: WeekParity?
    var text: String
    var notes: [String]

    var id: String {
        "\(day)-\(start)-\(end)-\(groups.joined(separator: ","))-\(week?.rawValue ?? "")-\(subject)-\(room ?? "")"
    }

    var lessonKind: LessonKind? {
        kind.flatMap(LessonKind.init(rawValue:))
    }

    var startMinutes: Int { Self.minutes(start) }
    var endMinutes: Int { Self.minutes(end) }

    static func minutes(_ value: String) -> Int {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return 0 }
        return parts[0] * 60 + parts[1]
    }
}

struct Timetable: Codable, Hashable, Sendable {
    enum Status: String, Codable, Sendable {
        case ok
        case unsupported
    }

    var scheduleId: Int
    var status: Status
    var url: String
    var weekOne: String?
    var groups: [String]
    var lessons: [TimetableLesson]
}
