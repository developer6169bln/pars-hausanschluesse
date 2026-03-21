import SwiftUI

@main
struct HausanschluesseApp: App {
    @StateObject private var store = AuftraegeStore(
        client: AuftraegeClient(baseURL: Config.apiBaseURL)
    )

    var body: some Scene {
        WindowGroup {
            AuftragListView()
                .environmentObject(store)
        }
    }
}
