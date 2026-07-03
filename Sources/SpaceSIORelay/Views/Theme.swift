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
    /// 0…1 — draws a sweeping playhead over the bars (the sonification cursor).
    var progress: Double? = nil
    var maxBars: Int = 44
    @State private var pulsing = false

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(bytes.prefix(maxBars).enumerated()), id: \.offset) { i, b in
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
        .overlay(alignment: .topLeading) {
            if let p = progress {
                GeometryReader { geo in
                    Capsule()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 2, height: geo.size.height)
                        .shadow(color: Theme.signal.opacity(0.9), radius: 5)
                        .offset(x: max(0, min(1, p)) * max(0, geo.size.width - 2))
                }
            }
        }
        .onAppear { pulsing = animate }
        .onChange(of: animate) { pulsing = $0 }
    }

    private func color(_ i: Int) -> Color {
        let palette: [Color] = [Theme.signal, Theme.beacon, Color(red: 0.9, green: 0.42, blue: 0.95)]
        return palette[i % palette.count].opacity(0.9)
    }
}

/// Proportional strip of the packet's real anatomy: fixed framing + content
/// hash overhead vs the compressed payload (and on-air thumbnail for media
/// signals). Truthful — derived from actual byte counts only.
struct PacketAnatomyView: View {
    let totalBytes: Int
    let type: String?

    private var framing: Int { min(34, max(0, totalBytes)) }
    private var payload: Int { max(0, totalBytes - framing) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.signal.opacity(0.85))
                        .frame(width: max(8, geo.size.width * fraction(framing)))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.beacon.opacity(0.75))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 10)
            HStack(spacing: 12) {
                legend(Theme.signal, "framing + hash · \(framing) B")
                legend(Theme.beacon, payloadLabel)
            }
        }
    }

    private var payloadLabel: String {
        let media = (type == "photo" || type == "video")
        return media
            ? "payload + on-air thumbnail · \(payload) B"
            : "compressed payload · \(payload) B"
    }

    private func fraction(_ part: Int) -> CGFloat {
        guard totalBytes > 0 else { return 0 }
        return CGFloat(part) / CGFloat(totalBytes)
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
        }
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
