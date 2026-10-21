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

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .glassEffect(.regular.tint(Theme.accent.opacity(0.55)), in: .circle)
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
