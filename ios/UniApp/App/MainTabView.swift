import SwiftUI

enum AppTab: Hashable {
    case home
    case grades
    case schedule
    case profile
}

struct MainTabView: View {
    @Environment(\.strings) private var s
    @State private var selection: AppTab = .home

    var body: some View {
        TabView(selection: $selection) {
            Tab(s.tabHome, systemImage: "house.fill", value: AppTab.home) {
                HomeView(selection: $selection)
                    .tabReveal(.home, selection: selection, glow: 1)
            }
            Tab(s.tabGrades, systemImage: "graduationcap.fill", value: AppTab.grades) {
                GradesView()
                    .tabReveal(.grades, selection: selection, glow: 0.75)
            }
            Tab(s.tabSchedule, systemImage: "calendar", value: AppTab.schedule) {
                ScheduleView()
                    .tabReveal(.schedule, selection: selection, glow: 0.75)
            }
            Tab(s.tabProfile, systemImage: "person.crop.circle.fill", value: AppTab.profile) {
                ProfileView()
                    .tabReveal(.profile, selection: selection, glow: 0.75)
            }
        }
        .appTabBarMinimizesOnScroll()
        .sensoryFeedback(.selection, trigger: selection)
    }
}

private extension View {
    func tabReveal(_ tab: AppTab, selection: AppTab, glow: Double) -> some View {
        modifier(TabReveal(isSelected: selection == tab, glow: glow))
    }
}

// Fades in only the tab being opened. The outgoing tab stays untouched while the
// switch completes, and a matching opaque backdrop keeps the page from flashing.
private struct TabReveal: ViewModifier {
    let isSelected: Bool
    let glow: Double

    @State private var reveals = 0

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: 1.0, trigger: reveals) { content, value in
                content
                    .opacity(value)
                    .background { AppBackground(glow: glow) }
            } keyframes: { _ in
                KeyframeTrack {
                    MoveKeyframe(0.5)
                    LinearKeyframe(1.0, duration: 0.45, timingCurve: .easeOut)
                }
            }
            .onChange(of: isSelected) { _, selected in
                if selected { reveals += 1 }
            }
    }
}
