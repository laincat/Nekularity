import SwiftUI
import NekularityKit

/// The shared look.
///
/// Liquid Glass is a **navigation-layer** material: Apple's guidance is that content
/// stays primary and the controls float above it. So glass goes on bars, toolbars and
/// buttons, and the cards that hold comics, episodes and text keep a plain surface.
/// Applying it to both is the "glass everywhere" anti-pattern, and stacking two glass
/// layers is worse: they refract each other and neither reads.
///
/// The deployment target is iOS 26, so `glassEffect` is available without a fallback.
///
/// Taken from the reference app's screens, but built from the theme tokens this
/// app already has — the accent and radius come from the chosen theme, so a
/// custom theme changes this surface too instead of fighting it.
enum Design {
    static let cardRadius: CGFloat = 22
    static let smallRadius: CGFloat = 14
    static let spacing: CGFloat = 12
}

extension Color {
    /// The blurred backdrop the cards sit on. Two tones of the accent, plus a
    /// neutral floor, so a theme with a red accent does not produce a red app.
    static func canvas(_ accent: Color, dark: Bool) -> LinearGradient {
        let base: [Color] = dark
            ? [Color(white: 0.09), Color(white: 0.14)]
            : [Color(white: 0.97), Color(white: 0.92)]
        return LinearGradient(
            colors: [accent.opacity(dark ? 0.28 : 0.16)] + base + [accent.opacity(dark ? 0.16 : 0.08)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// A translucent card, the one surface every screen draws with.
struct GlassCard: ViewModifier {
    var radius: CGFloat = Design.cardRadius
    var padding: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            )
    }
}

extension View {
    func glassCard(radius: CGFloat = Design.cardRadius, padding: CGFloat = 14) -> some View {
        modifier(GlassCard(radius: radius, padding: padding))
    }
}

/// The rounded capsule button the reference app puts in its bars.
/// The small wobble an editable board gives its cards.
///
/// It is the difference between a screen that happens to have drag targets and one that
/// says so: without it the gesture is invisible until someone guesses it.
struct Jiggle: ViewModifier {
    let active: Bool
    @State private var tilt = false

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(active && tilt ? 0.7 : -0.7))
            .animation(active ? .easeInOut(duration: 0.16).repeatForever(autoreverses: true) : .default,
                       value: tilt)
            .onAppear { tilt = active }
            .onChange(of: active) { _, on in tilt = on }
    }
}

extension View {
    /// Wobbles while `active`, the way an editable home board does.
    func jiggling(_ active: Bool) -> some View { modifier(Jiggle(active: active)) }

    /// A floating control's surface. Not for content: see the note at the top.
    @ViewBuilder func glassControl<S: Shape>(_ shape: S) -> some View {
        self.glassEffect(.regular, in: shape)
    }
}

struct Pill: ButtonStyle {
    // Optional on purpose: a ButtonStyle that traps when the theme is absent turns a
    // preview or a sheet built outside the root into a crash, and white is the same
    // fallback the kit picks when an accent cannot be read.
    @Environment(ThemeStore.self) private var themes: ThemeStore?
    var filled = false
    func makeBody(configuration: Configuration) -> some View {
        // Named so the type checker does not have to work it out of a ternary
        // inside a modifier chain.
        let surface: Glass = filled ? .identity : .regular
        return configuration.label
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            // A filled pill carries an action's meaning, so it is tinted rather than
            // glass; an unfilled one is a floating control and is glass.
            .background {
                if filled { Capsule().fill(.tint) }
            }
            .glassEffect(surface, in: .capsule)
            .foregroundStyle(filled ? AnyShapeStyle(themes?.active.onAccent ?? .white) : AnyShapeStyle(.primary))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension Theme {
    var onAccent: Color { accentTextIsDark ? .black : .white }
}

/// A section title with the chevron that says "there is more behind this".
struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var showsChevron = true

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
    }
}

/// A poster with the "看到 12:30" strip the reference app draws over it.
struct PosterTile: View {
    let source: String
    let cover: String?
    var title: String?
    var caption: String?
    var progress: Double?
    var width: CGFloat = 104
    var height: CGFloat = 144

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let cover, let url = URL(string: cover) {
                        SourceImage(key: .init(source: source, url: url.absoluteString, isThumbnail: true),
                                    maxPixel: 400)
                    } else {
                        Color.secondary.opacity(0.18)
                    }
                }
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: Design.smallRadius, style: .continuous))

                if let caption {
                    Text(caption)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(6)
                }
                if let progress {
                    VStack {
                        Spacer()
                        GeometryReader { proxy in
                            Capsule()
                                .fill(.white.opacity(0.85))
                                .frame(width: max(3, proxy.size.width * progress), height: 3)
                        }
                        .frame(height: 3)
                        .padding(6)
                    }
                }
            }
            if let title {
                Text(title).font(.caption).lineLimit(1)
            }
        }
        .frame(width: width)
    }
}

/// The big number and its unit, as the reference app's statistics cards show.
struct StatValue: View {
    let value: String
    var unit: String?
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 28, weight: .bold, design: .rounded))
                if let unit { Text(unit).font(.caption).foregroundStyle(.secondary) }
            }
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

extension Color {
    /// A danmaku colour, as the files carry it: one integer, 0xRRGGBB.
    ///
    /// White rather than clear for an unreadable value: a comment that vanishes is
    /// indistinguishable from a comment that never arrived.
    init(hex: Int) {
        let value = max(0, min(0xFFFFFF, hex))
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255,
                  opacity: 1)
    }
}
