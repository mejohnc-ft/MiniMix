import SwiftUI

@main
struct MiniMixApp: App {
    var body: some Scene {
        MenuBarExtra("MiniMix", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 8) {
                Text("MiniMix")
                    .font(.headline)
                Text("Detection prototype pending.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding()
            .frame(width: 240)
        }
        .menuBarExtraStyle(.window)
    }
}
