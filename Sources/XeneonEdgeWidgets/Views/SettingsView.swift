import SwiftUI

struct SettingsView: View {
    @Bindable var store: DashboardStore

    var body: some View {
        Form {
            Toggle("Pin dashboard in Edge mode", isOn: $store.isPinned)
            TextField("Note", text: $store.noteText)
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 420)
    }
}
