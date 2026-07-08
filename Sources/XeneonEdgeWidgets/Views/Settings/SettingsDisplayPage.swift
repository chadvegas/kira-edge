import SwiftUI

struct SettingsDisplayPage: View {
    @Bindable var store: DashboardStore

    var body: some View {
        SettingsPage(
            title: "Display",
            subtitle: "Choose the dashboard appearance, motion backdrop, and target Edge screen."
        ) {
            SettingsCard(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader("Appearance", subtitle: "Used by the Edge dashboard surface.")
                    FlowGrid(EdgeAppearanceMode.allCases, minItemWidth: 170) { mode in
                        DisplayOptionCard(
                            title: mode.title,
                            subtitle: mode == .system ? "Follow macOS" : "\(mode.title) dashboard",
                            symbolName: mode.symbolName,
                            tint: mode == .dark ? .purple : mode == .light ? .orange : .blue,
                            isSelected: store.appearanceMode == mode
                        ) {
                            store.setAppearanceMode(mode)
                        }
                    }
                }
            }

            SettingsCard(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        SectionHeader("Motion backdrop", subtitle: "Preview and tune the animated background behind widgets.")
                        Spacer()
                        Toggle("Pause", isOn: motionPausedBinding)
                            .toggleStyle(.switch)
                    }

                    FlowGrid(MotionBackdropMode.allCases, minItemWidth: 185) { mode in
                        MotionCard(
                            mode: mode,
                            isSelected: store.motionBackdropMode == mode
                        ) {
                            store.setMotionBackdropMode(mode)
                        }
                    }

                    SettingsDivider()
                        .padding(.top, 4)

                    HStack(spacing: 18) {
                        Picker("Tiles", selection: tileMaterialBinding) {
                            ForEach(MotionTileMaterial.allCases) { material in
                                Text(material.title).tag(material)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)

                        VStack(alignment: .leading) {
                            Text("Speed")
                                .font(.caption.weight(.semibold))
                            Slider(value: motionSpeedBinding, in: 0.3...2.0, step: 0.1)
                        }

                        VStack(alignment: .leading) {
                            Text("Intensity")
                                .font(.caption.weight(.semibold))
                            Slider(value: motionIntensityBinding, in: 0.4...1.4, step: 0.1)
                        }
                    }
                }
            }

            SettingsCard {
                SettingsRow(symbolName: "display", tint: .indigo, title: "Edge screen", subtitle: store.screenStatus) {
                    HStack {
                        Button {
                            store.screenStatus = ScreenResolver.targetDescription()
                        } label: {
                            Label("Identify", systemImage: "scope")
                        }
                        Button {
                            store.moveToEdge()
                        } label: {
                            Label("Send to Edge", systemImage: "arrow.up.forward.app")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                SettingsDivider()
                // Key by positional offset: identical monitors produce byte-identical
                // summary strings, so `id: \.self` would collide and drop rows.
                let summaries = ScreenResolver.screenSummaries()
                ForEach(Array(summaries.enumerated()), id: \.offset) { index, summary in
                    SettingsRow(
                        symbolName: summary.localizedCaseInsensitiveContains("XENEON") ? "display.and.arrow.down" : "display",
                        tint: summary.localizedCaseInsensitiveContains("XENEON") ? .green : .secondary,
                        title: summary,
                        subtitle: nil
                    ) {
                        EmptyView()
                    }
                    if index < summaries.count - 1 {
                        SettingsDivider()
                    }
                }
                SettingsDivider()
                SettingsRow(symbolName: "figure.walk.motion", tint: .teal, title: "Reduce motion tip", subtitle: "If macOS Reduce Motion is enabled, keep speed low or pause the backdrop.") {
                    EmptyView()
                }
            }
        }
    }

    private var motionPausedBinding: Binding<Bool> {
        Binding {
            store.motionIsPaused
        } set: { store.setMotionPaused($0) }
    }

    private var tileMaterialBinding: Binding<MotionTileMaterial> {
        Binding {
            store.motionTileMaterial
        } set: { store.setMotionTileMaterial($0) }
    }

    private var motionSpeedBinding: Binding<Double> {
        Binding {
            store.motionSpeed
        } set: { store.setMotionSpeed($0) }
    }

    private var motionIntensityBinding: Binding<Double> {
        Binding {
            store.motionIntensity
        } set: { store.setMotionIntensity($0) }
    }
}

private struct DisplayOptionCard: View {
    let title: String
    let subtitle: String
    let symbolName: String
    let tint: Color
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: 10) {
                SettingsIconBadge(symbolName: symbolName, tint: tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(tint)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
            .background(isSelected ? tint.opacity(0.12) : Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? tint.opacity(0.75) : Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct MotionCard: View {
    let mode: MotionBackdropMode
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        DisplayOptionCard(
            title: mode.shortTitle,
            subtitle: mode.title,
            symbolName: mode.symbolName,
            tint: tint,
            isSelected: isSelected,
            select: select
        )
    }

    private var tint: Color {
        switch mode {
        case .aurora: .teal
        case .sakura: .pink
        case .sparkle: .yellow
        case .nebula: .purple
        }
    }
}
