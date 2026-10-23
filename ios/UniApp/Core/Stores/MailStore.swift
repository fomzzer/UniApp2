import Foundation
import Observation

@MainActor
@Observable
final class MailStore {
    enum Phase: Equatable {
        case signedOut
        case ready
    }

    private(set) var phase: Phase
    private(set) var account: MailAccount?
    private(set) var lastUsername: String?
    private(set) var folders: [MailFolder] = []
    private(set) var folder: MailFolder?
    private(set) var messages: [MailSummary] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var nextBefore: Int?
    var error: MailError?

    private let service: MailService
    private let persists: Bool
    private var contents: [String: MailContent] = [:]
    private static let pageSize = 40

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["UNIAPP_UITEST_MAIL"] != nil {
            service = FixtureMailService()
            persists = false
            account = nil
            lastUsername = nil
            phase = .signedOut
            return
        }
        #endif
        let stored = KeychainStore.loadMail()
        service = IMAPMailService()
        persists = true
        account = stored
        lastUsername = stored?.username
        phase = stored == nil ? .signedOut : .ready
    }

    var inboxUnread: Int {
        folders.first { $0.role == .inbox }?.unread ?? 0
    }

    func signIn(username: String, password: String, host: String) async throws {
        let account = MailAccount(username: username.trimmingCharacters(in: .whitespacesAndNewlines), password: password, host: host)
        try await service.signIn(account)
        if persists {
            KeychainStore.saveMail(account)
        }
        self.account = account
        lastUsername = account.username
        error = nil
        folders = []
        messages = []
        contents = [:]
        phase = .ready
        await reload()
    }

    func start() async {
        guard phase == .ready, folders.isEmpty, !isLoading else { return }
        await reload()
    }

    func reload() async {
        guard phase == .ready, !isLoading else { return }
        if let account {
            await service.use(account)
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await service.folders()
            folders = loaded
            let current = folder.flatMap { selected in loaded.first { $0.path == selected.path } } ?? loaded.first
            if current?.path != folder?.path {
                contents = [:]
            }
            folder = current
            try await loadFirstPage()
            error = nil
        } catch {
            handle(error)
        }
    }

    func select(_ target: MailFolder) async {
        guard target.path != folder?.path else { return }
        folder = target
        messages = []
        nextBefore = nil
        contents = [:]
        isLoading = true
        defer { isLoading = false }
        do {
            try await loadFirstPage()
            error = nil
        } catch {
            handle(error)
        }
    }

    func loadMore() async {
        guard let folder, let before = nextBefore, !isLoadingMore, !isLoading else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await service.page(folder: folder.path, before: before, size: Self.pageSize)
            let known = Set(messages.map(\.uid))
            messages += page.summaries.filter { !known.contains($0.uid) }
            nextBefore = page.nextBefore
        } catch {
            handle(error)
        }
    }

    func content(for summary: MailSummary) async throws -> MailContent {
        guard let folder else { throw MailError.closed }
        let key = "\(folder.path)#\(summary.uid)"
        if let cached = contents[key] {
            return cached
        }
        do {
            let content = try await service.content(uid: summary.uid, folder: folder.path)
            contents[key] = content
            return content
        } catch {
            handle(error)
            throw error
        }
    }

    func summary(uid: UInt32) -> MailSummary? {
        messages.first { $0.uid == uid }
    }

    func setSeen(_ seen: Bool, for summary: MailSummary) async {
        guard let folder, let index = messages.firstIndex(where: { $0.uid == summary.uid }), messages[index].isSeen != seen else { return }
        messages[index].isSeen = seen
        adjustUnread(seen ? -1 : 1)
        do {
            try await service.setSeen(seen, uid: summary.uid, folder: folder.path)
        } catch {
            if let index = messages.firstIndex(where: { $0.uid == summary.uid }) {
                messages[index].isSeen = !seen
            }
            adjustUnread(seen ? 1 : -1)
            handle(error)
        }
    }

    func setFlagged(_ flagged: Bool, for summary: MailSummary) async {
        guard let folder, let index = messages.firstIndex(where: { $0.uid == summary.uid }), messages[index].isFlagged != flagged else { return }
        messages[index].isFlagged = flagged
        do {
            try await service.setFlagged(flagged, uid: summary.uid, folder: folder.path)
        } catch {
            if let index = messages.firstIndex(where: { $0.uid == summary.uid }) {
                messages[index].isFlagged = !flagged
            }
            handle(error)
        }
    }

    var moveTargets: [MailFolder] {
        folders.filter { $0.path != folder?.path }
    }

    var isInTrash: Bool {
        folder?.role == .trash
    }

    @discardableResult
    func move(_ summary: MailSummary, to target: MailFolder) async -> Bool {
        guard let folder else { return false }
        return await remove(summary) {
            try await self.service.move(uid: summary.uid, from: folder.path, to: target.path)
        } adjusting: { folders in
            if !summary.isSeen, let index = folders.firstIndex(where: { $0.path == target.path }) {
                folders[index].unread += 1
            }
        }
    }

    @discardableResult
    func delete(_ summary: MailSummary) async -> Bool {
        guard let folder else { return false }
        let trash = folders.first { $0.role == .trash }?.path
        let created = trash == nil && folder.role != .trash
        let removed = await remove(summary) {
            try await self.service.delete(uid: summary.uid, folder: folder.path, trash: trash)
        } adjusting: { _ in }
        if removed, created, let loaded = try? await service.folders() {
            folders = loaded.map { loadedFolder in
                var copy = loadedFolder
                if copy.path == folder.path, let current = self.folders.first(where: { $0.path == folder.path }) {
                    copy.unread = current.unread
                }
                return copy
            }
        }
        return removed
    }

    func compose(_ intent: RoundcubeCompose.Intent) async throws -> RoundcubeCompose {
        if let account {
            await service.use(account)
        }
        return try await service.compose(intent)
    }

    func send(_ message: RoundcubeMessage, using draft: RoundcubeCompose) async throws {
        try await service.send(message, using: draft)
        switch draft.intent {
        case .reply(let uid, _, _), .forward(let uid, _):
            if let index = messages.firstIndex(where: { $0.uid == uid }), !messages[index].isSeen {
                messages[index].isSeen = true
                adjustUnread(-1)
            }
        case .new:
            break
        }
        if folder?.role == .sent {
            await reload()
        }
    }

    private func remove(_ summary: MailSummary, _ action: @escaping () async throws -> Void, adjusting: (inout [MailFolder]) -> Void) async -> Bool {
        guard let index = messages.firstIndex(where: { $0.uid == summary.uid }) else { return false }
        let snapshot = (messages, folders, folder)
        messages.remove(at: index)
        if !summary.isSeen {
            adjustUnread(-1)
        }
        adjusting(&folders)
        do {
            try await action()
            return true
        } catch {
            messages = snapshot.0
            folders = snapshot.1
            folder = snapshot.2
            handle(error)
            return false
        }
    }

    func signOut() {
        let service = service
        Task { await service.signOut() }
        if persists {
            KeychainStore.deleteMail()
        }
        account = nil
        lastUsername = nil
        reset()
    }

    private func loadFirstPage() async throws {
        guard let folder else {
            messages = []
            nextBefore = nil
            return
        }
        let page = try await service.page(folder: folder.path, before: nil, size: Self.pageSize)
        messages = page.summaries
        nextBefore = page.nextBefore
    }

    private func adjustUnread(_ delta: Int) {
        guard let path = folder?.path, let index = folders.firstIndex(where: { $0.path == path }) else { return }
        folders[index].unread = max(0, folders[index].unread + delta)
        folder = folders[index]
    }

    private func handle(_ error: Error) {
        let mailError = error as? MailError ?? .connectionFailed
        if mailError == .authenticationFailed {
            if persists {
                KeychainStore.deleteMail()
            }
            account = nil
            reset()
        }
        self.error = mailError
    }

    private func reset() {
        folders = []
        folder = nil
        messages = []
        nextBefore = nil
        contents = [:]
        phase = .signedOut
    }
}
