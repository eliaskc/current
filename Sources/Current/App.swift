import SwiftUI

@main
struct CurrentApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Empty Settings scene is what lets SwiftUI exist without a main window.
        // Real preferences are opened manually from the status-bar right-click.
        Settings { EmptyView() }
    }
}
