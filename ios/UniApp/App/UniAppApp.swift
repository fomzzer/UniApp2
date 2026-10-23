import SwiftUI

@main
struct UniAppApp: App {
    @State private var session = SessionStore()
    @State private var schedules = ScheduleStore()
    @State private var settings = AppSettings()
    @State private var mail = MailStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(schedules)
                .environment(settings)
                .environment(mail)
                .environment(\.strings, settings.strings)
                .environment(\.locale, settings.language.locale)
                .preferredColorScheme(.dark)
                .tint(Theme.accentBright)
        }
    }
}
