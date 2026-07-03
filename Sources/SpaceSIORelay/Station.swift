import Foundation

enum LocationMode: String, CaseIterable, Identifiable {
    case automatic, manual
    var id: String { rawValue }
    var label: String { self == .automatic ? "Automatic (CoreLocation)" : "Manual coordinates" }
}

/// Station configuration. The API key lives in the Keychain; everything else
/// in UserDefaults.
final class Station: ObservableObject {
    @Published var apiKey: String { didSet { Keychain.set(apiKey, account: "api-key") } }
    @Published var serverURL: String { didSet { defaults.set(serverURL, forKey: "serverURL") } }
    @Published var rigName: String { didSet { defaults.set(rigName, forKey: "rigName") } }
    @Published var chirpEnabled: Bool { didSet { defaults.set(chirpEnabled, forKey: "chirpEnabled") } }
    @Published var locationMode: LocationMode { didSet { defaults.set(locationMode.rawValue, forKey: "locationMode") } }
    @Published var manualLat: String { didSet { defaults.set(manualLat, forKey: "manualLat") } }
    @Published var manualLon: String { didSet { defaults.set(manualLon, forKey: "manualLon") } }

    private let defaults = UserDefaults.standard

    init() {
        apiKey = Keychain.get(account: "api-key") ?? ""
        serverURL = defaults.string(forKey: "serverURL") ?? "https://spacemic.vercel.app"
        rigName = defaults.string(forKey: "rigName")
            ?? "\(Host.current().localizedName ?? "mac")-relay"
        chirpEnabled = defaults.object(forKey: "chirpEnabled") as? Bool ?? true
        locationMode = LocationMode(rawValue: defaults.string(forKey: "locationMode") ?? "")
            ?? .automatic
        manualLat = defaults.string(forKey: "manualLat") ?? ""
        manualLon = defaults.string(forKey: "manualLon") ?? ""
    }

    var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var api: RadioAPI? {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlString = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, let url = URL(string: urlString), url.scheme != nil else { return nil }
        return RadioAPI(baseURL: url, apiKey: key)
    }

    /// The coordinates that go into the signed confirmation — ALWAYS coarse.
    /// Rounded to 0.1° (≈ 5-mile radius) so the station attests roughly where
    /// the broadcast happened without pinpointing anyone's home. This is the
    /// single choke point: the UI display and the signed payload both come
    /// through here, so a precise fix can never leak downstream.
    func effectiveCoordinate(from provider: LocationProvider) -> (lat: Double, lon: Double)? {
        let raw: (Double, Double)?
        switch locationMode {
        case .automatic:
            if let c = provider.coordinate {
                raw = (c.latitude, c.longitude)
            } else {
                raw = manualCoordinate // graceful fallback
            }
        case .manual:
            raw = manualCoordinate
        }
        guard let r = raw else { return nil }
        return (coarse(r.0), coarse(r.1))
    }

    /// Round to 1 decimal place ≈ an 11 km latitude cell — anywhere inside is
    /// within roughly 5 miles of the stored point.
    private func coarse(_ v: Double) -> Double {
        (v * 10).rounded() / 10
    }

    private var manualCoordinate: (lat: Double, lon: Double)? {
        guard let lat = Double(manualLat.trimmingCharacters(in: .whitespaces)),
              let lon = Double(manualLon.trimmingCharacters(in: .whitespaces)),
              abs(lat) <= 90, abs(lon) <= 180
        else { return nil }
        return (lat, lon)
    }
}
