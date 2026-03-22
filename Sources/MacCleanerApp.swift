import SwiftUI

@main
struct MacCleanerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .commands {
            SidebarCommands()
        }
    }
}
