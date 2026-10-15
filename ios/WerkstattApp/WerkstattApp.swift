import SwiftUI

@main
@MainActor
struct WerkstattApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model)
        }
    }
}
