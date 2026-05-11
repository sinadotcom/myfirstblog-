import SwiftUI

@main
struct ImageToScreensaverApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup("Image to Screensaver") {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 880, minHeight: 600)
        }
        .windowResizability(.contentSize)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
