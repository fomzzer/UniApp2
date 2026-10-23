import Foundation
import Network

enum MailError: Error, Equatable, Sendable {
    case authenticationFailed
    case connectionFailed
    case timeout
    case closed
    case server(String)
}

actor IMAPConnection {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "com.fomzzer.uniapp.imap")
    private var buffer = Data()
    private var counter = 0
    private(set) var isOpen = false

    init(host: String, port: UInt16 = 993) {
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 15
        tcp.enableKeepalive = true
        let parameters = NWParameters(tls: NWProtocolTLS.Options(), tcp: tcp)
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port) ?? .imaps, using: parameters)
    }

    func open() async throws {
        try await waitReady(timeout: 20)
        let greeting = String(decoding: try await readResponse(), as: UTF8.self).uppercased()
        guard greeting.hasPrefix("* OK") || greeting.hasPrefix("* PREAUTH") else {
            connection.cancel()
            throw MailError.connectionFailed
        }
        isOpen = true
    }

    @discardableResult
    func command(_ text: String, timeout: Double = 30) async throws -> [Data] {
        do {
            return try await exchange(text, timeout: timeout)
        } catch MailError.server(let status) {
            throw MailError.server(status)
        } catch {
            isOpen = false
            connection.cancel()
            throw error
        }
    }

    private func exchange(_ text: String, timeout: Double) async throws -> [Data] {
        counter += 1
        let tag = "U\(counter)"
        let prefix = Data("\(tag) ".utf8)
        try await send(Data("\(tag) \(text)\r\n".utf8))
        var untagged: [Data] = []
        while true {
            let response = try await readResponse(timeout: timeout)
            if response.starts(with: prefix) {
                let status = String(decoding: response.dropFirst(prefix.count), as: UTF8.self)
                if status.uppercased().hasPrefix("OK") { return untagged }
                throw MailError.server(status)
            }
            if response.first == UInt8(ascii: "+") {
                try await send(Data("*\r\n".utf8))
                continue
            }
            if response.starts(with: Data("* BYE".utf8)) {
                isOpen = false
                throw MailError.closed
            }
            untagged.append(response)
        }
    }

    func close() async {
        if isOpen {
            isOpen = false
            _ = try? await command("LOGOUT", timeout: 5)
        }
        connection.cancel()
    }

    private func readResponse(timeout: Double = 30) async throws -> Data {
        var scan = 0
        while true {
            if let end = buffer.range(of: Data([13, 10]), in: scan..<buffer.count)?.lowerBound {
                if let length = Self.literalLength(in: buffer, endingAt: end) {
                    let needed = end + 2 + length
                    while buffer.count < needed {
                        buffer.append(try await receive(timeout: timeout))
                    }
                    scan = needed
                    continue
                }
                let response = Data(buffer.prefix(end))
                buffer = Data(buffer.dropFirst(end + 2))
                return response
            }
            buffer.append(try await receive(timeout: timeout))
        }
    }

    static func literalLength(in data: Data, endingAt end: Int) -> Int? {
        guard end > 0, data[end - 1] == UInt8(ascii: "}") else { return nil }
        var index = end - 2
        var digits: [UInt8] = []
        while index >= 0 {
            let byte = data[index]
            if byte == UInt8(ascii: "{") { break }
            if byte != UInt8(ascii: "+") && !(48...57).contains(byte) { return nil }
            if byte != UInt8(ascii: "+") { digits.insert(byte, at: 0) }
            index -= 1
        }
        guard index >= 0, !digits.isEmpty else { return nil }
        return Int(String(decoding: digits, as: UTF8.self))
    }

    private func waitReady(timeout: Double) async throws {
        let connection = connection
        let queue = queue
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = ResumeGate()
            let timer = DispatchWorkItem {
                if gate.claim() {
                    connection.cancel()
                    continuation.resume(throwing: MailError.timeout)
                }
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if gate.claim() {
                        timer.cancel()
                        continuation.resume()
                    }
                case .failed, .cancelled, .waiting:
                    if gate.claim() {
                        timer.cancel()
                        connection.cancel()
                        continuation.resume(throwing: MailError.connectionFailed)
                    }
                default:
                    break
                }
            }
            queue.asyncAfter(deadline: .now() + timeout, execute: timer)
            connection.start(queue: queue)
        }
    }

    private func receive(timeout: Double) async throws -> Data {
        let connection = connection
        let queue = queue
        return try await withCheckedThrowingContinuation { continuation in
            let expired = ResumeGate()
            let timer = DispatchWorkItem {
                _ = expired.claim()
                connection.cancel()
            }
            queue.asyncAfter(deadline: .now() + timeout, execute: timer)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { data, _, _, error in
                timer.cancel()
                if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if expired.isClaimed {
                    continuation.resume(throwing: MailError.timeout)
                } else if error != nil {
                    continuation.resume(throwing: MailError.connectionFailed)
                } else {
                    continuation.resume(throwing: MailError.closed)
                }
            }
        }
    }

    private func send(_ data: Data) async throws {
        let connection = connection
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if error != nil {
                    continuation.resume(throwing: MailError.connectionFailed)
                } else {
                    continuation.resume()
                }
            })
        }
    }
}

private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    var isClaimed: Bool {
        lock.withLock { claimed }
    }

    func claim() -> Bool {
        lock.withLock {
            if claimed { return false }
            claimed = true
            return true
        }
    }
}
