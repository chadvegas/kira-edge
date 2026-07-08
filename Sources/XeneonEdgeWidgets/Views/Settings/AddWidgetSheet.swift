import AppKit
import SwiftUI

struct AddWidgetSheetView: View {
    @Bindable var store: DashboardStore
    @Environment(\.dismiss) private var dismiss
    @State private var category: AddWidgetCategory = .essentials
    @State private var searchText = ""
    @State private var customURL = "https://"
    @State private var customTitle = "Website"

    private var filteredCatalog: [WidgetCatalogItem] {
        WidgetCatalogItem.catalog.filter { item in
            category.matches(item) &&
            (searchText.isEmpty ||
             item.title.localizedCaseInsensitiveContains(searchText) ||
             item.subtitle.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Add Widget")
                    .font(.title2.weight(.semibold))
                    .padding(.bottom, 8)

                ForEach(AddWidgetCategory.allCases) { option in
                    Button {
                        category = option
                    } label: {
                        HStack {
                            SettingsIconBadge(symbolName: option.symbolName, tint: option.tint)
                            Text(option.title)
                            Spacer()
                        }
                        .padding(7)
                        .background(category == option ? option.tint.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .frame(width: 190)
            .padding(18)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(category.title)
                        .font(.title2.weight(.semibold))
                    Spacer()
                    Button("Done") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }

                TextField("Search widgets", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                ScrollView {
                    FlowGrid(filteredCatalog, minItemWidth: 190, spacing: 12) { item in
                        WidgetCard(item: item) {
                            store.addTile(item.makeTile())
                        }
                    }

                    if category == .web {
                        CustomWebSetupCard(title: $customTitle, url: $customURL) {
                            store.addWebTile(title: customTitle, urlString: customURL)
                        }
                        .padding(.top, 12)
                    }
                }
            }
            .padding(22)
        }
        .frame(width: 860, height: 610)
    }
}

private enum AddWidgetCategory: String, CaseIterable, Identifiable {
    case essentials
    case web
    case home

    var id: String { rawValue }

    var title: String {
        switch self {
        case .essentials: "Essentials"
        case .web: "Web"
        case .home: "Home"
        }
    }

    var symbolName: String {
        switch self {
        case .essentials: "star"
        case .web: "globe"
        case .home: "house"
        }
    }

    var tint: Color {
        switch self {
        case .essentials: .blue
        case .web: .teal
        case .home: .green
        }
    }

    func matches(_ item: WidgetCatalogItem) -> Bool {
        switch self {
        case .essentials:
            item.category == .essentials
        case .web:
            item.category == .web && item.id != "home-assistant" && item.id != "weather"
        case .home:
            item.id == "home-assistant" || item.id == "weather"
        }
    }
}

private struct WidgetCard: View {
    let item: WidgetCatalogItem
    let add: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SettingsIconBadge(symbolName: item.symbolName, tint: item.accent.color)
                Spacer()
                Button(action: add) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Text(item.title)
                .font(.headline)
            Text(item.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct CustomWebSetupCard: View {
    @Binding var title: String
    @Binding var url: String
    let add: () -> Void

    var body: some View {
        SettingsCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("Custom website", subtitle: "Add any web app or dashboard URL.")
                TextField("Name", text: $title)
                TextField("Website", text: $url)
                Button(action: add) {
                    Label("Add Website Widget", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .textFieldStyle(.roundedBorder)
        }
    }
}

