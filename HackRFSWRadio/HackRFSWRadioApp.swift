import AppKit
import SwiftUI

@main
struct HackRFSWRadioApp: App {
    @State private var engine = RadioEngine()

    var body: some Scene {
        WindowGroup("HackRF Radio") {
            ContentView()
                .environment(engine)
                .preferredColorScheme(.dark)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    engine.shutdownBlocking()
                }
        }
        .defaultSize(width: 1280, height: 860)
        .windowResizability(.contentMinSize)
        .windowStyle(.plain)
    }
}
