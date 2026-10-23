import SwiftUI

struct AppBackground: View {
    var glow: Double = 1

    var body: some View {
        ZStack {
            Color.black
            MeshGradient(
                width: 3,
                height: 4,
                points: [
                    SIMD2<Float>(0, 0), SIMD2<Float>(0.5, 0), SIMD2<Float>(1, 0),
                    SIMD2<Float>(0, 0.22), SIMD2<Float>(0.62, 0.18), SIMD2<Float>(1, 0.26),
                    SIMD2<Float>(0, 0.55), SIMD2<Float>(0.4, 0.5), SIMD2<Float>(1, 0.58),
                    SIMD2<Float>(0, 1), SIMD2<Float>(0.5, 1), SIMD2<Float>(1, 1),
                ],
                colors: [
                    Theme.deepBlue, Theme.accent.opacity(0.9), Theme.deepBlue,
                    Theme.midnight, Theme.accent.opacity(0.45), Theme.deepBlue.opacity(0.8),
                    .black, Theme.midnight, .black,
                    .black, .black, .black,
                ]
            )
            .opacity(glow)
        }
        .ignoresSafeArea()
    }
}

struct SectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accentSoft)
            }
        }
        .padding(.horizontal, 4)
    }
}

struct AvatarView: View {
    let initials: String
    var size: CGFloat = 52
    var tint: Color = Theme.accent

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .glassEffect(.regular.tint(tint.opacity(0.55)), in: .circle)
    }
}

struct InfoRow: View {
    let title: String
    let value: String?
    var valueColor: Color = Theme.textPrimary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 12)
            Text(value?.isEmpty == false ? value! : "—")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 10)
    }
}

struct IconBadge: View {
    let systemImage: String
    var tint: Color = Theme.accent
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: size, height: size)
            .glassEffect(.regular.tint(tint.opacity(0.6)), in: .rect(cornerRadius: size * 0.32))
            .animation(.smooth(duration: 0.3), value: tint)
    }
}

struct GlassNavigationBar<Center: View, Trailing: View>: View {
    @ViewBuilder var center: Center
    @ViewBuilder var trailing: Trailing

    @Environment(\.dismiss) private var dismiss
    @Environment(\.strings) private var s

    var body: some View {
        ZStack {
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.backward")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel(s.back)
                .accessibilityIdentifier("nav.back")
                Spacer(minLength: 0)
                trailing
            }
            center
                .padding(.horizontal, 64)
        }
        .padding(.horizontal, Theme.pagePadding)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }
}

struct GlassBarButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

extension View {
    func swipeBack() -> some View {
        background { SwipeBackEnabler().frame(width: 0, height: 0) }
    }
}

private struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            enable()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            enable()
        }

        private func enable() {
            guard let navigation = navigationController else { return }
            SwipeBackDelegate.shared.attach(to: navigation)
        }
    }
}

private final class SwipeBackDelegate: NSObject, UIGestureRecognizerDelegate {
    static let shared = SwipeBackDelegate()

    private weak var navigation: UINavigationController?

    func attach(to navigation: UINavigationController) {
        self.navigation = navigation
        guard let recognizer = navigation.interactivePopGestureRecognizer else { return }
        recognizer.isEnabled = true
        recognizer.delegate = self
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        (navigation?.viewControllers.count ?? 0) > 1
    }
}
