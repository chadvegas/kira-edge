import SwiftUI

// MARK: - Icon picker

/// A visual SF Symbol picker: shows the current icon, and on tap opens a searchable,
/// categorized grid. A custom field at the bottom still allows typing any SF Symbol name.
struct IconPickerField: View {
    @Binding var symbol: String
    var accent: Color
    var onCommit: () -> Void

    @State private var isPresented = false
    @State private var search = ""

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol.isEmpty ? "questionmark.square.dashed" : symbol)
                    .foregroundStyle(accent)
                    .frame(width: 18)
                Text(symbol.isEmpty ? "Choose icon…" : symbol)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 190)
        }
        .buttonStyle(.bordered)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            popoverBody
        }
    }

    private var filteredSections: [(title: String, symbols: [String])] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return IconCatalog.sections.map { ($0.title, $0.symbols) } }
        return IconCatalog.sections.compactMap { section in
            let hits = section.symbols.filter { $0.contains(query) }
            return hits.isEmpty ? nil : (section.title, hits)
        }
    }

    private var popoverBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search icons", text: $search)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if filteredSections.isEmpty {
                        Text("No icons match “\(search)”. Type an exact SF Symbol name below.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                    }
                    ForEach(filteredSections, id: \.title) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 6), count: 7), spacing: 6) {
                                ForEach(section.symbols, id: \.self) { name in
                                    Button {
                                        symbol = name
                                        onCommit()
                                        isPresented = false
                                    } label: {
                                        Image(systemName: name)
                                            .font(.system(size: 16))
                                            .frame(width: 32, height: 32)
                                            .background(
                                                symbol == name ? accent.opacity(0.22) : Color.secondary.opacity(0.08),
                                                in: RoundedRectangle(cornerRadius: 7)
                                            )
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 7)
                                                    .stroke(symbol == name ? accent : .clear, lineWidth: 1.5)
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    .help(name)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: 260)

            Divider()
            HStack(spacing: 6) {
                Text("Custom")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("SF Symbol name", text: $symbol)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { onCommit() }
            }
        }
        .padding(12)
        .frame(width: 320)
    }
}

private enum IconCatalog {
    struct Section {
        let title: String
        let symbols: [String]
    }

    static let sections: [Section] = [
        Section(title: "Media", symbols: [
            "play.fill", "pause.fill", "playpause.fill", "backward.fill", "forward.fill",
            "tv", "tv.fill", "music.note", "music.note.list", "film.fill", "headphones",
            "speaker.wave.2.fill", "hifispeaker.fill", "airplayvideo", "radio", "gamecontroller.fill"
        ]),
        Section(title: "Web & Apps", symbols: [
            "app.fill", "square.grid.2x2.fill", "safari.fill", "globe", "network", "link",
            "cloud.fill", "bag.fill", "cart.fill", "creditcard.fill", "map.fill", "location.fill"
        ]),
        Section(title: "Communication", symbols: [
            "message.fill", "bubble.left.fill", "envelope.fill", "phone.fill", "video.fill", "bell.fill", "at"
        ]),
        Section(title: "Productivity", symbols: [
            "calendar", "clock.fill", "alarm.fill", "timer", "list.bullet", "note.text",
            "doc.fill", "folder.fill", "tray.fill", "pencil", "books.vertical.fill", "bookmark.fill"
        ]),
        Section(title: "System", symbols: [
            "cpu", "memorychip", "internaldrive.fill", "externaldrive.fill", "gauge.high",
            "bolt.fill", "battery.100percent", "wifi", "antenna.radiowaves.left.and.right",
            "gearshape.fill", "slider.horizontal.3", "terminal.fill", "desktopcomputer",
            "laptopcomputer", "display", "keyboard.fill"
        ]),
        Section(title: "Weather & Nature", symbols: [
            "sun.max.fill", "moon.fill", "moon.stars.fill", "cloud.sun.fill", "cloud.rain.fill",
            "snowflake", "sparkles", "flame.fill", "leaf.fill", "drop.fill", "wind"
        ]),
        Section(title: "Objects", symbols: [
            "house.fill", "building.2.fill", "car.fill", "airplane", "gift.fill", "camera.fill",
            "photo.fill", "paintbrush.fill", "hammer.fill", "lightbulb.fill", "key.fill",
            "lock.fill", "flag.fill", "tag.fill", "shippingbox.fill"
        ]),
        Section(title: "Symbols", symbols: [
            "star.fill", "heart.fill", "crown.fill", "sparkle", "circle.fill", "square.fill",
            "triangle.fill", "hexagon.fill", "seal.fill", "checkmark.seal.fill",
            "exclamationmark.triangle.fill", "questionmark.circle.fill", "plus.circle.fill",
            "number", "percent", "infinity"
        ])
    ]
}
