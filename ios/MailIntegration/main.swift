import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

func check(_ condition: Bool, _ message: String) {
    guard condition else {
        print("FAIL: \(message)")
        exit(1)
    }
    print("ok: \(message)")
}

guard CommandLine.arguments.count > 2, let base = URL(string: CommandLine.arguments[1]) else {
    print("usage: check <roundcube url> <user>")
    exit(2)
}
let user = CommandLine.arguments[2]
let client = RoundcubeClient(base: base)

do {
    try await client.login(username: user, password: "secret")
    print("ok: login")

    let fresh = try await client.compose(.new)
    check(!fresh.id.isEmpty && !fresh.token.isEmpty, "compose session \(fresh.id)")
    check(!fresh.identity.isEmpty, "identity \(fresh.identity)")
    check(fresh.storeTarget != nil, "store target \(fresh.storeTarget ?? "-")")
    try await client.send(RoundcubeMessage(to: user, cc: "", subject: "Проверка UniApp", body: "Здравей,\nтова е тест & <проверка>."), using: fresh)
    print("ok: sent new message")
    try await Task.sleep(nanoseconds: 1_500_000_000)

    let reply = try await client.compose(.reply(uid: 1, mailbox: "INBOX", all: false))
    check(reply.subject.hasPrefix("Re:"), "reply subject \(reply.subject)")
    check(reply.to.contains(user), "reply recipient \(reply.to)")
    check(reply.body.contains("това е тест & <проверка>."), "reply quote")
    try await client.send(RoundcubeMessage(to: reply.to, cc: "", subject: reply.subject, body: "Отговор\n\n" + reply.body), using: reply)
    print("ok: sent reply")

    let forward = try await client.compose(.forward(uid: 1, mailbox: "INBOX"))
    check(forward.subject.lowercased().hasPrefix("fwd:"), "forward subject \(forward.subject)")
    try await client.send(RoundcubeMessage(to: user, cc: "", subject: forward.subject, body: forward.body), using: forward)
    print("ok: sent forward")

    await client.expireSession()
    let late = try await client.compose(.new)
    try await client.send(RoundcubeMessage(to: user, cc: "", subject: "След изтекла сесия", body: "ok"), using: late)
    print("ok: sent after the session expired")

    do {
        try await client.send(RoundcubeMessage(to: "not an address", cc: "", subject: "x", body: "x"), using: try await client.compose(.new))
        check(false, "invalid recipient must be rejected")
    } catch RoundcubeError.rejected(let message) {
        check(!message.isEmpty, "rejected: \(message)")
    }
} catch {
    print("FAIL: \(error)")
    exit(1)
}
