import Foundation

struct MailAccount: Codable, Hashable, Sendable {
    var username: String
    var password: String
    var host: String

    static let hosts = ["tusmail.tu-sofia.bg", "mail.tu-sofia.bg"]
}

struct MailFolder: Hashable, Identifiable, Sendable {
    enum Role: Int, Sendable, Comparable {
        case inbox
        case drafts
        case sent
        case archive
        case junk
        case trash
        case other

        init(attributes: Set<String>, path: String, name: String) {
            let lowered = name.lowercased()
            if path.uppercased() == "INBOX" {
                self = .inbox
            } else if attributes.contains("\\sent") || ["sent", "sent items", "sent messages", "изпратени", "отправленные"].contains(lowered) {
                self = .sent
            } else if attributes.contains("\\drafts") || ["drafts", "чернови", "черновики"].contains(lowered) {
                self = .drafts
            } else if attributes.contains("\\trash") || ["trash", "deleted items", "deleted messages", "кошче", "корзина"].contains(lowered) {
                self = .trash
            } else if attributes.contains("\\junk") || ["junk", "spam", "спам", "нежелана поща"].contains(lowered) {
                self = .junk
            } else if attributes.contains("\\archive") || ["archive", "архив"].contains(lowered) {
                self = .archive
            } else {
                self = .other
            }
        }

        static func < (lhs: Role, rhs: Role) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var systemImage: String {
            switch self {
            case .inbox: "tray.fill"
            case .drafts: "doc.text.fill"
            case .sent: "paperplane.fill"
            case .archive: "archivebox.fill"
            case .junk: "xmark.bin.fill"
            case .trash: "trash.fill"
            case .other: "folder.fill"
            }
        }
    }

    let path: String
    let name: String
    let role: Role
    var unread: Int

    var id: String { path }

    var showsRecipients: Bool {
        role == .sent || role == .drafts
    }
}

struct MailAddress: Hashable, Sendable {
    let name: String?
    let email: String

    var display: String {
        name ?? email
    }

    var initials: String {
        let source = name ?? email
        let words = source.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "@" || $0 == "_" }).prefix(2)
        let letters = words.compactMap(\.first).map { String($0).uppercased() }.joined()
        return letters.isEmpty ? "?" : letters
    }
}

struct MailSummary: Hashable, Identifiable, Sendable {
    let uid: UInt32
    var subject: String
    var from: MailAddress?
    var to: [MailAddress]
    var cc: [MailAddress]
    var date: Date
    var isSeen: Bool
    var isFlagged: Bool
    var hasAttachments: Bool
    var size: Int

    var id: UInt32 { uid }
}

struct MailAttachment: Hashable, Identifiable, Sendable {
    let id: Int
    let filename: String
    let mimeType: String
    let data: Data
}

struct MailContent: Hashable, Sendable {
    let html: String?
    let text: String?
    let attachments: [MailAttachment]
}

struct MailPage: Sendable {
    let summaries: [MailSummary]
    let nextBefore: Int?
}

protocol MailService: Sendable {
    func use(_ account: MailAccount) async
    func signIn(_ account: MailAccount) async throws
    func folders() async throws -> [MailFolder]
    func page(folder: String, before: Int?, size: Int) async throws -> MailPage
    func content(uid: UInt32, folder: String) async throws -> MailContent
    func setSeen(_ seen: Bool, uid: UInt32, folder: String) async throws
    func signOut() async
}
