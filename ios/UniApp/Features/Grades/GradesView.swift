import Charts
import SwiftUI

struct SubjectSelection: Identifiable, Hashable {
    let subject: Subject
    let semester: Semester

    var id: String { semester.id + "|" + subject.id }
}

struct GradesView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.strings) private var s
    @Environment(\.locale) private var locale

    @State private var semesterFilter: String?
    @State private var query = ""
    @State private var selected: SubjectSelection?
    @State private var showReauth = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let grades = session.snapshot?.grades {
                    VStack(spacing: 20) {
                        if grades.semesters.isEmpty {
                            ContentUnavailableView(s.noGrades, systemImage: "graduationcap", description: Text(s.noGradesHint))
                                .padding(.top, 60)
                        } else {
                            if query.isEmpty {
                                summary(grades)
                                semesterChips(grades.semesters)
                            }
                            let visible = filtered(grades.semesters)
                            if visible.isEmpty {
                                ContentUnavailableView.search(text: query)
                            }
                            ForEach(visible) { semester in
                                semesterSection(semester)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.bottom, 32)
                }
            }
            .background { AppBackground(glow: 0.75) }
            .navigationTitle(s.tabGrades)
            .searchable(text: $query, prompt: s.searchSubjects)
            .refreshable {
                if session.canRefreshSilently {
                    await session.refresh()
                } else {
                    showReauth = true
                }
            }
            .sheet(item: $selected) { selection in
                SubjectDetailSheet(selection: selection)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showReauth) {
                LoginView(prefilledFacultyNo: session.lastKnownFacultyNo, isReauthentication: true)
            }
        }
    }

    private func filtered(_ semesters: [Semester]) -> [Semester] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let scoped = semesterFilter == nil || !trimmed.isEmpty ? semesters : semesters.filter { $0.id == semesterFilter }
        guard !trimmed.isEmpty else { return scoped }
        let needle = ScheduleMatcher.normalize(trimmed)
        return scoped.compactMap { semester in
            var copy = semester
            copy.subjects = semester.subjects.filter { ScheduleMatcher.normalize($0.name).contains(needle) }
            return copy.subjects.isEmpty ? nil : copy
        }
    }

    private func summary(_ grades: Grades) -> some View {
        GlassCard(tint: Theme.accent.opacity(0.22)) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.averageGrade)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                        Text(grades.gpa.map { $0.formatted(.number.precision(.fractionLength(2)).locale(locale)) } ?? "—")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Label(s.gradedCount(grades.gradedCount), systemImage: "checkmark.circle.fill")
                        Label(s.creditedCount(grades.creditedCount), systemImage: "seal.fill")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                }
                Text(s.distribution)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                GradeDistributionChart(distribution: grades.distribution)
            }
        }
    }

    private func semesterChips(_ semesters: [Semester]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    chip(title: s.allSemesters, isSelected: semesterFilter == nil) {
                        semesterFilter = nil
                    }
                    ForEach(semesters) { semester in
                        chip(title: semester.title, isSelected: semesterFilter == semester.id) {
                            semesterFilter = semester.id
                        }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
        }
        .scrollClipDisabled()
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.smooth) { action() }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(isSelected ? Glass.regular.tint(Theme.accent.opacity(0.8)).interactive() : Glass.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }

    private func semesterSection(_ semester: Semester) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(semester.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                if let average = semester.average {
                    Text("⌀ " + average.formatted(.number.precision(.fractionLength(2)).locale(locale)))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .glassEffect(.regular.tint(Theme.gradeColor(average).opacity(0.55)), in: .capsule)
                }
            }
            .padding(.horizontal, 4)

            GlassCard(padding: 6) {
                VStack(spacing: 0) {
                    ForEach(Array(semester.subjects.enumerated()), id: \.element.id) { index, subject in
                        Button {
                            selected = SubjectSelection(subject: subject, semester: semester)
                        } label: {
                            SubjectRow(subject: subject)
                                .padding(.horizontal, 12)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index < semester.subjects.count - 1 {
                            Divider().overlay(Theme.separator).padding(.leading, 14)
                        }
                    }
                }
            }
        }
    }
}

struct SubjectRow: View {
    let subject: Subject

    @Environment(\.strings) private var s

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(subject.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let control = subject.control {
                        Text(control.capitalized(with: nil))
                    }
                    if subject.hadRetake {
                        Text("· " + s.retake)
                            .foregroundStyle(Theme.gradeFair)
                    }
                    if subject.credited && subject.grade == nil {
                        Text("· " + s.credited)
                            .foregroundStyle(Theme.success)
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 8)
            GradeBadge(grade: subject.grade, credited: subject.credited)
        }
        .padding(.vertical, 12)
    }
}

struct GradeDistributionChart: View {
    let distribution: [String: Int]

    private struct Entry: Identifiable {
        let grade: Int
        let count: Int
        var id: Int { grade }
    }

    private var entries: [Entry] {
        (2...6).reversed().map { Entry(grade: $0, count: distribution[String($0)] ?? 0) }
    }

    var body: some View {
        Chart(entries) { entry in
            BarMark(
                x: .value("Grade", String(entry.grade)),
                y: .value("Count", entry.count)
            )
            .cornerRadius(8)
            .foregroundStyle(Theme.gradeColor(entry.grade).gradient)
            .annotation(position: .top, spacing: 4) {
                if entry.count > 0 {
                    Text("\(entry.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(height: 120)
    }
}

struct SubjectDetailSheet: View {
    let selection: SubjectSelection

    @Environment(\.strings) private var s
    @Environment(\.dismiss) private var dismiss

    private var subject: Subject { selection.subject }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    GradeBadge(grade: subject.grade, credited: subject.credited, size: 88)
                        .padding(.top, 8)
                    VStack(spacing: 6) {
                        Text(subject.name)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        Text(statusText)
                            .font(.headline)
                            .foregroundStyle(subject.grade == nil && subject.credited ? Theme.success : Theme.gradeColor(subject.grade))
                    }

                    GlassCard(padding: 16) {
                        VStack(spacing: 0) {
                            InfoRow(title: s.semester, value: selection.semester.title)
                            Divider().overlay(Theme.separator)
                            InfoRow(title: s.controlForm, value: subject.control?.capitalized(with: nil))
                        }
                    }

                    if !subject.attempts.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: s.attempts)
                            GlassCard(padding: 16) {
                                VStack(spacing: 0) {
                                    ForEach(Array(subject.attempts.enumerated()), id: \.offset) { index, attempt in
                                        HStack {
                                            Text(attempt.kind == .regular ? s.regularSession : s.retakeSession)
                                                .font(.subheadline)
                                                .foregroundStyle(Theme.textSecondary)
                                            Spacer()
                                            Text(attempt.label)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.white)
                                            GradeBadge(grade: attempt.grade, size: 32)
                                        }
                                        .padding(.vertical, 8)
                                        if index < subject.attempts.count - 1 {
                                            Divider().overlay(Theme.separator)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 24)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(s.close, systemImage: "xmark") { dismiss() }
                }
            }
        }
    }

    private var statusText: String {
        if let grade = subject.grade { return s.gradeWord(grade) }
        return subject.credited ? s.credited : s.noGradeYet
    }
}
