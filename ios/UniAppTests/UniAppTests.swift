import XCTest
@testable import UniApp

final class ContractTests: XCTestCase {
    func testSnapshotDecodesFromBackendContract() throws {
        let snapshot = try APIClient.decoder.decode(Snapshot.self, from: Data(Fixtures.snapshot.utf8))
        XCTAssertEqual(snapshot.student.facultyNo, "121221089")
        XCTAssertEqual(snapshot.student.course, 2)
        XCTAssertEqual(snapshot.student.firstName, "Иван")
        XCTAssertEqual(snapshot.student.initials, "ИИ")
        XCTAssertEqual(snapshot.loginMethod, .egn)
        XCTAssertEqual(snapshot.grades.gpa, 5.0)
        XCTAssertEqual(snapshot.grades.semesters.first?.number, 2)
        XCTAssertEqual(snapshot.grades.trend.map(\.number), [1, 2])
        XCTAssertTrue(snapshot.dormitory.accommodated)
    }

    func testSnapshotRoundTripsThroughCache() throws {
        let snapshot = try APIClient.decoder.decode(Snapshot.self, from: Data(Fixtures.snapshot.utf8))
        let data = try APIClient.encoder.encode(snapshot)
        let decoded = try APIClient.decoder.decode(Snapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }

    func testSchedulesDecode() throws {
        let list = try APIClient.decoder.decode(ScheduleList.self, from: Data(Fixtures.schedules.utf8))
        XCTAssertEqual(list.items.count, 2)
        XCTAssertTrue(list.items[0].isPdf)
        XCTAssertEqual(list.items[0].year, 1)
        XCTAssertNotNil(list.updatedAt)
    }
}

final class ScheduleMatcherTests: XCTestCase {
    private func item(id: Int, faculty: String, major: String, year: Int?, stream: String?) -> ScheduleItem {
        ScheduleItem(
            id: id, kind: .lectures, academicYear: "2026/2027", semester: "winter", degree: "bachelor",
            faculty: faculty, facultySlug: "f\(faculty.count)", major: major, majorSlug: "m\(major.count)",
            year: year, stream: stream, url: URL(string: "https://example.com/\(id).pdf")!, isPdf: true
        )
    }

    private func student(faculty: String, specialty: String, course: Int?, stream: String?) -> Student {
        Student(
            name: "Иван Иванов", facultyNo: "1", faculty: faculty, specialty: specialty, degree: nil,
            educationForm: nil, semester: nil, course: course, group: nil, stream: stream, email: nil, ean: nil, details: [:]
        )
    }

    func testNormalizationIgnoresQuotesAndCase() {
        XCTAssertEqual(
            ScheduleMatcher.normalize("Факултет „Компютърни системи и технологии“"),
            ScheduleMatcher.normalize("факултет компютърни СИСТЕМИ и технологии")
        )
    }

    func testAcronym() {
        XCTAssertEqual(ScheduleMatcher.acronym("Компютърни системи и технологии"), "КСТ")
    }

    func testBestMatchUsesStream() {
        let items = [
            item(id: 1, faculty: "Факултет „Компютърни системи и технологии“", major: "Компютърно и софтуерно инженерство", year: 2, stream: "7"),
            item(id: 2, faculty: "Факултет „Компютърни системи и технологии“", major: "Компютърно и софтуерно инженерство", year: 2, stream: "8"),
            item(id: 3, faculty: "Факултет „Компютърни системи и технологии“", major: "Компютърно и софтуерно инженерство", year: 3, stream: "8"),
        ]
        let me = student(faculty: "Факултет Компютърни системи и технологии", specialty: "Компютърно и софтуерно инженерство", course: 2, stream: "8")
        XCTAssertEqual(ScheduleMatcher.bestMatch(for: me, in: items)?.id, 2)
    }

    func testNoMatchForOtherSpecialty() {
        let items = [item(id: 1, faculty: "Факултет по транспорта", major: "Логистика", year: 1, stream: "1")]
        let me = student(faculty: "Факултет Компютърни системи и технологии", specialty: "Компютърно и софтуерно инженерство", course: 1, stream: "1")
        XCTAssertNil(ScheduleMatcher.bestMatch(for: me, in: items))
    }

    func testSelectionMatching() {
        let target = item(id: 5, faculty: "A", major: "B", year: 2, stream: "3")
        XCTAssertTrue(ScheduleSelection(item: target).matches(target))
        var other = target
        other.stream = "4"
        XCTAssertFalse(ScheduleSelection(item: target).matches(other))
    }
}

final class StringsTests: XCTestCase {
    func testServerErrorsAreLocalized() {
        let bg = Strings(language: .bg)
        let ru = Strings(language: .ru)
        let error = APIError.server(code: "invalid_credentials", message: nil)
        XCTAssertNotEqual(bg.message(for: error), ru.message(for: error))
        XCTAssertFalse(bg.message(for: APIError.offline).isEmpty)
    }

    func testGradeColorsFollowScale() {
        let excellent: Int? = 6
        let fail: Int? = 2
        XCTAssertEqual(Theme.gradeColor(excellent), Theme.gradeExcellent)
        XCTAssertEqual(Theme.gradeColor(fail), Theme.gradeFail)
    }
}
