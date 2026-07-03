import SwiftUI

struct ContentView: View {
    @EnvironmentObject var station: Station
    @EnvironmentObject var engine: RelayEngine
    @State private var showSettings = false

    var body: some View {
        ZStack {
            StarfieldView()
            if station.isConfigured {
                DashboardView(showSettings: $showSettings)
            } else {
                OnboardingView()
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(station)
                .environmentObject(engine)
        }
        // Keep the layout composed: below this the two-column dashboard has
        // no room to breathe and padding visibly collapses.
        .frame(minWidth: 940, minHeight: 700)
    }
}

struct OnboardingView: View {
    @EnvironmentObject var station: Station
    @State private var key = ""
    @State private var name = ""
    @State private var server = "https://spacemic.vercel.app"
    @State private var showAdvanced = false

    var body: some View {
        VStack(spacing: 24) {
            Wordmark(size: 30)

            Text("Join the distributed broadcast network")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)

            Text("Paste a radio-feed API key from the operator console (Admin → Radio API). This station pulls queued signals, puts each proof packet on the air over your WiFi radio, and sends back a signed, located confirmation.")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 14) {
                LabeledField(label: "API key") {
                    SecureField("sio_…", text: $key)
                }
                LabeledField(label: "Station name") {
                    TextField(station.rigName, text: $name)
                }
                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    LabeledField(label: "Server") {
                        TextField("https://spacemic.vercel.app", text: $server)
                    }
                    .padding(.top, 8)
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
            }

            Button {
                station.serverURL = server
                if !name.trimmingCharacters(in: .whitespaces).isEmpty {
                    station.rigName = name.trimmingCharacters(in: .whitespaces)
                }
                station.apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            } label: {
                Text("Bring station online")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
        }
        .padding(38)
        .frame(width: 500)
        .glassCard(cornerRadius: 26)
    }
}

struct LabeledField<Field: View>: View {
    let label: String
    @ViewBuilder var field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .kerning(1.2)
                .foregroundStyle(.white.opacity(0.45))
            field
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .padding(10)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.white.opacity(0.12))
                )
        }
    }
}
