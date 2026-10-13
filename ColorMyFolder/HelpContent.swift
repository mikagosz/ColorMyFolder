import Foundation

/// What the Help window says: each section is a picture of the app with numbered points and the same
/// numbers in the steps next to it. English source; the Polish text is in Localizable.xcstrings
/// (Tests/main.swift checks that every string has its translation).
enum HelpContent {
    /// Which picture stands next to the section; drawn by the app itself in HelpWindow.swift.
    enum Picture { case finder, pick, save, restore, choose, list }

    struct Section {
        let title: String
        let lead: String
        /// Numbered like the points on the picture: the first step is point 1.
        let steps: [String]
        /// The longer description, folded under "More".
        let more: String?
        let picture: Picture
    }

    struct Card {
        let symbol: String
        let title: String
        let text: String
    }

    static let title = "Getting started with ColorMyFolder"
    static let intro = "Any color for any folder, in the look of a real macOS folder — not just the seven tag colors."

    static let sections: [Section] = [
        Section(title: "Straight from Finder",
                lead: "ColorMyFolder waits in Finder's menu. Pick the folders there, and the window opens with them.",
                steps: ["Right-click a folder, or several.",
                        "Quick Actions → ColorMyFolder. The same item is also under Services.",
                        "The window opens with the folders you picked."],
                more: "The app runs quietly in the background and starts at login, so the paper sheet in a colored folder appears as soon as you put something in it.",
                picture: .finder),
        Section(title: "Pick a color",
                lead: "Click one of your saved colors, or pick any color you like.",
                steps: ["The folder that gets the color — or how many, when you picked several.",
                        "Your saved colors. One click colors the folder and closes the window.",
                        "Other Color opens the system color picker; Color Folder applies it."],
                more: "Besides plain colors there are black, white and a metallic chrome. The icon keeps the macOS folder look: the same gradient and shading as Finder's own folders.",
                picture: .pick),
        Section(title: "Save your colors",
                lead: "Keep the colors you use often, so they are one click away next time.",
                steps: ["Save Color adds the current color to your saved colors.",
                        "Right-click a saved color → Delete Color removes it."],
                more: "The window can be resized; it remembers its size and place, and when you have many saved colors, they scroll.",
                picture: .save),
        Section(title: "Back to the macOS look",
                lead: "Restore System Look gives the folder its normal icon back.",
                steps: ["Restore System Look, next to Choose Other Folders….",
                        "If a folder has a custom icon ColorMyFolder did not set, the app asks before removing it."],
                more: "A custom icon you pasted yourself in Get Info cannot be brought back once it is replaced, so ColorMyFolder always asks first — when coloring, too.",
                picture: .restore),
        Section(title: "Without Finder",
                lead: "Open ColorMyFolder from Applications or Spotlight, and choose the folders in its window.",
                steps: ["No folder chosen yet: the window says so.",
                        "Choose Folders… opens a window to pick them."],
                more: nil,
                picture: .choose),
        Section(title: "Where the list lives",
                lead: "Your saved colors and colored folders are kept in a small list, in a place you choose.",
                steps: ["The gear in the corner of the window.",
                        "List location: where the list is kept; Change… moves it.",
                        "Updates: a check once a month, or Check Now."],
                more: "The list lives in a hidden .ColorMyFolder folder inside the place you choose. Choose a folder you sync between your Macs, and both will have the same colors.",
                picture: .list),
    ]

    /// Finder's own menu, for the picture of the first section — the words macOS shows there.
    static let finderMenu = ["Open", "Get Info", "Rename", "Quick Actions", "Services", "Projects"]

    static let goodToKnow = "Good to know"
    static let cards: [Card] = [
        Card(symbol: "display.2", title: "The same colors on every Mac",
             text: "Keep the list in a folder you sync, such as iCloud Drive. Another Mac using the same place sees the same colors."),
        Card(symbol: "doc.text", title: "A real folder look",
             text: "The icon is built from the same parts Finder uses, with the paper sheet that appears only when the folder has something in it."),
        Card(symbol: "exclamationmark.shield", title: "Your own icons are safe",
             text: "ColorMyFolder never replaces an icon it did not set without asking you first."),
        Card(symbol: "globe", title: "Language",
             text: "ColorMyFolder speaks English and Polish and follows the language of your system."),
    ]

    static let more = "More"
    static let less = "Less"
    /// The line under the Fractal 8 Dev signature — the same as under the title on fractal8.eu.
    static let signatureLine = "Native macOS software, built to a single pattern."

    /// Every string of the window, for the translation check.
    static var allStrings: [String] {
        var all = [title, intro, goodToKnow, more, less, signatureLine] + finderMenu
        for s in sections { all += [s.title, s.lead] + s.steps + (s.more.map { [$0] } ?? []) }
        for c in cards { all += [c.title, c.text] }
        return all
    }
}
