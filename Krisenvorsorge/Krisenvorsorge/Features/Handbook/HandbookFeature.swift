import SwiftUI

struct HandbookFeature: View {
    @EnvironmentObject private var vm: AppViewModel

    var body: some View {
        NavigationStack {
            List {
                ForEach(handbookCategories(), id: \.self) { cat in
                    Section(cat) {
                        ForEach(vm.data.handbook.filter { $0.category == cat }) { article in
                            NavigationLink {
                                HandbookDetailView(article: article)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: article.iconName)
                                        .foregroundStyle(.blue)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(article.title).font(.headline)
                                        Text(article.paragraphs.first ?? "").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle(Localization.t("tabHandbook", lang: vm.language))
        }
    }

    private func handbookCategories() -> [String] {
        let cats = Set(vm.data.handbook.map(\.category))
        return Array(cats).sorted()
    }
}

private struct HandbookDetailView: View {
    let article: HandbookArticle
    @EnvironmentObject private var vm: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: article.iconName)
                        .font(.title2)
                        .foregroundStyle(.blue)
                    Text(article.title)
                        .font(.title2.bold())
                }
                ForEach(article.paragraphs, id: \.self) { paragraph in
                    Text(paragraph)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding()
        }
        .navigationTitle(article.category)
        .navigationBarTitleDisplayMode(.inline)
    }
}

