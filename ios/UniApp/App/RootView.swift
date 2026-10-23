import LocalAuthentication
import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(AppSettings.self) private var settings
    @Environment(MailStore.self) private var mail
    @Environment(\.scenePhase) private var scenePhase

    @State private var isLocked = false
    @State private var wasActive = false
    @State private var shieldVisible = false

    var body: some View {
        ZStack {
            AppBackground(glow: session.phase == .launching ? 0 : 1)

            switch session.phase {
            case .launching:
                SplashView()
                    .transition(.opacity)
            case .signedOut:
                LoginView()
                    .transition(.opacity)
            case .signedIn:
                MainTabView()
                    .transition(.opacity)
            }

            if session.phase == .signedIn && shieldVisible {
                PrivacyShield()
                    .transition(.opacity)
                    .zIndex(1)
            }

            if session.phase == .signedIn && scenePhase == .background {
                PrivacyShield()
                    .zIndex(1.5)
            }

            if session.phase == .signedIn && isLocked {
                LockView { isLocked = false }
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .animation(.smooth(duration: 0.55), value: session.phase)
        .animation(.smooth(duration: 0.45), value: isLocked)
        .animation(.smooth(duration: 0.35), value: settings.language)
        .task {
            isLocked = settings.biometricLock
            session.bootstrap()
        }
        .onChange(of: session.phase) { _, phase in
            if phase == .signedOut && mail.phase == .ready {
                mail.signOut()
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                wasActive = true
                withAnimation(.smooth(duration: 0.45)) { shieldVisible = false }
            case .inactive:
                if wasActive {
                    withAnimation(.smooth(duration: 0.3)) { shieldVisible = true }
                }
            case .background:
                shieldVisible = true
                if settings.biometricLock {
                    isLocked = true
                }
            @unknown default:
                break
            }
        }
    }
}

struct SplashView: View {
    @State private var appeared = false

    var body: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(width: 96, height: 96)
            .shadow(color: Theme.accentBright.opacity(0.7), radius: 28)
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.9)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                withAnimation(.smooth(duration: 0.4)) { appeared = true }
            }
    }
}

struct PrivacyShield: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Color.black.opacity(0.35)
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
        }
        .ignoresSafeArea()
    }
}

struct LockView: View {
    let onUnlock: () -> Void

    @Environment(\.strings) private var s
    @State private var attempted = false

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 24) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
                    .shadow(color: Theme.accentBright.opacity(0.7), radius: 24)
                Text(s.locked)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Button {
                    Task { await authenticate() }
                } label: {
                    Label(s.unlock, systemImage: "faceid")
                        .font(.headline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)
                .controlSize(.large)
            }
        }
        .task {
            guard !attempted else { return }
            attempted = true
            await authenticate()
        }
    }

    private func authenticate() async {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            onUnlock()
            return
        }
        do {
            if try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: s.unlockReason) {
                onUnlock()
            }
        } catch {
            return
        }
    }
}
