import SwiftUI

struct DisplayPanelView: View {
    @Bindable var store: DashboardStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Display")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    store.screenStatus = ScreenResolver.targetDescription()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Appearance", systemImage: store.appearanceMode.symbolName)
                        .font(.system(.body, design: .rounded))

                    Spacer()

                    Picker("Appearance", selection: appearanceBinding) {
                        ForEach(EdgeAppearanceMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.symbolName)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                }
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Motion Backdrop", systemImage: store.motionBackdropMode.symbolName)
                            .font(.system(.body, design: .rounded))

                        Spacer()

                        Toggle(isOn: motionPausedBinding) {
                            Text("Pause")
                        }
                        .toggleStyle(.switch)
                    }

                    Picker("Mode", selection: motionModeBinding) {
                        ForEach(MotionBackdropMode.allCases) { mode in
                            Label(mode.shortTitle, systemImage: mode.symbolName)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 16) {
                        Picker("Tiles", selection: tileMaterialBinding) {
                            ForEach(MotionTileMaterial.allCases) { material in
                                Label(material.title, systemImage: material.symbolName)
                                    .tag(material)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)

                        MotionSlider(
                            title: "Speed",
                            value: motionSpeedBinding,
                            range: 0.3...2.0,
                            suffix: "x"
                        )

                        MotionSlider(
                            title: "Intensity",
                            value: motionIntensityBinding,
                            range: 0.4...1.4,
                            suffix: ""
                        )
                    }
                }
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

                // Key by positional offset: identical monitors produce byte-identical
                // summary strings, so `id: \.self` would collide and drop rows.
                ForEach(Array(ScreenResolver.screenSummaries().enumerated()), id: \.offset) { _, summary in
                    Label(summary, systemImage: summary.localizedCaseInsensitiveContains("XENEON") ? "display.and.arrow.down" : "display")
                        .font(.system(.body, design: .rounded))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
            }

            HStack {
                Button {
                    store.moveToEdge()
                } label: {
                    Label("Send", systemImage: "arrow.up.forward.app")
                }

                Button {
                    store.exitEdgeMode()
                } label: {
                    Label("Controls", systemImage: "sidebar.leading")
                }

                Spacer()
            }

            Spacer()
        }
        .padding(24)
    }

    private var appearanceBinding: Binding<EdgeAppearanceMode> {
        Binding {
            store.appearanceMode
        } set: { mode in
            store.setAppearanceMode(mode)
        }
    }

    private var motionModeBinding: Binding<MotionBackdropMode> {
        Binding {
            store.motionBackdropMode
        } set: { mode in
            store.setMotionBackdropMode(mode)
        }
    }

    private var tileMaterialBinding: Binding<MotionTileMaterial> {
        Binding {
            store.motionTileMaterial
        } set: { material in
            store.setMotionTileMaterial(material)
        }
    }

    private var motionSpeedBinding: Binding<Double> {
        Binding {
            store.motionSpeed
        } set: { speed in
            store.setMotionSpeed(speed)
        }
    }

    private var motionIntensityBinding: Binding<Double> {
        Binding {
            store.motionIntensity
        } set: { intensity in
            store.setMotionIntensity(intensity)
        }
    }

    private var motionPausedBinding: Binding<Bool> {
        Binding {
            store.motionIsPaused
        } set: { isPaused in
            store.setMotionPaused(isPaused)
        }
    }
}

private struct MotionSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let suffix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text(formattedValue)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.system(.caption, design: .rounded).weight(.semibold))

            Slider(value: $value, in: range, step: 0.1)
        }
    }

    private var formattedValue: String {
        let base = value.formatted(.number.precision(.fractionLength(1)))
        return suffix.isEmpty ? base : "\(base)\(suffix)"
    }
}
