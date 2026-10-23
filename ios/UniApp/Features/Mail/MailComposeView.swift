import SwiftUI

struct ComposeRequest: Identifiable {
    let id = UUID()
    let intent: RoundcubeCompose.Intent
}

struct MailComposeView: View {
    let intent: RoundcubeCompose.Intent

    @Environment(MailStore.self) private var mail
    @Environment(\.strings) private var s
    @Environment(\.dismiss) private var dismiss

    @State private var draft: RoundcubeCompose?
    @State private var to = ""
    @State private var cc = ""
    @State private var subject = ""
    @State private var text = ""
    @State private var showCc = false
    @State private var isSending = false
    @State private var failure: String?
    @State private var loadError: String?
    @State private var sentTrigger = 0
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case to
        case cc
        case subject
        case body
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if draft != nil {
                    form
                        .transition(.opacity)
                } else if let loadError {
                    ContentUnavailableView {
                        Label(s.mailSendFailed, systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button(s.retry) { Task { await prepare() } }
                            .appProminentButton()
                            .tint(Theme.accent)
                    }
                    .foregroundStyle(.white)
                    .transition(.opacity)
                } else {
                    ProgressView(s.mailPreparing)
                        .tint(.white)
                        .foregroundStyle(Theme.textSecondary)
                        .transition(.opacity)
                }
            }
            .animation(.smooth(duration: 0.35), value: draft)
            .animation(.smooth(duration: 0.35), value: loadError)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { AppBackground(glow: 0.55) }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(s.cancel, systemImage: "xmark") { dismiss() }
                        .disabled(isSending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await send() }
                    } label: {
                        if isSending {
                            ProgressView().tint(.white)
                        } else {
                            Label(s.mailSend, systemImage: "paperplane.fill")
                        }
                    }
                    .disabled(draft == nil || isSending || recipients(to).isEmpty)
                    .accessibilityIdentifier("compose.send")
                }
            }
            .alert(s.mailSendFailed, isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(failure ?? "")
            }
            .interactiveDismissDisabled(isSending || !text.isEmpty && draft?.body != text)
            .sensoryFeedback(.success, trigger: sentTrigger)
            .task { await prepare() }
        }
    }

    private var title: String {
        switch intent {
        case .new: s.mailCompose
        case .reply(_, _, let all): all ? s.mailReplyAll : s.mailReply
        case .forward: s.mailForward
        }
    }

    private var form: some View {
        ScrollView {
            VStack(spacing: 14) {
                GlassCard(padding: 0) {
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            field(s.mailTo, text: $to, focus: .to, keyboard: .emailAddress, identifier: "compose.to")
                            if !showCc {
                                Button {
                                    withAnimation(.smooth(duration: 0.3)) { showCc = true }
                                    focus = .cc
                                } label: {
                                    Text(s.mailCc)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Theme.accentSoft)
                                        .padding(.trailing, 16)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if showCc {
                            Divider().overlay(Theme.separator).padding(.leading, 16)
                            field(s.mailCc, text: $cc, focus: .cc, keyboard: .emailAddress, identifier: "compose.cc")
                                .transition(.opacity)
                        }
                        Divider().overlay(Theme.separator).padding(.leading, 16)
                        field(s.mailSubject, text: $subject, focus: .subject, keyboard: .default, identifier: "compose.subject")
                    }
                }
                GlassCard(padding: 12) {
                    TextEditor(text: $text)
                        .focused($focus, equals: .body)
                        .font(.body)
                        .foregroundStyle(.white)
                        .tint(Theme.accentSoft)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 320)
                        .accessibilityIdentifier("compose.body")
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text(s.mailBody)
                                    .font(.body)
                                    .foregroundStyle(Theme.textTertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func field(_ title: String, text: Binding<String>, focus field: Field, keyboard: UIKeyboardType, identifier: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 58, alignment: .leading)
            TextField("", text: text, axis: field == .subject ? .vertical : .horizontal)
                .font(.subheadline.weight(field == .subject ? .semibold : .regular))
                .foregroundStyle(.white)
                .tint(Theme.accentSoft)
                .keyboardType(keyboard)
                .textInputAutocapitalization(field == .subject ? .sentences : .never)
                .autocorrectionDisabled(field != .subject)
                .textContentType(field == .subject ? nil : .emailAddress)
                .focused($focus, equals: field)
                .submitLabel(.next)
                .onSubmit { focus = field == .to ? (showCc ? .cc : .subject) : field == .cc ? .subject : .body }
                .accessibilityIdentifier(identifier)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func recipients(_ value: String) -> String {
        value
            .components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private func prepare() async {
        guard draft == nil else { return }
        loadError = nil
        do {
            let prepared = try await mail.compose(intent)
            to = prepared.to
            cc = prepared.cc
            showCc = !prepared.cc.isEmpty
            subject = prepared.subject
            let quote = prepared.body.trimmingCharacters(in: .whitespacesAndNewlines)
            text = quote.isEmpty ? "" : "\n\n" + quote
            draft = prepared
            try? await Task.sleep(for: .milliseconds(350))
            focus = to.isEmpty ? .to : .body
        } catch {
            loadError = s.mailSendMessage(for: error)
        }
    }

    private func send() async {
        guard let draft, !isSending else { return }
        focus = nil
        isSending = true
        defer { isSending = false }
        do {
            try await mail.send(RoundcubeMessage(to: recipients(to), cc: recipients(cc), subject: subject, body: text), using: draft)
            sentTrigger += 1
            dismiss()
        } catch {
            failure = s.mailSendMessage(for: error)
        }
    }
}
