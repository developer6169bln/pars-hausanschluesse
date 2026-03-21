import SwiftUI

struct AuftragDetailView: View {
    @EnvironmentObject var store: AuftraegeStore
    @Environment(\.dismiss) var dismiss

    @State var auftrag: Auftrag
    @State private var showAR = false

    var body: some View {
        Form {
            Section("Stammdaten") {
                TextField("Bezeichnung", text: $auftrag.bezeichnung)
                TextField("Adresse", text: $auftrag.adresse)
                TextField("PLZ", text: $auftrag.plz)
                TextField("Ort", text: $auftrag.ort)
                TextField("NVT", text: Binding($auftrag.nvt, replacingNilWith: ""))
            }

            Section("Baugruben-Messung") {
                let sum = store.gesamtLaengeBaugruben(auftrag)
                if sum > 0 {
                    Label("Gesamtlänge: \(sum, specifier: "%.2f") m", systemImage: "ruler")
                        .font(.headline)
                }

                if let arr = auftrag.baugrubenLaengen, !arr.isEmpty {
                    ForEach(Array(arr.enumerated()), id: \.offset) { idx, val in
                        HStack {
                            Text("Baugrube \(idx + 1)")
                            Spacer()
                            Text("\(val, specifier: "%.2f") m")
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Text("Noch keine Baugruben gemessen.")
                        .foregroundColor(.secondary)
                }

                Button {
                    showAR = true
                } label: {
                    Label("Baugrube messen (AR)", systemImage: "camera.viewfinder")
                }
            }
        }
        .navigationTitle(auftrag.bezeichnung.isEmpty ? "Auftrag" : auftrag.bezeichnung)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Speichern") {
                    Task {
                        await save()
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showAR) {
            BaugrubeARScreen { length in
                if length > 0 {
                    var arr = auftrag.baugrubenLaengen ?? []
                    arr.append(length)
                    auftrag.baugrubenLaengen = arr
                }
                showAR = false
            }
        }
    }

    private func save() async {
        store.update(auftrag)
        await store.save()
    }
}

private extension Binding where Value == String? {
    init(_ source: Binding<String?>, replacingNilWith defaultValue: String) {
        self.init(
            get: { source.wrappedValue ?? defaultValue },
            set: { source.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}
