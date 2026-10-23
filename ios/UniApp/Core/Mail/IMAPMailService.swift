import Foundation

actor IMAPMailService: MailService {
    private var account: MailAccount?
    private var connection: IMAPConnection?
    private var selected: String?
    private var exists = 0

    func use(_ account: MailAccount) async {
        if self.account != account {
            await drop()
            self.account = account
        }
    }

    func signIn(_ account: MailAccount) async throws {
        await drop()
        self.account = account
        do {
            _ = try await connected()
        } catch {
            self.account = nil
            throw error
        }
    }

    func folders() async throws -> [MailFolder] {
        try await perform { connection in
            let responses = try await connection.command("LIST \"\" \"*\"")
            var folders = responses.compactMap(IMAPResponses.folder)
            if !folders.contains(where: { $0.role == .inbox }) {
                folders.append(MailFolder(path: "INBOX", name: "INBOX", role: .inbox, unread: 0))
            }
            for index in folders.indices {
                let status = try? await connection.command("STATUS \(IMAPResponses.quote(folders[index].path)) (UNSEEN)")
                folders[index].unread = status.flatMap(IMAPResponses.unseen) ?? 0
            }
            return folders.sorted { lhs, rhs in
                lhs.role == rhs.role ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending : lhs.role < rhs.role
            }
        }
    }

    func page(folder: String, before: Int?, size: Int) async throws -> MailPage {
        try await perform { connection in
            if before == nil || selected != folder {
                try await select(folder, on: connection)
            }
            let end = min(before ?? exists, exists)
            guard end > 0 else { return MailPage(summaries: [], nextBefore: nil) }
            let start = max(1, end - size + 1)
            let responses = try await connection.command("FETCH \(start):\(end) (UID FLAGS INTERNALDATE RFC822.SIZE ENVELOPE BODYSTRUCTURE)", timeout: 60)
            let summaries = responses
                .compactMap(IMAPResponses.fetch)
                .compactMap(IMAPResponses.summary)
                .sorted { $0.uid > $1.uid }
            return MailPage(summaries: summaries, nextBefore: start > 1 ? start - 1 : nil)
        }
    }

    func content(uid: UInt32, folder: String) async throws -> MailContent {
        try await perform { connection in
            if selected != folder {
                try await select(folder, on: connection)
            }
            let responses = try await connection.command("UID FETCH \(uid) (BODY.PEEK[])", timeout: 90)
            guard let body = responses.compactMap(IMAPResponses.fetch).compactMap({ $0["BODY[]"]?.data }).first else {
                throw MailError.server("NO BODY")
            }
            return MIME.parse(body)
        }
    }

    func setSeen(_ seen: Bool, uid: UInt32, folder: String) async throws {
        try await perform { connection in
            if selected != folder {
                try await select(folder, on: connection)
            }
            try await connection.command("UID STORE \(uid) \(seen ? "+" : "-")FLAGS.SILENT (\\Seen)")
        }
    }

    func signOut() async {
        await drop()
        account = nil
    }

    private func select(_ folder: String, on connection: IMAPConnection) async throws {
        let responses = try await connection.command("SELECT \(IMAPResponses.quote(folder))")
        exists = IMAPResponses.exists(responses) ?? 0
        selected = folder
    }

    private func connected() async throws -> IMAPConnection {
        if let connection, await connection.isOpen {
            return connection
        }
        guard let account else { throw MailError.authenticationFailed }
        let connection = IMAPConnection(host: account.host)
        try await connection.open()
        let token = Data("\0\(account.username)\0\(account.password)".utf8).base64EncodedString()
        do {
            try await connection.command("AUTHENTICATE PLAIN \(token)")
        } catch MailError.server {
            await connection.close()
            throw MailError.authenticationFailed
        }
        self.connection = connection
        selected = nil
        return connection
    }

    private func perform<T>(_ body: (IMAPConnection) async throws -> T) async throws -> T {
        do {
            return try await body(try await connected())
        } catch MailError.closed, MailError.connectionFailed, MailError.timeout {
            await drop()
            return try await body(try await connected())
        }
    }

    private func drop() async {
        if let connection {
            await connection.close()
        }
        connection = nil
        selected = nil
        exists = 0
    }
}
