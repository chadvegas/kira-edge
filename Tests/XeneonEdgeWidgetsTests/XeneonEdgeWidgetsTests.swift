import AppKit
import Foundation
import Testing
@testable import XeneonEdgeWidgets

@MainActor
private func makeTestStore() -> DashboardStore {
    DashboardStore(defaultsKey: "test.dashboardProfile.\(UUID().uuidString)")
}

@Test func defaultWidgetsCoverEveryKind() async throws {
    let store = await makeTestStore()
    await store.applyPreset(.command)
    let configuredKinds = await Set(store.tiles.map(\.kind))

    #expect(configuredKinds.contains(.web))
    #expect(configuredKinds.contains(.launcher))
    #expect(configuredKinds.contains(.system))
}

@Test func enabledTilesRespectDisabledState() async throws {
    let store = await makeTestStore()
    await store.applyPreset(.command)
    let before = await store.enabledTiles.count
    let firstEnabled = try #require(await store.tiles.first { $0.isEnabled })

    await store.toggleWidget(firstEnabled)
    let enabledCount = await store.enabledTiles.count
    #expect(enabledCount == before - 1)
}

@Test func presetsLoadWebTiles() async throws {
    let store = await makeTestStore()
    await store.applyPreset(.media)

    let webTiles = await store.tiles.filter { $0.kind == .web }
    #expect(webTiles.count >= 2)
}

@Test func everyPresetLoadsTiles() async throws {
    let store = await makeTestStore()

    for preset in DashboardPreset.allCases {
        await store.applyPreset(preset)
        #expect(await store.selectedPreset == preset)
        #expect(await !store.tiles.isEmpty)
    }
}

@Test func reloadAllWebTilesUpdatesOnlyWebTiles() async throws {
    let store = await makeTestStore()
    await store.applyPreset(.work)
    let webIDs = await store.tiles.filter { $0.kind == .web }.map(\.id)

    await store.reloadAllWebTiles()

    for id in webIDs {
        #expect(await store.webReloadTokens[id] == 1)
    }
}

@Test func widgetCatalogCoversExpectedCategories() async throws {
    let categories = Set(WidgetCatalogItem.catalog.map(\.category))

    #expect(categories.contains(.web))
    #expect(categories.contains(.essentials))
    #expect(WidgetCatalogItem.catalog.count >= 12)
}

@Test func webTileConfigRestrictsURLsAndClampsReloadInterval() {
    let safe = WebTileConfig(
        title: "Dashboard",
        urlString: "example.com:8080/status",
        reloadInterval: 1
    )
    #expect(safe.url?.scheme == "https")
    #expect(safe.url?.host == "example.com")
    #expect(safe.reloadInterval == WebTileConfig.minimumReloadInterval)

    let unsafe = WebTileConfig(title: "Local file", urlString: "file:///etc/hosts")
    #expect(unsafe.url == nil)

    var bounded = WebTileConfig(title: "Dashboard", urlString: "https://example.com")
    bounded.reloadInterval = 999_999
    #expect(bounded.reloadInterval == WebTileConfig.maximumReloadInterval)
}

@Test func addingCatalogItemSelectsNewTile() async throws {
    let store = await makeTestStore()
    let before = await store.tiles.count
    let item = try #require(WidgetCatalogItem.catalog.first { $0.id == "github" })

    await store.addCatalogItem(item)

    #expect(await store.tiles.count == before + 1)
    #expect(await store.selectedTile?.displayTitle == "GitHub")
}

@Test func appearanceModeCanBePersisted() async throws {
    let key = "test.dashboardProfile.\(UUID().uuidString)"
    let store = await DashboardStore(defaultsKey: key)

    await store.setAppearanceMode(.light)
    let reloaded = await DashboardStore(defaultsKey: key)

    #expect(await reloaded.appearanceMode == .light)
}

@Test func appearanceModeResolvesOnlyTheDashboardScheme() {
    #expect(EdgeAppearanceMode.dark.resolvedColorScheme(system: .light) == .dark)
    #expect(EdgeAppearanceMode.light.resolvedColorScheme(system: .dark) == .light)
    #expect(EdgeAppearanceMode.system.resolvedColorScheme(system: .dark) == .dark)
    #expect(EdgeAppearanceMode.system.resolvedColorScheme(system: .light) == .light)
}

@Test func forecastTogglePersistsWithProfile() async throws {
    let key = "test.dashboardProfile.\(UUID().uuidString)"
    let store = await DashboardStore(defaultsKey: key)

    await store.toggleFullDayForecast()
    let reloaded = await DashboardStore(defaultsKey: key)

    #expect(await reloaded.showsFullDayForecast)
}

@Test func privacyModePersistsWithProfile() async throws {
    let key = "test.dashboardProfile.\(UUID().uuidString)"
    let store = await DashboardStore(defaultsKey: key)

    await store.setPrivacyMode(true)
    let reloaded = await DashboardStore(defaultsKey: key)

    #expect(await reloaded.privacyMode)
}

@Test func motionBackdropSettingsPersistWithProfile() async throws {
    let key = "test.dashboardProfile.\(UUID().uuidString)"
    let store = await DashboardStore(defaultsKey: key)

    await store.setMotionBackdropMode(.nebula)
    await store.setMotionTileMaterial(.solid)
    await store.setMotionSpeed(1.7)
    await store.setMotionIntensity(1.3)
    await store.setMotionPaused(true)

    let reloaded = await DashboardStore(defaultsKey: key)

    #expect(await reloaded.motionBackdropMode == .nebula)
    #expect(await reloaded.motionTileMaterial == .solid)
    #expect(await reloaded.motionSpeed == 1.7)
    #expect(await reloaded.motionIntensity == 1.3)
    #expect(await reloaded.motionIsPaused)
}

@Test func launcherEditsPersistWithProfile() async throws {
    let key = "test.dashboardProfile.\(UUID().uuidString)"
    let store = await DashboardStore(defaultsKey: key)
    let originalCount = await store.launchers.count

    await store.addLauncher(title: "Messages", appName: "Messages", symbolName: "message")
    #expect(await store.launchers.count == originalCount + 1)
    #expect(await store.launchers.last?.title == "Messages")

    if let last = await store.launchers.last {
        await store.moveLauncher(last, offset: -1)
    }

    let reloaded = await DashboardStore(defaultsKey: key)
    #expect(await reloaded.launchers.count == originalCount + 1)
    #expect(await reloaded.launchers.contains { $0.title == "Messages" && $0.appName == "Messages" && $0.symbolName == "message" })

    if let added = await reloaded.launchers.first(where: { $0.title == "Messages" }) {
        await reloaded.removeLauncher(added)
    }

    let removedReload = await DashboardStore(defaultsKey: key)
    #expect(await removedReload.launchers.count == originalCount)
    #expect(await !removedReload.launchers.contains { $0.title == "Messages" })
}

@Test func customAccentPersistsWithTile() async throws {
    let key = "test.dashboardProfile.\(UUID().uuidString)"
    let store = await DashboardStore(defaultsKey: key)
    let tile = try #require(await store.tiles.first)

    await store.selectWidget(tile)
    if let index = await store.tiles.firstIndex(where: { $0.id == tile.id }) {
        await MainActor.run {
            store.tiles[index].customAccentHex = "7CD7FF"
            store.persist()
        }
    }

    let reloaded = await DashboardStore(defaultsKey: key)
    #expect(await reloaded.tiles.first?.customAccentHex == "7CD7FF")
}

@Test func profilePagesPersistPerPreset() async throws {
    let key = "test.dashboardProfile.\(UUID().uuidString)"
    let store = await DashboardStore(defaultsKey: key)

    await store.applyPreset(.work)
    let firstPageCount = await store.tiles.count
    await store.addPage()
    #expect(await store.currentPages.count == 2)
    #expect(await store.tiles.isEmpty)

    let item = try #require(WidgetCatalogItem.catalog.first { $0.id == "github" })
    await store.addCatalogItem(item)
    #expect(await store.tiles.count == 1)

    await store.applyPreset(.command)
    #expect(await store.selectedPreset == .command)
    await store.applyPreset(.work)

    #expect(await store.currentPageIndex == 1)
    #expect(await store.tiles.first?.displayTitle == "GitHub")

    let reloaded = await DashboardStore(defaultsKey: key)
    await reloaded.applyPreset(.work)

    #expect(await reloaded.currentPages.count == 2)
    #expect(await reloaded.currentPageIndex == 1)
    #expect(await reloaded.tiles.first?.displayTitle == "GitHub")
    #expect(firstPageCount > 0)
}

@Test func deletingWidgetCanBeUndone() async throws {
    let store = await makeTestStore()
    let tile = try #require(await store.tiles.first)
    let originalCount = await store.tiles.count

    await store.removeTile(tile)
    #expect(await store.tiles.count == originalCount - 1)
    #expect(await store.canUndoDeleteWidget)

    await store.undoDeleteWidget()

    #expect(await store.tiles.count == originalCount)
    #expect(await store.tiles.first?.id == tile.id)
    #expect(await !store.canUndoDeleteWidget)
}

@Test func focusNavigationCyclesVisibleWidgets() async throws {
    let store = await makeTestStore()
    let first = try #require(await store.allVisibleTiles.first)
    let second = try #require(await store.allVisibleTiles.dropFirst().first)

    await store.focusNextWidget()
    #expect(await store.focusedTileID == first.id)

    await store.focusNextWidget()
    #expect(await store.focusedTileID == second.id)

    await store.focusPreviousWidget()
    #expect(await store.focusedTileID == first.id)

    await store.clearFocus()
    #expect(await store.focusedTileID == nil)
}

@Test func weatherCodesMapToReadableLabels() {
    #expect(WeatherCodeMapper.title(for: 0) == "Clear")
    #expect(WeatherCodeMapper.title(for: 63) == "Rain")
    #expect(WeatherCodeMapper.symbolName(for: 95) == "cloud.bolt.rain.fill")
}

@Test func deviceBatteryPercentParsingNormalizesCommonShapes() {
    #expect(DeviceBatteryReader.normalizedBatteryPercent(82) == 0.82)
    #expect(DeviceBatteryReader.normalizedBatteryPercent(0.43) == 0.43)
    #expect(DeviceBatteryReader.normalizedBatteryPercent("59%") == 0.59)
    #expect(DeviceBatteryReader.normalizedBatteryPercent("Battery Level: 100") == 1)
    #expect(DeviceBatteryReader.normalizedBatteryPercent("unknown") == nil)
    #expect(DeviceBatteryReader.normalizedBatteryPercent(130) == nil)
}

@Test func bluetoothProfilerParserFindsBatteryFields() {
    let json = """
    {
      "SPBluetoothDataType": [
        {
          "device_connected": [
            {
              "Magic Trackpad": {
                "device_minorType": "Trackpad",
                "device_batteryPercent": "77%"
              }
            },
            {
              "Speaker": {
                "device_minorType": "Speaker"
              }
            }
          ]
        }
      ]
    }
    """

    let devices = DeviceBatteryReader.bluetoothProfilerBatteries(from: json)

    #expect(devices.count == 1)
    #expect(devices.first?.name == "Magic Trackpad")
    #expect(devices.first?.percent == 0.77)
    #expect(devices.first?.source == .bluetoothProfiler)
}

@Test func mobileDeviceBatteryParserBuildsIOSSnapshots() {
    // Synthetic UDID in the real format (chip id + ECID), not a real device's.
    let udid = "00008110-000000000000001E"
    let devices = DeviceBatteryReader.mobileDeviceBatteries(
        ideviceIDOutput: "\(udid)\n",
        deviceInfoByID: [
            udid: """
            DeviceClass: iPad
            DeviceName: Test iPad Mini
            ProductType: iPad14,2
            """
        ],
        batteryInfoByID: [
            udid: """
            BatteryCurrentCapacity: 59
            BatteryIsCharging: true
            HasBattery: true
            """
        ],
        isNetwork: true
    )

    #expect(devices.count == 1)
    #expect(devices.first?.name == "Test iPad Mini")
    #expect(devices.first?.percent == 0.59)
    #expect(devices.first?.isCharging == true)
    #expect(devices.first?.kind == "iPad")
    #expect(devices.first?.source == .mobileDevice)
}

@Test func companionRegistryParserFindsAppleWatchBattery() {
    let json = """
    [
      {
        "DeviceName": "Test Apple Watch",
        "ProductType": "Watch7,2",
        "BatteryCurrentCapacity": 84,
        "BatteryIsCharging": false
      }
    ]
    """

    let devices = DeviceBatteryReader.watchBatteries(fromCompanionRegistryJSON: json)

    #expect(devices.count == 1)
    #expect(devices.first?.name == "Test Apple Watch")
    #expect(devices.first?.percent == 0.84)
    #expect(devices.first?.isCharging == false)
    #expect(devices.first?.source == .watchRelay)
}

@Test func companionRegistryParserFindsNestedAppleWatchBattery() {
    let json = """
    {
      "PairedDevices": {
        "watch-udid": {
          "Name": "Wrist Computer",
          "Class": "Apple Watch",
          "Power": {
            "BatteryCurrentCapacity": "42%",
            "BatteryIsCharging": true
          }
        }
      }
    }
    """

    let devices = DeviceBatteryReader.watchBatteries(fromCompanionRegistryJSON: json)

    #expect(devices.count == 1)
    #expect(devices.first?.name == "Apple Watch")
    #expect(devices.first?.percent == 0.42)
    #expect(devices.first?.isCharging == true)
}

@Test func companionRegistryParserFindsWrappedAppleWatchRegistryValues() {
    let json = """
    [
      {
        "CompanionUDID": "00008310-000000000000002E",
        "BatteryCurrentCapacity": { "BatteryCurrentCapacity": 69 },
        "BatteryIsCharging": { "BatteryIsCharging": false },
        "DeviceName": { "DeviceName": "Test Apple Watch" },
        "ProductType": { "ProductType": "Watch7,12" },
        "DeviceClass": { "DeviceClass": "Watch" }
      }
    ]
    """

    let devices = DeviceBatteryReader.watchBatteries(fromCompanionRegistryJSON: json)

    #expect(devices.count == 1)
    #expect(devices.first?.name == "Test Apple Watch")
    #expect(devices.first?.percent == 0.69)
    #expect(devices.first?.isCharging == false)
    #expect(devices.first?.kind == "Watch7,12")
}

@Test func nowPlayingParserParsesDataLine() throws {
    let line = """
    {"type":"data","diff":false,"payload":{"title":"Put Your Records On","artist":"Corinne Bailey Rae","album":"Corinne Bailey Rae","playing":true,"duration":215.36,"elapsedTime":12.5,"timestamp":"2026-07-14T15:10:16Z","bundleIdentifier":"com.spotify.client"}}
    """

    let event = NowPlayingParser.parse(line: line, previous: nil)
    guard case .update(let snapshot) = event, let snapshot else {
        Issue.record("Expected an update event with a snapshot")
        return
    }

    #expect(snapshot.title == "Put Your Records On")
    #expect(snapshot.artist == "Corinne Bailey Rae")
    #expect(snapshot.isPlaying)
    #expect(snapshot.duration == 215.36)
    #expect(snapshot.elapsedTime == 12.5)
    #expect(snapshot.bundleIdentifier == "com.spotify.client")
    #expect(snapshot.capturedAt != .distantPast)
}

@Test func nowPlayingParserTreatsEmptyPayloadAsNothingPlaying() {
    let event = NowPlayingParser.parse(line: #"{"type":"data","diff":false,"payload":{}}"#, previous: nil)
    #expect(event == .update(nil))
}

@Test func nowPlayingParserIgnoresNonDataLines() {
    #expect(NowPlayingParser.parse(line: "not json at all", previous: nil) == .ignored)
    #expect(NowPlayingParser.parse(line: #"{"type":"other","payload":{"title":"x"}}"#, previous: nil) == .ignored)
}

@Test func nowPlayingParserKeepsArtworkForSameItemWithoutArtworkPayload() throws {
    var previous = NowPlayingSnapshot()
    previous.title = "Song"
    previous.album = "Album"
    previous.artwork = NSImage(size: NSSize(width: 2, height: 2))
    previous.artworkKey = 42

    let line = #"{"type":"data","payload":{"title":"Song","album":"Album","playing":false}}"#
    let event = NowPlayingParser.parse(line: line, previous: previous)
    guard case .update(let snapshot) = event, let snapshot else {
        Issue.record("Expected an update event with a snapshot")
        return
    }

    #expect(snapshot.artworkKey == 42)
    #expect(snapshot.artwork != nil)
}

@Test func nowPlayingParserDoesNotReuseArtworkAcrossDifferentTrackIdentity() throws {
    var previous = NowPlayingSnapshot()
    previous.title = "Song"
    previous.artist = "Original Artist"
    previous.album = "Album"
    previous.bundleIdentifier = "com.example.player"
    previous.artwork = NSImage(size: NSSize(width: 2, height: 2))
    previous.artworkKey = 42

    let line = #"{"type":"data","payload":{"title":"Song","artist":"Different Artist","album":"Album","bundleIdentifier":"com.example.player","playing":false}}"#
    let event = NowPlayingParser.parse(line: line, previous: previous)
    guard case .update(let snapshot) = event, let snapshot else {
        Issue.record("Expected an update event with a snapshot")
        return
    }

    #expect(snapshot.artwork == nil)
    #expect(snapshot.artworkKey == 0)
}

@Test func nowPlayingElapsedExtrapolatesOnlyWhilePlaying() {
    var snapshot = NowPlayingSnapshot()
    snapshot.duration = 100
    snapshot.elapsedTime = 10
    snapshot.capturedAt = Date(timeIntervalSince1970: 1_000)

    snapshot.isPlaying = false
    #expect(snapshot.elapsed(at: Date(timeIntervalSince1970: 1_050)) == 10)

    snapshot.isPlaying = true
    #expect(snapshot.elapsed(at: Date(timeIntervalSince1970: 1_050)) == 60)
    // Clamped to the track length.
    #expect(snapshot.elapsed(at: Date(timeIntervalSince1970: 2_000)) == 100)
}

@Test func launcherSwapsToNowPlayingForMediaApps() async throws {
    let store = await makeTestStore()
    await store.applyPreset(.command)
    let launcherTile = try #require(await store.tiles.first { $0.kind == .launcher })
    let spotify = LauncherItem(title: "Spotify", appName: "Spotify", symbolName: "music.note")

    await store.swapLauncherForNowPlayingIfNeeded(item: spotify, sourceTile: launcherTile)
    #expect(await store.mediaSwapTileID == launcherTile.id)

    await store.restoreLauncherFromMediaSwap()
    #expect(await store.mediaSwapTileID == nil)
}

@Test func launcherDoesNotSwapForNonMediaApps() async throws {
    let store = await makeTestStore()
    await store.applyPreset(.command)
    let launcherTile = try #require(await store.tiles.first { $0.kind == .launcher })
    let safari = LauncherItem(title: "Safari", appName: "Safari", symbolName: "safari")

    await store.swapLauncherForNowPlayingIfNeeded(item: safari, sourceTile: launcherTile)
    #expect(await store.mediaSwapTileID == nil)
}

@Test func launcherDoesNotSwapWhenPageAlreadyShowsNowPlaying() async throws {
    let store = await makeTestStore()
    await store.applyPreset(.media)
    // The Media preset page already has an enabled Now Playing tile, so the
    // launcher (if any tile is passed) must keep its grid.
    let anyTile = try #require(await store.tiles.first)
    var launcherStandIn = anyTile
    launcherStandIn.kind = .launcher
    let music = LauncherItem(title: "Music", appName: "Music", symbolName: "music.note")

    await store.swapLauncherForNowPlayingIfNeeded(item: music, sourceTile: launcherStandIn)
    #expect(await store.mediaSwapTileID == nil)
}

@Test func mediaSwapClearsOnPageAndProfileSwitches() async throws {
    let store = await makeTestStore()
    await store.applyPreset(.command)
    let launcherTile = try #require(await store.tiles.first { $0.kind == .launcher })
    let spotify = LauncherItem(title: "Spotify", appName: "Spotify", symbolName: "music.note")

    await store.swapLauncherForNowPlayingIfNeeded(item: spotify, sourceTile: launcherTile)
    #expect(await store.mediaSwapTileID != nil)

    await store.applyPreset(.work)
    #expect(await store.mediaSwapTileID == nil)
}

@Test func mediaAppNamesMatchLauncherEntries() {
    #expect(DashboardStore.isMediaApp(named: "Music"))
    #expect(DashboardStore.isMediaApp(named: "Spotify.app"))
    #expect(DashboardStore.isMediaApp(named: " TIDAL "))
    #expect(!DashboardStore.isMediaApp(named: "Safari"))
    #expect(!DashboardStore.isMediaApp(named: "Xcode"))
}

@Test func musicLauncherTargetsSpotify() {
    let legacyMusic = LauncherItem(title: "Music", appName: "Music", symbolName: "music.note")
    let spotify = LauncherItem(title: "Music", appName: "Spotify", symbolName: "music.note")

    #expect(DashboardStore.launcherTargetAppName(for: legacyMusic) == "Spotify")
    #expect(DashboardStore.launcherTargetAppName(for: spotify) == "Spotify")
}

@Test func mediaTileSurvivesCodableRoundTrip() throws {
    let tile = WidgetTile(kind: .media, title: "Now Playing", size: .wide, accent: .violet)
    let data = try JSONEncoder().encode(tile)
    let decoded = try JSONDecoder().decode(WidgetTile.self, from: data)

    #expect(decoded.kind == .media)
    #expect(decoded.title == "Now Playing")
}

@Test func mediaPresetIncludesNowPlayingByDefault() async throws {
    let store = await makeTestStore()
    await store.applyPreset(.media)
    let kinds = await Set(store.tiles.map(\.kind))
    #expect(kinds.contains(.media))
}

@Test func topProcessesReadInProcessWithoutSpawning() {
    let processes = SystemStatsReader.readTopProcesses(limit: 5)

    // The test runner itself is a user process with resident memory, so the
    // list can never be empty on a live system.
    #expect(!processes.isEmpty)
    #expect(processes.count <= 5)
    #expect(processes.allSatisfy { $0.memoryBytes > 0 && !$0.name.isEmpty })
    // Sorted heaviest first.
    #expect(processes == processes.sorted { $0.memoryBytes > $1.memoryBytes })
}

@Test func artworkDecodeIsCappedToSaneSize() throws {
    let side = 1400
    let bitmap = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: side,
        pixelsHigh: side,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ))
    let png = try #require(bitmap.representation(using: .png, properties: [:]))

    let decoded = try #require(NowPlayingParser.decodedArtwork(from: png))
    #expect(max(decoded.size.width, decoded.size.height) <= 600)

    // Small art passes through without upscaling side effects.
    let junk = Data([0x00, 0x01, 0x02])
    #expect(NowPlayingParser.decodedArtwork(from: junk) == nil)
}

@Test func harnessUsageParserKeepsAvailableProvidersAndWindows() throws {
    let data = Data(
        """
        [
          {"provider":"codex","usage":{"primary":null,"secondary":{"usedPercent":51,"windowMinutes":10080,"resetsAt":"2026-08-08T03:33:51Z"}}},
          {"provider":"claude","error":"not signed in"},
          {"provider":"kimi","usage":{"primary":{"usedPercent":2,"windowMinutes":10080,"resetDescription":"2/100 requests"},"secondary":{"usedPercent":0,"windowMinutes":300},"extraRateWindows":[{"title":"Monthly","window":{"usedPercent":3.81,"windowMinutes":43200}}]}},
          {"provider":"empty","usage":{"primary":null,"secondary":null,"tertiary":null}}
        ]
        """.utf8
    )
    let retrievedAt = Date(timeIntervalSince1970: 1_000)

    let snapshot = HarnessUsageReader.parse(data, retrievedAt: retrievedAt)

    #expect(snapshot.entries.map(\.id) == ["codex", "claude", "kimi"])
    #expect(snapshot.entries[0].windows[0].usedPercent == 51)
    #expect(snapshot.entries[0].windows[0].resetsAt != nil)
    #expect(snapshot.entries[1].windows.isEmpty)
    #expect(snapshot.entries[1].status == "Unavailable")
    #expect(snapshot.entries[2].windows.count == 3)
    #expect(snapshot.entries[2].windows[0].resetDescription == "2/100 requests")
    #expect(snapshot.entries[2].windows[2].title == "Monthly")
    #expect(snapshot.retrievedAt == retrievedAt)
    #expect(snapshot.status == "Updated")
}
