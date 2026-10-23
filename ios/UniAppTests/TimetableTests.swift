import XCTest
@testable import UniApp

final class TimetableTests: XCTestCase {
    private let json = """
    {"scheduleId":491,"status":"ok","url":"https://x/a.pdf","weekOne":"2026-09-14","groups":["37а","37б","38а","38б"],
     "lessons":[
      {"day":0,"start":"7:30","end":"10:15","groups":["37а","37б"],"subject":"САА","kind":"lab","room":"714","week":"odd","text":"САА лб 714","notes":[]},
      {"day":0,"start":"7:30","end":"10:15","groups":["38а","38б"],"subject":"САА","kind":"lab","room":"714","week":"even","text":"САА лб 714","notes":[]},
      {"day":0,"start":"10:30","end":"13:15","groups":["37а","37б","38а","38б"],"subject":"МС","kind":"lecture","room":"1154","week":null,"text":"МС л 1154","notes":[]},
      {"day":0,"start":"13:45","end":"16:30","groups":["37а"],"subject":"ППЕ","kind":"lab","room":"1437","week":null,"text":"ППЕ лб 1437","notes":[]},
      {"day":0,"start":"13:45","end":"16:30","groups":["37б"],"subject":"ППЕ","kind":"lab","room":"1438","week":null,"text":"ППЕ лб 1438","notes":[]},
      {"day":2,"start":"7:30","end":"10:15","groups":[],"subject":"ППЕ","kind":"strange","room":null,"week":null,"text":"ППЕ","notes":["от 2 седмица"]}
     ]}
    """

    private func timetable() throws -> Timetable {
        try APIClient.decoder.decode(Timetable.self, from: Data(json.utf8))
    }

    private func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Sofia")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: value)!
    }

    func testDecodesUnknownKindsWithoutFailing() throws {
        let timetable = try timetable()
        XCTAssertEqual(timetable.lessons.count, 6)
        XCTAssertEqual(timetable.lessons[0].week, .odd)
        XCTAssertEqual(timetable.lessons[0].lessonKind, .lab)
        XCTAssertNil(timetable.lessons[5].lessonKind)
    }

    func testStudentGroupNeedsSubgroupWhenTimetableSplitsIt() throws {
        let timetable = try timetable()
        var student = Student(name: "Иван", facultyNo: "1", details: [:])
        student.group = "37"
        let group = TimetablePlanner.defaultGroup(for: student, in: timetable)
        XCTAssertEqual(group, "37")
        let planner = TimetablePlanner(timetable: timetable, group: group)
        XCTAssertTrue(planner.needsSubgroup)
        XCTAssertEqual(planner.subgroups, ["37а", "37б"])
    }

    func testSubgroupFiltersLabsButKeepsStreamLectures() throws {
        let planner = TimetablePlanner(timetable: try timetable(), group: "37б")
        let monday = planner.lessons(day: 0, parity: .odd)
        XCTAssertEqual(monday.map(\.subject), ["САА", "МС", "ППЕ"])
        XCTAssertEqual(monday.last?.room, "1438")
        XCTAssertEqual(planner.lessons(day: 0, parity: .even).map(\.subject), ["МС", "ППЕ"])
        XCTAssertEqual(planner.lessons(day: 2, parity: .even).count, 1)
    }

    func testWeekParityCountsFromWeekOne() throws {
        let planner = TimetablePlanner(timetable: try timetable(), group: "37а")
        XCTAssertEqual(planner.parity(on: date("2026-09-14 09:00")), .odd)
        XCTAssertEqual(planner.parity(on: date("2026-09-20 22:00")), .odd)
        XCTAssertEqual(planner.parity(on: date("2026-09-21 08:00")), .even)
        XCTAssertEqual(planner.weekNumber(on: date("2026-10-23 12:00")), 6)
        var flipped = planner
        flipped.parityFlipped = true
        XCTAssertEqual(flipped.parity(on: date("2026-09-14 09:00")), .even)
    }

    func testMomentFindsCurrentAndNextLesson() throws {
        let planner = TimetablePlanner(timetable: try timetable(), group: "37а")
        let during = planner.moment(at: date("2026-09-14 11:00"))
        XCTAssertEqual(during.current?.subject, "МС")
        XCTAssertEqual(during.next?.subject, "ППЕ")
        let evening = planner.moment(at: date("2026-09-14 20:00"))
        XCTAssertNil(evening.current)
        XCTAssertEqual(evening.next?.day, 2)
    }
}
