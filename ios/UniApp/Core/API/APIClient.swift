import Foundation

enum APIError: Error, Equatable, Sendable {
    case server(code: String, message: String?)
    case http(Int)
    case offline
    case timeout
    case decoding
    case transport(String)
}

private struct ErrorEnvelope: Decodable {
    struct Detail: Decodable {
        var code: String
        var message: String?
    }

    var error: Detail
}

private struct MethodResponse: Decodable {
    var method: LoginMethod
}

private struct LoginBody: Encodable {
    var facultyNo: String
    var secret: String
}

struct APIClient: Sendable {
    let baseURL: URL
    private let session: URLSession

    static let live = APIClient(baseURL: configuredBaseURL)

    static var configuredBaseURL: URL {
        let host = (Bundle.main.object(forInfoDictionaryKey: "UniAppAPIHost") as? String)?.trimmingCharacters(in: .whitespaces)
        let resolved = (host?.isEmpty == false ? host : nil) ?? "20-215-255-122.sslip.io"
        return URL(string: "https://\(resolved)") ?? URL(string: "https://20-215-255-122.sslip.io")!
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    init(baseURL: URL, session: URLSession? = nil) {
        self.baseURL = baseURL
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 150
            configuration.timeoutIntervalForResource = 180
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.httpAdditionalHeaders = ["Accept": "application/json", "User-Agent": "UniApp-iOS/2.0"]
            self.session = URLSession(configuration: configuration)
        }
    }

    func loginMethod(facultyNo: String) async throws -> LoginMethod {
        var components = URLComponents(url: baseURL.appending(path: "v2/auth/method"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "facultyNo", value: facultyNo)]
        guard let url = components?.url else { throw APIError.decoding }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        return try await send(request, as: MethodResponse.self).method
    }

    func login(facultyNo: String, secret: String) async throws -> Snapshot {
        var request = URLRequest(url: baseURL.appending(path: "v2/auth/login"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(LoginBody(facultyNo: facultyNo, secret: secret))
        return try await send(request, as: Snapshot.self)
    }

    func schedules(kind: ScheduleKind) async throws -> ScheduleList {
        var components = URLComponents(url: baseURL.appending(path: "v2/schedules"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "kind", value: kind.rawValue)]
        guard let url = components?.url else { throw APIError.decoding }
        var request = URLRequest(url: url)
        request.timeoutInterval = 90
        return try await send(request, as: ScheduleList.self)
    }

    func download(_ remote: URL, to destination: URL) async throws {
        let result: (URL, URLResponse)
        do {
            result = try await session.download(from: remote)
        } catch {
            throw Self.map(error)
        }
        let (temporary, response) = result
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.http(http.statusCode)
        }
        let manager = FileManager.default
        try? manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? manager.removeItem(at: destination)
        try manager.moveItem(at: temporary, to: destination)
    }

    private func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch {
            throw Self.map(error)
        }
        let (data, response) = result
        guard let http = response as? HTTPURLResponse else { throw APIError.decoding }
        guard (200..<300).contains(http.statusCode) else {
            if let envelope = try? Self.decoder.decode(ErrorEnvelope.self, from: data) {
                throw APIError.server(code: envelope.error.code, message: envelope.error.message)
            }
            throw APIError.http(http.statusCode)
        }
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }

    private static func map(_ error: Error) -> APIError {
        if let error = error as? APIError { return error }
        guard let urlError = error as? URLError else { return .transport(error.localizedDescription) }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            return .offline
        case .timedOut:
            return .timeout
        default:
            return .transport(urlError.localizedDescription)
        }
    }
}
