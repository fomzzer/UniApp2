import SwiftUI

enum Theme {
    static let accent = Color(red: 0.012, green: 0.333, blue: 0.969)
    static let accentBright = Color(red: 0.239, green: 0.482, blue: 1.0)
    static let accentSoft = Color(red: 0.49, green: 0.68, blue: 1.0)
    static let deepBlue = Color(red: 0.008, green: 0.09, blue: 0.30)
    static let midnight = Color(red: 0.01, green: 0.025, blue: 0.08)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.64)
    static let textTertiary = Color.white.opacity(0.42)
    static let separator = Color.white.opacity(0.09)

    static let gradeExcellent = Color(red: 0.239, green: 0.482, blue: 1.0)
    static let gradeVeryGood = Color(red: 0.30, green: 0.70, blue: 1.0)
    static let gradeGood = Color(red: 0.52, green: 0.58, blue: 0.93)
    static let gradeFair = Color(red: 1.0, green: 0.62, blue: 0.22)
    static let gradeFail = Color(red: 1.0, green: 0.30, blue: 0.34)
    static let success = Color(red: 0.25, green: 0.85, blue: 0.62)
    static let danger = Color(red: 1.0, green: 0.36, blue: 0.38)

    static let cardRadius: CGFloat = 28
    static let rowRadius: CGFloat = 20
    static let pagePadding: CGFloat = 16

    static func gradeColor(_ value: Double?) -> Color {
        guard let value else { return textTertiary }
        switch value {
        case 5.5...: return gradeExcellent
        case 4.5..<5.5: return gradeVeryGood
        case 3.5..<4.5: return gradeGood
        case 3..<3.5: return gradeFair
        default: return gradeFail
        }
    }

    static func gradeColor(_ value: Int?) -> Color {
        gradeColor(value.map(Double.init))
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = Theme.cardRadius, tint: Color? = nil) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, tint: tint))
    }
}

struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color?

    func body(content: Content) -> some View {
        content.glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
    }

    private var glass: Glass {
        var glass = Glass.regular
        if let tint {
            glass = glass.tint(tint)
        }
        return glass
    }
}

struct GlassCard<Content: View>: View {
    var tint: Color? = nil
    var padding: CGFloat = 20
    var cornerRadius: CGFloat = Theme.cardRadius
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: cornerRadius, tint: tint)
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}
