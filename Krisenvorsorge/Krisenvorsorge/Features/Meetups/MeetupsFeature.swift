import SwiftUI

struct MeetupsFeature: View {
    @EnvironmentObject private var vm: AppViewModel

    var body: some View {
        NavigationStack {
            List {
                ForEach(vm.data.meetups) { point in
                    Section(meetupTitle(point.key)) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(point.title).font(.headline)
                            Text(point.addressOrHint).font(.body).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .navigationTitle(Localization.t("tabMeetups", lang: vm.language))
        }
    }

    private func meetupTitle(_ key: MeetupKey) -> String {
        switch key {
        case .home: return vm.language == .de ? "Zuhause" : "Home"
        case .backup: return vm.language == .de ? "Backup-Ort" : "Backup"
        case .outsideCity: return vm.language == .de ? "Außerhalb der Stadt" : "Outside city"
        }
    }
}

