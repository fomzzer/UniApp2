import Foundation

enum LoginMethod: String, Codable, Sendable, Hashable {
    case egn
    case otp
    case password
}

struct Snapshot: Codable, Hashable, Sendable {
    var student: Student
    var grades: Grades
    var dormitory: Dormitory
    var loginMethod: LoginMethod?
    var fetchedAt: Date
}

struct Student: Codable, Hashable, Sendable {
    var name: String
    var facultyNo: String
    var faculty: String?
    var specialty: String?
    var degree: String?
    var educationForm: String?
    var semester: Int?
    var course: Int?
    var group: String?
    var stream: String?
    var email: String?
    var ean: String?
    var details: [String: String]

    var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    var initials: String {
        let parts = name.split(separator: " ")
        let letters = [parts.first, parts.count > 1 ? parts.last : nil].compactMap { $0?.first }
        return letters.isEmpty ? "U" : String(letters).uppercased()
    }

    var isMaster: Bool {
        (degree ?? "").lowercased().contains("магист")
    }
}

struct Grades: Codable, Hashable, Sendable {
    var gpa: Double?
    var gradedCount: Int
    var creditedCount: Int
    var distribution: [String: Int]
    var semesters: [Semester]

    var latestSemester: Semester? {
        semesters.first { !$0.subjects.isEmpty }
    }

    var trend: [Semester] {
        semesters.filter { $0.number != nil && $0.average != nil }.sorted { ($0.number ?? 0) < ($1.number ?? 0) }
    }
}

struct Semester: Codable, Hashable, Sendable, Identifiable {
    var number: Int?
    var title: String
    var average: Double?
    var subjects: [Subject]

    var id: String { title }
}

struct Subject: Codable, Hashable, Sendable, Identifiable {
    var name: String
    var control: String?
    var grade: Int?
    var label: String?
    var credited: Bool
    var attempts: [Attempt]

    var id: String { name + "|" + (control ?? "") }

    var hadRetake: Bool {
        attempts.contains { $0.kind == .retake }
    }
}

struct Attempt: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case regular
        case retake
    }

    var kind: Kind
    var grade: Int
    var label: String
}

struct Dormitory: Codable, Hashable, Sendable {
    var status: String?
    var accommodated: Bool
}
