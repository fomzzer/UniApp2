import SwiftUI

struct ScheduleView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ScheduleStore.self) private var store
    @Environment(\.strings) private var s

    @AppStorage("schedule.kind") private var kind: ScheduleKind = .lectures
    @State private var degree = "bachelor"
    @State private var facultySlug: String?
    @State private var majorSlug: String?
    @State private var year: Int?
    @State private var stream: String?
    @State private var opened: ScheduleItem?
    @State private var didPrefill = false

    private struct Option: Hashable, Identifiable {
        let id: String
        let title: String

        var short: String {
            let acronym = ScheduleMatcher.acronym(title)
            return acronym.count >= 2 && acronym.count < title.count ? acronym : title
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Picker(s.tabSchedule, selection: $kind.animation(.smooth(duration: 0.35))) {
                        ForEach(ScheduleKind.allCases) { kind in
                            Text(s.kindTitle(kind)).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    if let mine = store.myItem(kind, student: session.snapshot?.student) {
                        myCard(mine)
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    }

                    filterCard
                    content
                        .animation(.smooth(duration: 0.35), value: contentKey)
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 32)
            }
            .background { AppBackground(glow: 0.75) }
            .navigationTitle(s.tabSchedule)
            .refreshable { await store.load(kind, force: true) }
            .task(id: kind) {
                await store.load(kind)
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { prefillIfNeeded() }
            }
            .sheet(item: $opened) { item in
                ScheduleDocumentView(item: item)
            }
        }
    }

    private var items: [ScheduleItem] {
        store.items(kind)
    }

    private var degreeItems: [ScheduleItem] {
        items.filter { $0.degree == degree }
    }

    private var degrees: [String] {
        let available = Array(Set(items.map(\.degree))).sorted()
        return available.isEmpty ? ["bachelor", "master"] : available
    }

    private var faculties: [Option] {
        unique(degreeItems.map { Option(id: $0.facultySlug, title: $0.faculty) }).sorted { $0.title < $1.title }
    }

    private var majors: [Option] {
        guard let facultySlug else { return [] }
        let scoped = degreeItems.filter { $0.facultySlug == facultySlug }
        return unique(scoped.map { Option(id: $0.majorSlug, title: $0.major) }).sorted { $0.title < $1.title }
    }

    private var years: [Int] {
        Array(Set(majorItems.compactMap(\.year))).sorted()
    }

    private var streams: [String] {
        let scoped = majorItems.filter { year == nil || $0.year == year }
        let values = scoped.compactMap(\.stream)
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }.sorted { (Int($0) ?? 999, $0) < (Int($1) ?? 999, $1) }
    }

    private var majorItems: [ScheduleItem] {
        guard let facultySlug, let majorSlug else { return [] }
        return degreeItems.filter { $0.facultySlug == facultySlug && $0.majorSlug == majorSlug }
    }

    private var results: [ScheduleItem] {
        majorItems.filter { (year == nil || $0.year == year) && (stream == nil || $0.stream == stream) }
    }

    private func unique(_ options: [Option]) -> [Option] {
        var seen = Set<String>()
        return options.filter { seen.insert($0.id).inserted }
    }

    private var degreeBinding: Binding<String> {
        Binding(get: { degree }, set: { value in
            degree = value
            facultySlug = nil
            majorSlug = nil
            year = nil
            stream = nil
        })
    }

    private var facultyBinding: Binding<String?> {
        Binding(get: { facultySlug }, set: { value in
            facultySlug = value
            majorSlug = nil
            year = nil
            stream = nil
        })
    }

    private var majorBinding: Binding<String?> {
        Binding(get: { majorSlug }, set: { value in
            majorSlug = value
            year = nil
            stream = nil
        })
    }

    private var yearBinding: Binding<Int?> {
        Binding(get: { year }, set: { value in
            year = value
            stream = nil
        })
    }

    private var filterCard: some View {
        GlassCard(padding: 16) {
            VStack(spacing: 0) {
                filterRow(s.degree, value: s.degreeTitle(degree)) {
                    Picker(s.degree, selection: degreeBinding.animation(.smooth(duration: 0.35))) {
                        ForEach(degrees, id: \.self) { value in
                            Text(s.degreeTitle(value)).tag(value)
                        }
                    }
                }
                Divider().overlay(Theme.separator)
                filterRow(s.faculty, value: faculties.first { $0.id == facultySlug }?.short) {
                    Picker(s.faculty, selection: facultyBinding.animation(.smooth(duration: 0.35))) {
                        Text(s.choose).tag(String?.none)
                        ForEach(faculties) { option in
                            Text(option.title).tag(Optional(option.id))
                        }
                    }
                }
                Divider().overlay(Theme.separator)
                filterRow(s.major, value: majors.first { $0.id == majorSlug }?.short) {
                    Picker(s.major, selection: majorBinding.animation(.smooth(duration: 0.35))) {
                        Text(s.choose).tag(String?.none)
                        ForEach(majors) { option in
                            Text(option.title).tag(Optional(option.id))
                        }
                    }
                }
                .disabled(facultySlug == nil)
                Divider().overlay(Theme.separator)
                filterRow(s.year, value: year.map(String.init) ?? s.any) {
                    Picker(s.year, selection: yearBinding.animation(.smooth(duration: 0.35))) {
                        Text(s.any).tag(Int?.none)
                        ForEach(years, id: \.self) { value in
                            Text("\(value)").tag(Optional(value))
                        }
                    }
                }
                .disabled(majorSlug == nil)
                Divider().overlay(Theme.separator)
                filterRow(s.stream, value: stream ?? s.any) {
                    Picker(s.stream, selection: $stream.animation(.smooth(duration: 0.35))) {
                        Text(s.any).tag(String?.none)
                        ForEach(streams, id: \.self) { value in
                            Text(value).tag(Optional(value))
                        }
                    }
                }
                .disabled(majorSlug == nil)
            }
        }
    }

    private var selectedMajorTitle: String? {
        majors.first { $0.id == majorSlug }?.title
    }

    private func filterRow<Content: View>(_ title: String, value: String?, @ViewBuilder picker: () -> Content) -> some View {
        FilterRow(title: title, value: value, placeholder: s.choose) {
            picker()
                .pickerStyle(.inline)
        }
    }

    private var contentKey: Int {
        if items.isEmpty && store.isLoading(kind) { return 0 }
        if store.errors[kind] != nil && items.isEmpty { return 1 }
        if items.isEmpty { return 2 }
        if majorSlug == nil { return 3 }
        return results.isEmpty ? 4 : 5
    }

    @ViewBuilder
    private var content: some View {
        if items.isEmpty && store.isLoading(kind) {
            ProgressView(s.loading)
                .tint(.white)
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 40)
                .transition(.opacity)
        } else if let error = store.errors[kind], items.isEmpty {
            ContentUnavailableView {
                Label(s.message(for: error), systemImage: "wifi.exclamationmark")
            } description: {
                Text(s.noSchedulesHint)
            } actions: {
                Button(s.retry) {
                    Task { await store.load(kind, force: true) }
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)
            }
        } else if items.isEmpty {
            ContentUnavailableView(s.noSchedules, systemImage: "calendar.badge.exclamationmark", description: Text(s.noSchedulesHint))
        } else if majorSlug == nil {
            Text(s.selectMajorHint)
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .transition(.opacity)
        } else if results.isEmpty {
            ContentUnavailableView(s.noSchedules, systemImage: "calendar.badge.exclamationmark", description: Text(s.noSchedulesHint))
        } else {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: selectedMajorTitle ?? s.results)
                ForEach(results) { item in
                    resultRow(item)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
        }
    }

    private func myCard(_ item: ScheduleItem) -> some View {
        Button {
            opened = item
        } label: {
            HStack(spacing: 14) {
                IconBadge(systemImage: "star.fill", tint: Theme.accentBright, size: 46)
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.mySchedule)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(item.major)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(s.courseStream(year: item.year, stream: item.stream))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accentSoft)
                }
                Spacer(minLength: 8)
                Image(systemName: item.isPdf ? "doc.richtext.fill" : "safari.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
            .padding(18)
        }
        .buttonStyle(.glassTile(cornerRadius: Theme.cardRadius, tint: Theme.accent.opacity(0.35)))
    }

    private func resultRow(_ item: ScheduleItem) -> some View {
        let isPinned = store.pinned.map { $0.matches(item) } ?? false
        return Button {
            opened = item
        } label: {
            HStack(spacing: 14) {
                IconBadge(systemImage: item.isPdf ? "doc.text.fill" : "safari.fill", tint: item.isPdf ? Theme.accent : Theme.gradeGood)
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.courseStream(year: item.year, stream: item.stream))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                    Text([item.academicYear, s.semesterTitle(item.semester)].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if isPinned {
                    Text(s.pinned)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.accentSoft)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(14)
        }
        .buttonStyle(.glassTile())
        .contentShape(.contextMenuPreview, .rect(cornerRadius: Theme.rowRadius))
        .contextMenu {
            if isPinned {
                Button(s.unpin, systemImage: "star.slash") {
                    withAnimation(.smooth(duration: 0.35)) { store.pinned = nil }
                }
            } else {
                Button(s.pinAsMine, systemImage: "star") {
                    withAnimation(.smooth(duration: 0.35)) { store.pinned = ScheduleSelection(item: item) }
                }
            }
        }
    }

    private func prefillIfNeeded() {
        guard !didPrefill, !items.isEmpty else { return }
        didPrefill = true
        let student = session.snapshot?.student
        let source = store.myItem(kind, student: student)
        if let source {
            degree = source.degree
            facultySlug = source.facultySlug
            majorSlug = source.majorSlug
            year = source.year
            stream = nil
        } else if student?.isMaster == true {
            degree = "master"
        }
    }
}

private struct FilterRow<Options: View>: View {
    let title: String
    let value: String?
    let placeholder: String
    @ViewBuilder var options: Options

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Menu {
            options
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize()
                Spacer(minLength: 8)
                Text(value ?? placeholder)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(value == nil ? Theme.textSecondary : .white)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 12)
            }
            .frame(minHeight: 46)
            .contentShape(.rect)
        }
        .opacity(isEnabled ? 1 : 0.4)
        .animation(.smooth(duration: 0.3), value: isEnabled)
    }
}
