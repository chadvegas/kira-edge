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
