import SwiftUI

struct LoginView: View {
    var prefilledFacultyNo: String? = nil
    var isReauthentication = false

    @Environment(SessionStore.self) private var session
    @Environment(AppSettings.self) private var settings
    @Environment(\.strings) private var s
    @Environment(\.dismiss) private var dismiss

    @State private var facultyNo = ""
    @State private var secret = ""
    @State private var method: LoginMethod?
    @State private var isDetecting = false
    @State private var isSubmitting = false
    @State private var remember = true
    @State private var errorText: String?
    @State private var progressStep = 0
    @State private var revealSecret = false
    @State private var successTrigger = 0
    @FocusState private var focus: Field?

    private static let facultyNoLimit = 10

    private enum Field {
        case facultyNo
        case secret
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AppBackground()
                .onTapGesture { focus = nil }
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 28) {
                        header
                        form
                        if let errorText {
                            Label(errorText, systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.danger)
                                .multilineTextAlignment(.center)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        submitButton
                        footer
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, isReauthentication ? 40 : 72)
                    .padding(.bottom, 40)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .top)
                    .background {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { focus = nil }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollBounceBehavior(.basedOnSize)
            }

            languageMenu
                .padding(.trailing, 20)
                .padding(.top, 8)
        }
        .animation(.smooth(duration: 0.35), value: method)
        .animation(.smooth(duration: 0.35), value: errorText)
        .animation(.smooth(duration: 0.3), value: isSubmitting)
        .animation(.smooth(duration: 0.3), value: isDetecting)
        .animation(.smooth(duration: 0.25), value: revealSecret)
        .sensoryFeedback(.success, trigger: successTrigger)
        .onAppear {
            if facultyNo.isEmpty {
                facultyNo = prefilledFacultyNo ?? session.lastKnownFacultyNo ?? ""
            }
        }
        .task(id: facultyNo) {
            await detectMethod()
        }
        .task(id: isSubmitting) {
            guard isSubmitting else { return }
            progressStep = 0
            while !Task.isCancelled && isSubmitting {
                try? await Task.sleep(for: .seconds(2.4))
                if isSubmitting { withAnimation(.smooth) { progressStep += 1 } }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 84, height: 84)
                .shadow(color: Theme.accentBright.opacity(0.7), radius: 24)
            Text(isReauthentication ? s.reauthTitle : s.appName)
                .font(.system(size: isReauthentication ? 30 : 44, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(isReauthentication ? s.reauthHint : s.slogan)
                .font(.headline.weight(.regular))
                .italic(!isReauthentication)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var form: some View {
        GlassCard(padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                inputRow(systemImage: "person.text.rectangle") {
                    TextField(s.facultyNumber, text: $facultyNo)
                        .keyboardType(.numberPad)
                        .textContentType(.username)
                        .focused($focus, equals: .facultyNo)
                        .onChange(of: facultyNo) { _, value in
                            let digits = String(value.filter(\.isNumber).prefix(Self.facultyNoLimit))
                            if digits != value { facultyNo = digits }
                        }
                    if isDetecting {
                        ProgressView().controlSize(.small).tint(.white)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }

                inputRow(systemImage: secretIcon) {
                    Group {
                        if revealSecret || method == .otp {
                            TextField(s.secretTitle(method), text: $secret)
                        } else {
                            SecureField(s.secretTitle(method), text: $secret)
                        }
                    }
                    .keyboardType(method == .password ? .default : .numberPad)
                    .textContentType(method == .otp ? .oneTimeCode : .password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .secret)
                    .submitLabel(.go)
                    .onSubmit { submit() }
                    if method != .otp {
                        Button {
                            revealSecret.toggle()
                        } label: {
                            Image(systemName: revealSecret ? "eye.slash" : "eye")
                                .foregroundStyle(Theme.textSecondary)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text(isDetecting ? s.detectingMethod : s.methodHint(method))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .contentTransition(.opacity)
                    .padding(.horizontal, 4)

                if !isReauthentication {
                    Divider().overlay(Theme.separator)
                    Toggle(isOn: $remember) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.rememberMe)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Text(s.rememberHint)
                                .font(.caption)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .tint(Theme.accent)
                    .padding(.horizontal, 4)
                }
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

    private var secretIcon: String {
        switch method {
        case .otp: "lock.rotation"
        case .password: "key.fill"
        default: "lock.fill"
        }
    }

    private var submitButton: some View {
        Button(action: submit) {
            HStack(spacing: 12) {
                if isSubmitting {
                    ProgressView().tint(.white)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                Text(isSubmitting ? s.loginStep(progressStep) : s.signIn)
                    .font(.headline)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.accent)
        .controlSize(.large)
        .disabled(isSubmitting)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if isReauthentication {
                Button(s.cancel) { dismiss() }
                    .buttonStyle(.glass)
            }
            Text(s.disclaimerShort)
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
    }

    private var languageMenu: some View {
        Menu {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    withAnimation(.smooth(duration: 0.35)) { settings.language = language }
                } label: {
                    if language == settings.language {
                        Label("\(language.flag) \(language.nativeName)", systemImage: "checkmark")
                    } else {
                        Text("\(language.flag) \(language.nativeName)")
                    }
                }
            }
        } label: {
            EmojiGlyph(emoji: settings.language.flag, size: 22)
                .frame(width: 44, height: 44)
                .glassEffect(.regular, in: .circle)
        }
    }

    private func detectMethod() async {
        let number = facultyNo
        guard number.count >= 5 else {
            method = nil
            isDetecting = false
            return
        }
        try? await Task.sleep(for: .milliseconds(650))
        guard !Task.isCancelled, number == facultyNo else { return }
        isDetecting = true
        defer { isDetecting = false }
        do {
            let detected = try await session.detectMethod(facultyNo: number)
            guard !Task.isCancelled, number == facultyNo else { return }
            method = detected
            errorText = nil
        } catch {
            guard !Task.isCancelled else { return }
            method = nil
            if let apiError = error as? APIError, case .server(code: "unknown_student", _) = apiError {
                errorText = s.message(for: error)
            }
        }
    }

    private func submit() {
        guard !isSubmitting else { return }
        guard !facultyNo.isEmpty, !secret.isEmpty else {
            errorText = s.fieldsMissing
            return
        }
        focus = nil
        errorText = nil
        isSubmitting = true
        let number = facultyNo
        let code = secret
        let shouldRemember = isReauthentication ? session.canRefreshSilently || remember : remember
        Task {
            do {
                try await session.signIn(facultyNo: number, secret: code, method: method, remember: shouldRemember)
                successTrigger += 1
                isSubmitting = false
                if isReauthentication { dismiss() }
            } catch {
                isSubmitting = false
                errorText = s.message(for: error)
            }
        }
    }
}
