import SwiftUI

extension View {
    @ViewBuilder
    func appGlass<S: Shape>(tint: Color? = nil, interactive: Bool = false, in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(Self.glass(tint: tint, interactive: interactive), in: shape)
        } else {
            background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(Theme.midnight.opacity(0.35))
                    if let tint {
                        shape.fill(tint)
                    }
                    shape.fill(LinearGradient(colors: [.white.opacity(0.10), .white.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                    shape.stroke(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
                }
                .compositingGroup()
                .shadow(color: .black.opacity(0.28), radius: 12, y: 6)
            }
        }
    }

    @available(iOS 26.0, *)
    private static func glass(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint {
            glass = glass.tint(tint)
        }
        if interactive {
            glass = glass.interactive()
        }
        return glass
    }

    @ViewBuilder
    func appProminentButton() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
        }
    }

    @ViewBuilder
    func appGlassButton() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
        }
    }

    @ViewBuilder
    func appTabBarMinimizesOnScroll() -> some View {
        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }

    @ViewBuilder
    func appHidesTopScrollEdge() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectHidden(true, for: .top)
        } else {
            self
        }
    }

    @ViewBuilder
    func appTopBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .top, content: bar)
        } else {
            safeAreaInset(edge: .top, spacing: 0) {
                bar()
                    .background {
                        LinearGradient(colors: [.black.opacity(0.75), .black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                            .ignoresSafeArea(edges: .top)
                            .allowsHitTesting(false)
                    }
            }
        }
    }
}

struct AppGlassContainer<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
