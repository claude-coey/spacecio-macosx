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
            // faint inner tint + top-lit sheen so cards read as glass panels on
            // the busy starfield and feel a touch more three-dimensional.
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.05), Color.white.opacity(0.01)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.30),
                                Color.white.opacity(0.06),
                                Theme.beacon.opacity(0.12),
                            ],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.45), radius: 20, x: 0, y: 12)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 20) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}

struct Wordmark: View {
    var size: CGFloat = 22

    /// Loaded explicitly with NSImage(contentsOf:) — `Image(_:bundle:)` looks
    /// in an ASSET CATALOG and silently renders nothing for a loose PNG in an
    /// SPM resource bundle (the "lost logo" bug).
    private static let brandImage: NSImage? = {
        guard let url = Bundle.module.url(forResource: "spacesio-logo", withExtension: "png")
        else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let brand = Self.brandImage {
                Image(nsImage: brand)
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

/// The cosmic backdrop: a parallax, twinkling starfield with depth (so it reads
/// a little 3D), a very subtle drifting aurora, and occasional shooting stars.
/// All motion derives from the TimelineView clock (no per-frame state), so it's
/// cheap and deterministic.
struct StarfieldView: View {
    private struct Star {
        let x: Double, y: Double, r: Double, phase: Double, depth: Double, drift: Double
    }
    private struct Meteor {
        let period: Double, offset: Double, dur: Double
        let x0: Double, y0: Double, dx: Double, dy: Double, len: Double
    }

    // depth 0 = far (small, dim, slow); 1 = near (big, bright, faster parallax).
    private static let stars: [Star] = (0..<210).map { _ in
        let depth = Double.random(in: 0...1)
        return Star(
            x: .random(in: 0...1), y: .random(in: 0...1),
            r: 0.4 + depth * 1.7,
            phase: .random(in: 0...(2 * .pi)),
            depth: depth,
            drift: .random(in: -1...1)
        )
    }

    // Rare shooting stars: 2 meteors on long, staggered periods → on average
    // one streak roughly every ~30s, not a steady shower.
    private static let meteors: [Meteor] = (0..<2).map { i in
        Meteor(
            period: .random(in: 55...80),
            offset: Double(i) * 27 + .random(in: 0...12),
            dur: .random(in: 1.1...1.7),
            x0: .random(in: -0.1...0.6),
            y0: .random(in: -0.05...0.35),
            dx: .random(in: 0.5...0.9),
            dy: .random(in: 0.22...0.5),
            len: .random(in: 0.10...0.18)
        )
    }

    private static let auroraColors: [Color] = [Theme.signal, Theme.beacon, Theme.go]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let W = size.width, H = size.height

                // --- very subtle cosmic aurora: slow drifting radial blobs ---
                for (i, color) in Self.auroraColors.enumerated() {
                    let fi = Double(i)
                    let cx = (0.25 + 0.5 * (0.5 + 0.5 * sin(t * 0.045 + fi * 2.1))) * W
                    let cy = (0.18 + 0.7 * (0.5 + 0.5 * cos(t * 0.037 + fi * 1.3))) * H
                    let R = min(W, H) * (0.5 + 0.12 * sin(t * 0.05 + fi))
                    let a = 0.05 + 0.03 * (0.5 + 0.5 * sin(t * 0.06 + fi))
                    let rect = CGRect(x: cx - R, y: cy - R, width: R * 2, height: R * 2)
                    ctx.fill(
                        Path(ellipseIn: rect),
                        with: .radialGradient(
                            Gradient(colors: [color.opacity(a), .clear]),
                            center: CGPoint(x: cx, y: cy),
                            startRadius: 0, endRadius: R
                        )
                    )
                }

                // --- parallax starfield (very slow drift) ---
                for s in Self.stars {
                    let speed = 0.0006 + s.depth * 0.0022
                    var x = (s.x + t * speed * (0.5 + s.drift * 0.5))
                        .truncatingRemainder(dividingBy: 1)
                    if x < 0 { x += 1 }
                    let twinkle = 0.35 + 0.65 * (0.5 + 0.5 * sin(t * (0.22 + s.depth * 0.45) + s.phase))
                    let alpha = (0.12 + 0.55 * s.depth) * twinkle
                    let px = x * W, py = s.y * H, r = s.r
                    if s.depth > 0.8 {
                        let g = CGRect(x: px - r, y: py - r, width: r * 4, height: r * 4)
                        ctx.fill(Path(ellipseIn: g), with: .color(Theme.signal.opacity(alpha * 0.18)))
                    }
                    let rect = CGRect(x: px, y: py, width: r * 2, height: r * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(alpha)))
                }

                // --- occasional shooting stars ---
                for m in Self.meteors {
                    let phase = (t + m.offset).truncatingRemainder(dividingBy: m.period)
                    guard phase >= 0, phase < m.dur else { continue }
                    let p = phase / m.dur
                    let hx = (m.x0 + m.dx * p) * W
                    let hy = (m.y0 + m.dy * p) * H
                    let tailLen = m.len * Double(max(W, H))
                    let ang = atan2(m.dy * H, m.dx * W)
                    let tx = hx - cos(ang) * tailLen
                    let ty = hy - sin(ang) * tailLen
                    let fade = sin(p * .pi)
                    var trail = Path()
                    trail.move(to: CGPoint(x: tx, y: ty))
                    trail.addLine(to: CGPoint(x: hx, y: hy))
                    ctx.stroke(
                        trail,
                        with: .linearGradient(
                            Gradient(colors: [.clear, .white.opacity(0.9 * fade)]),
                            startPoint: CGPoint(x: tx, y: ty),
                            endPoint: CGPoint(x: hx, y: hy)
                        ),
                        lineWidth: 1.6
                    )
                    let head = CGRect(x: hx - 1.6, y: hy - 1.6, width: 3.2, height: 3.2)
                    ctx.fill(Path(ellipseIn: head), with: .color(.white.opacity(fade)))
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

// (The old two-segment PacketAnatomyView was replaced by PacketBlocksView —
// the real field-labeled byte grid in Views/PacketBlocks.swift.)

/// A single boxed metric tile: a tinted SF Symbol, an all-caps label, and a
/// mono value, inside a soft glass panel. `glow` makes the icon gently breathe
/// and casts a colored halo (used for "live" metrics like a confirmed count),
/// and the whole tile lifts + brightens its border on hover for a tactile feel.
struct StatTile: View {
    let icon: String
    let label: String
    let value: String
    var tint: Color = Theme.signal
    var glow: Bool = false

    @State private var breathe = false
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .shadow(color: tint.opacity(glow ? 0.75 : 0), radius: glow ? 9 : 0)
                .scaleEffect(glow && breathe ? 1.10 : 1)
                .frame(height: 18)

            Text(label)
                .font(.system(size: 8.5, weight: .bold))
                .kerning(1.1)
                .foregroundStyle(.white.opacity(0.42))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(value)
                .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(hovering ? 0.055 : 0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            tint.opacity(hovering ? 0.5 : 0.16),
                            Color.white.opacity(0.05),
                        ],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: tint.opacity(hovering ? 0.25 : 0), radius: 12, y: 4)
        .offset(y: hovering ? -2 : 0)
        .animation(.easeOut(duration: 0.18), value: hovering)
        .onHover { hovering = $0 }
        .onAppear {
            guard glow else { return }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }
}

struct StatusPill: View {
    let phase: RelayEngine.Phase
    @State private var ping = false

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

    private var isLive: Bool { phase != .offline }

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                // radar ping — a ring that expands + fades while the station is live
                Circle()
                    .stroke(info.1.opacity(0.7), lineWidth: 1.4)
                    .frame(width: 8, height: 8)
                    .scaleEffect(ping && isLive ? 2.6 : 1)
                    .opacity(ping && isLive ? 0 : 0.9)
                Circle()
                    .fill(info.1)
                    .frame(width: 8, height: 8)
                    .shadow(color: info.1.opacity(0.9), radius: 4)
            }
            .animation(
                isLive ? .easeOut(duration: 1.8).repeatForever(autoreverses: false) : .default,
                value: ping
            )
            Text(info.0)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .kerning(1.5)
                .foregroundStyle(info.1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(info.1.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(info.1.opacity(0.35)))
        .onAppear { ping = true }
    }
}
