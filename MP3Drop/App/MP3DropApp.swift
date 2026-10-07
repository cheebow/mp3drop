import SwiftUI

/// Receives files opened via "Open With MP3 Drop" or dropped on the Dock icon.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var onOpenFiles: (@MainActor ([URL]) -> Void)? {
        didSet {
            if let handler = onOpenFiles, !pendingURLs.isEmpty {
                handler(pendingURLs)
                pendingURLs = []
            }
        }
    }
    private var pendingURLs: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        if let onOpenFiles {
            onOpenFiles(urls)
        } else {
            pendingURLs.append(contentsOf: urls)
        }
    }
}

@main
struct MP3DropApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var viewModel = ConversionViewModel()

    var body: some Scene {
        Window("MP3 Drop", id: "main") {
            MainView()
                .environment(viewModel)
                .onAppear {
                    appDelegate.onOpenFiles = { urls in
                        viewModel.addFiles(urls)
                    }
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Files...") {
                    viewModel.presentOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Open Output Folder") {
                    viewModel.openOutputFolder()
                }
            }
        }

        Settings {
            SettingsView()
                .environment(viewModel)
        }
    }
}
