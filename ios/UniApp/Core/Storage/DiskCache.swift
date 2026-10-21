import Foundation

enum DiskCache {
    private static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "UniApp", directoryHint: .isDirectory)
    }

    private static var cachesDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appending(path: "UniApp", directoryHint: .isDirectory)
    }

    private static var snapshotURL: URL {
        supportDirectory.appending(path: "snapshot.json")
    }

    private static func scheduleURL(_ kind: ScheduleKind) -> URL {
        cachesDirectory.appending(path: "schedules-\(kind.rawValue).json")
    }

    static func documentURL(for item: ScheduleItem) -> URL {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        let cleaned = String(item.url.lastPathComponent.filter { allowed.contains($0) }.prefix(80))
        let suffix = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: ".")).isEmpty ? "document.pdf" : cleaned
        return cachesDirectory.appending(path: "documents", directoryHint: .isDirectory).appending(path: "\(item.id)-\(suffix)")
    }

    private static func write<T: Encodable>(_ value: T, to url: URL, protected: Bool) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try APIClient.encoder.encode(value)
            try data.write(to: url, options: protected ? [.atomic, .completeFileProtection] : [.atomic])
        } catch {
            return
        }
    }

    private static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? APIClient.decoder.decode(type, from: data)
    }

    static func saveSnapshot(_ snapshot: Snapshot) {
        write(snapshot, to: snapshotURL, protected: true)
    }

    static func loadSnapshot() -> Snapshot? {
        read(Snapshot.self, from: snapshotURL)
    }

    static func saveSchedules(_ list: ScheduleList, kind: ScheduleKind) {
        write(list, to: scheduleURL(kind), protected: false)
    }

    static func loadSchedules(_ kind: ScheduleKind) -> ScheduleList? {
        read(ScheduleList.self, from: scheduleURL(kind))
    }

    static func clearPersonalData() {
        try? FileManager.default.removeItem(at: snapshotURL)
    }
}
