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
                    .tabReveal(selection)
            }
            Tab(s.tabGrades, systemImage: "graduationcap.fill", value: AppTab.grades) {
                GradesView()
                    .tabReveal(selection)
            }
            Tab(s.tabSchedule, systemImage: "calendar", value: AppTab.schedule) {
                ScheduleView()
                    .tabReveal(selection)
            }
            Tab(s.tabProfile, systemImage: "person.crop.circle.fill", value: AppTab.profile) {
                ProfileView()
                    .tabReveal(selection)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

private extension View {
    func tabReveal(_ selection: AppTab) -> some View {
        keyframeAnimator(initialValue: 1.0, trigger: selection) { content, value in
            content.opacity(value)
        } keyframes: { _ in
            KeyframeTrack {
                MoveKeyframe(0.35)
                CubicKeyframe(1.0, duration: 0.3)
            }
        }
    }
}
