import SwiftUI

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup("Walking Tracks") {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .defaultSize(width: 1100, height: 760)
    }
}
