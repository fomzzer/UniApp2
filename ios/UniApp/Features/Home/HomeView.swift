import Charts
import SwiftUI

struct HomeView: View {
    @Binding var selection: AppTab

    @Environment(SessionStore.self) private var session
    @Environment(ScheduleStore.self) private var schedules
    @Environment(MailStore.self) private var mail
    @Environment(\.strings) private var s
    @Environment(\.locale) private var locale

    @AppStorage("schedule.kind") private var scheduleKind: ScheduleKind = .lectures
    @State private var openedSchedule: ScheduleItem?
    @State private var showReauth = false
    @State private var showMail = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let snapshot = session.snapshot {
                    VStack(spacing: 22) {
                        header(snapshot.student)
                        if let error = session.refreshError {
                            refreshBanner(error)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        GPAHeroCard(grades: snapshot.grades)
                        quickActions(snapshot.student)
                        if snapshot.grades.trend.count >= 2 {
                            SemesterTrendCard(semesters: snapshot.grades.trend)
                        }
                        myScheduleCard(snapshot.student)
                        DormitoryCard(dormitory: snapshot.dormitory)
                        if let latest = snapshot.grades.latestSemester {
                            latestGrades(latest)
                        }
                        Text(s.updated(snapshot.fetchedAt.formatted(.relative(presentation: .named).locale(locale))))
                            .font(.footnote)
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.bottom, 32)
                    .animation(.smooth(duration: 0.4), value: snapshot)
                    .animation(.smooth(duration: 0.35), value: session.refreshError != nil)
                }
            }
            .appHidesTopScrollEdge()
            .background { AppBackground() }
            .toolbarVisibility(.hidden, for: .navigationBar)
            .refreshable { await refresh() }
            .sheet(item: $openedSchedule) { item in
                ScheduleDocumentView(item: item)
            }
            .sheet(isPresented: $showReauth) {
                LoginView(prefilledFacultyNo: session.lastKnownFacultyNo, isReauthentication: true)
            }
            .navigationDestination(isPresented: $showMail) {
                MailView()
            }
            .task {
                await schedules.load(.lectures)
                if let item = schedules.myItem(.lectures, student: session.snapshot?.student) {
                    await schedules.loadTimetable(item)
                }
            }
            .task {
                await mail.start()
            }
        }
    }

    private func header(_ student: Student) -> some View {
        HStack(spacing: 14) {
            Button {
                selection = .profile
            } label: {
                AvatarView(initials: student.initials, size: 48)
            }
            .buttonStyle(.pressable)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.greeting(student.firstName))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(s.facultyNoShort) \(student.facultyNo)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button {
                Task { await refresh() }
            } label: {
                ZStack {
                    if session.isRefreshing {
                        ProgressView()
                            .tint(.white)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .animation(.smooth(duration: 0.3), value: session.isRefreshing)
                .frame(width: 44, height: 44)
                .appGlass(in: .circle)
            }
            .buttonStyle(.pressable)
            .disabled(session.isRefreshing)
            .accessibilityLabel(s.refresh)
        }
        .padding(.top, 8)
    }

    private func refreshBanner(_ error: APIError) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.gradeFair)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.refreshFailed)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(s.message(for: error))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button {
                withAnimation(.smooth(duration: 0.35)) { session.refreshError = nil }
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

    private func quickActions(_ student: Student) -> some View {
        HStack(alignment: .top) {
            QuickActionButton(title: s.actionGrades, systemImage: "graduationcap.fill") {
                selection = .grades
            }
            Spacer()
            QuickActionButton(title: s.actionSchedule, systemImage: "calendar") {
                scheduleKind = .lectures
                selection = .schedule
            }
            Spacer()
            QuickActionButton(title: s.actionExams, systemImage: "pencil.and.list.clipboard") {
                scheduleKind = .exams
                selection = .schedule
            }
            Spacer()
            QuickActionButton(title: s.actionMail, systemImage: "envelope.fill", badge: mail.inboxUnread) {
                showMail = true
            }
            .accessibilityIdentifier("home.mail")
        }
        .padding(.horizontal, 8)
    }

    private func myScheduleCard(_ student: Student) -> some View {
        let item = schedules.myItem(.lectures, student: student)
        return GlassCard {
            HStack(spacing: 14) {
                IconBadge(systemImage: "calendar.badge.clock")
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.mySchedule)
                        .font(.headline)
                        .foregroundStyle(.white)
                    if let item {
                        Text(item.major)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                        Text(s.courseStream(year: item.year, stream: item.stream))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accentSoft)
                        TimetableGlance(item: item)
                    } else if schedules.isLoading(.lectures) {
                        Text(s.loading)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Text(s.scheduleNotMatched)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: 8)
                Button {
                    if let item {
                        openedSchedule = item
                    } else {
                        scheduleKind = .lectures
                        selection = .schedule
                    }
                } label: {
                    Text(item == nil ? s.choose : s.open)
                        .contentTransition(.opacity)
                }
                .buttonStyle(.pill(tint: Theme.accent))
                .animation(.smooth(duration: 0.3), value: item == nil)
                .accessibilityIdentifier("home.openSchedule")
            }
        }
    }

    private func latestGrades(_ semester: Semester) -> some View {
        VStack(spacing: 12) {
            SectionHeader(title: s.latestGrades, actionTitle: s.seeAll) {
                selection = .grades
            }
            GlassCard(padding: 6) {
                VStack(spacing: 0) {
                    let subjects = Array(semester.subjects.prefix(4))
                    ForEach(Array(subjects.enumerated()), id: \.element.id) { index, subject in
                        SubjectRow(subject: subject)
                            .padding(.horizontal, 12)
                        if index < subjects.count - 1 {
                            Divider().overlay(Theme.separator).padding(.leading, 14)
                        }
                    }
                }
            }
        }
    }

    private func refresh() async {
        if session.canRefreshSilently {
            await session.refresh()
        } else {
            showReauth = true
        }
        await schedules.load(.lectures, force: true)
    }
}

struct QuickActionButton: View {
    let title: String
    let systemImage: String
    var badge = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .appGlass(tint: Theme.accent.opacity(0.35), in: .circle)
                    if badge > 0 {
                        Text(badge > 99 ? "99+" : "\(badge)")
                            .font(.caption2.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(Theme.danger, in: .capsule)
                            .offset(x: 4, y: -2)
                            .transition(.scale.combined(with: .opacity))
                            .zIndex(1)
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.65), value: badge)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
    }
}

struct GPAHeroCard: View {
    let grades: Grades

    @Environment(\.strings) private var s
    @Environment(\.locale) private var locale

    var body: some View {
        GlassCard(tint: Theme.accent.opacity(0.32), padding: 24) {
            VStack(alignment: .leading, spacing: 16) {
                Text(s.averageGrade)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(gpaText)
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(value: grades.gpa ?? 0))
                        .animation(.smooth(duration: 0.5), value: grades.gpa)
                    Text("/ 6")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                    Spacer()
                    if let gpa = grades.gpa {
                        Text(s.gradeWord(Int(gpa.rounded())))
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .appGlass(tint: Theme.gradeColor(gpa).opacity(0.6), in: .capsule)
                    }
                }
                GPAScale(value: grades.gpa)
                HStack {
                    Label(s.gradedCount(grades.gradedCount), systemImage: "checkmark.circle.fill")
                    Spacer()
                    Label(s.creditedCount(grades.creditedCount), systemImage: "seal.fill")
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var gpaText: String {
        guard let gpa = grades.gpa else { return "—" }
        return gpa.formatted(.number.precision(.fractionLength(2)).locale(locale))
    }
}

struct SemesterTrendCard: View {
    let semesters: [Semester]

    @Environment(\.strings) private var s
    @State private var progress = 0.0

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(s.trendTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                Chart(semesters) { semester in
                    AreaMark(
                        x: .value("Semester", label(for: semester)),
                        yStart: .value("Base", 2.0),
                        yEnd: .value("Average", grown(semester))
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LinearGradient(colors: [Theme.accentBright.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom))

                    LineMark(
                        x: .value("Semester", label(for: semester)),
                        y: .value("Average", grown(semester))
                    )
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    .foregroundStyle(Theme.accentBright)

                    PointMark(
                        x: .value("Semester", label(for: semester)),
                        y: .value("Average", grown(semester))
                    )
                    .symbolSize(40)
                    .foregroundStyle(.white)
                }
                .chartYScale(domain: 2.0...6.0)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [2.0, 3.0, 4.0, 5.0, 6.0]) { _ in
                        AxisGridLine().foregroundStyle(Theme.separator)
                        AxisValueLabel().foregroundStyle(Theme.textTertiary)
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel().foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(height: 170)
                .onAppear {
                    withAnimation(.smooth(duration: 0.9).delay(0.1)) { progress = 1 }
                }
            }
        }
    }

    private func grown(_ semester: Semester) -> Double {
        2 + ((semester.average ?? 2) - 2) * progress
    }

    private func label(for semester: Semester) -> String {
        semester.number.map { s.semesterShort($0) } ?? semester.title
    }
}

struct DormitoryCard: View {
    let dormitory: Dormitory

    @Environment(\.strings) private var s

    var body: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 14) {
                IconBadge(systemImage: "building.2.fill", tint: dormitory.accommodated ? Theme.success : Theme.accent)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(s.dormitory)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Spacer()
                        if dormitory.status != nil {
                            Text(dormitory.accommodated ? s.accommodated : s.notAccommodated)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(dormitory.accommodated ? Theme.success : Theme.textSecondary)
                        }
                    }
                    Text(dormitory.status ?? s.noData)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
