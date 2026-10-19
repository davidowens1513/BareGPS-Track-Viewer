import SwiftUI

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup("Walking Tracks") {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1200, height: 760)
    }
}
