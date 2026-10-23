import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum RoundcubeError: Error, Equatable, Sendable {
    case authenticationFailed
    case secondFactorRequired
    case sessionExpired
    case rejected(String)
    case unexpectedPage
    case transport(String)
}

struct RoundcubeCompose: Sendable, Equatable {
    enum Intent: Sendable, Equatable {
        case new
        case reply(uid: UInt32, mailbox: String, all: Bool)
        case forward(uid: UInt32, mailbox: String)
    }

    var intent: Intent
    var id: String
    var token: String
    var identity: String
    var storeTarget: String?
    var to: String
    var cc: String
    var subject: String
    var body: String
}

struct RoundcubeMessage: Sendable, Equatable {
    var to: String
    var cc: String
    var subject: String
    var body: String
}

actor RoundcubeClient {
    private let base: URL
    private let session: URLSession
    private var cookies: [String: String] = [:]
    private var credentials: (username: String, password: String)?

    init(base: URL) {
        self.base = base
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration, delegate: RedirectBlocker(), delegateQueue: nil)
    }

    static func base(forIMAPHost host: String) -> URL? {
        URL(string: "https://\(host)/")
    }

    func login(username: String, password: String) async throws {
        cookies = [:]
        let page = try await fetch(path: "", query: [:])
        guard let token = Self.first(#"name="_token" value="([^"]+)""#, in: page.text) else { throw RoundcubeError.unexpectedPage }
        let response = try await fetch(path: "", query: ["_task": "login"], form: [
            ("_token", token), ("_task", "login"), ("_action", "login"), ("_timezone", "Europe/Sofia"), ("_url", ""),
            ("_user", username), ("_pass", password),
        ], followRedirects: false)
        if (300..<400).contains(response.status), let location = response.location, !location.contains("_task=login") {
            credentials = (username, password)
            return
        }
        if response.text.range(of: "twofactor|2fa|kolab_2fa|totp", options: [.regularExpression, .caseInsensitive]) != nil {
            throw RoundcubeError.secondFactorRequired
        }
        throw RoundcubeError.authenticationFailed
    }

    func compose(_ intent: RoundcubeCompose.Intent) async throws -> RoundcubeCompose {
        do {
            return try await openCompose(intent)
        } catch RoundcubeError.sessionExpired {
            try await relogin()
            return try await openCompose(intent)
        }
    }

    func send(_ message: RoundcubeMessage, using draft: RoundcubeCompose) async throws {
        do {
            try await submit(message, draft)
        } catch RoundcubeError.sessionExpired {
            try await relogin()
            try await submit(message, try await openCompose(draft.intent))
        }
    }

    func logout() {
        cookies = [:]
        credentials = nil
    }

    func expireSession() {
        cookies = [:]
    }

    private func relogin() async throws {
        guard let credentials else { throw RoundcubeError.authenticationFailed }
        try await login(username: credentials.username, password: credentials.password)
    }

    private func openCompose(_ intent: RoundcubeCompose.Intent) async throws -> RoundcubeCompose {
        var query = ["_task": "mail", "_action": "compose"]
        switch intent {
        case .new:
            break
        case .reply(let uid, let mailbox, let all):
            query["_reply_uid"] = String(uid)
            query["_mbox"] = mailbox
            if all { query["_all"] = "all" }
        case .forward(let uid, let mailbox):
            query["_forward_uid"] = String(uid)
            query["_mbox"] = mailbox
        }
        let page = try await fetch(path: "", query: query)
        guard !Self.isLogin(page.text) else { throw RoundcubeError.sessionExpired }
        guard let id = Self.first(#""compose_id":"([^"]+)""#, in: page.text) ?? page.finalURL.flatMap({ Self.first(#"_id=([A-Za-z0-9]+)"#, in: $0.absoluteString) }),
              let token = Self.first(#""request_token":"([^"]+)""#, in: page.text) else {
            throw RoundcubeError.unexpectedPage
        }
        let identity = Self.selectValue("_from", in: page.text) ?? Self.inputValue("_from", in: page.text) ?? ""
        return RoundcubeCompose(
            intent: intent,
            id: id,
            token: token,
            identity: identity,
            storeTarget: Self.selectValue("_store_target", in: page.text),
            to: Self.textareaOrInput("_to", in: page.text),
            cc: Self.textareaOrInput("_cc", in: page.text),
            subject: Self.inputValue("_subject", in: page.text).map(Self.decodeEntities) ?? "",
            body: Self.textarea("_message", in: page.text) ?? ""
        )
    }

    private func submit(_ message: RoundcubeMessage, _ draft: RoundcubeCompose) async throws {
        var form: [(String, String)] = [
            ("_token", draft.token), ("_task", "mail"), ("_action", "send"), ("_id", draft.id), ("_attachments", ""),
            ("_from", draft.identity), ("_to", message.to), ("_cc", message.cc), ("_bcc", ""), ("_replyto", ""), ("_followupto", ""),
            ("_subject", message.subject), ("_message", message.body), ("_draft", ""), ("_is_html", "0"), ("_priority", "0"),
            ("_mdn", ""), ("_dsn", ""), ("_framed", "1"),
        ]
        if let target = draft.storeTarget {
            form.append(("_store_target", target))
        }
        let response = try await fetch(path: "", query: ["_task": "mail", "_unlock": "loading1", "_framed": "1"], form: form, followRedirects: false)
        if response.text.contains("sent_successfully") {
            return
        }
        if Self.isLogin(response.text) || ((300..<400).contains(response.status) && (response.location ?? "").contains("_task=login")) || response.status == 401 || response.status == 403 {
            throw RoundcubeError.sessionExpired
        }
        if let message = Self.first(#"display_message\("((?:[^"\\]|\\.)*)",\s*"error""#, in: response.text) {
            throw RoundcubeError.rejected(Self.decodeEntities(message.replacingOccurrences(of: "\\\"", with: "\"")))
        }
        throw RoundcubeError.unexpectedPage
    }

    private struct Page {
        var status: Int
        var text: String
        var location: String?
        var finalURL: URL?
    }

    private func fetch(path: String, query: [String: String], form: [(String, String)]? = nil, followRedirects: Bool = true) async throws -> Page {
        var components = URLComponents(url: path.isEmpty ? base : base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard var url = components?.url else { throw RoundcubeError.unexpectedPage }
        var method = form == nil ? "GET" : "POST"
        var body = form.map(Self.encode)
        for _ in 0..<6 {
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) UniApp", forHTTPHeaderField: "User-Agent")
            if !cookies.isEmpty {
                request.setValue(cookies.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "; "), forHTTPHeaderField: "Cookie")
            }
            if let body {
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                request.httpBody = body
            }
            let (data, response) = try await perform(request)
            absorbCookies(response)
            let location = response.value(forHTTPHeaderField: "Location")
            if followRedirects, (300..<400).contains(response.statusCode), let location, let next = URL(string: location, relativeTo: url)?.absoluteURL {
                url = next
                method = "GET"
                body = nil
                continue
            }
            return Page(status: response.statusCode, text: String(decoding: data, as: UTF8.self), location: location, finalURL: url)
        }
        throw RoundcubeError.unexpectedPage
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: RoundcubeError.transport(error.localizedDescription))
                } else if let response = response as? HTTPURLResponse {
                    continuation.resume(returning: (data ?? Data(), response))
                } else {
                    continuation.resume(throwing: RoundcubeError.unexpectedPage)
                }
            }.resume()
        }
    }

    private func absorbCookies(_ response: HTTPURLResponse) {
        for (key, value) in response.allHeaderFields {
            guard String(describing: key).lowercased() == "set-cookie" else { continue }
            for header in Self.splitCookies(String(describing: value)) {
                let pair = header.split(separator: ";", maxSplits: 1).first.map(String.init) ?? ""
                guard let equals = pair.firstIndex(of: "=") else { continue }
                let name = pair[..<equals].trimmingCharacters(in: .whitespaces)
                let value = pair[pair.index(after: equals)...].trimmingCharacters(in: .whitespaces)
                if value.isEmpty || value == "-del-" || header.lowercased().contains("expires=thu, 01 jan 1970") {
                    cookies[name] = nil
                } else {
                    cookies[name] = value
                }
            }
        }
    }

    private static func splitCookies(_ value: String) -> [String] {
        var result: [String] = []
        var current = ""
        let parts = value.components(separatedBy: ",")
        for part in parts {
            if current.isEmpty {
                current = part
            } else if part.range(of: #"^\s*[A-Za-z0-9_\-]+="#, options: .regularExpression) != nil {
                result.append(current)
                current = part
            } else {
                current += "," + part
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func encode(_ form: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        let text = form.map { key, value in
            let escaped = value.addingPercentEncoding(withAllowedCharacters: allowed)?.replacingOccurrences(of: "%20", with: "+") ?? ""
            return "\(key)=\(escaped)"
        }.joined(separator: "&")
        return Data(text.utf8)
    }

    private static func isLogin(_ text: String) -> Bool {
        text.contains(#""task":"login""#) || text.contains("id=\"login-form\"")
    }

    static func first(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1, let result = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[result])
    }

    static func selectValue(_ name: String, in text: String) -> String? {
        guard let select = first(#"<select[^>]*name="\#(name)"[^>]*>(.*?)</select>"#, in: text) else { return nil }
        return first(#"<option[^>]*value="([^"]*)"[^>]*selected"#, in: select) ?? first(#"<option[^>]*value="([^"]*)""#, in: select)
    }

    static func inputValue(_ name: String, in text: String) -> String? {
        guard let tag = first(#"(<input[^>]*name="\#(name)"[^>]*>)"#, in: text) else { return nil }
        return first(#"value="([^"]*)""#, in: tag)
    }

    static func textarea(_ name: String, in text: String) -> String? {
        first(#"<textarea[^>]*name="\#(name)"[^>]*>(.*?)</textarea>"#, in: text).map(decodeEntities)
    }

    static func textareaOrInput(_ name: String, in text: String) -> String {
        (textarea(name, in: text) ?? inputValue(name, in: text).map(decodeEntities) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ text: String) -> String {
        var result = text
        if let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") {
            let source = result as NSString
            var output = ""
            var cursor = 0
            for match in regex.matches(in: result, range: NSRange(location: 0, length: source.length)) {
                output += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                let hex = source.substring(with: match.range(at: 1)) == "x"
                let digits = source.substring(with: match.range(at: 2))
                if let value = UInt32(digits, radix: hex ? 16 : 10), let scalar = Unicode.Scalar(value) {
                    output += String(Character(scalar))
                } else {
                    output += source.substring(with: match.range)
                }
                cursor = match.range.location + match.range.length
            }
            result = output + source.substring(from: cursor)
        }
        for (entity, value) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&nbsp;", "\u{00A0}"), ("&amp;", "&")] {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        return result
    }
}

private final class RedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
