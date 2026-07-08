import SwiftUI

func settingsPresetTint(_ preset: DashboardPreset) -> Color {
    switch preset {
    case .command: .cyan
    case .media: .red
    case .work: .green
    case .streaming: .purple
    case .aiOps: .indigo
    case .home: .mint
    }
}
