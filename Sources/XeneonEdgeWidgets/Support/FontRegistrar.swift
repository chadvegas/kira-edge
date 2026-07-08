import AppKit
import CoreText
import Foundation

enum FontRegistrar {
    static func registerBundledFonts() {
        let candidates = [
            Bundle.module.resourceURL?.appendingPathComponent("Fonts"),
            Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
            Bundle.main.resourceURL?.appendingPathComponent("XeneonEdgeWidgets_XeneonEdgeWidgets.bundle/Contents/Resources/Fonts")
        ]

        for directory in candidates.compactMap(\.self) {
            registerFonts(in: directory)
        }
    }

    private static func registerFonts(in directory: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for file in files where ["ttf", "otf"].contains(file.pathExtension.lowercased()) {
            CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
        }
    }
}
