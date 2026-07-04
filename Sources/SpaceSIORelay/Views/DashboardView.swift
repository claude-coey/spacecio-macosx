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
                    .frame(width: 310)
            }
        }
        .padding(24)
        // Consistent composition at any window size: content column caps out
        // and centers instead of stretching edge-to-edge on wide windows.
        .frame(maxWidth: 1180)
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
        VStack(spacing: 16) {
            OnAirButton(isOn: engine.onAir, phase: engine.phase) {
                engine.setOnAir(!engine.onAir)
            }

            // Live 3D globe — very slowly rotating Earth marking the station's
            // approximate broadcast location.
            VStack(spacing: 6) {
                RelayGlobe(lat: globeCoordinate?.lat, lon: globeCoordinate?.lon)
                    .frame(width: 168, height: 168)
                Text(globeCoordinate != nil ? "BROADCAST ORIGIN" : "LOCATION PENDING")
                    .font(.system(size: 9, weight: .bold))
                    .kerning(1.4)
                    .foregroundStyle(.white.opacity(0.4))
            }

            HStack(spacing: 20) {
                stat("CONFIRMED", "\(engine.confirmedCount)")
                stat("CHIRP", station.chirpEnabled ? "ON" : "MUTED")
                stat("LOCATION", locationSummary)
            }
            statsStrip
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .glassCard()
    }

    /// The station's approximate coordinate for the globe marker (or nil).
    private var globeCoordinate: (lat: Double, lon: Double)? {
        if let c = station.effectiveCoordinate(from: engine.locationProvider) {
            return (c.lat, c.lon)
        }
        return nil
    }

    /// Session + lifetime station stats — updates every second while on air.
    private var statsStrip: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(spacing: 20) {
                stat("UPTIME", uptimeText)
                stat("POLLS", "\(engine.pollCount)")
                stat("BYTES ON AIR", formatBytes(engine.sessionBytes))
                stat("LIFETIME", "\(engine.lifetimeRelayed) · \(formatBytes(engine.lifetimeBytes))")
            }
        }
        .padding(.top, 4)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
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

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .kerning(1.2)
                .foregroundStyle(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
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
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(engine.log) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Circle()
                                .fill(color(for: entry.kind))
                                .frame(width: 6, height: 6)
                                .padding(.top, 4)
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
                    }
                }
            }
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
        .glassCard()
    }

    private func color(for kind: LogEntry.Kind) -> Color {
        switch kind {
        case .info: return Theme.signal
        case .success: return Theme.go
        case .error: return Theme.ember
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

    var body: some View {
        Button(action: action) {
            ZStack {
                // Expanding pulse ring (breathes while on air).
                Circle()
                    .strokeBorder(ringColor.opacity(pulse ? 0.05 : 0.4), lineWidth: 2)
                    .frame(width: 176, height: 176)
                    .scaleEffect(pulse ? 1.12 : 0.98)
                    .animation(
                        isOn ? .easeInOut(duration: 1.6).repeatForever(autoreverses: true) : .default,
                        value: pulse
                    )

                // Slowly rotating scanner ring — reads as "actively working".
                Circle()
                    .strokeBorder(
                        AngularGradient(
                            colors: [
                                ringColor.opacity(0),
                                ringColor.opacity(0.85),
                                ringColor.opacity(0),
                            ],
                            center: .center
                        ),
                        lineWidth: 2.5
                    )
                    .frame(width: 190, height: 190)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 7).repeatForever(autoreverses: false), value: spin)
                    .opacity(isOn ? 0.95 : 0.30)

                // Faint tick marks around the dial (technical instrument feel).
                ForEach(0..<48, id: \.self) { i in
                    Rectangle()
                        .fill(ringColor.opacity(i % 4 == 0 ? 0.35 : 0.12))
                        .frame(width: 1.2, height: i % 4 == 0 ? 7 : 4)
                        .offset(y: -100)
                        .rotationEffect(.degrees(Double(i) / 48 * 360))
                }
                .opacity(isOn ? 0.9 : 0.4)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [ringColor.opacity(0.38), Color.black.opacity(0.55)],
                            center: .center, startRadius: 6, endRadius: 84
                        )
                    )
                    .frame(width: 148, height: 148)
                    .overlay(Circle().strokeBorder(ringColor.opacity(0.6), lineWidth: 1.5))
                    .shadow(color: ringColor.opacity(isOn ? 0.6 : 0.15), radius: 30)
                VStack(spacing: 6) {
                    Image(systemName: isOn ? "antenna.radiowaves.left.and.right" : "power")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(isOn ? "ON AIR" : "GO ON AIR")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .kerning(2)
                        .foregroundStyle(.white.opacity(0.9))
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
