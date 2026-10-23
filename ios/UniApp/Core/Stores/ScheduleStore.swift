import Foundation
import Observation

@MainActor
@Observable
final class ScheduleStore {
    private(set) var lists: [ScheduleKind: ScheduleList] = [:]
    private(set) var loading: Set<ScheduleKind> = []
    private(set) var errors: [ScheduleKind: APIError] = [:]
    private(set) var lastFetch: [ScheduleKind: Date] = [:]
    private(set) var timetables: [Int: Timetable] = [:]
    private(set) var timetableLoading: Set<Int> = []
    private(set) var timetableErrors: [Int: APIError] = [:]
    private var timetableFetch: [Int: Date] = [:]
    var pinned: ScheduleSelection? = nil {
        didSet { persistPinned() }
    }

    private let api: APIClient
    private static let pinnedKey = "schedule.pinned"
    private static let freshness: TimeInterval = 15 * 60

    init(api: APIClient = .live) {
        self.api = api
        for kind in ScheduleKind.allCases {
            if let cached = DiskCache.loadSchedules(kind) {
                lists[kind] = cached
            }
        }
        if let data = UserDefaults.standard.data(forKey: Self.pinnedKey) {
            pinned = try? JSONDecoder().decode(ScheduleSelection.self, from: data)
        }
    }

    func items(_ kind: ScheduleKind) -> [ScheduleItem] {
        lists[kind]?.items ?? []
    }

    func isLoading(_ kind: ScheduleKind) -> Bool {
        loading.contains(kind)
    }

    func load(_ kind: ScheduleKind, force: Bool = false) async {
        if loading.contains(kind) { return }
        if !force, let last = lastFetch[kind], Date().timeIntervalSince(last) < Self.freshness, lists[kind] != nil {
            return
        }
        loading.insert(kind)
        defer { loading.remove(kind) }
        do {
            let list = try await api.schedules(kind: kind)
            lists[kind] = list
            errors[kind] = nil
            lastFetch[kind] = Date()
            DiskCache.saveSchedules(list, kind: kind)
        } catch let error as APIError {
            errors[kind] = error
        } catch {
            errors[kind] = .transport(error.localizedDescription)
        }
    }

    func myItem(_ kind: ScheduleKind, student: Student?) -> ScheduleItem? {
        let available = items(kind)
        if let pinned, let item = available.first(where: { pinned.matches($0) }) {
            return item
        }
        if let pinned, let item = available.first(where: {
            $0.degree == pinned.degree && $0.facultySlug == pinned.facultySlug && $0.majorSlug == pinned.majorSlug && $0.year == pinned.year
        }) {
            return item
        }
        guard let student else { return nil }
        return ScheduleMatcher.bestMatch(for: student, in: available)
    }

    func timetable(for item: ScheduleItem) -> Timetable? {
        if let loaded = timetables[item.id], loaded.url == item.url.absoluteString {
            return loaded
        }
        return nil
    }

    func loadTimetable(_ item: ScheduleItem, force: Bool = false) async {
        guard item.isPdf, !timetableLoading.contains(item.id) else { return }
        #if DEBUG
        if let json = ProcessInfo.processInfo.environment["UNIAPP_UITEST_TIMETABLE"],
           var fixture = try? APIClient.decoder.decode(Timetable.self, from: Data(json.utf8)) {
            fixture.scheduleId = item.id
            fixture.url = item.url.absoluteString
            timetables[item.id] = fixture
            return
        }
        #endif
        if timetables[item.id] == nil, let cached = DiskCache.loadTimetable(item.id), cached.url == item.url.absoluteString {
            timetables[item.id] = cached
        }
        if !force, let last = timetableFetch[item.id], Date().timeIntervalSince(last) < Self.freshness, timetables[item.id] != nil {
            return
        }
        timetableLoading.insert(item.id)
        defer { timetableLoading.remove(item.id) }
        do {
            let loaded = try await api.timetable(scheduleId: item.id)
            timetables[item.id] = loaded
            timetableErrors[item.id] = nil
            timetableFetch[item.id] = Date()
            DiskCache.saveTimetable(loaded)
        } catch let error as APIError {
            timetableErrors[item.id] = error
        } catch {
            timetableErrors[item.id] = .transport(error.localizedDescription)
        }
    }

    func document(for item: ScheduleItem, forceReload: Bool = false) async throws -> URL {
        let destination = DiskCache.documentURL(for: item)
        if !forceReload, FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
            return destination
        }
        guard let remote = item.webURL, remote.scheme?.lowercased() == "https" else {
            throw APIError.transport("Unsupported document address")
        }
        try await api.download(remote, to: destination)
        return destination
    }

    private func persistPinned() {
        if let pinned, let data = try? JSONEncoder().encode(pinned) {
            UserDefaults.standard.set(data, forKey: Self.pinnedKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.pinnedKey)
        }
    }
}
