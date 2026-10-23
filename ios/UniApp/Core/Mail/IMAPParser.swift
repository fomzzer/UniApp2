import Foundation

enum IMAPValue: Hashable, Sendable {
    case atom(String)
    case string(Data)
    case none
    case list([IMAPValue])

    var text: String? {
        switch self {
        case .atom(let value): value
        case .string(let data): String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        default: nil
        }
    }

    var data: Data? {
        switch self {
        case .string(let data): data
        case .atom(let value): Data(value.utf8)
        default: nil
        }
    }

    var items: [IMAPValue] {
        if case .list(let values) = self { return values }
        return []
    }
}

struct IMAPParser {
    private let bytes: [UInt8]
    private var index = 0

    private init(_ data: Data) {
        bytes = Array(data)
    }

    static func parse(_ data: Data) -> [IMAPValue] {
        var parser = IMAPParser(data)
        return parser.values(nested: false)
    }

    private mutating func values(nested: Bool) -> [IMAPValue] {
        var result: [IMAPValue] = []
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 32 || byte == 13 || byte == 10 {
                index += 1
            } else if byte == UInt8(ascii: ")") {
                index += 1
                if nested { return result }
            } else {
                result.append(value())
            }
        }
        return result
    }

    private mutating func value() -> IMAPValue {
        let byte = bytes[index]
        if byte == UInt8(ascii: "(") {
            index += 1
            return .list(values(nested: true))
        }
        if byte == UInt8(ascii: "\"") {
            return quoted()
        }
        if byte == UInt8(ascii: "{"), let literal = literal() {
            return literal
        }
        return atom()
    }

    private mutating func quoted() -> IMAPValue {
        index += 1
        var output: [UInt8] = []
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "\\") && index + 1 < bytes.count {
                output.append(bytes[index + 1])
                index += 2
                continue
            }
            index += 1
            if byte == UInt8(ascii: "\"") { break }
            output.append(byte)
        }
        return .string(Data(output))
    }

    private mutating func literal() -> IMAPValue? {
        let start = index
        guard let close = bytes[index...].firstIndex(of: UInt8(ascii: "}")) else { return nil }
        let digits = bytes[(index + 1)..<close].filter { (48...57).contains($0) }
        guard let length = Int(String(decoding: digits, as: UTF8.self)) else { return nil }
        var cursor = close + 1
        if cursor < bytes.count && bytes[cursor] == 13 { cursor += 1 }
        if cursor < bytes.count && bytes[cursor] == 10 { cursor += 1 }
        guard cursor + length <= bytes.count else {
            index = start
            return nil
        }
        index = cursor + length
        return .string(Data(bytes[cursor..<(cursor + length)]))
    }

    private mutating func atom() -> IMAPValue {
        var output: [UInt8] = []
        var depth = 0
        while index < bytes.count {
            let byte = bytes[index]
            if depth == 0 && (byte == 32 || byte == 13 || byte == 10 || byte == UInt8(ascii: "(") || byte == UInt8(ascii: ")")) {
                break
            }
            if byte == UInt8(ascii: "[") { depth += 1 }
            if byte == UInt8(ascii: "]") { depth = max(0, depth - 1) }
            output.append(byte)
            index += 1
        }
        if output.isEmpty {
            index += 1
            return .none
        }
        let text = String(decoding: output, as: UTF8.self)
        return text.uppercased() == "NIL" ? .none : .atom(text)
    }
}

enum IMAPResponses {
    static func fetch(_ response: Data) -> [String: IMAPValue]? {
        let values = IMAPParser.parse(response)
        guard values.count >= 4, values[0].text == "*", values[2].text?.uppercased() == "FETCH" else { return nil }
        let items = values[3].items
        var result: [String: IMAPValue] = [:]
        var index = 0
        while index + 1 < items.count {
            if let key = items[index].text?.uppercased() {
                result[key] = items[index + 1]
            }
            index += 2
        }
        return result
    }

    static func exists(_ responses: [Data]) -> Int? {
        for response in responses {
            let values = IMAPParser.parse(response)
            if values.count >= 3, values[0].text == "*", values[2].text?.uppercased() == "EXISTS", let count = values[1].text.flatMap(Int.init) {
                return count
            }
        }
        return nil
    }

    static func folder(_ response: Data) -> MailFolder? {
        let values = IMAPParser.parse(response)
        guard values.count >= 5, values[0].text == "*", values[1].text?.uppercased() == "LIST" else { return nil }
        let attributes = Set(values[2].items.compactMap { $0.text?.lowercased() })
        guard !attributes.contains("\\noselect"), !attributes.contains("\\nonexistent"), let path = values[4].text else { return nil }
        let delimiter = values[3].text ?? ""
        let decoded = MailboxName.decode(path)
        let name = delimiter.isEmpty ? decoded : (decoded.components(separatedBy: delimiter).last ?? decoded)
        return MailFolder(path: path, name: name, role: MailFolder.Role(attributes: attributes, path: path, name: name), unread: 0)
    }

    static func unseen(_ responses: [Data]) -> Int? {
        for response in responses {
            let values = IMAPParser.parse(response)
            guard values.count >= 4, values[1].text?.uppercased() == "STATUS" else { continue }
            let items = values[3].items
            var index = 0
            while index + 1 < items.count {
                if items[index].text?.uppercased() == "UNSEEN" {
                    return items[index + 1].text.flatMap(Int.init)
                }
                index += 2
            }
        }
        return nil
    }

    static func summary(_ attributes: [String: IMAPValue]) -> MailSummary? {
        guard let uid = attributes["UID"]?.text.flatMap(UInt32.init) else { return nil }
        let flags = Set((attributes["FLAGS"]?.items ?? []).compactMap { $0.text?.lowercased() })
        let envelope = attributes["ENVELOPE"]?.items ?? []
        let date = attributes["INTERNALDATE"]?.text.flatMap(internalDate)
            ?? envelope.first?.text.flatMap(MIME.headerDate)
            ?? Date(timeIntervalSince1970: 0)
        let subject = envelope.count > 1 ? envelope[1].data.map { MIME.decodeHeader(MIME.headerString($0)) } : nil
        return MailSummary(
            uid: uid,
            subject: subject?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            from: envelope.count > 2 ? addresses(envelope[2]).first : nil,
            to: envelope.count > 5 ? addresses(envelope[5]) : [],
            cc: envelope.count > 6 ? addresses(envelope[6]) : [],
            date: date,
            isSeen: flags.contains("\\seen"),
            isFlagged: flags.contains("\\flagged"),
            hasAttachments: attributes["BODYSTRUCTURE"].map(containsAttachment) ?? false,
            size: attributes["RFC822.SIZE"]?.text.flatMap(Int.init) ?? 0
        )
    }

    static func addresses(_ value: IMAPValue) -> [MailAddress] {
        value.items.compactMap { entry in
            let parts = entry.items
            guard parts.count >= 4, let mailbox = parts[2].text else { return nil }
            let email = parts[3].text.map { "\(mailbox)@\($0)" } ?? mailbox
            let name = parts[0].data.map { MIME.decodeHeader(MIME.headerString($0)) }
            return MailAddress(name: name?.isEmpty == false ? name : nil, email: email)
        }
    }

    static func containsAttachment(_ value: IMAPValue) -> Bool {
        switch value {
        case .list(let items):
            return items.contains(where: containsAttachment)
        case .atom(let text):
            return text.lowercased() == "attachment"
        case .string(let data):
            return String(decoding: data, as: UTF8.self).lowercased() == "attachment"
        case .none:
            return false
        }
    }

    private static let internalFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d-MMM-yyyy HH:mm:ss Z"
        return formatter
    }()

    static func internalDate(_ text: String) -> Date? {
        internalFormatter.date(from: text.trimmingCharacters(in: .whitespaces))
    }

    static func quote(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

enum MailboxName {
    static func decode(_ name: String) -> String {
        var result = ""
        var index = name.startIndex
        while index < name.endIndex {
            let character = name[index]
            guard character == "&", let end = name[index...].firstIndex(of: "-") else {
                result.append(character)
                index = name.index(after: index)
                continue
            }
            let encoded = name[name.index(after: index)..<end]
            if encoded.isEmpty {
                result.append("&")
            } else {
                var base64 = encoded.replacingOccurrences(of: ",", with: "/")
                while base64.count % 4 != 0 { base64 += "=" }
                if let data = Data(base64Encoded: base64), let text = String(data: data, encoding: .utf16BigEndian) {
                    result += text
                } else {
                    result += name[index...end]
                }
            }
            index = name.index(after: end)
        }
        return result
    }
}
