import SwiftUI

struct ShopFeature: View {
    @EnvironmentObject private var vm: AppViewModel
    @State private var selectedKit: PreparedKit?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(vm.data.kits) { kit in
                        NavigationLink {
                            KitDetailView(kit: kit)
                        } label: {
                            KitRow(kit: kit)
                        }
                    }
                }
            }
            .navigationTitle(Localization.t("tabShop", lang: vm.language))
        }
    }
}

private struct KitRow: View {
    let kit: PreparedKit
    @EnvironmentObject private var vm: AppViewModel

    var body: some View {
        let completion = completionForKit(kit)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(kit.name).font(.headline)
                Spacer()
                Text(String(format: "%.0f%%", completion * 100))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("\(kit.durationDays) Tage · \(kit.persons) Person(en)")
                .font(.caption)
                .foregroundStyle(.secondary)
            let missingCount = missingCountForKit(kit)
            if missingCount > 0 {
                Text("\(missingCount) Items \(Localization.t("missing", lang: vm.language))")
                    .font(.caption2)
                    .foregroundStyle(.red.opacity(0.9))
            } else {
                Text("✓ Vollständig")
                    .font(.caption2)
                    .foregroundStyle(.green.opacity(0.95))
            }
        }
        .padding(.vertical, 4)
    }

    private func completionForKit(_ kit: PreparedKit) -> Double {
        let inventoryByKey = Dictionary(uniqueKeysWithValues: vm.data.inventory.map { ($0.itemKey, $0.quantity) })
        let required = kit.items
        guard !required.isEmpty else { return 0 }
        let satisfied = required.filter { req in
            (inventoryByKey[req.itemKey] ?? 0) >= req.quantity
        }
        return Double(satisfied.count) / Double(required.count)
    }

    private func missingCountForKit(_ kit: PreparedKit) -> Int {
        let inventoryByKey = Dictionary(uniqueKeysWithValues: vm.data.inventory.map { ($0.itemKey, $0.quantity) })
        kit.items.filter { req in
            (inventoryByKey[req.itemKey] ?? 0) < req.quantity
        }.count
    }
}

private struct KitDetailView: View {
    let kit: PreparedKit
    @EnvironmentObject private var vm: AppViewModel
    @State private var showBuyInfo = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(kit.name)
                        .font(.title3.bold())
                    Text("\(kit.durationDays) Tage · \(kit.persons) Person(en)")
                        .foregroundStyle(.secondary)
                    if let price = kit.priceEstimate {
                        Text("~ €\(price, specifier: "%.2f")")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 6)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Inhalt")
                        .font(.headline)

                    let inventoryByKey = Dictionary(uniqueKeysWithValues: vm.data.inventory.map { ($0.itemKey, $0.quantity) })
                    ForEach(kit.items) { req in
                        let owned = inventoryByKey[req.itemKey] ?? 0
                        let statusColor: Color = owned >= req.quantity ? .green : .orange
                        let title = vm.data.inventory.first(where: { $0.itemKey == req.itemKey })?.name ?? req.itemKey

                        HStack(spacing: 12) {
                            Circle()
                                .fill(statusColor.opacity(0.9))
                                .frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(title)
                                    .font(.subheadline)
                                Text("\(owned)/\(req.quantity) benötigt")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }

                Button {
                    showBuyInfo = true
                } label: {
                    Text(Localization.t("buy", lang: vm.language))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(kit.affiliateLink == nil)

                if showBuyInfo {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("MVP Hinweis")
                            .font(.headline)
                        Text("Für das echte Kaufen brauchst du später Affiliate-/Shop-Integration (Links).")
                            .foregroundStyle(.secondary)
                        if let link = kit.affiliateLink {
                            Text(link).font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

