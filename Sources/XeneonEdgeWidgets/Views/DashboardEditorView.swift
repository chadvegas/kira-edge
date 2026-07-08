import SwiftUI

struct DashboardEditorView: View {
    @Bindable var store: DashboardStore

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text("Kira Edge")
                    .font(.title2.weight(.semibold))

                Spacer()

                Button {
                    store.moveToEdge()
                } label: {
                    Label("Send", systemImage: "arrow.up.forward.app")
                }
                .help("Send to XENEON Edge")

                Button {
                    store.moveToEdge()
                } label: {
                    Label("Edge", systemImage: "rectangle.inset.filled")
                }
                .help("Enter Edge mode")
            }

            EdgePreviewFrame {
                EdgeDashboardView(store: store, isPreview: true)
            }

            ProfilePageControlsView(store: store)

            HStack(spacing: 16) {
                StatusChip(symbolName: "display", title: store.screenStatus)
                StatusChip(symbolName: "bolt.horizontal", title: store.actionStatus)

                Toggle(isOn: $store.isPinned) {
                    Label("Pinned", systemImage: "pin")
                }
                .toggleStyle(.switch)
                .onChange(of: store.isPinned) {
                    store.configureWindow()
                }

                Toggle(isOn: forecastBinding) {
                    Label("Full Forecast", systemImage: "cloud.sun")
                }
                .toggleStyle(.switch)

                Spacer()
            }

            PresetGridView(store: store)

            TextEditor(text: $store.noteText)
                .font(.system(.body, design: .rounded))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(height: 104)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .onChange(of: store.noteText) {
                    store.persist()
                }
        }
        .padding(24)
    }

    fileprivate static func presetTint(_ preset: DashboardPreset) -> Color {
        switch preset {
        case .command: .cyan
        case .media: .red
        case .work: .green
        case .streaming: .purple
        case .aiOps: .indigo
        case .home: .mint
        }
    }

    private var forecastBinding: Binding<Bool> {
        Binding {
            store.showsFullDayForecast
        } set: { _ in
            store.toggleFullDayForecast()
        }
    }
}

private struct PresetGridView: View {
    @Bindable var store: DashboardStore

    private var rows: [[DashboardPreset]] {
        let presets = DashboardPreset.allCases
        return stride(from: 0, to: presets.count, by: 3).map { index in
            Array(presets[index..<min(index + 3, presets.count)])
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: 10) {
                    ForEach(rows[rowIndex]) { preset in
                        PresetButton(
                            preset: preset,
                            isSelected: store.selectedPreset == preset
                        ) {
                            store.applyPreset(preset)
                        }
                    }

                    ForEach(0..<(3 - rows[rowIndex].count), id: \.self) { _ in
                        Color.clear
                    }
                }
            }
        }
    }
}

struct ProfilePageControlsView: View {
    @Bindable var store: DashboardStore

    var body: some View {
        HStack(spacing: 10) {
            Label("\(store.selectedPreset.title) Pages", systemImage: "rectangle.stack")
                .font(.headline)

            ForEach(Array(store.currentPages.enumerated()), id: \.element.id) { index, page in
                Button {
                    store.selectPage(at: index)
                } label: {
                    Text(page.title)
                        .lineLimit(1)
                        .frame(minWidth: 64)
                }
                .buttonStyle(.borderedProminent)
                .tint(index == store.currentPageIndex ? DashboardEditorView.presetTint(store.selectedPreset) : .secondary.opacity(0.28))
                .controlSize(.small)
                .help("Show \(page.title)")
            }

            Button {
                store.addPage()
            } label: {
                Label("Add Page", systemImage: "plus")
            }
            .controlSize(.small)

            Button(role: .destructive) {
                store.removeCurrentPage()
            } label: {
                Label("Delete Page", systemImage: "trash")
            }
            .controlSize(.small)
            .disabled(store.currentPages.count <= 1)

            Spacer()
        }
        .padding(10)
        .background(.quaternary.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct PresetButton: View {
    let preset: DashboardPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: preset.symbolName)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.title)
                        .font(.headline)
                    Text(preset.intent)
                        .font(.caption)
                        .lineLimit(2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(10)
        .background(fillColor, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(strokeColor, lineWidth: 1)
        }
    }

    private var tint: Color {
        DashboardEditorView.presetTint(preset)
    }

    private var fillColor: Color {
        isSelected ? tint.opacity(0.18) : Color.secondary.opacity(0.08)
    }

    private var strokeColor: Color {
        isSelected ? tint.opacity(0.8) : Color.secondary.opacity(0.14)
    }
}

struct EdgePreviewFrame<Content: View>: View {
    @ViewBuilder var content: Content
    private let edgeSize = CGSize(width: 2560, height: 720)

    var body: some View {
        Color.clear
            .aspectRatio(edgeSize.width / edgeSize.height, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                GeometryReader { proxy in
                    let scale = min(proxy.size.width / edgeSize.width, proxy.size.height / edgeSize.height)
                    let renderedSize = CGSize(width: edgeSize.width * scale, height: edgeSize.height * scale)

                    // Backdrop, clip, and border hug the rendered dashboard and the
                    // whole card centers itself — a wide settings window used to show
                    // the render pinned left with a dead black bar filling the rest.
                    content
                        .frame(width: edgeSize.width, height: edgeSize.height)
                        .scaleEffect(scale, anchor: .topLeading)
                        .frame(width: renderedSize.width, height: renderedSize.height, alignment: .topLeading)
                        .background(.black, in: RoundedRectangle(cornerRadius: 8))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(.quaternary, lineWidth: 1)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
    }
}

struct StatusChip: View {
    let symbolName: String
    let title: String

    var body: some View {
        Label(title, systemImage: symbolName)
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.quaternary, in: Capsule())
    }
}
