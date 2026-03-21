import SwiftUI

struct AuftragListView: View {
    @EnvironmentObject var store: AuftraegeStore
    @State private var isLoaded = false

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && !isLoaded {
                    ProgressView("Aufträge laden…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(store.auftraege) { a in
                            NavigationLink(value: a) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(a.bezeichnung.isEmpty ? "Auftrag \(a.id)" : a.bezeichnung)
                                        .font(.headline)
                                    Text("\(a.adresse), \(a.plz) \(a.ort)")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    let sum = store.gesamtLaengeBaugruben(a)
                                    if sum > 0 {
                                        Text("Baugruben: \(sum, specifier: "%.2f") m")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Hausanschlüsse")
            .navigationDestination(for: Auftrag.self) { a in
                AuftragDetailView(auftrag: a)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await store.load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(store.isLoading)
                }
            }
            .task {
                guard !isLoaded else { return }
                isLoaded = true
                await store.load()
            }
            .alert("Fehler", isPresented: .constant(store.error != nil)) {
                Button("OK") { store.error = nil }
            } message: {
                Text(store.error ?? "")
            }
        }
    }
}
