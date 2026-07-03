import SwiftUI

enum Theme {
    static let signal = Color(red: 0.35, green: 0.85, blue: 1.0)      // cyan
    static let beacon = Color(red: 0.62, green: 0.48, blue: 1.0)      // violet
    static let ember = Color(red: 1.0, green: 0.45, blue: 0.35)       // ember
    static let go = Color(red: 0.35, green: 0.95, blue: 0.65)         // confirm green
    static let bgTop = Color(red: 0.02, green: 0.03, blue: 0.08)
    static let bgBottom = Color(red: 0.05, green: 0.02, blue: 0.12)

    static let accent = LinearGradient(
        colors: [signal, beacon], startPoint: .leading, endPoint: .trailing
    )
}

struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.white.opacity(0.10))
            )
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 20) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}

struct Wordmark: View {
    var size: CGFloat = 22
    var body: some View {
        HStack(spacing: 0) {
            Text("Space")
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text("SIO")
                .font(.system(size: size, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.accent)
            Text("  RELAY")
                .font(.system(size: size * 0.72, weight: .light, design: .rounded))
                .kerning(3)
                .foregroundStyle(.white.opacity(0.65))
        }
    }
}

struct StarfieldView: View {
    private struct Star {
        let x: Double, y: Double, r: Double, phase: Double
    }

    private static let stars: [Star] = (0..<170).map { _ in
        Star(
            x: .random(in: 0...1), y: .random(in: 0...1),
            r: .random(in: 0.4...1.7), phase: .random(in: 0...(2 * .pi))
        )
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                for s in Self.stars {
                    let alpha = 0.22 + 0.5 * (0.5 + 0.5 * sin(t * 0.8 + s.phase))
                    let rect = CGRect(
                        x: s.x * size.width, y: s.y * size.height,
                        width: s.r * 2, height: s.r * 2
                    )
                    ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(alpha)))
                }
            }
        }
        .background(
            LinearGradient(
                colors: [Theme.bgTop, Theme.bgBottom],
                startPoint: .top, endPoint: .bottom
            )
        )
        .ignoresSafeArea()
    }
}

/// Multi-hue capsule bars derived from the packet bytes — the app-side cousin
/// of the web waveform.
struct WaveformView: View {
    let bytes: [UInt8]
    var animate: Bool = false
    @State private var pulsing = false

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(bytes.prefix(44).enumerated()), id: \.offset) { i, b in
                Capsule()
                    .fill(color(i))
                    .frame(width: 4, height: 8 + CGFloat(b) / 255 * 42)
                    .scaleEffect(y: animate && pulsing ? 0.45 : 1.0, anchor: .center)
                    .animation(
                        animate
                            ? .easeInOut(duration: 0.5)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.03)
                            : .default,
                        value: pulsing
                    )
            }
        }
        .frame(height: 54)
        .onAppear { pulsing = animate }
        .onChange(of: animate) { pulsing = $0 }
    }

    private func color(_ i: Int) -> Color {
        let palette: [Color] = [Theme.signal, Theme.beacon, Color(red: 0.9, green: 0.42, blue: 0.95)]
        return palette[i % palette.count].opacity(0.9)
    }
}

struct StatusPill: View {
    let phase: RelayEngine.Phase

    private var info: (String, Color) {
        switch phase {
        case .offline: return ("OFFLINE", .gray)
        case .listening: return ("LISTENING", Theme.signal)
        case .receiving: return ("RECEIVING", Theme.signal)
        case .broadcasting: return ("ON AIR", Theme.ember)
        case .confirming: return ("CONFIRMING", Theme.beacon)
        case .confirmed: return ("CONFIRMED", Theme.go)
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(info.1)
                .frame(width: 8, height: 8)
                .shadow(color: info.1.opacity(0.9), radius: 4)
            Text(info.0)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .kerning(1.5)
                .foregroundStyle(info.1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(info.1.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(info.1.opacity(0.35)))
    }
}
