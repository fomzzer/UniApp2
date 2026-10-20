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
            }
            Tab(s.tabGrades, systemImage: "graduationcap.fill", value: AppTab.grades) {
                GradesView()
            }
            Tab(s.tabSchedule, systemImage: "calendar", value: AppTab.schedule) {
                ScheduleView()
            }
            Tab(s.tabProfile, systemImage: "person.crop.circle.fill", value: AppTab.profile) {
                ProfileView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
