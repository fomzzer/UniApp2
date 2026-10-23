#if DEBUG
import Foundation

actor FixtureMailService: MailService {
    private var seen: Set<UInt32> = [3, 4, 5, 6, 7, 8]

    func use(_ account: MailAccount) async {}

    func signIn(_ account: MailAccount) async throws {
        try await Task.sleep(for: .milliseconds(700))
        guard !account.password.isEmpty else { throw MailError.authenticationFailed }
    }

    func folders() async throws -> [MailFolder] {
        [
            MailFolder(path: "INBOX", name: "INBOX", role: .inbox, unread: 2 - min(2, seen.intersection([1, 2]).count)),
            MailFolder(path: "Drafts", name: "Чернови", role: .drafts, unread: 0),
            MailFolder(path: "Sent", name: "Изпратени", role: .sent, unread: 0),
            MailFolder(path: "Junk", name: "Спам", role: .junk, unread: 0),
            MailFolder(path: "Trash", name: "Кошче", role: .trash, unread: 0),
        ]
    }

    func page(folder: String, before: Int?, size: Int) async throws -> MailPage {
        try await Task.sleep(for: .milliseconds(400))
        guard folder == "INBOX" else { return MailPage(summaries: [], nextBefore: nil) }
        let now = Date()
        let hour: TimeInterval = 3600
        let entries: [(UInt32, String, String, String, TimeInterval, Bool)] = [
            (1, "Учебен отдел", "ucheben@tu-sofia.bg", "Промяна в графика на изпитната сесия", 0.6 * hour, false),
            (2, "Доц. д-р Петър Георгиев", "pgeorgiev@tu-sofia.bg", "Курсова работа по Бази от данни — краен срок", 3 * hour, true),
            (3, "Библиотека ТУ-София", "library@tu-sofia.bg", "Напомняне за връщане на книги", 26 * hour, false),
            (4, "Студентски съвет", "ss@tu-sofia.bg", "Покана: Ден на отворените врати 2026", 30 * hour, false),
            (5, "TUSmail", "tusmail@tu-sofia.bg", "Вашата пощенска кутия е почти пълна", 4 * 24 * hour, false),
            (6, "Мария Иванова", "mivanova@tu-sofia.bg", "Re: Лабораторно упражнение 4", 6 * 24 * hour, false),
            (7, "Деканат ФКСТ", "dekanat.fkst@tu-sofia.bg", "Записване за избираеми дисциплини", 12 * 24 * hour, true),
            (8, "Кариерен център", "career@tu-sofia.bg", "Стажантска програма — зимен прием", 20 * 24 * hour, false),
        ]
        let summaries = entries.map { entry in
            MailSummary(
                uid: entry.0,
                subject: entry.3,
                from: MailAddress(name: entry.1, email: entry.2),
                to: [MailAddress(name: "Иван Петров Иванов", email: "ivan@tu-sofia.bg")],
                cc: [],
                date: now.addingTimeInterval(-entry.4),
                isSeen: seen.contains(entry.0),
                isFlagged: false,
                hasAttachments: entry.5,
                size: 4096
            )
        }
        return MailPage(summaries: summaries, nextBefore: nil)
    }

    func content(uid: UInt32, folder: String) async throws -> MailContent {
        try await Task.sleep(for: .milliseconds(500))
        if uid == 2 {
            let html = """
            <p>Здравейте, колеги,</p>
            <p>Напомням, че крайният срок за предаване на <b>курсовата работа по Бази от данни</b> е <b>15 ноември</b>.</p>
            <ul><li>Схема на базата данни (ER диаграма)</li><li>SQL скриптове за създаване и попълване</li><li>Кратък доклад до 10 страници</li></ul>
            <p>Изискванията са в прикачения файл. Въпроси — на <a href="mailto:pgeorgiev@tu-sofia.bg">pgeorgiev@tu-sofia.bg</a>.</p>
            <p>Поздрави,<br>доц. д-р Петър Георгиев</p>
            """
            let attachment = MailAttachment(id: 0, filename: "Изисквания_курсова_работа.txt", mimeType: "text/plain", data: Data("Изисквания към курсовата работа.".utf8))
            return MailContent(html: html, text: nil, attachments: [attachment])
        }
        let text = """
        Уважаеми студенти,

        Графикът на изпитната сесия е обновен. Актуалната версия е публикувана на https://tu-sofia.bg.

        Поздрави,
        Учебен отдел
        """
        return MailContent(html: nil, text: text, attachments: [])
    }

    func setSeen(_ value: Bool, uid: UInt32, folder: String) async throws {
        if value {
            seen.insert(uid)
        } else {
            seen.remove(uid)
        }
    }

    func signOut() async {}
}
#endif
