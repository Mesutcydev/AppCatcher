import SwiftUI
import UIKit

// MARK: - Buttons

/// Press feedback that scales like a real control instead of just dimming.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(ACTheme.Motion.quick, value: configuration.isPressed)
    }
}

/// Applies native iOS button styling: Liquid Glass on iOS 26+, with the
/// equivalent crisp system style as a fallback on older iOS.
extension View {
    @ViewBuilder
    func nativeButton(tone: ButtonTone) -> some View {
        if #available(iOS 26.0, *) {
            switch tone {
            case .hero, .premium:
                self.buttonStyle(.glassProminent)
            case .ghost:
                self.buttonStyle(.glass(.regular))
            case .danger:
                self.buttonStyle(.glassProminent)
            }
        } else {
            switch tone {
            case .hero, .premium, .danger:
                self.buttonStyle(.borderedProminent)
            case .ghost:
                self.buttonStyle(.bordered)
            }
        }
    }

    /// System material glass for cards and surfaces, falling back to a
    /// material fill on older iOS.
    @ViewBuilder
    func nativeGlassCard(radius: CGFloat, opaque: Bool = true) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            if opaque {
                self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            } else {
                self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
        }
    }
}

enum ButtonTone: Equatable {
    case hero
    case premium
    case ghost
    case danger

    /// Native control tint. Glass buttons read their colour from here in the
    /// system styles, so gradients move to `background` for the few custom
    /// surfaces that still want them.
    var tint: Color {
        switch self {
        case .hero: return ACTheme.Palette.mint
        case .premium: return ACTheme.Palette.gold
        case .ghost: return ACTheme.Palette.text
        case .danger: return ACTheme.Palette.danger
        }
    }

    var foreground: Color { tint }
}

struct ActionButton: View {
    var title: String
    var systemImage: String? = nil
    var tone: ButtonTone = .hero
    var isBusy = false
    var isDisabled = false
    var action: () -> Void

    var body: some View {
        Button(action: {
            guard !isBusy, !isDisabled else { return }
            Haptics.tap()
            action()
        }) {
            HStack(spacing: ACTheme.Space.sm) {
                if isBusy {
                    ProgressView().controlSize(.small)
                } else if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 15, weight: .bold))
                }
                Text(title)
                    .font(ACType.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, ACTheme.Space.md + 1)
        }
        .nativeButton(tone: tone)
        .tint(tone.tint)
        .controlSize(.large)
        .disabled(isBusy || isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
    }
}

// MARK: - Instruments

/// The ring: how much of this container AppCatcher can win back.
struct MetricGauge: View {
    var progress: Double
    var value: String
    var unit: String
    var caption: String
    var size: CGFloat = 176

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    private var clamped: Double { min(max(progress, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(ACTheme.Palette.hairline, lineWidth: 13)

            Circle()
                .trim(from: 0, to: animate ? clamped : 0)
                .stroke(
                    ACTheme.Gradients.ring,
                    style: StrokeStyle(lineWidth: 13, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: ACTheme.Palette.aqua.opacity(0.35), radius: 12)

            VStack(spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(size > 150 ? ACType.hero : ACType.heroSmall)
                        .foregroundStyle(ACTheme.Palette.text)
                        .contentTransition(.numericText())
                    Text(unit)
                        .font(ACType.footnote)
                        .foregroundStyle(ACTheme.Palette.textSecondary)
                }
                Text(caption)
                    .font(ACType.caption)
                    .foregroundStyle(ACTheme.Palette.textTertiary)
                    .textCase(.uppercase)
                    .tracking(1.1)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            if reduceMotion {
                animate = true
            } else {
                withAnimation(ACTheme.Motion.standard.delay(0.12)) { animate = true }
            }
        }
        .onChange(of: clamped) { _, newValue in
            guard !reduceMotion else { animate = true; return }
            withAnimation(ACTheme.Motion.standard) {
                animate = newValue > 0
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption)
        .accessibilityValue("\(value) \(unit)")
    }
}

/// Stacked bar for the container breakdown on the dashboard.
struct UsageBar: View {
    struct Segment: Identifiable {
        let id = UUID()
        var bytes: Int64
        var color: Color
        var label: String
    }

    var segments: [Segment]
    var height: CGFloat = 12

    private var total: Int64 { max(segments.reduce(0) { $0 + $1.bytes }, 1) }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                ForEach(segments) { segment in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(segment.color)
                        .frame(width: max(proxy.size.width * CGFloat(Double(segment.bytes) / Double(total)) - 2, 2))
                }
            }
            .frame(height: height)
        }
        .frame(height: height)
    }
}

// MARK: - Rows and labels

struct IconBadge: View {
    var systemImage: String
    var tint: Color = ACTheme.Palette.aqua
    var size: CGFloat = 38

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(tint.opacity(0.16))
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .strokeBorder(tint.opacity(0.30), lineWidth: 1)
            Image(systemName: systemImage)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
    }
}

struct Chip: View {
    var text: String
    var systemImage: String? = nil
    var tint: Color = ACTheme.Palette.textSecondary

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 9, weight: .bold))
            }
            Text(text).font(ACType.micro)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(tint.opacity(0.12), in: Capsule())
        .overlay { Capsule().strokeBorder(tint.opacity(0.25), lineWidth: 1) }
    }
}

struct ProBadge: View {
    var body: some View {
        Chip(text: "PRO", systemImage: "crown.fill", tint: ACTheme.Palette.gold)
    }
}

/// A selectable row of data with a trailing amount and a checkbox affordance.
struct DataRow: View {
    var title: String
    var subtitle: String
    var amount: String
    var systemImage: String
    var tint: Color
    var isOn: Binding<Bool>
    var isProtected: Bool = false

    var body: some View {
        HStack(spacing: ACTheme.Space.md) {
            IconBadge(systemImage: systemImage, tint: isProtected ? ACTheme.Palette.textTertiary : tint)

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(ACType.row).foregroundStyle(ACTheme.Palette.text)
                Text(subtitle)
                    .font(ACType.caption)
                    .foregroundStyle(ACTheme.Palette.textTertiary)
                    .lineLimit(2)
            }

            Spacer(minLength: ACTheme.Space.sm)

            VStack(alignment: .trailing, spacing: 6) {
                Text(amount)
                    .font(ACType.footnote)
                    .monospacedDigit()
                    .foregroundStyle(ACTheme.Palette.textSecondary)
                if isProtected {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(ACTheme.Palette.textTertiary)
                } else {
                    Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 21, weight: .regular))
                        .foregroundStyle(isOn.wrappedValue ? ACTheme.Palette.mint : ACTheme.Palette.hairlineStrong)
                }
            }
        }
        .contentShape(Rectangle())
        .opacity(isProtected ? 0.6 : 1)
        .onTapGesture {
            guard !isProtected else { Haptics.warning(); return }
            isOn.wrappedValue.toggle()
            Haptics.select()
        }
    }
}

struct StatTile: View {
    var label: String
    var value: String
    var systemImage: String
    var tint: Color = ACTheme.Palette.aqua

    var body: some View {
        VStack(alignment: .leading, spacing: ACTheme.Space.xs) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
            Text(value)
                .font(ACType.headline)
                .monospacedDigit()
                .foregroundStyle(ACTheme.Palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .eyebrow()
        }
        .padding(ACTheme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ACTheme.Palette.surface, in: RoundedRectangle(cornerRadius: ACTheme.Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ACTheme.Radius.md, style: .continuous)
                .strokeBorder(ACTheme.Palette.hairline, lineWidth: 1)
        }
    }
}

// MARK: - Feedback

struct EmptyState: View {
    var systemImage: String
    var title: String
    var message: String
    var action: (() -> Void)? = nil
    var actionTitle: String = "Try again"

    var body: some View {
        VStack(spacing: ACTheme.Space.md) {
            ZStack {
                Circle().fill(ACTheme.Palette.surfaceRaised).frame(width: 78, height: 78)
                Image(systemName: systemImage)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(ACTheme.Palette.textSecondary)
            }
            Text(title).font(ACType.headline).foregroundStyle(ACTheme.Palette.text)
            Text(message)
                .font(ACType.body)
                .foregroundStyle(ACTheme.Palette.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(ACType.footnote)
                        .foregroundStyle(ACTheme.Palette.mint)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(ACTheme.Palette.mint.opacity(0.12), in: Capsule())
                }
                .buttonStyle(PressableStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ACTheme.Space.xxl)
    }
}

struct ToastBar: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(ACTheme.Palette.mint)
            Text(text)
                .font(ACType.footnote)
                .foregroundStyle(ACTheme.Palette.text)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(ACTheme.Palette.hairlineStrong, lineWidth: 1) }
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
    }
}

/// Thin determinate bar for the scanning/cleaning states.
struct FlowBar: View {
    var progress: Double
    var indeterminate: Bool = false

    @State private var slide = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(ACTheme.Palette.hairline)
                if indeterminate {
                    Capsule()
                        .fill(ACTheme.Gradients.glow)
                        .frame(width: proxy.size.width * 0.36)
                        .offset(x: slide ? proxy.size.width * 0.64 : -proxy.size.width * 0.36)
                        .onAppear {
                            withAnimation(ACTheme.Motion.sweep) { slide = true }
                        }
                } else {
                    Capsule()
                        .fill(ACTheme.Gradients.glow)
                        .frame(width: proxy.size.width * CGFloat(min(max(progress, 0), 1)))
                        .animation(ACTheme.Motion.quick, value: progress)
                }
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Layout helpers

struct SectionHeader: View {
    var title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).eyebrow()
            Spacer()
            if let detail {
                Text(detail)
                    .font(ACType.caption)
                    .foregroundStyle(ACTheme.Palette.textTertiary)
            }
        }
        .padding(.horizontal, 2)
    }
}

struct FadeInOnAppear: ViewModifier {
    var delay: Double = 0
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 10)
            .onAppear {
                withAnimation(ACTheme.Motion.standard.delay(delay)) { shown = true }
            }
    }
}

extension View {
    func staged(_ delay: Double = 0) -> some View {
        modifier(FadeInOnAppear(delay: delay))
    }
}
