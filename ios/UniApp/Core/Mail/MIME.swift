import Foundation

enum MIME {
    struct Part {
        var headers: [String: String]
        var body: Data
    }

    static func parse(_ message: Data) -> MailContent {
        var html: String?
        var text: String?
        var attachments: [MailAttachment] = []
        var inline: [String: (type: String, data: Data)] = [:]
        collect(split(message), html: &html, text: &text, attachments: &attachments, inline: &inline)
        if var page = html, !inline.isEmpty {
            for (id, image) in inline {
                page = page.replacingOccurrences(of: "cid:\(id)", with: "data:\(image.type);base64,\(image.data.base64EncodedString())")
            }
            html = page
        }
        return MailContent(html: html, text: text, attachments: attachments)
    }

    private static func collect(
        _ part: Part,
        html: inout String?,
        text: inout String?,
        attachments: inout [MailAttachment],
        inline: inout [String: (type: String, data: Data)]
    ) {
        let (type, parameters) = contentType(part.headers["content-type"] ?? "text/plain")
        if type.hasPrefix("multipart/"), let boundary = parameters["boundary"] {
            for child in multipart(part.body, boundary: boundary) {
                collect(split(child), html: &html, text: &text, attachments: &attachments, inline: &inline)
            }
            return
        }
        let disposition = contentType(part.headers["content-disposition"] ?? "")
        let filename = disposition.parameters["filename"] ?? parameters["name"]
        let data = transferDecode(part.body, encoding: part.headers["content-transfer-encoding"])
        let isAttachment = disposition.type == "attachment" || (filename != nil && !type.hasPrefix("text/"))
        if !isAttachment && type == "text/html" && html == nil {
            html = decodeText(data, charset: parameters["charset"])
            return
        }
        if !isAttachment && type == "text/plain" && text == nil {
            text = decodeText(data, charset: parameters["charset"])
            return
        }
        if let id = part.headers["content-id"]?.trimmingCharacters(in: CharacterSet(charactersIn: "<> ")), type.hasPrefix("image/"), disposition.type != "attachment" {
            inline[id] = (type, data)
            return
        }
        guard isAttachment || filename != nil || type == "message/rfc822" else { return }
        let name = filename.map(decodeHeader) ?? (type == "message/rfc822" ? "message.eml" : "attachment")
        attachments.append(MailAttachment(id: attachments.count, filename: name, mimeType: type, data: data))
    }

    static func split(_ data: Data) -> Part {
        let bytes = [UInt8](data)
        var headerEnd = bytes.count
        var bodyStart = bytes.count
        var index = 0
        while index < bytes.count {
            if bytes[index] == 10 {
                if index + 1 < bytes.count && bytes[index + 1] == 10 {
                    headerEnd = index
                    bodyStart = index + 2
                    break
                }
                if index + 2 < bytes.count && bytes[index + 1] == 13 && bytes[index + 2] == 10 {
                    headerEnd = index
                    bodyStart = index + 3
                    break
                }
            }
            index += 1
        }
        if bytes.starts(with: [13, 10]) {
            headerEnd = 0
            bodyStart = 2
        } else if bytes.first == 10 {
            headerEnd = 0
            bodyStart = 1
        }
        let headerText = headerString(Data(bytes[0..<min(headerEnd, bytes.count)]))
        let body = bodyStart < bytes.count ? Data(bytes[bodyStart...]) : Data()
        return Part(headers: headers(headerText), body: body)
    }

    static func headers(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        var current: (String, String)?
        for rawLine in text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : String(rawLine)
            if let first = line.first, first == " " || first == "\t", let pending = current {
                current = (pending.0, pending.1 + " " + line.trimmingCharacters(in: .whitespaces))
                continue
            }
            if let pending = current, result[pending.0] == nil {
                result[pending.0] = pending.1
            }
            guard let colon = line.firstIndex(of: ":") else {
                current = nil
                continue
            }
            current = (line[..<colon].trimmingCharacters(in: .whitespaces).lowercased(), line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
        }
        if let pending = current, result[pending.0] == nil {
            result[pending.0] = pending.1
        }
        return result
    }

    static func headerString(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1251) ?? String(decoding: data, as: UTF8.self)
    }

    static func contentType(_ value: String) -> (type: String, parameters: [String: String]) {
        let pieces = splitParameters(value)
        let type = (pieces.first ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        var simple: [String: String] = [:]
        var extended: [String: [(Int, String, Bool)]] = [:]
        for piece in pieces.dropFirst() {
            guard let equals = piece.firstIndex(of: "=") else { continue }
            var key = piece[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            var value = piece[piece.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"")
            }
            let encoded = key.hasSuffix("*")
            if encoded { key.removeLast() }
            if let star = key.lastIndex(of: "*"), let order = Int(key[key.index(after: star)...]) {
                extended[String(key[..<star]), default: []].append((order, value, encoded))
            } else if encoded {
                extended[key, default: []].append((0, value, true))
            } else {
                simple[key] = value
            }
        }
        for (key, chunks) in extended {
            var charset = "utf-8"
            var bytes = Data()
            for (position, chunk) in chunks.sorted(by: { $0.0 < $1.0 }).enumerated() {
                var value = chunk.1
                if chunk.2 {
                    if position == 0 {
                        let fields = value.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false)
                        if fields.count == 3 {
                            charset = fields[0].isEmpty ? charset : String(fields[0])
                            value = String(fields[2])
                        }
                    }
                    bytes.append(percentDecode(value))
                } else {
                    bytes.append(Data(value.utf8))
                }
            }
            simple[key] = decodeText(bytes, charset: charset)
        }
        return (type, simple)
    }

    private static func splitParameters(_ value: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quoted = false
        var previous: Character?
        for character in value {
            if character == "\"" && previous != "\\" { quoted.toggle() }
            if character == ";" && !quoted {
                result.append(current)
                current = ""
            } else {
                current.append(character)
            }
            previous = character
        }
        result.append(current)
        return result
    }

    private static func percentDecode(_ value: String) -> Data {
        var output = Data()
        let bytes = Array(value.utf8)
        var index = 0
        while index < bytes.count {
            if bytes[index] == UInt8(ascii: "%"), index + 2 < bytes.count, let byte = UInt8(String(decoding: bytes[(index + 1)...(index + 2)], as: UTF8.self), radix: 16) {
                output.append(byte)
                index += 3
            } else {
                output.append(bytes[index])
                index += 1
            }
        }
        return output
    }

    static func multipart(_ body: Data, boundary: String) -> [Data] {
        let bytes = [UInt8](body)
        let marker = Array("--\(boundary)".utf8)
        var starts: [(Int, Int, Bool)] = []
        var lineStart = 0
        while lineStart < bytes.count {
            var lineEnd = lineStart
            while lineEnd < bytes.count && bytes[lineEnd] != 10 { lineEnd += 1 }
            if lineEnd - lineStart >= marker.count && Array(bytes[lineStart..<(lineStart + marker.count)]) == marker {
                let after = lineStart + marker.count
                let closing = after + 1 < bytes.count && bytes[after] == UInt8(ascii: "-") && bytes[after + 1] == UInt8(ascii: "-")
                starts.append((lineStart, min(lineEnd + 1, bytes.count), closing))
                if closing { break }
            }
            lineStart = lineEnd + 1
        }
        var parts: [Data] = []
        for (index, delimiter) in starts.enumerated() where !delimiter.2 && index + 1 < starts.count {
            var end = starts[index + 1].0
            if end > delimiter.1 && bytes[end - 1] == 10 { end -= 1 }
            if end > delimiter.1 && bytes[end - 1] == 13 { end -= 1 }
            parts.append(Data(bytes[delimiter.1..<max(delimiter.1, end)]))
        }
        if let last = starts.last, !last.2, last.1 < bytes.count {
            parts.append(Data(bytes[last.1...]))
        }
        return parts
    }

    static func transferDecode(_ data: Data, encoding: String?) -> Data {
        switch encoding?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "base64":
            let cleaned = String(decoding: data, as: UTF8.self).filter { !$0.isWhitespace }
            var padded = cleaned
            while padded.count % 4 != 0 { padded += "=" }
            return Data(base64Encoded: padded) ?? data
        case "quoted-printable":
            return quotedPrintable(data)
        default:
            return data
        }
    }

    static func quotedPrintable(_ data: Data, underscoreIsSpace: Bool = false) -> Data {
        let bytes = [UInt8](data)
        var output = Data()
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: "=") {
                if index + 1 < bytes.count && bytes[index + 1] == 10 {
                    index += 2
                    continue
                }
                if index + 2 < bytes.count && bytes[index + 1] == 13 && bytes[index + 2] == 10 {
                    index += 3
                    continue
                }
                if index + 2 < bytes.count, let value = UInt8(String(decoding: bytes[(index + 1)...(index + 2)], as: UTF8.self), radix: 16) {
                    output.append(value)
                    index += 3
                    continue
                }
            }
            output.append(underscoreIsSpace && byte == UInt8(ascii: "_") ? 32 : byte)
            index += 1
        }
        return output
    }

    static func encoding(for charset: String?) -> String.Encoding? {
        guard let charset = charset?.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")).lowercased(), !charset.isEmpty else { return nil }
        switch charset {
        case "utf-8", "utf8": return .utf8
        case "us-ascii", "ascii": return .utf8
        case "windows-1251", "cp1251": return .windowsCP1251
        default:
            let value = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
            guard value != kCFStringEncodingInvalidId else { return nil }
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(value))
        }
    }

    static func decodeText(_ data: Data, charset: String?) -> String {
        if let encoding = encoding(for: charset), let text = String(data: data, encoding: encoding) {
            return text
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1251) ?? String(decoding: data, as: UTF8.self)
    }

    private static let encodedWord = try? NSRegularExpression(pattern: "=\\?([^?]+)\\?([BbQq])\\?([^?]*)\\?=")

    static func decodeHeader(_ value: String) -> String {
        guard let encodedWord, value.contains("=?") else { return value }
        let source = value as NSString
        let matches = encodedWord.matches(in: value, range: NSRange(location: 0, length: source.length))
        guard !matches.isEmpty else { return value }
        var result = ""
        var cursor = 0
        for match in matches {
            let gap = source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            if cursor == 0 || !gap.allSatisfy(\.isWhitespace) {
                result += gap
            }
            let charset = source.substring(with: match.range(at: 1)).split(separator: "*").first.map(String.init)
            let mode = source.substring(with: match.range(at: 2)).uppercased()
            let payload = source.substring(with: match.range(at: 3))
            let bytes: Data
            if mode == "B" {
                var padded = payload
                while padded.count % 4 != 0 { padded += "=" }
                bytes = Data(base64Encoded: padded) ?? Data(payload.utf8)
            } else {
                bytes = quotedPrintable(Data(payload.utf8), underscoreIsSpace: true)
            }
            result += decodeText(bytes, charset: charset)
            cursor = match.range.location + match.range.length
        }
        result += source.substring(from: cursor)
        return result
    }

    private static let headerFormatters: [DateFormatter] = ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm Z"].map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }

    static func headerDate(_ value: String) -> Date? {
        let cleaned = value.replacingOccurrences(of: "\\s*\\(.*\\)\\s*$", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        for formatter in headerFormatters {
            if let date = formatter.date(from: cleaned) { return date }
        }
        return nil
    }
}
