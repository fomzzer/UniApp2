import SwiftUI

struct MailView: View {
    @Environment(MailStore.self) private var mail
    @Environment(\.strings) private var s
    @Environment(\.openURL) private var openURL

    @State private var confirmSignOut = false

    var body: some View {
        ZStack {
            switch mail.phase {
            case .signedOut:
                MailSignInView()
                    .transition(.opacity)
            case .ready:
                inbox
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.4), value: mail.phase)
        .background { AppBackground(glow: 0.75) }
        .navigationTitle(mail.phase == .ready ? mail.folder.map(s.folderName) ?? s.mailTitle : s.mailTitle)
        .navigationBarTitleDisplayMode(.inline)
        .folderMenu(enabled: mail.phase == .ready && !mail.folders.isEmpty) {
            ForEach(mail.folders) { folder in
                Button {
                    Task { await mail.select(folder) }
                } label: {
                    Label(folder.unread > 0 ? "\(s.folderName(folder)) · \(folder.unread)" : s.folderName(folder), systemImage: folder.role.systemImage)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(s.mailWeb, systemImage: "safari") { openWebMail() }
                    if mail.phase == .ready {
                        Button(s.mailSignOut, systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            confirmSignOut = true
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityIdentifier("mail.menu")
            }
        }
        .confirmationDialog(s.mailSignOut, isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button(s.mailSignOut, role: .destructive) {
                withAnimation(.smooth(duration: 0.35)) { mail.signOut() }
            }
            Button(s.cancel, role: .cancel) {}
        }
        .navigationDestination(for: MailSummary.self) { summary in
            MailMessageView(summary: summary)
        }
        .task { await mail.start() }
    }

    private var inbox: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                if let error = mail.error {
                    errorBanner(error)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if mail.messages.isEmpty {
                    if mail.isLoading {
                        ProgressView()
                            .tint(.white)
                            .padding(.top, 80)
                    } else {
                        ContentUnavailableView(s.mailEmpty, systemImage: "tray")
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.top, 60)
                    }
                } else {
                    ForEach(sections, id: \.title) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: section.title)
                            GlassCard(padding: 6) {
                                VStack(spacing: 0) {
                                    ForEach(Array(section.items.enumerated()), id: \.element.id) { index, summary in
                                        NavigationLink(value: summary) {
                                            MailRow(summary: summary, showsRecipients: mail.folder?.showsRecipients ?? false)
                                                .padding(.horizontal, 10)
                                        }
                                        .buttonStyle(.row())
                                        .accessibilityIdentifier("mail.row")
                                        if index < section.items.count - 1 {
                                            Divider().overlay(Theme.separator).padding(.leading, 66)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if mail.nextBefore != nil {
                        Button {
                            Task { await mail.loadMore() }
                        } label: {
                            ZStack {
                                if mail.isLoadingMore {
                                    ProgressView().tint(.white)
                                } else {
                                    Text(s.mailLoadMore)
                                }
                            }
                            .frame(minWidth: 120)
                        }
                        .buttonStyle(.pill(tint: Theme.accent))
                        .onAppear { Task { await mail.loadMore() } }
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .animation(.smooth(duration: 0.35), value: mail.messages)
            .animation(.smooth(duration: 0.35), value: mail.error)
        }
        .refreshable { await mail.reload() }
    }

    private func errorBanner(_ error: MailError) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.gradeFair)
            Text(s.mailMessage(for: error))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            Button {
                withAnimation(.smooth(duration: 0.35)) { mail.error = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.pressable)
        }
        .padding(14)
        .glassCard(cornerRadius: Theme.rowRadius, tint: Theme.gradeFair.opacity(0.18))
    }

    private var sections: [(title: String, items: [MailSummary])] {
        let calendar = Calendar.current
        var result: [(title: String, items: [MailSummary])] = []
        for summary in mail.messages {
            let title = sectionTitle(summary.date, calendar: calendar)
            if result.last?.title == title {
                result[result.count - 1].items.append(summary)
            } else {
                result.append((title, [summary]))
            }
        }
        return result
    }

    private func sectionTitle(_ date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return s.mailToday }
        if calendar.isDateInYesterday(date) { return s.mailYesterday }
        let sameYear = calendar.isDate(date, equalTo: .now, toGranularity: .year)
        let style = Date.FormatStyle(date: .omitted, time: .omitted).locale(s.language.locale).day().month(.wide).weekday(.wide)
        let text = sameYear ? date.formatted(style) : date.formatted(Date.FormatStyle(date: .long, time: .omitted).locale(s.language.locale))
        return text.prefix(1).uppercased(with: s.language.locale) + text.dropFirst()
    }

    private func openWebMail() {
        if let url = URL(string: "https://tusmail.tu-sofia.bg/") {
            openURL(url)
        }
    }
}

private extension View {
    @ViewBuilder
    func folderMenu<Content: View>(enabled: Bool, @ViewBuilder content: () -> Content) -> some View {
        if enabled {
            toolbarTitleMenu(content: content)
        } else {
            self
        }
    }
}

struct MailRow: View {
    let summary: MailSummary
    var showsRecipients = false

    @Environment(\.strings) private var s

    private var address: MailAddress? {
        showsRecipients ? summary.to.first ?? summary.from : summary.from
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SenderAvatar(address: address, size: 42)
                .overlay(alignment: .topLeading) {
                    if !summary.isSeen {
                        Circle()
                            .fill(Theme.accentBright)
                            .frame(width: 11, height: 11)
                            .overlay { Circle().stroke(Color.black.opacity(0.6), lineWidth: 2) }
                            .offset(x: -3, y: -2)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(address?.display ?? s.mailNoSender)
                        .font(.subheadline.weight(summary.isSeen ? .medium : .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if summary.hasAttachments {
                        Image(systemName: "paperclip")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Text(timeText)
                        .font(.caption.weight(summary.isSeen ? .regular : .semibold))
                        .foregroundStyle(summary.isSeen ? Theme.textTertiary : Theme.accentSoft)
                        .monospacedDigit()
                }
                Text(summary.subject.isEmpty ? s.mailNoSubject : summary.subject)
                    .font(.subheadline)
                    .foregroundStyle(summary.isSeen ? Theme.textSecondary : .white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(.vertical, 12)
        .animation(.smooth(duration: 0.3), value: summary.isSeen)
    }

    private var timeText: String {
        let calendar = Calendar.current
        let locale = s.language.locale
        if calendar.isDateInToday(summary.date) {
            return summary.date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
        }
        if calendar.isDate(summary.date, equalTo: .now, toGranularity: .year) {
            return summary.date.formatted(Date.FormatStyle().locale(locale).day().month(.abbreviated))
        }
        return summary.date.formatted(Date.FormatStyle(date: .numeric, time: .omitted).locale(locale))
    }
}

struct SenderAvatar: View {
    let address: MailAddress?
    var size: CGFloat = 42

    private static let palette = [Theme.accent, Theme.gradeVeryGood, Theme.gradeGood, Theme.success, Theme.gradeFair, Theme.accentBright]

    var body: some View {
        AvatarView(initials: address?.initials ?? "?", size: size, tint: tint)
    }

    private var tint: Color {
        let key = (address?.email ?? "").lowercased()
        let hash = key.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Self.palette[hash % Self.palette.count]
    }
}

struct MailSignInView: View {
    @Environment(MailStore.self) private var mail
    @Environment(SessionStore.self) private var session
    @Environment(\.strings) private var s

    @State private var username = ""
    @State private var password = ""
    @State private var host = MailAccount.hosts[0]
    @State private var isSubmitting = false
    @State private var errorText: String?
    @State private var passwordFocused = false
    @State private var successTrigger = 0
    @FocusState private var usernameFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 14) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 84, height: 84)
                        .glassEffect(.regular.tint(Theme.accent.opacity(0.6)), in: .rect(cornerRadius: 26))
                        .shadow(color: Theme.accentBright.opacity(0.5), radius: 20)
                    Text(s.mailTitle)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    Text(s.mailSignInHint)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)

                GlassCard(padding: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        inputRow(systemImage: "person.fill") {
                            TextField(s.mailUsername, text: $username)
                                .keyboardType(.emailAddress)
                                .textContentType(.username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($usernameFocused)
                                .submitLabel(.next)
                                .onSubmit { passwordFocused = true }
                                .accessibilityIdentifier("mail.username")
                        }
                        inputRow(systemImage: "key.fill") {
                            SecretField(
                                placeholder: s.mailPassword,
                                text: $password,
                                isSecure: true,
                                isFocused: $passwordFocused,
                                identifier: "mail.password",
                                onSubmit: submit
                            )
                        }
                        Menu {
                            Picker(s.mailServer, selection: $host) {
                                ForEach(MailAccount.hosts, id: \.self) { value in
                                    Text(value).tag(value)
                                }
                            }
                            .pickerStyle(.inline)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "server.rack")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Theme.accentSoft)
                                    .frame(width: 24)
                                Text(s.mailServer)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                Spacer(minLength: 8)
                                Text(host)
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                            .contentShape(.rect)
                        }
                    }
                }

                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.danger)
                        .multilineTextAlignment(.center)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Button(action: submit) {
                    HStack(spacing: 12) {
                        if isSubmitting {
                            ProgressView().tint(.white)
                                .transition(.scale(scale: 0.6).combined(with: .opacity))
                        }
                        Text(s.signIn)
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)
                .controlSize(.large)
                .disabled(isSubmitting)
                .accessibilityIdentifier("mail.signIn")

                Label(s.mailReadOnly, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .animation(.smooth(duration: 0.35), value: errorText)
        .animation(.smooth(duration: 0.3), value: isSubmitting)
        .sensoryFeedback(.success, trigger: successTrigger)
        .onAppear {
            if username.isEmpty {
                username = mail.lastUsername ?? session.snapshot?.student.email ?? ""
            }
            if let error = mail.error, error == .authenticationFailed {
                errorText = s.mailMessage(for: error)
                mail.error = nil
            }
        }
    }

    private func inputRow<Content: View>(systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.accentSoft)
                .frame(width: 24)
            content()
        }
        .font(.body.weight(.medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(height: 54)
        .glassEffect(.regular.tint(.white.opacity(0.04)), in: .rect(cornerRadius: 18))
    }

    private func submit() {
        guard !isSubmitting else { return }
        guard !username.trimmingCharacters(in: .whitespaces).isEmpty, !password.isEmpty else {
            errorText = s.fieldsMissing
            return
        }
        usernameFocused = false
        passwordFocused = false
        errorText = nil
        isSubmitting = true
        Task {
            do {
                try await mail.signIn(username: username, password: password, host: host)
                successTrigger += 1
                password = ""
            } catch {
                errorText = s.mailMessage(for: error as? MailError ?? .connectionFailed)
            }
            isSubmitting = false
        }
    }
}
