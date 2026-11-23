import SwiftUI
import UIKit

// MARK: - Colour helpers

extension Color {
    /// `RRGGBB`, optionally multiplied by an alpha.
    init(hex: UInt32, opacity: Double = 1) {
        let hasAlpha = hex > 0xFFFFFF
        let rgb = hasAlpha ? hex >> 8 : hex
        let stored = hasAlpha ? Double(hex & 0xFF) / 255 : 1
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: stored * opacity
        )
    }
}

// MARK: - Tokens

/// AppCatcher's visual language: a deep graphite canvas lit by one cold
/// gradient, cards separated by hairlines instead of shadows, and hierarchy
/// carried by weight and tracking rather than size.
enum ACTheme {
    enum Palette {
        static let canvas = Color(hex: 0x07090E)
        static let canvasDeep = Color(hex: 0x030407)
        static let surface = Color(hex: 0xFFFFFF, opacity: 0.055)
        static let surfaceRaised = Color(hex: 0xFFFFFF, opacity: 0.085)
        static let surfaceSunken = Color(hex: 0x000000, opacity: 0.28)
        static let hairline = Color(hex: 0xFFFFFF, opacity: 0.10)
        static let hairlineStrong = Color(hex: 0xFFFFFF, opacity: 0.18)

        static let text = Color(hex: 0xF5F7FA)
        static let textSecondary = Color(hex: 0xFFFFFF, opacity: 0.62)
        static let textTertiary = Color(hex: 0xFFFFFF, opacity: 0.38)

        /// The house gradient: cleaning, progress, "done".
        static let mint = Color(hex: 0x5AF2C0)
        static let aqua = Color(hex: 0x38BDF8)
        static let violet = Color(hex: 0x8B7CF6)

        static let amber = Color(hex: 0xFFC46B)
        static let danger = Color(hex: 0xFF6B6B)
        static let gold = Color(hex: 0xF3D08A)
    }

    enum Gradients {
        static let hero = LinearGradient(
            colors: [Palette.mint, Palette.aqua, Palette.violet],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        static let glow = LinearGradient(
            colors: [Palette.mint, Palette.aqua],
            startPoint: .leading,
            endPoint: .trailing
        )
        static let premium = LinearGradient(
            colors: [Palette.gold, Color(hex: 0xE3A851), Palette.violet],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        static let ring = AngularGradient(
            gradient: Gradient(colors: [Palette.mint, Palette.aqua, Palette.violet, Palette.mint]),
            center: .center,
            startAngle: .degrees(-90),
            endAngle: .degrees(270)
        )
        static let danger = LinearGradient(
            colors: [Palette.danger, Color(hex: 0xFF9A6B)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    enum Space {
        static let xxs: CGFloat = 3
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 14
        static let lg: CGFloat = 18
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 34
    }

    enum Radius {
        static let chip: CGFloat = 999
        static let sm: CGFloat = 12
        static let md: CGFloat = 18
        static let lg: CGFloat = 24
        static let xl: CGFloat = 30
    }

    enum Motion {
        static let quick = Animation.spring(response: 0.24, dampingFraction: 1)
        static let standard = Animation.spring(response: 0.38, dampingFraction: 1)
        static let springy = Animation.spring(response: 0.46, dampingFraction: 0.74)
        static let sweep = Animation.easeInOut(duration: 1.6).repeatForever(autoreverses: false)
    }
}

// MARK: - Typography

enum ACType {
    /// Hero numbers. Tabular figures stop the value jittering while it counts.
    static let hero = Font.system(size: 52, weight: .bold, design: .rounded).monospacedDigit()
    static let heroSmall = Font.system(size: 34, weight: .bold, design: .rounded).monospacedDigit()
    static let title = Font.system(size: 28, weight: .bold, design: .rounded)
    static let headline = Font.system(size: 19, weight: .semibold)
    static let row = Font.system(size: 16, weight: .medium)
    static let body = Font.system(size: 15)
    static let footnote = Font.system(size: 13, weight: .medium)
    static let caption = Font.system(size: 12)
    static let micro = Font.system(size: 10, weight: .semibold)
}

extension Text {
    /// Section eyebrows: small, wide-tracked, uppercase.
    func eyebrow() -> some View {
        self.font(ACType.micro)
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(ACTheme.Palette.textTertiary)
    }
}

// MARK: - Surfaces

/// The canvas every screen sits on: graphite with two cold light sources.
struct CanvasBackground: View {
    var body: some View {
        ZStack {
            ACTheme.Palette.canvas
            RadialGradient(
                colors: [ACTheme.Palette.aqua.opacity(0.20), .clear],
                center: .topLeading,
                startRadius: 8,
                endRadius: 420
            )
            RadialGradient(
                colors: [ACTheme.Palette.violet.opacity(0.18), .clear],
                center: .bottomTrailing,
                startRadius: 8,
                endRadius: 460
            )
            ACTheme.Palette.canvasDeep.opacity(0.35)
        }
        .ignoresSafeArea()
    }
}

/// Frosted panel with a hairline. The only container in the app.
struct Card<Content: View>: View {
    var padding: CGFloat = ACTheme.Space.lg
    var tint: Color? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ACTheme.Palette.surface, in: RoundedRectangle(cornerRadius: ACTheme.Radius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ACTheme.Radius.lg, style: .continuous)
                    .strokeBorder(tint?.opacity(0.35) ?? ACTheme.Palette.hairline, lineWidth: 1)
            }
    }
}

/// Same panel, but with iOS's native Liquid Glass treatment on iOS 26+,
    /// falling back to the frosted material card on older systems.
    struct GlassCard<Content: View>: View {
        @ViewBuilder var content: () -> Content

        var body: some View {
            content()
                .padding(ACTheme.Space.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
                .nativeGlassCard(radius: ACTheme.Radius.xl)
        }
    }
