import AppKit
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

    /// True when the brand PNG shipped in the SPM resource bundle is present
    /// (it is for both `swift run` and the .app built by make-installer).
    private var hasBrandAsset: Bool {
        Bundle.module.url(forResource: "spacesio-logo", withExtension: "png") != nil
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if hasBrandAsset {
                Image("spacesio-logo", bundle: .module)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(height: size * 1.35)
                    .accessibilityLabel("SpaceSIO")
            } else {
                // Fallback text lockup if the resource bundle is missing.
                HStack(spacing: 0) {
                    Text("Space")
                        .font(.system(size: size, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("SIO")
                        .font(.system(size: size, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.accent)
                }
            }
            Text("RELAY")
                .font(.system(size: size * 0.66, weight: .light, design: .rounded))
                .kerning(3)
                .foregroundStyle(.white.opacity(0.65))
        }
    }
}

/// AppKit-backed icon button. SwiftUI's Button gesture dispatch crashes on
/// macOS 26 for some controls (MainActor.assumeIsolated segfault in
/// _ButtonGesture), so chrome controls route through a plain NSButton
/// target/action — no SwiftUI gesture machinery involved.
struct AppKitIconButton: NSViewRepresentable {
    let systemName: String
    let label: String
    let action: () -> Void

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func fire() { action() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let b = NSButton()
        b.isBordered = false
        b.bezelStyle = .regularSquare
        b.setButtonType(.momentaryChange)
        b.imageScaling = .scaleProportionallyDown
        b.image = NSImage(systemSymbolName: systemName, accessibilityDescription: label)
        b.contentTintColor = NSColor.white.withAlphaComponent(0.75)
        b.target = context.coordinator
        b.action = #selector(Coordinator.fire)
        b.setAccessibilityLabel(label)
        return b
    }

    func updateNSView(_ b: NSButton, context: Context) {
        context.coordinator.action = action
        b.image = NSImage(systemSymbolName: systemName, accessibilityDescription: label)
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
/// Multi-hue byte waveform, drawn with Canvas so it FILLS the available width
/// and scales with the window. `time` (from an enclosing TimelineView) drives
/// a gentle travelling pulse while broadcasting; `progress` draws the
/// sonification playhead.
struct WaveformView: View {
    let bytes: [UInt8]
    var animate: Bool = false
    /// 0…1 — sweeping playhead position (the sonification cursor).
    var progress: Double? = nil
    /// Timebase for the broadcast pulse; pass timeline.date.timeIntervalSinceReferenceDate.
    var time: Double = 0
    var maxBars: Int = 96
    var height: CGFloat = 56

    private static let palette: [Color] = [
        Theme.signal, Theme.beacon, Color(red: 0.9, green: 0.42, blue: 0.95),
    ]

    var body: some View {
        Canvas { ctx, size in
            let shown = Array(bytes.prefix(maxBars))
            guard !shown.isEmpty, size.width > 4 else { return }
            let n = shown.count
            let gap: CGFloat = 3
            let barW = max(2, (size.width - gap * CGFloat(n - 1)) / CGFloat(n))
            let midY = size.height / 2

            for (i, b) in shown.enumerated() {
                let base = 0.16 + (CGFloat(b) / 255) * 0.84 // 16%…100% of height
                let wobble: CGFloat = animate
                    ? 0.62 + 0.38 * CGFloat(sin(time * 5.0 + Double(i) * 0.45))
                    : 1.0
                let h = max(4, size.height * base * wobble)
                let x = CGFloat(i) * (barW + gap)
                let rect = CGRect(x: x, y: midY - h / 2, width: barW, height: h)
                let color = Self.palette[i % Self.palette.count].opacity(0.9)
                ctx.fill(Path(roundedRect: rect, cornerRadius: barW / 2), with: .color(color))
            }

            if let p = progress {
                let px = max(0, min(1, p)) * (size.width - 2)
                let cursor = CGRect(x: px, y: 0, width: 2, height: size.height)
                ctx.fill(Path(roundedRect: cursor, cornerRadius: 1), with: .color(.white.opacity(0.9)))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .accessibilityLabel("Packet byte waveform")
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
