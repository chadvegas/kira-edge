import SwiftUI

struct WidgetGalleryView: View {
    @Bindable var store: DashboardStore

    private var columns: [[WidgetCatalogItem]] {
        let catalog = WidgetCatalogItem.catalog
        return stride(from: 0, to: catalog.count, by: 2).map { index in
            Array(catalog[index..<min(index + 2, catalog.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Gallery", systemImage: "square.grid.3x3")
                    .font(.headline)

                Spacer()

                Text("\(WidgetCatalogItem.catalog.count) tiles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(columns.indices, id: \.self) { columnIndex in
                        VStack(spacing: 10) {
                            ForEach(columns[columnIndex]) { item in
                                WidgetGalleryCard(item: item) {
                                    store.addCatalogItem(item)
                                }
                                .frame(width: 238, height: 66)
                            }
                        }
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.visible)
        }
    }
}

private struct WidgetGalleryCard: View {
    let item: WidgetCatalogItem
    let add: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(item.accent.color.opacity(0.18))

                Image(systemName: item.symbolName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(item.accent.color)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text("\(item.category.title) / \(item.subtitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Button {
                add()
            } label: {
                Label("Add", systemImage: "plus")
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .help("Add \(item.title)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(item.accent.color.opacity(0.18), lineWidth: 1)
        }
    }
}
