import Foundation

/// Pure decisions, no AppKit — compiled on its own by `Testy/sprawdz.sh`.
enum Logic {
    /// The file macOS writes inside a folder that carries a custom icon.
    static let iconFileName = "Icon\r"

    /// Finder draws the paper sheet only for folders with *visible* content.
    /// Hidden entries (dot files) and our own icon file do not count.
    static func hasVisibleContent(_ names: [String]) -> Bool {
        names.contains { !$0.hasPrefix(".") && $0 != iconFileName }
    }

    /// Paths are stored relative to the home folder, so one list works on every Mac
    /// regardless of the account name.
    static func storedPath(_ absolute: String, home: String) -> String {
        if absolute == home { return "~" }
        if absolute.hasPrefix(home + "/") { return "~" + absolute.dropFirst(home.count) }
        return absolute
    }

    /// Hidden folder the app creates for its list inside the folder the user chose.
    static let storeFolderName = ".ColorMyFolder"

    /// The user picks a place; the list lives in `.ColorMyFolder` inside it. Picking that
    /// hidden folder itself (e.g. with ⌘⇧. in the open panel) uses it as is.
    static func storeDirectory(forChosen chosen: String) -> String {
        let trimmed = chosen.hasSuffix("/") && chosen.count > 1 ? String(chosen.dropLast()) : chosen
        if (trimmed as NSString).lastPathComponent == storeFolderName { return trimmed }
        return (trimmed as NSString).appendingPathComponent(storeFolderName)
    }

    static func absolutePath(_ stored: String, home: String) -> String {
        if stored == "~" { return home }
        if stored.hasPrefix("~/") { return home + stored.dropFirst(1) }
        return stored
    }

    /// Rewriting the icon costs a write (and a sync on the other Mac), so it happens only when
    /// the user asked for it, the empty/full state changed, or the icon went missing —
    /// Syncthing carries the icon file but not the Finder flag that switches it on.
    static func needsApply(forced: Bool, lastFull: Bool?, full: Bool, hasCustomIcon: Bool) -> Bool {
        forced || lastFull != full || !hasCustomIcon
    }
}
