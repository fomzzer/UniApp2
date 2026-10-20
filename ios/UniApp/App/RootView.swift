import LocalAuthentication
import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase

    @State private var isLocked = false

    var body: some View {
        ZStack {
            switch session.phase {
            case .launching:
                SplashView()
            case .signedOut:
                LoginView()
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
            case .signedIn:
                MainTabView()
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }

            if session.phase == .signedIn && isLocked {
                LockView { isLocked = false }
                    .transition(.opacity)
                    .zIndex(2)
            } else if session.phase == .signedIn && scenePhase != .active {
                PrivacyShield()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.smooth(duration: 0.45), value: session.phase)
        .animation(.smooth(duration: 0.25), value: isLocked)
        .task {
            session.bootstrap()
            isLocked = settings.biometricLock
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && settings.biometricLock {
                isLocked = true
            }
        }
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            AppBackground()
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .shadow(color: Theme.accentBright.opacity(0.7), radius: 28)
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
