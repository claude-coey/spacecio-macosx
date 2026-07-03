import SwiftUI

@main
struct SpaceSIORelayApp: App {
    @StateObject private var station: Station
    @StateObject private var engine: RelayEngine

    init() {
        let station = Station()
        _station = StateObject(wrappedValue: station)
        _engine = StateObject(wrappedValue: RelayEngine(station: station))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(station)
                .environmentObject(engine)
                .frame(minWidth: 880, minHeight: 640)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
