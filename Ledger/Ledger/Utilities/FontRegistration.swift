import CoreText
import Foundation

/// Loads every `.ttf` font file found in the app bundle at launch.
///
/// `UIAppFonts` alone is brittle with Xcode's synchronized folders (wrong paths often cause fonts
/// to silently fall back to the system font), so we explicitly register the bundled fonts with
/// Core Text before any `Font.custom(...)` call.
enum FontRegistration {
    static func registerAll() {
        guard let enumerator = FileManager.default.enumerator(
            at: Bundle.main.bundleURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let url as URL in enumerator {
            // Skip nested bundles and signature/CodeResources directories.
            let path = url.path
            guard path.hasSuffix(".ttf") else { continue }
            if path.contains("/Frameworks/") || path.contains("/PlugIns/") || path.contains("/_CodeSignature/") {
                continue
            }

            var error: Unmanaged<CFError>?
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            // Ignore already-registered or non-font errors.
        }
    }
}
