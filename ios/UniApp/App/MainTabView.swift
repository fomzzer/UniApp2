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
                    .tabReveal(selection, glow: 1)
            }
            Tab(s.tabGrades, systemImage: "graduationcap.fill", value: AppTab.grades) {
                GradesView()
                    .tabReveal(selection, glow: 0.75)
            }
            Tab(s.tabSchedule, systemImage: "calendar", value: AppTab.schedule) {
                ScheduleView()
                    .tabReveal(selection, glow: 0.75)
            }
            Tab(s.tabProfile, systemImage: "person.crop.circle.fill", value: AppTab.profile) {
                ProfileView()
                    .tabReveal(selection, glow: 0.75)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

private extension View {
    // Only the content fades in: a matching backdrop stays opaque underneath,
    // so nothing darker or brighter shows through mid-reveal.
    func tabReveal(_ selection: AppTab, glow: Double) -> some View {
        keyframeAnimator(initialValue: 1.0, trigger: selection) { content, value in
            content
                .opacity(value)
                .background { AppBackground(glow: glow) }
        } keyframes: { _ in
            KeyframeTrack {
                MoveKeyframe(0.5)
                LinearKeyframe(1.0, duration: 0.45, timingCurve: .easeOut)
            }
        }
    }
}
