import SwiftUI

struct ScheduleView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ScheduleStore.self) private var store
    @Environment(\.strings) private var s

    @AppStorage("schedule.kind") private var kind: ScheduleKind = .lectures
    @State private var filters: [ScheduleKind: ScheduleFilter] = [:]
    @State private var resolvedKinds: Set<ScheduleKind> = []
    @State private var missingKinds: Set<ScheduleKind> = []
    @State private var opened: ScheduleItem?

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
                        if kind == .lectures, mine.isPdf {
                            MyTimetableSection(item: mine) { opened = mine }
                                .transition(.opacity)
                        } else {
                            myCard(mine)
                                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        }
                    }

                    let catalog = self.catalog
                    let filter = catalog.sanitized(filters[kind] ?? ScheduleFilter())
                    filterCard(catalog, filter)
                    content(catalog, filter)
                        .animation(.smooth(duration: 0.35), value: contentKey(catalog, filter))
                }
                .padding(.horizontal, Theme.pagePadding)
                .padding(.bottom, 32)
            }
            .background { AppBackground(glow: 0.75) }
            .navigationTitle(s.tabSchedule)
            .refreshable { await store.load(kind, force: true) }
            .task(id: kind) {
                resolveIfNeeded()
                await store.load(kind)
                resolveIfNeeded()
            }
            .onChange(of: store.items(kind)) {
                if missingKinds.contains(kind) {
                    resolvedKinds.remove(kind)
                }
                resolveIfNeeded()
            }
            .onChange(of: session.snapshot?.student) {
                resolvedKinds = resolvedKinds.filter { filters[$0]?.facultySlug != nil }
                resolveIfNeeded()
            }
            .sheet(item: $opened) { item in
                ScheduleDocumentView(item: item)
            }
        }
    }

    private var catalog: ScheduleCatalog {
        ScheduleCatalog(items: store.items(kind))
    }

    private var currentFilter: ScheduleFilter {
        catalog.sanitized(filters[kind] ?? ScheduleFilter())
    }

    private func commit(_ filter: ScheduleFilter) {
        filters[kind] = filter
        resolvedKinds.insert(kind)
        missingKinds.remove(kind)
        guard filter.hasMajor else { return }
        for other in ScheduleKind.allCases where other != kind {
            filters[other] = nil
            resolvedKinds.remove(other)
        }
    }

    private var degreeBinding: Binding<String> {
        Binding(get: { currentFilter.degree }, set: { value in
            commit(ScheduleFilter(degree: value))
        })
    }

    private var facultyBinding: Binding<String?> {
        Binding(get: { currentFilter.facultySlug }, set: { value in
            commit(ScheduleFilter(degree: currentFilter.degree, facultySlug: value))
        })
    }

    private var majorBinding: Binding<String?> {
        Binding(get: { currentFilter.majorSlug }, set: { value in
            let filter = currentFilter
            commit(ScheduleFilter(degree: filter.degree, facultySlug: filter.facultySlug, majorSlug: value))
        })
    }

    private var yearBinding: Binding<Int?> {
        Binding(get: { currentFilter.year }, set: { value in
            var filter = currentFilter
            filter.year = value
            commit(catalog.sanitized(filter))
        })
    }

    private var streamBinding: Binding<String?> {
        Binding(get: { currentFilter.stream }, set: { value in
            var filter = currentFilter
            filter.stream = value
            commit(filter)
        })
    }

    private func filterCard(_ catalog: ScheduleCatalog, _ filter: ScheduleFilter) -> some View {
        let faculties = catalog.faculties(filter)
        let majors = catalog.majors(filter)
        let years = catalog.years(filter)
        let streams = catalog.streams(filter)
        return GlassCard(padding: 16) {
            VStack(spacing: 0) {
                filterRow(s.degree, value: s.degreeTitle(filter.degree)) {
                    Picker(s.degree, selection: degreeBinding.animation(.smooth(duration: 0.35))) {
                        ForEach(catalog.degrees, id: \.self) { value in
                            Text(s.degreeTitle(value)).tag(value)
                        }
                    }
                }
                Divider().overlay(Theme.separator)
                filterRow(s.faculty, value: faculties.first { $0.id == filter.facultySlug }?.short) {
                    Picker(s.faculty, selection: facultyBinding.animation(.smooth(duration: 0.35))) {
                        Text(s.choose).tag(String?.none)
                        ForEach(faculties) { option in
                            Text(option.title).tag(Optional(option.id))
                        }
                    }
                }
                .disabled(faculties.isEmpty)
                Divider().overlay(Theme.separator)
                filterRow(s.major, value: majors.first { $0.id == filter.majorSlug }?.short) {
                    Picker(s.major, selection: majorBinding.animation(.smooth(duration: 0.35))) {
                        Text(s.choose).tag(String?.none)
                        ForEach(majors) { option in
                            Text(option.title).tag(Optional(option.id))
                        }
                    }
                }
                .disabled(majors.isEmpty)
                Divider().overlay(Theme.separator)
                filterRow(s.year, value: filter.year.map(String.init)) {
                    Picker(s.year, selection: yearBinding.animation(.smooth(duration: 0.35))) {
                        Text(s.choose).tag(Int?.none)
                        ForEach(years, id: \.self) { value in
                            Text("\(value)").tag(Optional(value))
                        }
                    }
                }
                .disabled(years.isEmpty)
                Divider().overlay(Theme.separator)
                filterRow(s.stream, value: filter.stream) {
                    Picker(s.stream, selection: streamBinding.animation(.smooth(duration: 0.35))) {
                        Text(s.choose).tag(String?.none)
                        ForEach(streams, id: \.self) { value in
                            Text(value).tag(Optional(value))
                        }
                    }
                }
                .disabled(streams.isEmpty)
            }
        }
        // Moves the card as one piece, so its rows don't animate their own frames.
        .geometryGroup()
    }

    private func filterRow<Content: View>(_ title: String, value: String?, @ViewBuilder picker: () -> Content) -> some View {
        FilterRow(title: title, value: value, placeholder: s.choose) {
            picker()
                .pickerStyle(.inline)
        }
    }

    private func contentKey(_ catalog: ScheduleCatalog, _ filter: ScheduleFilter) -> Int {
        if catalog.items.isEmpty && store.isLoading(kind) { return 0 }
        if store.errors[kind] != nil && catalog.items.isEmpty { return 1 }
        if catalog.items.isEmpty { return 2 }
        if !filter.hasMajor { return 3 }
        return catalog.results(filter).isEmpty ? 4 : 5
    }

    @ViewBuilder
    private func content(_ catalog: ScheduleCatalog, _ filter: ScheduleFilter) -> some View {
        let results = catalog.results(filter)
        if catalog.items.isEmpty && store.isLoading(kind) {
            ProgressView(s.loading)
                .tint(.white)
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 40)
                .transition(.opacity)
        } else if let error = store.errors[kind], catalog.items.isEmpty {
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
        } else if catalog.items.isEmpty {
            ContentUnavailableView(s.noSchedules, systemImage: "calendar.badge.exclamationmark", description: Text(s.noSchedulesHint))
        } else if !filter.hasMajor {
            Text(missingKinds.contains(kind) ? s.mineNotPublished : s.selectMajorHint)
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .transition(.opacity)
        } else if results.isEmpty {
            ContentUnavailableView(s.noSchedules, systemImage: "calendar.badge.exclamationmark", description: Text(s.noSchedulesHint))
        } else {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: catalog.majors(filter).first { $0.id == filter.majorSlug }?.title ?? s.results)
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

    private func resolveIfNeeded() {
        let items = store.items(kind)
        guard !resolvedKinds.contains(kind), !items.isEmpty else { return }
        let student = session.snapshot?.student
        let target = carriedFilter ?? mineFilter(student)
        let resolved = ScheduleCatalog(items: items).resolve(target, student: student)
        let missing = !resolved.hasMajor && (target?.hasMajor == true || student?.specialty?.isEmpty == false)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            filters[kind] = resolved
            resolvedKinds.insert(kind)
            if missing {
                missingKinds.insert(kind)
            } else {
                missingKinds.remove(kind)
            }
        }
    }

    private var carriedFilter: ScheduleFilter? {
        ScheduleKind.allCases
            .filter { $0 != kind }
            .compactMap { filters[$0] }
            .first { $0.hasMajor }
    }

    private func mineFilter(_ student: Student?) -> ScheduleFilter? {
        let order = [kind] + ScheduleKind.allCases.filter { $0 != kind }
        guard let mine = order.lazy.compactMap({ store.myItem($0, student: student) }).first else { return nil }
        var filter = ScheduleFilter(item: mine)
        if let pinned = store.pinned, pinned.matches(mine) {
            filter.year = pinned.year
            filter.stream = pinned.stream
        }
        return filter
    }
}

private struct FilterRow<Options: View>: View {
    let title: String
    let value: String?
    let placeholder: String
    @ViewBuilder var options: Options

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        // The label is drawn outside the Menu: a Menu label is hosted in UIKit and
        // lags behind when the card moves, so the text would jitter on its own.
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
        // Values swap in place instead of sliding while the card itself animates.
        .transaction { $0.animation = nil }
        .overlay {
            Menu {
                options
            } label: {
                Color.clear
                    .contentShape(.rect)
            }
        }
        .opacity(isEnabled ? 1 : 0.4)
        .animation(.smooth(duration: 0.3), value: isEnabled)
    }
}
