import SwiftUI

@main
struct UniAppApp: App {
    @State private var session = SessionStore()
    @State private var schedules = ScheduleStore()
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(schedules)
                .environment(settings)
                .environment(\.strings, settings.strings)
                .environment(\.locale, settings.language.locale)
                .preferredColorScheme(.dark)
                .tint(Theme.accentBright)
        }
    }
}
