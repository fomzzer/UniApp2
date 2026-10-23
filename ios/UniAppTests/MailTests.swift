import XCTest
@testable import UniApp

final class IMAPParserTests: XCTestCase {
    private func crlf(_ text: String) -> Data {
        Data(text.replacingOccurrences(of: "\n", with: "\r\n").utf8)
    }

    func testFetchSummaryWithEnvelopeAndLiteral() throws {
        let subject = "=?UTF-8?B?0JrRg9GA0YHQvtCy0LAg0YDQsNCx0L7RgtCw?="
        let response = Data("* 12 FETCH (UID 345 FLAGS (\\Seen \\Flagged) INTERNALDATE \"22-Oct-2026 14:05:00 +0300\" RFC822.SIZE 2048 ENVELOPE (\"Thu, 22 Oct 2026 14:05:00 +0300\" {\(subject.utf8.count)}\r\n\(subject) ((\"=?utf-8?Q?=D0=9F=D0=B5=D1=82=D1=8A=D1=80?=\" NIL \"petar\" \"tu-sofia.bg\")) NIL NIL ((NIL NIL \"ivan\" \"tu-sofia.bg\")) NIL NIL NIL \"<id@tu-sofia.bg>\") BODYSTRUCTURE ((\"TEXT\" \"PLAIN\" (\"CHARSET\" \"utf-8\") NIL NIL \"7BIT\" 10 1 NIL NIL NIL NIL)(\"APPLICATION\" \"PDF\" (\"NAME\" \"a.pdf\") NIL NIL \"BASE64\" 100 NIL (\"ATTACHMENT\" (\"FILENAME\" \"a.pdf\")) NIL NIL) \"MIXED\" (\"BOUNDARY\" \"b\") NIL NIL NIL))".utf8)
        let attributes = try XCTUnwrap(IMAPResponses.fetch(response))
        let summary = try XCTUnwrap(IMAPResponses.summary(attributes))
        XCTAssertEqual(summary.uid, 345)
        XCTAssertEqual(summary.subject, "Курсова работа")
        XCTAssertEqual(summary.from?.name, "Петър")
        XCTAssertEqual(summary.from?.email, "petar@tu-sofia.bg")
        XCTAssertEqual(summary.to.first?.email, "ivan@tu-sofia.bg")
        XCTAssertTrue(summary.isSeen)
        XCTAssertTrue(summary.isFlagged)
        XCTAssertTrue(summary.hasAttachments)
        XCTAssertEqual(summary.size, 2048)
        XCTAssertEqual(summary.date, IMAPResponses.internalDate("22-Oct-2026 14:05:00 +0300"))
    }

    func testBodyLiteral() throws {
        let body = "Subject: Hi\r\n\r\nHello"
        let response = Data("* 3 FETCH (UID 9 BODY[] {\(body.utf8.count)}\r\n\(body))".utf8)
        let attributes = try XCTUnwrap(IMAPResponses.fetch(response))
        XCTAssertEqual(attributes["BODY[]"]?.data, Data(body.utf8))
    }

    func testFolderListWithModifiedUTF7() throws {
        let folder = try XCTUnwrap(IMAPResponses.folder(Data("* LIST (\\HasNoChildren \\Sent) \".\" \"INBOX.&BBgENwQ,BEAEMARCBDUEPQQ4-\"".utf8)))
        XCTAssertEqual(folder.name, "Изпратени")
        XCTAssertEqual(folder.role, .sent)
        XCTAssertNil(IMAPResponses.folder(Data("* LIST (\\Noselect) \"/\" \"Public\"".utf8)))
        XCTAssertEqual(IMAPResponses.folder(Data("* LIST () \"/\" INBOX".utf8))?.role, .inbox)
    }

    func testExistsAndUnseen() {
        XCTAssertEqual(IMAPResponses.exists([Data("* FLAGS (\\Seen)".utf8), Data("* 172 EXISTS".utf8)]), 172)
        XCTAssertEqual(IMAPResponses.unseen([Data("* STATUS \"INBOX\" (UNSEEN 4)".utf8)]), 4)
    }

    func testLiteralLengthDetection() {
        let data = Data("* 1 FETCH (BODY[] {42}".utf8)
        XCTAssertEqual(IMAPConnection.literalLength(in: data, endingAt: data.count), 42)
        let plus = Data("A1 LOGIN {5+}".utf8)
        XCTAssertEqual(IMAPConnection.literalLength(in: plus, endingAt: plus.count), 5)
        let none = Data("* OK ready".utf8)
        XCTAssertNil(IMAPConnection.literalLength(in: none, endingAt: none.count))
    }

    func testQuoteEscapes() {
        XCTAssertEqual(IMAPResponses.quote("a\"b\\c"), "\"a\\\"b\\\\c\"")
    }
}

final class MIMETests: XCTestCase {
    func testMultipartAlternativeWithAttachment() throws {
        let html = Data("<p>Здравей</p>".utf8).base64EncodedString()
        let cp1251 = try XCTUnwrap("Привет".data(using: .windowsCP1251))
        let qp = cp1251.map { String(format: "=%02X", $0) }.joined()
        let message = """
        From: Test <t@tu-sofia.bg>
        Subject: =?windows-1251?Q?=CF=F0=E8=E2=E5=F2?=
        Content-Type: multipart/mixed; boundary="outer"

        --outer
        Content-Type: multipart/alternative; boundary=inner

        --inner
        Content-Type: text/plain; charset=windows-1251
        Content-Transfer-Encoding: quoted-printable

        \(qp)
        --inner
        Content-Type: text/html; charset="utf-8"
        Content-Transfer-Encoding: base64

        \(html)
        --inner--

        --outer
        Content-Type: application/pdf
        Content-Disposition: attachment;
         filename*=UTF-8''%D0%9F%D1%80%D0%BE%D0%B3%D1%80%D0%B0%D0%BC%D0%B0.pdf
        Content-Transfer-Encoding: base64

        JVBERi0xLjQ=
        --outer--
        """.replacingOccurrences(of: "\n", with: "\r\n")
        let content = MIME.parse(Data(message.utf8))
        XCTAssertEqual(content.html, "<p>Здравей</p>")
        XCTAssertEqual(content.text, "Привет")
        XCTAssertEqual(content.attachments.count, 1)
        XCTAssertEqual(content.attachments.first?.filename, "Програма.pdf")
        XCTAssertEqual(content.attachments.first?.data, Data("%PDF-1.4".utf8))
        XCTAssertEqual(MIME.decodeHeader("=?windows-1251?Q?=CF=F0=E8=E2=E5=F2?="), "Привет")
    }

    func testEncodedWordsJoinAcrossWhitespace() {
        XCTAssertEqual(MIME.decodeHeader("=?UTF-8?Q?=D0=94=D0=B5?= =?UTF-8?Q?=D0=BA=D0=B0=D0=BD?= ФКСТ"), "Декан ФКСТ")
        XCTAssertEqual(MIME.decodeHeader("Plain subject"), "Plain subject")
    }

    func testInlineImageBecomesDataURI() {
        let message = """
        Content-Type: multipart/related; boundary=rel

        --rel
        Content-Type: text/html; charset=utf-8

        <img src="cid:logo@x">
        --rel
        Content-Type: image/png
        Content-ID: <logo@x>
        Content-Transfer-Encoding: base64

        iVBORw0KGgo=
        --rel--
        """.replacingOccurrences(of: "\n", with: "\r\n")
        let content = MIME.parse(Data(message.utf8))
        XCTAssertEqual(content.html, "<img src=\"data:image/png;base64,iVBORw0KGgo=\">")
        XCTAssertTrue(content.attachments.isEmpty)
    }

    func testSinglePartPlainText() {
        let message = "Subject: x\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: quoted-printable\r\n\r\n=D0=97=D0=B4=D1=80=D0=B0=D0=B2=D0=B5=D0=B9=\r\n!"
        XCTAssertEqual(MIME.parse(Data(message.utf8)).text, "Здравей!")
    }

    func testHeaderDate() {
        XCTAssertNotNil(MIME.headerDate("Thu, 22 Oct 2026 14:05:00 +0300 (EEST)"))
    }
}
