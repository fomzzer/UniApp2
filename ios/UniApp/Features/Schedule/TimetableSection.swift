import SwiftUI

extension TimetablePlanner {
    init(timetable: Timetable, student: Student?, savedGroup: String, flipWeek: Bool) {
        let known = !savedGroup.isEmpty && (timetable.groups.contains(savedGroup) || timetable.groups.contains { TimetablePlanner.base($0) == savedGroup })
        self.init(timetable: timetable, group: known ? savedGroup : TimetablePlanner.defaultGroup(for: student, in: timetable), parityFlipped: flipWeek)
    }
}

extension LessonKind {
    var color: Color {
        switch self {
        case .lecture: Theme.accentBright
        case .lab: Theme.success
        case .seminar: Theme.gradeFair
        }
    }
}

struct MyTimetableSection: View {
    let item: ScheduleItem
    let openDocument: () -> Void

    @Environment(ScheduleStore.self) private var store
    @Environment(SessionStore.self) private var session
    @Environment(\.strings) private var s

    @AppStorage("timetable.group") private var savedGroup = ""
    @AppStorage("timetable.flipWeek") private var flipWeek = false
    @State private var selectedDay: Int?
    @State private var shownParity: WeekParity?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let timetable = store.timetable(for: item), timetable.status == .ok, !timetable.lessons.isEmpty {
                content(TimetablePlanner(timetable: timetable, student: session.snapshot?.student, savedGroup: savedGroup, flipWeek: flipWeek))
                    .transition(.opacity)
            } else if store.timetableLoading.contains(item.id) && store.timetable(for: item) == nil {
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text(s.timetablePreparing)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .transition(.opacity)
            } else {
                unsupported
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.35), value: store.timetable(for: item))
        .task(id: item.id) { await store.loadTimetable(item) }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(s.mySchedule)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Text([item.major, s.courseStream(year: item.year, stream: item.stream)].joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Menu {
                if let timetable = store.timetable(for: item), timetable.status == .ok, !timetable.groups.isEmpty {
                    Picker(s.timetableGroup, selection: groupBinding(timetable)) {
                        Text(s.timetableAllGroups).tag("")
                        ForEach(groupChoices(timetable), id: \.self) { group in
                            Text(group).tag(group)
                        }
                    }
                    Toggle(s.timetableFlipWeek, systemImage: "arrow.left.arrow.right", isOn: $flipWeek)
                }
                Button(s.openPdf, systemImage: "doc.richtext", action: openDocument)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .contentShape(.circle)
            }
            .appGlass(interactive: true, in: .circle)
            .accessibilityIdentifier("timetable.menu")
        }
        .padding(.horizontal, 4)
    }

    private func groupChoices(_ timetable: Timetable) -> [String] {
        var result: [String] = []
        for group in timetable.groups {
            if let base = TimetablePlanner.base(group), base != group, timetable.groups.filter({ TimetablePlanner.base($0) == base }).count > 1, !result.contains(base), !timetable.groups.contains(base) {
                result.append(base)
            }
            result.append(group)
        }
        return result
    }

    private func groupBinding(_ timetable: Timetable) -> Binding<String> {
        Binding(
            get: { TimetablePlanner(timetable: timetable, student: session.snapshot?.student, savedGroup: savedGroup, flipWeek: flipWeek).group ?? "" },
            set: { value in withAnimation(.smooth(duration: 0.35)) { savedGroup = value } }
        )
    }

    private var unsupported: some View {
        Button(action: openDocument) {
            HStack(spacing: 14) {
                IconBadge(systemImage: "doc.richtext.fill", tint: Theme.accentBright, size: 46)
                Text(s.timetableUnsupported)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(16)
        }
        .buttonStyle(.glassTile(cornerRadius: Theme.cardRadius, tint: Theme.accent.opacity(0.25)))
        .accessibilityIdentifier("timetable.openPdf")
    }

    @ViewBuilder
    private func content(_ planner: TimetablePlanner) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            TimetableNowCard(planner: planner, date: context.date)
        }
        if planner.group == nil, !planner.timetable.groups.isEmpty {
            groupPrompt(s.timetableChooseGroup, choices: groupChoices(planner.timetable), planner: planner)
        } else if planner.needsSubgroup {
            groupPrompt(s.timetableChooseSubgroup, choices: planner.subgroups, planner: planner)
        }
        let today = planner.dayIndex(.now)
        let day = selectedDay ?? (planner.days.contains(today) ? today : planner.days.first ?? 0)
        let current = planner.parity(on: .now)
        let parity = shownParity ?? current
        weekBar(planner, current: current, shown: parity)
        dayPicker(planner, selected: day, today: today, parity: parity)
        lessonList(planner.lessons(day: day, parity: parity), planner: planner)
            .id("\(day)-\(parity.rawValue)-\(planner.group ?? "")")
            .transition(.opacity)
            .animation(.smooth(duration: 0.3), value: "\(day)-\(parity.rawValue)-\(planner.group ?? "")")
    }

    private func groupPrompt(_ title: String, choices: [String], planner: TimetablePlanner) -> some View {
        GlassCard(tint: Theme.accent.opacity(0.22), padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(choices, id: \.self) { group in
                            Button {
                                withAnimation(.smooth(duration: 0.35)) { savedGroup = group }
                            } label: {
                                Text(group)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 9)
                                    .appGlass(tint: Theme.accent.opacity(planner.group == group ? 0.7 : 0.2), interactive: true, in: .capsule)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("timetable.group")
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func weekBar(_ planner: TimetablePlanner, current: WeekParity, shown: WeekParity) -> some View {
        HStack(spacing: 12) {
            Text(s.currentWeek(planner.weekNumber(on: .now), current))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            Picker(s.timetableGroup, selection: Binding(get: { shown }, set: { value in
                withAnimation(.smooth(duration: 0.3)) { shownParity = value == current ? nil : value }
            })) {
                ForEach(WeekParity.allCases) { parity in
                    Text(s.weekParity(parity)).tag(parity)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()
        }
        .padding(.horizontal, 4)
    }

    private func dayPicker(_ planner: TimetablePlanner, selected: Int, today: Int, parity: WeekParity) -> some View {
        GlassCard(padding: 6) {
            HStack(spacing: 4) {
                ForEach(planner.days, id: \.self) { day in
                    let busy = !planner.lessons(day: day, parity: parity).isEmpty
                    Button {
                        withAnimation(.smooth(duration: 0.3)) { selectedDay = day }
                    } label: {
                        VStack(spacing: 5) {
                            Text(s.dayShort(day))
                                .font(.subheadline.weight(day == selected ? .bold : .semibold))
                                .foregroundStyle(day == selected ? .white : (day == today ? Theme.accentSoft : Theme.textSecondary))
                            Circle()
                                .fill(busy ? (day == selected ? Color.white : Theme.accentSoft) : .clear)
                                .frame(width: 5, height: 5)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if day == selected {
                                Capsule()
                                    .fill(Theme.accent.opacity(0.55))
                                    .matchedGeometryEffect(id: "day", in: dayNamespace)
                            }
                        }
                        .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("timetable.day")
                }
            }
        }
    }

    @Namespace private var dayNamespace

    @ViewBuilder
    private func lessonList(_ lessons: [TimetableLesson], planner: TimetablePlanner) -> some View {
        if lessons.isEmpty {
            GlassCard(padding: 22) {
                HStack(spacing: 12) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.accentSoft)
                    Text(s.timetableFreeDay)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            GlassCard(padding: 6) {
                VStack(spacing: 0) {
                    ForEach(Array(lessons.enumerated()), id: \.element.id) { index, lesson in
                        TimetableLessonRow(lesson: lesson, showGroups: planner.group == nil || planner.needsSubgroup)
                            .padding(.horizontal, 12)
                        if index < lessons.count - 1 {
                            Divider().overlay(Theme.separator).padding(.leading, 76)
                        }
                    }
                }
            }
            .accessibilityIdentifier("timetable.lessons")
        }
    }
}

struct TimetableLessonRow: View {
    let lesson: TimetableLesson
    var showGroups = false

    @Environment(\.strings) private var s

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(lesson.start)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Text(lesson.end)
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            .monospacedDigit()
            .frame(width: 46, alignment: .trailing)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(lesson.lessonKind?.color ?? Theme.textTertiary)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 5) {
                Text(lesson.subject.isEmpty ? lesson.text : lesson.subject)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if let kind = lesson.lessonKind {
                        Text(s.lessonKind(kind))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(kind.color)
                    }
                    if let room = lesson.room {
                        Label(s.room(room), systemImage: "mappin")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.textSecondary)
                            .labelStyle(.titleAndIcon)
                    }
                }
                if lesson.week != nil || (showGroups && !lesson.groups.isEmpty) {
                    HStack(spacing: 6) {
                        if let week = lesson.week {
                            tag(s.weekParityShort(week), tint: Theme.gradeGood)
                        }
                        if showGroups, !lesson.groups.isEmpty {
                            tag(lesson.groups.joined(separator: ", "), tint: Theme.accent)
                        }
                    }
                }
                ForEach(lesson.notes, id: \.self) { note in
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }

    private func tag(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.35), in: .capsule)
    }
}

struct TimetableNowCard: View {
    let planner: TimetablePlanner
    let date: Date

    @Environment(\.strings) private var s

    var body: some View {
        let moment = planner.moment(at: date)
        VStack(spacing: 10) {
            if let current = moment.current {
                GlassCard(tint: (current.lessonKind?.color ?? Theme.accent).opacity(0.3), padding: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label(s.timetableNow, systemImage: "dot.radiowaves.left.and.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                            Spacer()
                            Text("\(current.start) – \(current.end)")
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Text(current.subject.isEmpty ? current.text : current.subject)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                        details(current)
                        let minutes = minutesNow
                        let total = max(1, current.endMinutes - current.startMinutes)
                        ProgressView(value: Double(min(max(minutes - current.startMinutes, 0), total)), total: Double(total))
                            .tint(.white)
                        Text(s.minutesLeft(max(0, current.endMinutes - minutes)))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            if let next = moment.next, let day = moment.nextDate {
                GlassCard(padding: 16) {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(s.timetableNext) · \(when(next, day: day))")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.accentSoft)
                            Text(next.subject.isEmpty ? next.text : next.subject)
                                .font(.headline)
                                .foregroundStyle(.white)
                            details(next)
                        }
                        Spacer(minLength: 0)
                    }
                }
            } else if moment.current == nil {
                GlassCard(padding: 16) {
                    Text(s.timetableEmpty)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityIdentifier("timetable.now")
    }

    private var minutesNow: Int {
        planner.calendar.component(.hour, from: date) * 60 + planner.calendar.component(.minute, from: date)
    }

    private func details(_ lesson: TimetableLesson) -> some View {
        HStack(spacing: 8) {
            if let kind = lesson.lessonKind {
                Text(s.lessonKind(kind))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(kind.color)
            }
            if let room = lesson.room {
                Text(s.room(room))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func when(_ lesson: TimetableLesson, day: Date) -> String {
        let calendar = planner.calendar
        if calendar.isDate(day, inSameDayAs: date) {
            let minutes = lesson.startMinutes - minutesNow
            return minutes <= 120 ? s.startsIn(minutes) : "\(s.timetableToday), \(lesson.start)"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: date), calendar.isDate(day, inSameDayAs: tomorrow) {
            return "\(s.timetableTomorrow), \(lesson.start)"
        }
        return "\(s.dayShort(planner.dayIndex(day))), \(lesson.start)"
    }
}

struct TimetableGlance: View {
    let item: ScheduleItem

    @Environment(ScheduleStore.self) private var store
    @Environment(SessionStore.self) private var session
    @Environment(\.strings) private var s

    @AppStorage("timetable.group") private var savedGroup = ""
    @AppStorage("timetable.flipWeek") private var flipWeek = false

    var body: some View {
        if let timetable = store.timetable(for: item), timetable.status == .ok, !timetable.lessons.isEmpty {
            let planner = TimetablePlanner(timetable: timetable, student: session.snapshot?.student, savedGroup: savedGroup, flipWeek: flipWeek)
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let moment = planner.moment(at: context.date)
                if let lesson = moment.current ?? moment.next {
                    let prefix = moment.current != nil ? s.timetableNow : s.timetableNext
                    let place = lesson.room.map { " · " + s.room($0) } ?? ""
                    let time = moment.current != nil ? "\(lesson.start)–\(lesson.end)" : nextTime(lesson, day: moment.nextDate, planner: planner, now: context.date)
                    Text("\(prefix): \(lesson.subject) · \(time)\(place)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accentSoft)
                        .lineLimit(2)
                        .contentTransition(.opacity)
                }
            }
        }
    }

    private func nextTime(_ lesson: TimetableLesson, day: Date?, planner: TimetablePlanner, now: Date) -> String {
        guard let day, !planner.calendar.isDate(day, inSameDayAs: now) else { return lesson.start }
        if let tomorrow = planner.calendar.date(byAdding: .day, value: 1, to: now), planner.calendar.isDate(day, inSameDayAs: tomorrow) {
            return "\(s.timetableTomorrow), \(lesson.start)"
        }
        return "\(s.dayShort(planner.dayIndex(day))), \(lesson.start)"
    }
}
