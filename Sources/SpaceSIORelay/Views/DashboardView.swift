import AppKit
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var station: Station
    @EnvironmentObject var engine: RelayEngine
    @Binding var showSettings: Bool

    var body: some View {
        VStack(spacing: 18) {
            header
            HStack(alignment: .top, spacing: 18) {
                // Scrolls within the window so a large packet's byte grid can't
                // grow the layout past the window height and push the header
                // (logo) off the top.
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 18) {
                        onAirCard
                        if let t = engine.current {
                            transmissionCard(t)
                        }
                        if let c = engine.lastConfirmation {
                            ConfirmationCard(confirmation: c)
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                logPanel
                    .frame(width: 320)
            }
            // Fill the available height so the columns (esp. the station log)
            // stretch to the window bottom instead of leaving dead space.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(24)
        // Fluid width: fills the window, capped generously so it doesn't stretch
        // absurdly on ultra-wide displays; centered within the window.
        .frame(maxWidth: 1600)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Wordmark()
            Spacer()
            StatusPill(phase: engine.phase)
            VStack(alignment: .trailing, spacing: 2) {
                Text(station.rigName)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                Text("ID \(String(engine.stationPublicKey.prefix(12)))…")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
            // Chrome controls are AppKit-backed (SwiftUI Button dispatch
            // segfaults on macOS 26 for these — see AppKitIconButton).
            AppKitIconButton(
                systemName: station.chirpEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                label: station.chirpEnabled ? "Mute chirp" : "Unmute chirp"
            ) {
                station.chirpEnabled.toggle()
                if station.chirpEnabled { engine.testChirp() }
            }
            .frame(width: 32, height: 32)
            .background(Color.white.opacity(0.07), in: Circle())

            AppKitIconButton(systemName: "gearshape.fill", label: "Settings") {
                showSettings = true
            }
            .frame(width: 32, height: 32)
            .background(Color.white.opacity(0.07), in: Circle())
        }
    }

    private var onAirCard: some View {
        ZStack(alignment: .top) {
            // Darker base so the on-air section reads deeper and the globe pops.
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(red: 0.01, green: 0.02, blue: 0.06).opacity(0.55))

            // Large orthographic globe living in the BACKGROUND: a big, cut-off
            // wireframe Earth (continents + graticule) with soft edge fades,
            // very slowly rotating and marking the broadcast location.
            GeometryReader { geo in
                let d = min(geo.size.width * 0.95, geo.size.height * 1.6)
                RelayGlobe(lat: globeCoordinate?.lat, lon: globeCoordinate?.lon)
                    .frame(width: d, height: d)
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.58)
                    .opacity(0.5)
                    .allowsHitTesting(false)
            }

            VStack(spacing: 18) {
                OnAirButton(isOn: engine.onAir, phase: engine.phase) {
                    engine.setOnAir(!engine.onAir)
                }
                .padding(.top, 8)
                Spacer(minLength: 8)
                statTiles
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(24)
        }
        .frame(maxWidth: .infinity, minHeight: 400)
        .glassCard()
    }

    /// The station's approximate coordinate for the globe marker (or nil).
    private var globeCoordinate: (lat: Double, lon: Double)? {
        if let c = station.effectiveCoordinate(from: engine.locationProvider) {
            return (c.lat, c.lon)
        }
        return nil
    }

    /// The full metric strip: seven boxed icon tiles in one row, re-rendered
    /// every second so the live counters (uptime, polls, bytes) tick.
    private var statTiles: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(spacing: 12) {
                StatTile(
                    icon: "checkmark.shield.fill", label: "CONFIRMED",
                    value: "\(engine.confirmedCount)",
                    tint: Theme.go, glow: engine.confirmedCount > 0
                )
                StatTile(
                    icon: station.chirpEnabled ? "waveform" : "speaker.slash.fill",
                    label: "CHIRP",
                    value: station.chirpEnabled ? "ON" : "MUTED",
                    tint: station.chirpEnabled ? Theme.go : Color.gray,
                    glow: station.chirpEnabled && engine.phase == .broadcasting
                )
                StatTile(
                    icon: "mappin.and.ellipse", label: "LOCATION",
                    value: locationSummary, tint: Theme.signal
                )
                StatTile(
                    icon: "clock", label: "UPTIME",
                    value: uptimeText, tint: Theme.signal
                )
                StatTile(
                    icon: "chart.bar.fill", label: "POLLS",
                    value: "\(engine.pollCount)", tint: Theme.beacon
                )
                StatTile(
                    icon: "icloud.and.arrow.up", label: "BYTES ON AIR",
                    value: formatBytes(engine.sessionBytes), tint: Theme.beacon
                )
                StatTile(
                    icon: "hourglass", label: "LIFETIME",
                    value: "\(engine.lifetimeRelayed) · \(formatBytes(engine.lifetimeBytes))",
                    tint: Theme.signal
                )
            }
        }
    }

    private var uptimeText: String {
        guard let start = engine.sessionStartedAt else { return "—" }
        let s = Int(Date().timeIntervalSince(start))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \((s % 3600) / 60)m"
    }

    private func formatBytes(_ n: Int) -> String {
        if n < 1024 { return "\(n) B" }
        if n < 1024 * 1024 { return String(format: "%.1f KB", Double(n) / 1024) }
        return String(format: "%.1f MB", Double(n) / 1024 / 1024)
    }

    private var locationSummary: String {
        if let c = station.effectiveCoordinate(from: engine.locationProvider) {
            return String(format: "≈ %.1f, %.1f", c.lat, c.lon)
        }
        return station.locationMode == .automatic ? engine.locationProvider.status : "Not set"
    }

    private func transmissionCard(_ t: Transmission) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("NOW BROADCASTING")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1.5)
                    .foregroundStyle(Theme.ember)
                Spacer()
                if let callsign = t.callsign {
                    Text("@\(callsign)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.signal)
                }
            }
            Text(t.title ?? "Untitled signal")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)

            // Live packet: waveform with the sonification playhead, and the
            // REAL data blocks materializing byte-by-byte as they go on air.
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                VStack(alignment: .leading, spacing: 14) {
                    WaveformView(
                        bytes: engine.onAirBytes,
                        animate: engine.phase == .broadcasting,
                        progress: playheadProgress(at: timeline.date),
                        time: timeline.date.timeIntervalSinceReferenceDate
                    )
                    PacketBlocksView(
                        bytes: engine.onAirBytes,
                        progress: blocksProgress(at: timeline.date),
                        time: timeline.date.timeIntervalSinceReferenceDate
                    )
                }
            }

            HStack(spacing: 14) {
                if let pb = t.packet_bytes {
                    metaChip("\(pb) B packet")
                }
                if let type = t.type {
                    metaChip(type.uppercased())
                }
                metaChip("WIFI RADIO")
            }

            Text("You're hearing the actual packet bytes — one note per byte, one-time playback. The packet is destroyed the moment this broadcast ends; the station retains nothing.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    /// 0…1 sonification cursor across the waveform while the chirp plays.
    private func playheadProgress(at now: Date) -> Double? {
        guard engine.phase == .broadcasting,
              let start = engine.broadcastStartedAt,
              engine.chirpDuration > 0
        else { return nil }
        let p = now.timeIntervalSince(start) / engine.chirpDuration
        return p > 1 ? nil : p
    }

    /// 0…1 materialization sweep for the data blocks — runs over the on-air
    /// hold (chirp duration, min 1.2s) then clamps fully lit.
    private func blocksProgress(at now: Date) -> Double {
        guard let start = engine.broadcastStartedAt else { return 1 }
        let window = max(engine.chirpDuration, 1.2)
        return min(1, now.timeIntervalSince(start) / window)
    }

    private func metaChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.55))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.06), in: Capsule())
    }

    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("STATION LOG")
                .font(.system(size: 10, weight: .bold))
                .kerning(1.5)
                .foregroundStyle(.white.opacity(0.4))
            if engine.log.isEmpty {
                Text("Quiet for now. Flip the station on air to start relaying.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 11) {
                    ForEach(engine.log) { entry in
                        let g = glyph(for: entry)
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: g.symbol)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(g.color)
                                .shadow(color: g.color.opacity(0.55), radius: 4)
                                .frame(width: 15, height: 15)
                                .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.text)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.8))
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(entry.date, style: .time)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.28), value: engine.log.count)
            }
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
        .glassCard()
    }

    /// Pick a contextual SF Symbol + color for a log line. Keyword matching
    /// first (so "offline", "watchdog", "chirp", … each get a fitting glyph),
    /// falling back to the entry's semantic kind.
    private func glyph(for entry: LogEntry) -> (symbol: String, color: Color) {
        let t = entry.text.lowercased()
        if t.contains("offline") || t.contains("no internet") {
            return ("wifi.slash", Theme.ember)
        }
        if t.contains("back online") || t.contains("connection restored") {
            return ("wifi", Theme.go)
        }
        if t.contains("watchdog") || t.contains("abandon") {
            return ("exclamationmark.triangle.fill", Theme.ember)
        }
        if t.contains("cancel") {
            return ("xmark.circle.fill", .gray)
        }
        if t.contains("destroyed") || t.contains("retains nothing") {
            return ("flame.fill", Theme.ember)
        }
        if t.contains("chirp") {
            return ("waveform", Theme.beacon)
        }
        if t.contains("signing") || t.contains("signature") || t.contains("signed") {
            return ("signature", Theme.signal)
        }
        if t.contains("on air") || t.contains("confirmation delivered") || t.contains("confirmed") {
            return ("checkmark.seal.fill", Theme.go)
        }
        if t.contains("received") || t.contains("packet") || t.contains("wifi") {
            return ("antenna.radiowaves.left.and.right", Theme.signal)
        }
        switch entry.kind {
        case .info: return ("dot.radiowaves.left.and.right", Theme.signal)
        case .success: return ("checkmark.circle.fill", Theme.go)
        case .error: return ("exclamationmark.circle.fill", Theme.ember)
        }
    }
}

/// The big pulsing on-air control.
struct OnAirButton: View {
    let isOn: Bool
    let phase: RelayEngine.Phase
    let action: () -> Void
    @State private var pulse = false
    @State private var spin = false

    // Cyan→violet neon sweep used for the glowing rings (matches the reference).
    private var ringGradient: AngularGradient {
        AngularGradient(
            colors: [
                Theme.signal,                              // cyan
                Color(red: 0.40, green: 0.80, blue: 1.00), // bright blue
                Theme.beacon,                              // violet
                Color(red: 0.85, green: 0.45, blue: 1.00), // magenta-violet
                Theme.signal,                              // back to cyan
            ],
            center: .center
        )
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // 1. Broad outer bloom — a soft radial wash of light behind the
                //    dial that gently breathes. This is the ambient glow.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Theme.signal.opacity(0.55),
                                Theme.beacon.opacity(0.30),
                                .clear,
                            ],
                            center: .center, startRadius: 30, endRadius: 150
                        )
                    )
                    .frame(width: 300, height: 300)
                    .blur(radius: 26)
                    .opacity(isOn ? 0.9 : 0.28)
                    .scaleEffect(pulse ? 1.06 : 0.92)
                    .animation(
                        isOn ? .easeInOut(duration: 2.6).repeatForever(autoreverses: true) : .default,
                        value: pulse
                    )

                // 2. Bloom ring — a thick, heavily blurred copy of the main ring
                //    that reads as the neon "glow" spilling off the crisp ring.
                Circle()
                    .stroke(ringGradient, lineWidth: 11)
                    .frame(width: 178, height: 178)
                    .blur(radius: 16)
                    .opacity(isOn ? 0.95 : 0.30)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 20).repeatForever(autoreverses: false), value: spin)

                // 3. Faint radar ticks + the 12-o'clock index line.
                ForEach(0..<60, id: \.self) { i in
                    Rectangle()
                        .fill(Theme.signal.opacity(i % 5 == 0 ? 0.30 : 0.10))
                        .frame(width: 1, height: i == 0 ? 12 : (i % 5 == 0 ? 6 : 3))
                        .offset(y: -104)
                        .rotationEffect(.degrees(Double(i) / 60 * 360))
                }
                .opacity(isOn ? 0.85 : 0.35)

                // 4. Main crisp neon ring — bright, thin, with a tight glow.
                Circle()
                    .stroke(ringGradient, lineWidth: 3.5)
                    .frame(width: 178, height: 178)
                    .shadow(color: Theme.signal.opacity(isOn ? 0.9 : 0.2), radius: 9)
                    .shadow(color: Theme.beacon.opacity(isOn ? 0.7 : 0.15), radius: 16)
                    .opacity(isOn ? 1 : 0.55)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 20).repeatForever(autoreverses: false), value: spin)

                // 5. Inner + outer hairline rings for a crisp double-ring edge.
                Circle()
                    .strokeBorder(.white.opacity(isOn ? 0.45 : 0.18), lineWidth: 1)
                    .frame(width: 168, height: 168)
                Circle()
                    .strokeBorder(Theme.beacon.opacity(isOn ? 0.4 : 0.15), lineWidth: 1)
                    .frame(width: 194, height: 194)

                // 6. Dark glassy hub with the antenna glyph.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                ringColor.opacity(0.30),
                                Color(red: 0.02, green: 0.04, blue: 0.10).opacity(0.92),
                            ],
                            center: .center, startRadius: 4, endRadius: 86
                        )
                    )
                    .frame(width: 150, height: 150)
                    .overlay(Circle().strokeBorder(ringColor.opacity(0.5), lineWidth: 1))
                    .shadow(color: ringColor.opacity(isOn ? 0.5 : 0.12), radius: 24)

                VStack(spacing: 6) {
                    Image(systemName: isOn ? "antenna.radiowaves.left.and.right" : "power")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: Theme.signal.opacity(isOn ? 0.8 : 0), radius: 8)
                    Text(isOn ? "ON AIR" : "GO ON AIR")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .kerning(2)
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
            .frame(width: 200, height: 200)
        }
        .buttonStyle(.plain)
        .onAppear { pulse = isOn; spin = true }
        .onChange(of: isOn) { pulse = $0 }
    }

    private var ringColor: Color {
        guard isOn else { return .gray }
        switch phase {
        case .broadcasting: return Theme.ember
        case .confirming: return Theme.beacon
        case .confirmed: return Theme.go
        default: return Theme.signal
        }
    }
}

struct ConfirmationCard: View {
    let confirmation: Confirmation
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Theme.go)
                Text("SIGNED CONFIRMATION DELIVERED")
                    .font(.system(size: 10, weight: .bold))
                    .kerning(1.4)
                    .foregroundStyle(Theme.go)
                Spacer()
                Text(confirmation.date, style: .time)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }

            Text(confirmation.title)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(2)

            HStack(spacing: 14) {
                if let lat = confirmation.lat, let lon = confirmation.lon {
                    detail("BROADCAST FROM · ~5 MI", String(format: "≈ %.1f, %.1f", lat, lon))
                } else {
                    detail("BROADCAST FROM", "location not shared")
                }
                detail("ED25519 SIG", "\(confirmation.signaturePrefix)…")
            }

            HStack(spacing: 6) {
                Image(systemName: "flame")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.ember.opacity(0.8))
                Text("Packet destroyed after broadcast — this station retains nothing.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
            }

            HStack(spacing: 10) {
                if let link = confirmation.permalink, let url = URL(string: link) {
                    Link(destination: url) {
                        Label("View signal", systemImage: "arrow.up.right.square")
                    }
                }
                if let cert = confirmation.certificateURL, let url = URL(string: cert) {
                    Link(destination: url) {
                        Label("Certificate", systemImage: "doc.badge.ellipsis")
                    }
                }
                Spacer()
                Button {
                    if let link = confirmation.permalink {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(link, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy link", systemImage: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.signal)
            }
            .font(.system(size: 12))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .kerning(1.2)
                .foregroundStyle(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}
