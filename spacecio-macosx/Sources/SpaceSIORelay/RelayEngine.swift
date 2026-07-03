import Foundation

/// The station's control loop: poll the feed, put the packet on the air
/// (UDP broadcast + optional chirp), then send back a signed, located
/// confirmation.
@MainActor
final class RelayEngine: ObservableObject {
    enum Phase: Equatable {
        case offline, listening, receiving, broadcasting, confirming, confirmed
    }

    @Published private(set) var phase: Phase = .offline
    @Published private(set) var onAir = false
    @Published private(set) var current: Transmission?
    @Published private(set) var lastConfirmation: Confirmation?
    @Published private(set) var log: [LogEntry] = []
    @Published private(set) var confirmedCount = 0

    let station: Station
    let locationProvider = LocationProvider()
    private let signer = Signer.load()
    private let chirp = Chirp()
    private var loopTask: Task<Void, Never>?

    /// Base64 raw Ed25519 public key — the station's verifiable identity.
    var stationPublicKey: String { signer.publicKeyBase64 }

    init(station: Station) {
        self.station = station
    }

    func setOnAir(_ on: Bool) {
        guard on != onAir else { return }
        onAir = on
        if on {
            if station.locationMode == .automatic {
                locationProvider.request()
            }
            phase = .listening
            appendLog("Station online — listening for queued signals.", .info)
            loopTask = Task { [weak self] in await self?.runLoop() }
        } else {
            loopTask?.cancel()
            loopTask = nil
            phase = .offline
            current = nil
            appendLog("Station offline.", .info)
        }
    }

    private func runLoop() async {
        while !Task.isCancelled && onAir {
            await cycle()
            try? await Task.sleep(nanoseconds: 6_000_000_000)
        }
    }

    private func cycle() async {
        guard let api = station.api else {
            appendLog("Server URL or API key looks invalid — check Settings.", .error)
            setOnAir(false)
            return
        }
        if case .confirmed = phase {} else { phase = .receiving }

        do {
            let feed = try await api.next(rig: station.rigName)
            guard let t = feed.transmission else {
                if phase != .confirmed { phase = .listening }
                return
            }

            current = t
            lastConfirmation = nil
            appendLog("Received \"\(t.title ?? t.slug ?? "signal")\" — going on air.", .info)
            phase = .broadcasting

            // The proof packet is what physically goes out over the WiFi radio.
            let packetData = t.packet.flatMap { Data(base64Encoded: $0) }
                ?? Data((t.title ?? t.id).utf8)
            let bytes = [UInt8](packetData)

            let sent = await Task.detached(priority: .userInitiated) {
                Broadcaster.broadcast(packetData)
            }.value

            var chirpSeconds = 0.0
            if station.chirpEnabled {
                chirpSeconds = chirp.play(bytes)
            }
            // Hold the on-air moment for at least the chirp's duration.
            try? await Task.sleep(nanoseconds: UInt64(max(chirpSeconds, 1.2) * 1_000_000_000))

            phase = .confirming
            let coord = station.effectiveCoordinate(from: locationProvider)
            let latStr = coord.map { String(format: "%.5f", $0.lat) } ?? ""
            let lonStr = coord.map { String(format: "%.5f", $0.lon) } ?? ""
            let payload = Signer.confirmationPayload(
                id: t.id, payloadHash: t.payload_hash, at: Date(), lat: latStr, lon: lonStr
            )
            guard let signature = signer.sign(payload) else {
                appendLog("Signing failed — confirmation not sent.", .error)
                phase = .listening
                return
            }

            let res = try await api.complete(
                id: t.id, signedPayload: payload,
                signature: signature, pubkey: signer.publicKeyBase64
            )

            if res.ok == true {
                confirmedCount += 1
                lastConfirmation = Confirmation(
                    title: t.title ?? "Untitled signal",
                    permalink: res.permalink ?? t.permalink,
                    certificateURL: res.certificate_url,
                    lat: coord?.lat,
                    lon: coord?.lon,
                    signaturePrefix: String(signature.prefix(16)),
                    verified: res.signature_verified ?? false,
                    date: Date()
                )
                appendLog(
                    sent
                        ? "On air ✓ — signed confirmation delivered."
                        : "Confirmation delivered (UDP send reported an issue).",
                    .success
                )
                phase = .confirmed
            } else {
                appendLog("Confirmation rejected: \(res.error ?? "unknown error").", .error)
                phase = .listening
            }
            current = nil
        } catch {
            appendLog(error.localizedDescription, .error)
            current = nil
            phase = .listening
        }
    }

    private func appendLog(_ text: String, _ kind: LogEntry.Kind) {
        log.insert(LogEntry(date: Date(), text: text, kind: kind), at: 0)
        if log.count > 60 { log.removeLast(log.count - 60) }
    }
}
