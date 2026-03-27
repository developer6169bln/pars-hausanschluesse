import SwiftUI

struct RootTabView: View {
    @StateObject private var vm = AppViewModel()

    var body: some View {
        let dir: SwiftUI.LayoutDirection = Localization.isRTL(for: vm.language) ? .rightToLeft : .leftToRight

        TabView {
            EmergencyPlanFeature()
                .environmentObject(vm)
                .tabItem { Label(Localization.t("tabEmergencyPlan", lang: vm.language), systemImage: "list.bullet.clipboard") }

            InventoryFeature()
                .environmentObject(vm)
                .tabItem { Label(Localization.t("tabInventory", lang: vm.language), systemImage: "tray.full") }

            HandbookFeature()
                .environmentObject(vm)
                .tabItem { Label(Localization.t("tabHandbook", lang: vm.language), systemImage: "book.closed") }

            ShopFeature()
                .environmentObject(vm)
                .tabItem { Label(Localization.t("tabShop", lang: vm.language), systemImage: "bag.fill") }

            MeetupsFeature()
                .environmentObject(vm)
                .tabItem { Label(Localization.t("tabMeetups", lang: vm.language), systemImage: "mappin.and.ellipse") }
        }
        .environment(\.layoutDirection, dir)
    }
}

