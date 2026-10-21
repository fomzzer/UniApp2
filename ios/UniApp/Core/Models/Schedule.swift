import Foundation

enum ScheduleKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case lectures
    case exams

    var id: String { rawValue }
}

struct ScheduleItem: Codable, Hashable, Sendable, Identifiable {
    var id: Int
    var kind: ScheduleKind
    var academicYear: String?
    var semester: String?
    var degree: String
    var faculty: String
    var facultySlug: String
    var major: String
    var majorSlug: String
    var year: Int?
    var stream: String?
    var url: URL
    var isPdf: Bool

    var webURL: URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http", url.host() != nil else { return nil }
        return url
    }
}

struct ScheduleList: Codable, Sendable {
    var updatedAt: Date?
    var items: [ScheduleItem]
}

struct ScheduleSelection: Codable, Hashable, Sendable {
    var degree: String
    var facultySlug: String
    var majorSlug: String
    var year: Int?
    var stream: String?

    init(degree: String, facultySlug: String, majorSlug: String, year: Int?, stream: String?) {
        self.degree = degree
        self.facultySlug = facultySlug
        self.majorSlug = majorSlug
        self.year = year
        self.stream = stream
    }

    init(item: ScheduleItem) {
        self.init(degree: item.degree, facultySlug: item.facultySlug, majorSlug: item.majorSlug, year: item.year, stream: item.stream)
    }

    func matches(_ item: ScheduleItem) -> Bool {
        item.degree == degree
            && item.facultySlug == facultySlug
            && item.majorSlug == majorSlug
            && (year == nil || item.year == year)
            && (stream == nil || item.stream == stream)
    }
}
