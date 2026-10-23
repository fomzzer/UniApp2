import Foundation

actor IMAPMailService: MailService {
    private var account: MailAccount?
    private var connection: IMAPConnection?
    private var selected: String?
    private var exists = 0
    private var webmail: RoundcubeClient?
    private var webmailReady = false

    func use(_ account: MailAccount) async {
        if self.account != account {
            await drop()
            self.account = account
            webmail = nil
            webmailReady = false
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

    func setFlagged(_ flagged: Bool, uid: UInt32, folder: String) async throws {
        try await perform { connection in
            if selected != folder {
                try await select(folder, on: connection)
            }
            try await connection.command("UID STORE \(uid) \(flagged ? "+" : "-")FLAGS.SILENT (\\Flagged)")
        }
    }

    func move(uid: UInt32, from folder: String, to target: String) async throws {
        try await perform { connection in
            try await transfer(uid: uid, from: folder, to: target, on: connection)
        }
    }

    func delete(uid: UInt32, folder: String, trash: String?) async throws {
        try await perform { connection in
            if let trash, trash != folder {
                try await transfer(uid: uid, from: folder, to: trash, on: connection)
                return
            }
            if trash == nil, folder != MailFolder.trashPath {
                _ = try? await connection.command("CREATE \(IMAPResponses.quote(MailFolder.trashPath))")
                _ = try? await connection.command("SUBSCRIBE \(IMAPResponses.quote(MailFolder.trashPath))")
                try await transfer(uid: uid, from: folder, to: MailFolder.trashPath, on: connection)
                return
            }
            if selected != folder {
                try await select(folder, on: connection)
            }
            try await connection.command("UID STORE \(uid) +FLAGS.SILENT (\\Deleted)")
            try await expunge(uid, on: connection)
        }
    }

    func compose(_ intent: RoundcubeCompose.Intent) async throws -> RoundcubeCompose {
        try await mapWebmail {
            try await $0.compose(intent)
        }
    }

    func send(_ message: RoundcubeMessage, using draft: RoundcubeCompose) async throws {
        try await mapWebmail {
            try await $0.send(message, using: draft)
        }
    }

    func signOut() async {
        await drop()
        await webmail?.logout()
        webmail = nil
        webmailReady = false
        account = nil
    }

    private func mapWebmail<T: Sendable>(_ body: (RoundcubeClient) async throws -> T) async throws -> T {
        guard let account, let base = RoundcubeClient.base(forIMAPHost: account.host) else { throw RoundcubeError.authenticationFailed }
        let client = webmail ?? RoundcubeClient(base: base)
        webmail = client
        if !webmailReady {
            try await client.login(username: account.username, password: account.password)
            webmailReady = true
        }
        return try await body(client)
    }

    private func transfer(uid: UInt32, from folder: String, to target: String, on connection: IMAPConnection) async throws {
        if selected != folder {
            try await select(folder, on: connection)
        }
        do {
            try await connection.command("UID MOVE \(uid) \(IMAPResponses.quote(target))")
        } catch MailError.server {
            try await connection.command("UID COPY \(uid) \(IMAPResponses.quote(target))")
            try await connection.command("UID STORE \(uid) +FLAGS.SILENT (\\Deleted)")
            try await expunge(uid, on: connection)
        }
        selected = nil
    }

    private func expunge(_ uid: UInt32, on connection: IMAPConnection) async throws {
        do {
            try await connection.command("UID EXPUNGE \(uid)")
        } catch MailError.server {
            try await connection.command("EXPUNGE")
        }
        selected = nil
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
