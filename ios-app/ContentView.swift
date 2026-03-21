import SwiftUI

/// Standard-Einstiegsview für das Xcode-Template.
/// Zeigt die Auftragsliste; erwartet `AuftraegeStore` als EnvironmentObject.
struct ContentView: View {
    @EnvironmentObject var store: AuftraegeStore

    var body: some View {
        AuftragListView()
    }
}
