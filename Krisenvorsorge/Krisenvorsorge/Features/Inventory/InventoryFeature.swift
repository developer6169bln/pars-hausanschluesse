import SwiftUI

struct InventoryFeature: View {
    @EnvironmentObject private var vm: AppViewModel

    var body: some View {
        NavigationStack {
            List {
                ForEach(InventoryCategoryKey.allCases, id: \.self) { category in
                    Section(categoryTitle(category)) {
                        let items = vm.data.inventory.filter { $0.category == category }
                        ForEach(items) { item in
                            InventoryRow(item: item)
                        }
                    }
                }
            }
            .navigationTitle(Localization.t("tabInventory", lang: vm.language))
        }
    }

    private func categoryTitle(_ category: InventoryCategoryKey) -> String {
        // MVP: einfache Kategorien in allen Sprachen über den Rohtext.
        // Später kann man das in Localization ausbauen.
        switch category {
        case .water: return vm.language == .de ? "Wasser" : "Water"
        case .food: return vm.language == .de ? "Nahrung" : "Food"
        case .medicine: return vm.language == .de ? "Medizin" : "Medicine"
        case .equipment: return vm.language == .de ? "Ausrüstung" : "Equipment"
        }
    }
}

private struct InventoryRow: View {
    let item: InventoryItem
    @EnvironmentObject private var vm: AppViewModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name).font(.headline)
                    if item.essential {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("essential")
                    }
                }
                Text("\(item.quantity) \(item.unit)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Stepper(
                value: Binding(
                    get: { item.quantity },
                    set: { newValue in
                        vm.setInventoryQuantity(itemId: item.id, quantity: newValue)
                    }
                ),
                in: 0...999
            ) {
                Text("")
            }
        }
        .padding(.vertical, 4)
    }
}

