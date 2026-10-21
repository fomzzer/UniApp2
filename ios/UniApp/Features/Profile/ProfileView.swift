import SwiftUI
import UIKit

struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(AppSettings.self) private var settings
    @Environment(\.strings) private var s

    @State private var confirmSignOut = false
    @State private var copiedTrigger = 0
    @State private var showCopied = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            ScrollView {
                if let snapshot = session.snapshot {
                    let student = snapshot.student
                    VStack(spacing: 20) {
                        header(student)
                        studiesCard(student)
                        contactsCard(student, dormitory: snapshot.dormitory)
                        if !student.details.isEmpty {
                            detailsCard(student.details)
                        }
                        settingsCard(language: $settings.language, biometricLock: $settings.biometricLock)
                        NavigationLink {
                            AboutView()
                        } label: {
                            navigationRow(title: s.about, systemImage: "info.circle.fill")
                        }
                        .buttonStyle(.pressable)
                        Button(role: .destructive) {
                            confirmSignOut = true
                        } label: {
                            Label(s.signOut, systemImage: "rectangle.portrait.and.arrow.right")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.glass)
                        .tint(Theme.danger)
                        .controlSize(.large)
                        .confirmationDialog(s.signOut, isPresented: $confirmSignOut, titleVisibility: .visible) {
                            Button(s.signOut, role: .destructive) { session.signOut() }
                            Button(s.cancel, role: .cancel) {}
                        } message: {
                            Text(s.signOutConfirm)
                        }
                    }
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.bottom, 32)
                }
            }
            .background { AppBackground(glow: 0.75) }
            .navigationTitle(s.tabProfile)
            .sensoryFeedback(.success, trigger: copiedTrigger)
            .overlay(alignment: .top) {
                if showCopied {
                    Label(s.copied, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .glassEffect(.regular.tint(Theme.success.opacity(0.5)), in: .capsule)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 8)
                }
            }
            .animation(.smooth, value: showCopied)
        }
    }

    private func header(_ student: Student) -> some View {
        VStack(spacing: 12) {
            AvatarView(initials: student.initials, size: 96)
            Text(student.name)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text("\(s.facultyNoShort) \(student.facultyNo)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule)
        }
        .padding(.top, 8)
    }

    private func studiesCard(_ student: Student) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: s.studies)
            GlassCard(padding: 16) {
                VStack(spacing: 0) {
                    InfoRow(title: s.faculty, value: student.faculty)
                    Divider().overlay(Theme.separator)
                    InfoRow(title: s.specialty, value: student.specialty)
                    if student.degree != nil {
                        Divider().overlay(Theme.separator)
                        InfoRow(title: s.educationDegree, value: student.degree)
                    }
                    if student.educationForm != nil {
                        Divider().overlay(Theme.separator)
                        InfoRow(title: s.educationForm, value: student.educationForm)
                    }
                    Divider().overlay(Theme.separator)
                    InfoRow(title: s.courseSemester, value: courseSemester(student))
                    Divider().overlay(Theme.separator)
                    InfoRow(title: s.groupStream, value: "\(student.group ?? "—") / \(student.stream ?? "—")")
                }
            }
        }
    }

    private func contactsCard(_ student: Student, dormitory: Dormitory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: s.contacts)
            GlassCard(padding: 16) {
                VStack(spacing: 0) {
                    Button {
                        guard let email = student.email else { return }
                        UIPasteboard.general.string = email
                        copiedTrigger += 1
                        showCopied = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.6))
                            showCopied = false
                        }
                    } label: {
                        InfoRow(title: s.universityEmail, value: student.email, valueColor: Theme.accentSoft)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                    Divider().overlay(Theme.separator)
                    InfoRow(
                        title: s.dormitory,
                        value: dormitory.status == nil ? s.noData : (dormitory.accommodated ? s.accommodated : s.notAccommodated),
                        valueColor: dormitory.accommodated ? Theme.success : Theme.textPrimary
                    )
                }
            }
        }
    }

    private func detailsCard(_ details: [String: String]) -> some View {
        GlassCard(padding: 16) {
            DisclosureGroup {
                VStack(spacing: 0) {
                    let keys = details.keys.sorted()
                    ForEach(Array(keys.enumerated()), id: \.element) { index, key in
                        InfoRow(title: key, value: details[key])
                        if index < keys.count - 1 {
                            Divider().overlay(Theme.separator)
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                Text(s.allDetails)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .tint(Theme.textSecondary)
        }
    }

    private func settingsCard(language: Binding<AppLanguage>, biometricLock: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: s.settings)
            GlassCard(padding: 16) {
                VStack(spacing: 0) {
                    HStack {
                        Label(s.languageTitle, systemImage: "globe")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                        Spacer()
                        Picker(s.languageTitle, selection: language) {
                            ForEach(AppLanguage.allCases) { option in
                                Text("\(option.flag) \(option.nativeName)").tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.white)
                    }
                    .frame(minHeight: 46)
                    Divider().overlay(Theme.separator)
                    Toggle(isOn: biometricLock) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(s.faceIDLock, systemImage: "faceid")
                                .font(.subheadline)
                                .foregroundStyle(.white)
                            Text(s.faceIDHint)
                                .font(.caption)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .tint(Theme.accent)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    private func navigationRow(title: String, systemImage: String) -> some View {
        HStack(spacing: 14) {
            IconBadge(systemImage: systemImage, size: 36)
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(14)
        .glassCard(cornerRadius: Theme.rowRadius)
    }

    private func courseSemester(_ student: Student) -> String {
        let course = student.course.map(String.init) ?? "—"
        let semester = student.semester.map(String.init) ?? "—"
        return "\(course) / \(semester)"
    }
}

struct AboutView: View {
    @Environment(\.strings) private var s
    @Environment(\.openURL) private var openURL

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .shadow(color: Theme.accentBright.opacity(0.7), radius: 26)
                    .padding(.top, 16)
                VStack(spacing: 6) {
                    Text(s.appName)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("\(s.version) \(version)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                GlassCard {
                    Text(s.aboutText)
                        .font(.body)
                        .foregroundStyle(.white)
                }
                GlassCard(padding: 16) {
                    VStack(spacing: 0) {
                        InfoRow(title: s.developer, value: "fomzzer")
                        Divider().overlay(Theme.separator)
                        Button {
                            if let url = URL(string: "https://github.com/fomzzer") { openURL(url) }
                        } label: {
                            InfoRow(title: s.sourceCode, value: "github.com/fomzzer", valueColor: Theme.accentSoft)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressable)
                        Divider().overlay(Theme.separator)
                        InfoRow(title: s.dataSources, value: "e-university.tu-sofia.bg\ntu-sofia.bg")
                    }
                }
                GlassCard(tint: Theme.accent.opacity(0.15)) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(s.privacyNote, systemImage: "lock.shield.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                        Label(s.disclaimerLong, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .padding(.horizontal, Theme.pagePadding)
            .padding(.bottom, 32)
        }
        .background { AppBackground(glow: 0.6) }
        .navigationTitle(s.about)
        .navigationBarTitleDisplayMode(.inline)
    }
}
