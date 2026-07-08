import AppKit
import SwiftUI

struct SettingsProfilesPage: View {
    @Bindable var store: DashboardStore
    @State private var isDeletePageConfirmationPresented = false

    var body: some View {
        SettingsPage(
            title: "Profiles",
            subtitle: "Pick a dashboard mode, manage pages, and keep each profile focused on a real workflow."
        ) {
            FlowGrid(DashboardPreset.allCases, minItemWidth: 270) { preset in
                ProfileCard(preset: preset, store: store)
            }

            SettingsCard(padding: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        SectionHeader(
                            "\(store.selectedPreset.title) pages",
                            subtitle: "Each page has its own widget layout."
                        )
                        Spacer()
                        Button {
                            store.addPage()
                        } label: {
                            Label("Add Page", systemImage: "plus")
                        }
                        Button {
                            store.duplicateCurrentPage()
                        } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        Button(role: .destructive) {
                            isDeletePageConfirmationPresented = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(store.currentPages.count <= 1)
                        .confirmationDialog("Delete this page?", isPresented: $isDeletePageConfirmationPresented) {
                            Button("Remove from Profile", role: .destructive) {
                                store.removeCurrentPage()
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("This removes \(store.currentPageTitle) from \(store.selectedPreset.title).")
                        }
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(store.currentPages.enumerated()), id: \.element.id) { index, page in
                                PageThumbnail(
                                    page: page,
                                    index: index,
                                    isSelected: index == store.currentPageIndex
                                ) {
                                    store.selectPage(at: index)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            SettingsCard {
                SettingsRow(
                    symbolName: "text.alignleft",
                    tint: .purple,
                    title: "Profile note",
                    subtitle: "Shown by Note widgets on this profile."
                ) {
                    EmptyView()
                }
                TextEditor(text: $store.noteText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 92)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                    .onChange(of: store.noteText) {
                        store.persist()
                    }
            }

            SettingsCard {
                SectionHeader(
                    "Automation",
                    subtitle: "Let the dashboard switch itself when your day changes."
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 14)

                SettingsRow(
                    symbolName: "calendar.badge.clock",
                    tint: .teal,
                    title: "Switch profile before meetings",
                    subtitle: store.calendarConnected
                        ? "Loads a profile shortly before your next calendar event."
                        : "Connect Google Calendar in the Clock widget settings to use this."
                ) {
                    Toggle("", isOn: meetingAutomationBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(!store.calendarConnected && !store.automationMeetingEnabled)
                }

                if store.automationMeetingEnabled {
                    SettingsDivider()
                    SettingsRow(
                        symbolName: "rectangle.3.group",
                        tint: .teal,
                        title: "Switch to",
                        subtitle: "Profile loaded when a meeting is coming up."
                    ) {
                        Picker("Switch to", selection: meetingPresetBinding) {
                            ForEach(DashboardPreset.allCases) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 170)
                    }
                    SettingsDivider()
                    SettingsRow(
                        symbolName: "clock.arrow.circlepath",
                        tint: .teal,
                        title: "Lead time",
                        subtitle: "How early the profile switch happens."
                    ) {
                        HStack(spacing: 10) {
                            Text("\(store.automationMeetingLeadMinutes) min before")
                                .font(.body.weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Stepper("Lead time", value: meetingLeadMinutesBinding, in: 1...30)
                                .labelsHidden()
                        }
                    }
                }
            }
        }
    }

    private var meetingAutomationBinding: Binding<Bool> {
        Binding(
            get: { store.automationMeetingEnabled },
            set: { store.setAutomationMeetingEnabled($0) }
        )
    }

    private var meetingPresetBinding: Binding<DashboardPreset> {
        Binding(
            get: { store.automationMeetingPreset },
            set: { store.setAutomationMeetingPreset($0) }
        )
    }

    private var meetingLeadMinutesBinding: Binding<Int> {
        Binding(
            get: { store.automationMeetingLeadMinutes },
            set: { store.setAutomationMeetingLeadMinutes($0) }
        )
    }
}

private struct ProfileCard: View {
    let preset: DashboardPreset
    @Bindable var store: DashboardStore

    private var pages: [DashboardPage] {
        store.pagesByPreset[preset.rawValue] ?? []
    }

    private var widgetCount: Int {
        pages.reduce(0) { $0 + $1.tiles.count }
    }

    var body: some View {
        Button {
            store.applyPreset(preset)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SettingsIconBadge(symbolName: preset.symbolName, tint: tint)
                    Spacer()
                    if store.selectedPreset == preset {
                        StatusPill(title: "On Edge", tint: tint)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(preset.title)
                        .font(.title3.weight(.semibold))
                    Text(preset.intent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                MiniTilePreview(preset: preset, pages: pages)

                Text("\(max(pages.count, 1)) pages · \(widgetCount) widgets")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 11))
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .stroke(store.selectedPreset == preset ? tint.opacity(0.9) : Color.primary.opacity(0.08), lineWidth: store.selectedPreset == preset ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var tint: Color {
        settingsPresetTint(preset)
    }
}

private struct MiniTilePreview: View {
    let preset: DashboardPreset
    let pages: [DashboardPage]

    private var tiles: [WidgetTile] {
        pages.first?.tiles ?? []
    }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(tiles.prefix(6).enumerated()), id: \.offset) { _, tile in
                RoundedRectangle(cornerRadius: 5)
                    .fill(tile.accentColor.opacity(0.78))
                    .frame(width: tile.size == .wide ? 44 : 28, height: 24)
            }
            if tiles.isEmpty {
                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 5)
                        .fill(settingsPresetTint(preset).opacity(index == 0 ? 0.65 : 0.22))
                        .frame(width: index == 1 ? 44 : 28, height: 24)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct PageThumbnail: View {
    let page: DashboardPage
    let index: Int
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(page.title)
                        .font(.headline)
                    Spacer()
                    Text("\(page.tiles.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 4) {
                    ForEach(Array(page.tiles.prefix(8).enumerated()), id: \.offset) { _, tile in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(tile.isEnabled ? tile.accentColor.opacity(0.82) : Color.secondary.opacity(0.20))
                            .frame(width: tile.size == .wide ? 34 : 22, height: 18)
                    }
                    Spacer(minLength: 0)
                }

                Text("Page \(index + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(width: 210, height: 106, alignment: .topLeading)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
    }
}
