import SwiftUI

struct GradeBadge: View {
    let grade: Int?
    var credited: Bool = false
    var size: CGFloat = 44

    var body: some View {
        Text(text)
            .font(.system(size: size * 0.44, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .glassEffect(.regular.tint(color.opacity(0.75)), in: .rect(cornerRadius: size * 0.34))
    }

    private var color: Color {
        if grade == nil && credited { return Theme.success }
        return Theme.gradeColor(grade)
    }

    private var text: String {
        if let grade { return "\(grade)" }
        return credited ? "✓" : "–"
    }
}

struct GPAScale: View {
    let value: Double?

    var body: some View {
        GeometryReader { proxy in
            let fraction = max(0, min(1, ((value ?? 2) - 2) / 4))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.12))
                Capsule()
                    .fill(LinearGradient(colors: [Theme.accent, Theme.accentSoft], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(10, proxy.size.width * fraction))
                    .shadow(color: Theme.accentBright.opacity(0.6), radius: 8)
            }
        }
        .frame(height: 8)
    }
}
