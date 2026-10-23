import QuickLook
import SwiftUI
import WebKit

struct MailMessageView: View {
    let summary: MailSummary

    @Environment(MailStore.self) private var mail
    @Environment(\.strings) private var s
    @Environment(\.openURL) private var openURL

    @State private var content: MailContent?
    @State private var failure: MailError?
    @State private var preview: URL?
    @State private var bodyHeight: CGFloat = 1

    private var current: MailSummary {
        mail.summary(uid: summary.uid) ?? summary
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let content {
                    if !content.attachments.isEmpty {
                        attachments(content.attachments)
                            .transition(.opacity)
                    }
                    messageBody(content)
                        .transition(.opacity)
                } else if let failure {
                    ContentUnavailableView {
                        Label(s.mailOpenFailed, systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(s.mailMessage(for: failure))
                    } actions: {
                        Button(s.retry) { Task { await load() } }
                            .buttonStyle(.glassProminent)
                            .tint(Theme.accent)
                    }
                    .foregroundStyle(.white)
                } else {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .animation(.smooth(duration: 0.35), value: content)
            .animation(.smooth(duration: 0.35), value: failure)
        }
        .background { AppBackground(glow: 0.6) }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .safeAreaBar(edge: .top) {
            GlassNavigationBar {
                EmptyView()
            } trailing: {
                HStack(spacing: 0) {
                    GlassBarButton(title: current.isSeen ? s.mailMarkUnread : s.mailMarkRead, systemImage: current.isSeen ? "envelope.badge" : "envelope.open") {
                        let target = current
                        Task { await mail.setSeen(!target.isSeen, for: target) }
                    }
                    .contentTransition(.symbolEffect(.replace))
                    GlassBarButton(title: s.mailReplyWeb, systemImage: "arrowshape.turn.up.left") {
                        if let url = URL(string: "https://tusmail.tu-sofia.bg/") { openURL(url) }
                    }
                }
                .padding(.horizontal, 4)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
        }
        .sensoryFeedback(.selection, trigger: current.isSeen)
        .quickLookPreview($preview)
        .task { await load() }
    }

    private var header: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text(current.subject.isEmpty ? s.mailNoSubject : current.subject)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                HStack(spacing: 12) {
                    SenderAvatar(address: current.from, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(current.from?.display ?? s.mailNoSender)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if let email = current.from?.email, current.from?.name != nil {
                            Text(email)
                                .font(.caption)
                                .foregroundStyle(Theme.accentSoft)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(current.date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(s.language.locale)))
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.trailing)
                }
                if !current.to.isEmpty || !current.cc.isEmpty {
                    Divider().overlay(Theme.separator)
                    VStack(alignment: .leading, spacing: 6) {
                        if !current.to.isEmpty {
                            recipients(s.mailTo, current.to)
                        }
                        if !current.cc.isEmpty {
                            recipients(s.mailCc, current.cc)
                        }
                    }
                }
            }
        }
    }

    private func recipients(_ title: String, _ addresses: [MailAddress]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
            Text(addresses.map(\.display).joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(3)
        }
    }

    private func attachments(_ items: [MailAttachment]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: s.mailAttachments)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(items) { item in
                        Button {
                            preview = Self.file(for: item, uid: current.uid)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: Self.icon(for: item))
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.white)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.filename)
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Text(item.data.count.formatted(.byteCount(style: .file)))
                                        .font(.caption2)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                            .frame(maxWidth: 220, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .glassEffect(.regular.tint(Theme.accent.opacity(0.3)), in: .capsule)
                        }
                        .buttonStyle(.pressable)
                        .accessibilityIdentifier("mail.attachment")
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private func messageBody(_ content: MailContent) -> some View {
        if let html = content.html {
            MailHTMLView(html: html, height: $bodyHeight)
                .frame(height: bodyHeight)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .fill(Theme.deepBlue.opacity(0.35))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                        }
                }
        } else {
            GlassCard(padding: 18) {
                Text(Self.linkified(content.text ?? ""))
                    .font(.body)
                    .foregroundStyle(.white)
                    .tint(Theme.accentSoft)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func load() async {
        failure = nil
        do {
            let loaded = try await mail.content(for: current)
            content = loaded
            if !current.isSeen {
                await mail.setSeen(true, for: current)
            }
        } catch {
            failure = error as? MailError ?? .connectionFailed
        }
    }

    private static func icon(for item: MailAttachment) -> String {
        let name = item.filename.lowercased()
        if item.mimeType.hasPrefix("image/") { return "photo.fill" }
        if name.hasSuffix(".pdf") { return "doc.richtext.fill" }
        if name.hasSuffix(".zip") || name.hasSuffix(".rar") || name.hasSuffix(".7z") { return "doc.zipper" }
        if name.hasSuffix(".xls") || name.hasSuffix(".xlsx") { return "tablecells.fill" }
        return "doc.fill"
    }

    private static func file(for item: MailAttachment, uid: UInt32) -> URL? {
        let directory = FileManager.default.temporaryDirectory.appending(path: "mail-\(uid)-\(item.id)", directoryHint: .isDirectory)
        let disallowed = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = item.filename.components(separatedBy: disallowed).joined(separator: "_")
        let url = directory.appending(path: cleaned.isEmpty ? "attachment" : cleaned)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try item.data.write(to: url, options: [.atomic, .completeFileProtection])
            return url
        } catch {
            return nil
        }
    }

    static func linkified(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return attributed }
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let url = match.url,
                  let range = Range(match.range, in: text),
                  let lower = AttributedString.Index(range.lowerBound, within: attributed),
                  let upper = AttributedString.Index(range.upperBound, within: attributed) else { continue }
            attributed[lower..<upper].link = url
            attributed[lower..<upper].foregroundColor = Theme.accentSoft
        }
        return attributed
    }
}

struct MailHTMLView: UIViewRepresentable {
    let html: String
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.dataDetectorTypes = [.link, .phoneNumber]
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.navigationDelegate = context.coordinator
        context.coordinator.observe(view)
        view.loadHTMLString(Self.document(html), baseURL: nil)
        context.coordinator.loaded = html
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.height = $height
        if context.coordinator.loaded != html {
            context.coordinator.loaded = html
            view.loadHTMLString(Self.document(html), baseURL: nil)
        }
    }

    static func document(_ html: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <style>
        :root { color-scheme: dark; }
        html, body { margin: 0; padding: 0; background: transparent !important; }
        body { font: -apple-system-body; font-size: 16px; line-height: 1.45; color: #EAF0FB; word-wrap: break-word; overflow-wrap: anywhere; -webkit-text-size-adjust: 100%; }
        * { background-color: transparent !important; background-image: none !important; color: #EAF0FB !important; border-color: rgba(255,255,255,0.14) !important; max-width: 100%; }
        a, a * { color: #7DADFF !important; }
        img { max-width: 100% !important; height: auto !important; border-radius: 8px; }
        table { width: auto !important; max-width: 100% !important; }
        td, th { word-break: break-word; }
        pre, code { white-space: pre-wrap; font-family: ui-monospace, Menlo, monospace; font-size: 14px; }
        blockquote { margin: 8px 0; padding-left: 12px; border-left: 3px solid rgba(125,173,255,0.6) !important; }
        hr { border: none; border-top: 1px solid rgba(255,255,255,0.14) !important; }
        </style></head><body>\(neutralized(html))</body></html>
        """
    }

    private static let styleAttribute = try? NSRegularExpression(pattern: #"(?is)\bstyle\s*=\s*("[^"]*"|'[^']*')"#)
    private static let styleBlock = try? NSRegularExpression(pattern: #"(?is)<style\b[^>]*>.*?</style>"#)
    private static let paintDeclaration = try? NSRegularExpression(pattern: #"(?i)(?<![-\w])(background(-color|-image)?|color)\s*:(url\([^)]*\)|[^;}"'])*;?"#)
    private static let paintAttribute = try? NSRegularExpression(pattern: #"(?i)\s(bgcolor|background)\s*=\s*("[^"]*"|'[^']*'|[^\s>]+)"#)

    static func neutralized(_ html: String) -> String {
        guard let paintDeclaration else { return html }
        var result = html
        for pattern in [styleAttribute, styleBlock].compactMap({ $0 }) {
            result = replacing(pattern, in: result) { match in
                let source = match as NSString
                return paintDeclaration.stringByReplacingMatches(in: match, range: NSRange(location: 0, length: source.length), withTemplate: "")
            }
        }
        if let paintAttribute {
            result = paintAttribute.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: (result as NSString).length), withTemplate: "")
        }
        return result
    }

    private static func replacing(_ pattern: NSRegularExpression, in text: String, transform: (String) -> String) -> String {
        let source = text as NSString
        var result = ""
        var cursor = 0
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            result += transform(source.substring(with: match.range))
            cursor = match.range.location + match.range.length
        }
        return result + source.substring(from: cursor)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var height: Binding<CGFloat>
        var loaded: String?
        private var observation: NSKeyValueObservation?

        init(height: Binding<CGFloat>) {
            self.height = height
        }

        func observe(_ view: WKWebView) {
            observation = view.scrollView.observe(\.contentSize, options: [.new]) { [weak self] scrollView, _ in
                let value = ceil(scrollView.contentSize.height)
                DispatchQueue.main.async {
                    guard let self, value > 0, abs(self.height.wrappedValue - value) > 0.5 else { return }
                    self.height.wrappedValue = value
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .other {
                return .allow
            }
            if let url = navigationAction.request.url {
                await UIApplication.shared.open(url)
            }
            return .cancel
        }
    }
}
