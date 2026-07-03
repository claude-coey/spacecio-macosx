import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var station: Station
    @EnvironmentObject var engine: RelayEngine
    @Environment(\.dismiss) private var dismiss
    @State private var copiedKey = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Station settings")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            LabeledField(label: "API key") {
                SecureField("sio_…", text: $station.apiKey)
            }
            LabeledField(label: "Station name (rig id)") {
                TextField("my-mac-relay", text: $station.rigName)
            }
            LabeledField(label: "Server") {
                TextField("https://spacemic.vercel.app", text: $station.serverURL)
            }

            Divider().overlay(Color.white.opacity(0.1))

            Toggle(isOn: $station.chirpEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Audible chirp").font(.system(size: 13, weight: .medium))
                    Text("Sonify each packet through the speakers while it goes on air.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 10) {
                Picker("Location", selection: $station.locationMode) {
                    ForEach(LocationMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if station.locationMode == .automatic {
                    HStack(spacing: 8) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.signal)
                        Text(engine.locationProvider.status)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                        Button("Request now") { engine.locationProvider.request() }
                            .font(.caption)
                    }
                } else {
                    HStack(spacing: 10) {
                        LabeledField(label: "Latitude") {
                            TextField("28.34000", text: $station.manualLat)
                        }
                        LabeledField(label: "Longitude") {
                            TextField("-80.73000", text: $station.manualLon)
                        }
                    }
                }
            }

            Divider().overlay(Color.white.opacity(0.1))

            VStack(alignment: .leading, spacing: 6) {
                Text("STATION IDENTITY (ED25519 PUBLIC KEY)")
                    .font(.system(size: 9, weight: .bold))
                    .kerning(1.2)
                    .foregroundStyle(.white.opacity(0.4))
                HStack {
                    Text(engine.stationPublicKey)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.75))
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(engine.stationPublicKey, forType: .string)
                        copiedKey = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedKey = false }
                    } label: {
                        Image(systemName: copiedKey ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
                Text("Generated on this Mac and kept in your Keychain. Every confirmation this station sends is signed with it.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(28)
        .frame(width: 480)
    }
}
