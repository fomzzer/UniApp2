import Foundation
import Observation

@MainActor
@Observable
final class SessionStore {
    enum Phase: Equatable {
        case launching
        case signedOut
        case signedIn
    }

    private(set) var phase: Phase = .launching
    private(set) var snapshot: Snapshot? = nil
    private(set) var savedCredentials: Credentials? = nil
    private(set) var isRefreshing = false
    var refreshError: APIError? = nil

    private let api: APIClient

    init(api: APIClient = .live) {
        self.api = api
    }

    var canRefreshSilently: Bool {
        savedCredentials != nil
    }

    var lastKnownFacultyNo: String? {
        snapshot?.student.facultyNo ?? savedCredentials?.facultyNo
    }

    func bootstrap() {
        guard phase == .launching else { return }
        savedCredentials = KeychainStore.load()
        if let cached = DiskCache.loadSnapshot() {
            snapshot = cached
            phase = .signedIn
        } else {
            phase = .signedOut
        }
    }

    func detectMethod(facultyNo: String) async throws -> LoginMethod {
        try await api.loginMethod(facultyNo: facultyNo)
    }

    func signIn(facultyNo: String, secret: String, method: LoginMethod?, remember: Bool) async throws {
        let fresh = try await api.login(facultyNo: facultyNo, secret: secret)
        let resolvedMethod = fresh.loginMethod ?? method ?? .egn
        snapshot = fresh
        refreshError = nil
        if remember {
            DiskCache.saveSnapshot(fresh)
            if resolvedMethod == .otp {
                KeychainStore.delete()
                savedCredentials = nil
            } else {
                let credentials = Credentials(facultyNo: facultyNo, secret: secret, method: resolvedMethod)
                KeychainStore.save(credentials)
                savedCredentials = credentials
            }
        } else {
            DiskCache.clearPersonalData()
            KeychainStore.delete()
            savedCredentials = nil
        }
        phase = .signedIn
    }

    func refresh() async {
        guard let credentials = savedCredentials, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let fresh = try await api.login(facultyNo: credentials.facultyNo, secret: credentials.secret)
            snapshot = fresh
            DiskCache.saveSnapshot(fresh)
            refreshError = nil
        } catch let error as APIError {
            refreshError = error
        } catch {
            refreshError = .transport(error.localizedDescription)
        }
    }

    func signOut() {
        KeychainStore.delete()
        DiskCache.clearPersonalData()
        savedCredentials = nil
        snapshot = nil
        refreshError = nil
        phase = .signedOut
    }
}
