import SwiftUI

/// Now Playing widget: album artwork, track metadata, live progress, and
/// touch-sized transport controls, fed by the system-wide MediaRemote stream
/// (works with Music, Spotify, browsers, and anything else that publishes
/// Now Playing info).
struct MediaWidgetView: View {
    let snapshot: NowPlayingSnapshot?
    let accent: Color
    let helperAvailable: Bool
    let onPlayPause: () -> Void
    let onNext: () -> Void
    let onPrevious: () -> Void
    /// When set, the widget is standing in for a launcher tile and shows a
    /// small apps button that returns to the grid.
    var onShowLauncher: (() -> Void)?

    @Environment(\.privacyMode) private var privacyMode
    @Environment(\.widgetTextScale) private var textScale

    var body: some View {
        Group {
            if !helperAvailable {
                emptyState(
                    symbolName: "wrench.and.screwdriver",
                    title: "Media helper missing",
                    subtitle: "Reinstall the app bundle to enable playback controls"
                )
            } else if let snapshot {
                nowPlayingContent(snapshot)
            } else {
                emptyState(
                    symbolName: "music.note",
                    title: "Nothing playing",
                    subtitle: "Start playback in any app"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            // Labeled so it reads as the way back at a glance; a bare icon
            // chip here got missed entirely on the strip.
            if let onShowLauncher {
                Button(action: onShowLauncher) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 12, weight: .heavy))
                        Text("Apps")
                            .font(EdgeTheme.bodyFont(size: 12, weight: .heavy))
                    }
                    .padding(.horizontal, 13)
                    .frame(height: 32)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(EdgeTheme.overlayText)
                .background(EdgeTheme.overlayFill, in: Capsule())
                .overlay {
                    Capsule().stroke(.white.opacity(0.24), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
                .help("Back to apps")
                .accessibilityLabel("Back to apps")
                .accessibilityHint("Returns this launcher tile to the app grid.")
            }
        }
    }

    /// Wide tiles get artwork beside the metadata; portrait-shaped tiles (a
    /// swapped standard-width launcher, for instance) stack artwork above it —
    /// the side-by-side layout crushes text into a sliver there.
    private func nowPlayingContent(_ snapshot: NowPlayingSnapshot) -> some View {
        GeometryReader { proxy in
            if proxy.size.width < proxy.size.height {
                verticalLayout(snapshot, in: proxy.size)
            } else {
                horizontalLayout(snapshot, in: proxy.size)
            }
        }
    }

    private func horizontalLayout(_ snapshot: NowPlayingSnapshot, in size: CGSize) -> some View {
        HStack(spacing: 18) {
            artworkView(snapshot, side: max(96, min(size.height, 250)))

            VStack(alignment: .leading, spacing: 7) {
                Text(titleText(snapshot))
                    .font(EdgeTheme.bodyFont(size: 23 * textScale, weight: .heavy))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.trailing, onShowLauncher == nil ? 0 : 96)

                if !privacyMode {
                    Text(subtitleText(snapshot))
                        .font(EdgeTheme.bodyFont(size: 15 * textScale, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 4)

                progressView(snapshot)
                transportRow(snapshot, centered: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: size.width, height: size.height, alignment: .leading)
    }

    private func verticalLayout(_ snapshot: NowPlayingSnapshot, in size: CGSize) -> some View {
        VStack(spacing: 10) {
            artworkView(snapshot, side: max(96, min(size.width, size.height - 195)))

            Text(titleText(snapshot))
                .font(EdgeTheme.bodyFont(size: 20 * textScale, weight: .heavy))
                .lineLimit(1)
                .truncationMode(.tail)

            if !privacyMode {
                Text(subtitleText(snapshot))
                    .font(EdgeTheme.bodyFont(size: 14 * textScale, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 2)

            progressView(snapshot)
            transportRow(snapshot, centered: true)
        }
        .frame(width: size.width, height: size.height)
    }

    private func transportRow(_ snapshot: NowPlayingSnapshot, centered: Bool) -> some View {
        HStack(spacing: 14) {
            if centered { Spacer(minLength: 0) }
            transportButton(symbolName: "backward.fill", diameter: 52, action: onPrevious)
                .accessibilityLabel("Previous track")
                .accessibilityHint("Skips to the previous track.")
            transportButton(
                symbolName: snapshot.isPlaying ? "pause.fill" : "play.fill",
                diameter: 64,
                isProminent: true,
                action: onPlayPause
            )
            .accessibilityLabel(snapshot.isPlaying ? "Pause" : "Play")
            .accessibilityValue(snapshot.isPlaying ? "Playing" : "Paused")
            .accessibilityHint("Toggles playback.")
            .accessibilityAddTraits(snapshot.isPlaying ? .isSelected : [])
            transportButton(symbolName: "forward.fill", diameter: 52, action: onNext)
                .accessibilityLabel("Next track")
                .accessibilityHint("Skips to the next track.")
            Spacer(minLength: 0)
        }
    }

    private func titleText(_ snapshot: NowPlayingSnapshot) -> String {
        privacyMode ? "Now Playing" : snapshot.title
    }

    private func subtitleText(_ snapshot: NowPlayingSnapshot) -> String {
        switch (snapshot.artist.isEmpty, snapshot.album.isEmpty) {
        case (false, false): "\(snapshot.artist) · \(snapshot.album)"
        case (false, true): snapshot.artist
        case (true, false): snapshot.album
        case (true, true): " "
        }
    }

    @ViewBuilder
    private func artworkView(_ snapshot: NowPlayingSnapshot, side: CGFloat) -> some View {
        ZStack {
            if let artwork = snapshot.artwork, !privacyMode {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [accent.opacity(0.55), accent.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "music.note")
                    .font(.system(size: side * 0.3, weight: .bold))
                    .foregroundStyle(EdgeTheme.overlayText.opacity(0.85))
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(EdgeTheme.stroke, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func progressView(_ snapshot: NowPlayingSnapshot) -> some View {
        if snapshot.duration > 0 {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = snapshot.elapsed(at: context.date)
                let fraction = min(1, max(0, elapsed / snapshot.duration))
                VStack(spacing: 5) {
                    GeometryReader { bar in
                        ZStack(alignment: .leading) {
                            Capsule().fill(EdgeTheme.overlaySubtleFill)
                            Capsule()
                                .fill(EdgeTheme.accentFill(accent))
                                .frame(width: max(6, bar.size.width * fraction))
                        }
                    }
                    .frame(height: 7)

                    HStack {
                        Text(Self.timeString(elapsed))
                        Spacer()
                        Text(Self.timeString(snapshot.duration))
                    }
                    .font(EdgeTheme.bodyFont(size: 11 * textScale, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func transportButton(
        symbolName: String,
        diameter: CGFloat,
        isProminent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.system(size: diameter * 0.38, weight: .heavy))
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isProminent ? EdgeTheme.accentGlyph : EdgeTheme.overlayText)
        .background {
            if isProminent {
                Circle().fill(EdgeTheme.accentFill(accent))
            } else {
                Circle().fill(EdgeTheme.overlaySubtleFill)
            }
        }
        .overlay {
            Circle().stroke(isProminent ? accent.opacity(0.5) : EdgeTheme.stroke, lineWidth: 1)
        }
        .accessibilityHint("Playback control.")
    }

    private func emptyState(symbolName: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(accent)
            Text(title)
                .font(EdgeTheme.bodyFont(size: 17 * textScale, weight: .heavy))
            Text(subtitle)
                .font(EdgeTheme.bodyFont(size: 12 * textScale, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    static func timeString(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
