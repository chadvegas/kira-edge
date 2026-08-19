import AppKit
import Darwin
import Foundation
import ImageIO
import os

/// System-wide Now Playing snapshot rendered by the media widget.
struct NowPlayingSnapshot: Equatable {
    var title = ""
    var artist = ""
    var album = ""
    var isPlaying = false
    /// Track length in seconds; 0 when the source doesn't report one (live streams).
    var duration: TimeInterval = 0
    /// Elapsed seconds as of `capturedAt`; extrapolate with `elapsed(at:)`.
    var elapsedTime: TimeInterval = 0
    var capturedAt = Date.distantPast
    var bundleIdentifier = ""
    var artwork: NSImage?
    /// Hash of the raw artwork payload; artwork equality is keyed on this so the
    /// synthesized-style comparison below never touches NSImage identity.
    var artworkKey = 0

    static func == (lhs: NowPlayingSnapshot, rhs: NowPlayingSnapshot) -> Bool {
        lhs.title == rhs.title
            && lhs.artist == rhs.artist
            && lhs.album == rhs.album
            && lhs.isPlaying == rhs.isPlaying
            && lhs.duration == rhs.duration
            && lhs.elapsedTime == rhs.elapsedTime
            && lhs.capturedAt == rhs.capturedAt
            && lhs.bundleIdentifier == rhs.bundleIdentifier
            && lhs.artworkKey == rhs.artworkKey
    }

    /// Best-guess elapsed time at `date`. The adapter only emits events on
    /// change (track/state/seek), so playback position is extrapolated from the
    /// last event's timestamp while playing.
    func elapsed(at date: Date) -> TimeInterval {
        guard isPlaying else { return elapsedTime }
        let projected = elapsedTime + max(0, date.timeIntervalSince(capturedAt))
        return duration > 0 ? min(projected, duration) : projected
    }
}

/// MediaRemote command IDs understood by `mediaremote-adapter.pl send`.
enum NowPlayingCommand: Int {
    case togglePlayPause = 2
    case nextTrack = 4
    case previousTrack = 5
}

/// One parsed line of `mediaremote-adapter.pl stream --no-diff` output.
enum NowPlayingStreamEvent: Equatable {
    /// A payload describing the current item (or nil when nothing is playing).
    case update(NowPlayingSnapshot?)
    /// A line that isn't a data event (heartbeats, warnings); ignored.
    case ignored
}

/// Pure parser for adapter stream lines, split out for unit testing.
enum NowPlayingParser {
    static func parse(line: String, previous: NowPlayingSnapshot?) -> NowPlayingStreamEvent {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let envelope = object as? [String: Any],
              envelope["type"] as? String == "data",
              let payload = envelope["payload"] as? [String: Any] else {
            return .ignored
        }

        guard let title = payload["title"] as? String, !title.isEmpty else {
            return .update(nil)
        }

        var snapshot = NowPlayingSnapshot()
        snapshot.title = title
        snapshot.artist = payload["artist"] as? String ?? ""
        snapshot.album = payload["album"] as? String ?? ""
        snapshot.isPlaying = payload["playing"] as? Bool ?? false
        snapshot.duration = payload["duration"] as? TimeInterval ?? 0
        snapshot.elapsedTime = payload["elapsedTime"] as? TimeInterval ?? 0
        snapshot.bundleIdentifier = payload["bundleIdentifier"] as? String ?? ""
        snapshot.capturedAt = (payload["timestamp"] as? String).flatMap { try? Date($0, strategy: .iso8601) } ?? Date()

        if let base64 = payload["artworkData"] as? String, !base64.isEmpty {
            let key = base64.hashValue
            if key == previous?.artworkKey, let cached = previous?.artwork {
                snapshot.artwork = cached
                snapshot.artworkKey = key
            } else if let artworkData = Data(base64Encoded: base64),
                      let image = decodedArtwork(from: artworkData) {
                snapshot.artwork = image
                snapshot.artworkKey = key
            }
        } else if let previous,
                  previous.title == title,
                  previous.artist == snapshot.artist,
                  previous.album == snapshot.album,
                  previous.bundleIdentifier == snapshot.bundleIdentifier {
            // Same item without artwork in this event: keep what we had.
            snapshot.artwork = previous.artwork
            snapshot.artworkKey = previous.artworkKey
        }

        return .update(snapshot)
    }

    /// The largest edge artwork is ever drawn at on the strip is ~450pt, but
    /// some services ship 3000px art; decoding that at source resolution holds
    /// a 30MB+ bitmap (and GPU texture) to paint a small square. Downsample at
    /// decode time instead.
    private static let artworkMaxPixelSize = 600

    static func decodedArtwork(from data: Data) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: artworkMaxPixelSize
        ]
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else {
            return NSImage(data: data)
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

/// Streams system-wide Now Playing info via the bundled mediaremote-adapter
/// (BSD-3, github.com/ungive/mediaremote-adapter). MediaRemote can't be loaded
/// from our own process on macOS 15.4+, so the adapter framework is hosted by
/// Apple's /usr/bin/perl, which passes the entitlement check. Requires no
/// permissions of any kind.
@MainActor
final class NowPlayingService {
    private static let logger = Logger(subsystem: "com.chadvegas.XeneonEdgeWidgets", category: "NowPlaying")

    var onUpdate: ((NowPlayingSnapshot?) -> Void)?

    private var process: Process?
    private var readTask: Task<Void, Never>?
    private var restartAttempts = 0
    private var isStopped = true
    private var latest: NowPlayingSnapshot?
    private var activeStreamID: UUID?

    /// Helper artifacts are staged by build_and_run.sh into Resources/Helpers.
    nonisolated static var helperResources: (script: URL, framework: URL)? {
        guard let base = Bundle.main.resourceURL?.appendingPathComponent("Helpers", isDirectory: true) else {
            return nil
        }
        let script = base.appendingPathComponent("mediaremote-adapter.pl")
        let framework = base.appendingPathComponent("MediaRemoteAdapter.framework", isDirectory: true)
        guard FileManager.default.fileExists(atPath: script.path),
              FileManager.default.fileExists(atPath: framework.path) else {
            return nil
        }
        return (script, framework)
    }

    nonisolated static var isHelperAvailable: Bool {
        helperResources != nil
    }

    func start() {
        guard isStopped, process == nil, let resources = Self.helperResources else { return }
        restartAttempts = 0
        isStopped = false
        launchStream(script: resources.script, framework: resources.framework)
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        readTask?.cancel()
        readTask = nil
        activeStreamID = nil
        process?.terminate()
        process = nil
        latest = nil
        onUpdate?(nil)
    }

    func send(_ command: NowPlayingCommand) {
        guard let resources = Self.helperResources else { return }
        let scriptPath = resources.script.path
        let frameworkPath = resources.framework.path
        let argument = String(command.rawValue)
        Task.detached(priority: .userInitiated) {
            let sender = Process()
            sender.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            sender.arguments = [scriptPath, frameworkPath, "send", argument]
            sender.standardOutput = FileHandle.nullDevice
            sender.standardError = FileHandle.nullDevice
            do {
                try sender.run()
            } catch {
                return
            }

            let deadline = Date().addingTimeInterval(3)
            while sender.isRunning, Date() < deadline {
                do {
                    try await Task.sleep(for: .milliseconds(50))
                } catch {
                    break
                }
            }

            guard sender.isRunning else { return }
            sender.terminate()
            let terminationDeadline = Date().addingTimeInterval(0.25)
            while sender.isRunning, Date() < terminationDeadline {
                do {
                    try await Task.sleep(for: .milliseconds(25))
                } catch {
                    break
                }
            }
            if sender.isRunning {
                kill(sender.processIdentifier, SIGKILL)
            }
            sender.waitUntilExit()
        }
    }

    private func launchStream(script: URL, framework: URL) {
        // Reap any stream orphaned by a previous app instance: if the app dies
        // without teardown (reinstall pkill, crash), the child perl only
        // notices when its next pipe write hits SIGPIPE, which can be minutes
        // away. Scoped to our bundled script path so adapters shipped by other
        // apps are untouched; "stream" excludes in-flight send commands.
        let reaper = Process()
        reaper.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        reaper.arguments = ["-f", script.path + ".*stream"]
        try? reaper.run()
        reaper.waitUntilExit()

        let stream = Process()
        stream.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        stream.arguments = [script.path, framework.path, "stream", "--no-diff", "--debounce=250"]
        let stdout = Pipe()
        stream.standardOutput = stdout
        stream.standardError = FileHandle.nullDevice

        do {
            try stream.run()
            Self.logger.info("stream launched, pid \(stream.processIdentifier)")
        } catch {
            Self.logger.error("stream launch failed: \(error.localizedDescription)")
            scheduleRestart()
            return
        }

        process = stream
        let streamID = UUID()
        activeStreamID = streamID
        // Structured read loop on the main actor: FileHandle.bytes suspends off
        // the main thread and each line hops back here, so no work happens in
        // background system callbacks (hard rule, see CONTRIBUTING.md).
        readTask = Task { [weak self] in
            let handle = stdout.fileHandleForReading
            do {
                for try await line in handle.bytes.lines {
                    guard let self, !Task.isCancelled else { return }
                    self.consume(line: line)
                }
            } catch {
                // Fall through to the restart path below.
            }
            self?.streamEnded(for: streamID)
        }
    }

    private func consume(line: String) {
        switch NowPlayingParser.parse(line: line, previous: latest) {
        case .update(let snapshot):
            restartAttempts = 0
            latest = snapshot
            onUpdate?(snapshot)
        case .ignored:
            break
        }
    }

    private func streamEnded(for streamID: UUID) {
        guard activeStreamID == streamID else { return }
        activeStreamID = nil
        process = nil
        readTask = nil
        guard !isStopped else { return }
        scheduleRestart()
    }

    private func scheduleRestart() {
        guard !isStopped else { return }
        guard restartAttempts < 5, let resources = Self.helperResources else {
            // Permit a later lifecycle sync to recover after the bounded retry
            // budget is exhausted or the helper temporarily disappears.
            isStopped = true
            latest = nil
            onUpdate?(nil)
            return
        }
        restartAttempts += 1
        let delay = Duration.seconds(min(30, 1 << restartAttempts))
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !self.isStopped, self.process == nil else { return }
            self.launchStream(script: resources.script, framework: resources.framework)
        }
    }
}
