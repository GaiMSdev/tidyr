import SwiftUI

@main
struct TidyrApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 900, height: 600)
        .commands {
            // Remove "New Window" from File menu — single-window app
            CommandGroup(replacing: .newItem) {}
        }
    }
}
