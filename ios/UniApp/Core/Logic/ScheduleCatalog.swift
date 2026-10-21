import Foundation

struct ScheduleFilter: Hashable, Sendable {
    var degree: String
    var facultySlug: String?
    var majorSlug: String?
    var year: Int?
    var stream: String?

    init(degree: String = "bachelor", facultySlug: String? = nil, majorSlug: String? = nil, year: Int? = nil, stream: String? = nil) {
        self.degree = degree
        self.facultySlug = facultySlug
        self.majorSlug = majorSlug
        self.year = year
        self.stream = stream
    }

    init(item: ScheduleItem) {
        self.init(degree: item.degree, facultySlug: item.facultySlug, majorSlug: item.majorSlug, year: item.year, stream: item.stream)
    }

    var hasMajor: Bool { majorSlug != nil }
}

struct ScheduleOption: Hashable, Identifiable, Sendable {
    let id: String
    let title: String

    var short: String {
        let acronym = ScheduleMatcher.acronym(title)
        return acronym.count >= 2 && acronym.count < title.count ? acronym : title
    }
}

struct ScheduleCatalog {
    let items: [ScheduleItem]

    var degrees: [String] {
        let available = Array(Set(items.map(\.degree))).sorted()
        return available.isEmpty ? ["bachelor", "master"] : available
    }

    func faculties(_ filter: ScheduleFilter) -> [ScheduleOption] {
        options(items.filter { $0.degree == filter.degree }.map { ScheduleOption(id: $0.facultySlug, title: $0.faculty) })
    }

    func majors(_ filter: ScheduleFilter) -> [ScheduleOption] {
        guard let facultySlug = filter.facultySlug else { return [] }
        let scoped = items.filter { $0.degree == filter.degree && $0.facultySlug == facultySlug }
        return options(scoped.map { ScheduleOption(id: $0.majorSlug, title: $0.major) })
    }

    func years(_ filter: ScheduleFilter) -> [Int] {
        Array(Set(majorItems(filter).compactMap(\.year))).sorted()
    }

    func streams(_ filter: ScheduleFilter) -> [String] {
        let values = majorItems(filter).filter { filter.year == nil || $0.year == filter.year }.compactMap(\.stream)
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }.sorted { (Int($0) ?? 999, $0) < (Int($1) ?? 999, $1) }
    }

    func results(_ filter: ScheduleFilter) -> [ScheduleItem] {
        majorItems(filter).filter { (filter.year == nil || $0.year == filter.year) && (filter.stream == nil || $0.stream == filter.stream) }
    }

    func sanitized(_ filter: ScheduleFilter) -> ScheduleFilter {
        guard !items.isEmpty else { return ScheduleFilter(degree: filter.degree) }
        var result = ScheduleFilter(degree: degrees.contains(filter.degree) ? filter.degree : degrees[0])
        guard result.degree == filter.degree else { return result }
        result.facultySlug = faculties(result).first { $0.id == filter.facultySlug }?.id
        result.majorSlug = majors(result).first { $0.id == filter.majorSlug }?.id
        result.year = filter.year.flatMap { years(result).contains($0) ? $0 : nil }
        result.stream = filter.stream.flatMap { streams(result).contains($0) ? $0 : nil }
        return result
    }

    func resolve(_ target: ScheduleFilter?, student: Student?) -> ScheduleFilter {
        var result = ScheduleFilter(degree: preferredDegree(target, student: student))
        let faculties = faculties(result)
        result.facultySlug = faculties.first { $0.id == target?.facultySlug }?.id ?? best(faculties, for: student?.faculty)
        let majors = majors(result)
        result.majorSlug = majors.first { $0.id == target?.majorSlug }?.id ?? best(majors, for: student?.specialty)
        let wantedYear = target?.year ?? student?.course
        result.year = wantedYear.flatMap { years(result).contains($0) ? $0 : nil }
        let wantedStream = target?.stream ?? student?.stream
        let streams = streams(result)
        let key = ScheduleMatcher.streamKey(wantedStream)
        result.stream = streams.first { $0 == wantedStream } ?? (key == nil ? nil : streams.first { ScheduleMatcher.streamKey($0) == key })
        return result
    }

    private func preferredDegree(_ target: ScheduleFilter?, student: Student?) -> String {
        let available = degrees
        if let degree = target?.degree, available.contains(degree) { return degree }
        if student?.isMaster == true, available.contains("master") { return "master" }
        return available.contains("bachelor") ? "bachelor" : available[0]
    }

    private func best(_ options: [ScheduleOption], for title: String?) -> String? {
        guard let title, !title.isEmpty else { return nil }
        let needle = ScheduleMatcher.normalize(title)
        return options.first { ScheduleMatcher.normalize($0.title) == needle }?.id
            ?? options.first { ScheduleMatcher.similar(title, $0.title) }?.id
    }

    private func majorItems(_ filter: ScheduleFilter) -> [ScheduleItem] {
        guard let facultySlug = filter.facultySlug, let majorSlug = filter.majorSlug else { return [] }
        return items.filter { $0.degree == filter.degree && $0.facultySlug == facultySlug && $0.majorSlug == majorSlug }
    }

    private func options(_ values: [ScheduleOption]) -> [ScheduleOption] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.id).inserted }.sorted { $0.title < $1.title }
    }
}
