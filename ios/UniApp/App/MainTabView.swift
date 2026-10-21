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

private struct TabRevealState {
    var opacity = 1.0
    var scale = 1.0
}

private extension View {
    func tabReveal(_ selection: AppTab) -> some View {
        keyframeAnimator(initialValue: TabRevealState(), trigger: selection) { content, value in
            content
                .opacity(value.opacity)
                .scaleEffect(value.scale)
        } keyframes: { _ in
            KeyframeTrack(\.opacity) {
                MoveKeyframe(0)
                CubicKeyframe(0.6, duration: 0.14)
                CubicKeyframe(1, duration: 0.34)
            }
            KeyframeTrack(\.scale) {
                MoveKeyframe(0.985)
                SpringKeyframe(1, duration: 0.5, spring: .smooth)
            }
        }
    }
}
