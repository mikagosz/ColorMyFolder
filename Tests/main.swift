import AppKit
// Headless check of the pure logic and the list file — run with Tests/check.sh
var failures = 0
func check(_ ok: Bool, _ what: String) { print(ok ? "ok   " : "FAIL ", what); if !ok { failures += 1 } }

check(!Logic.hasVisibleContent([]), "empty folder — no paper sheet")
check(!Logic.hasVisibleContent([".DS_Store", "Icon\r"]), "only hidden files and the icon file — no paper sheet")
check(Logic.hasVisibleContent([".DS_Store", "file.txt"]), "a visible file — paper sheet")

let home = "/home/someone"
check(Logic.storedPath("/home/someone/Desktop/A", home: home) == "~/Desktop/A", "path stored relative to ~")
check(Logic.storedPath("/home/someoneX/A", home: home) == "/home/someoneX/A", "a similar prefix is not the home folder")
check(Logic.storedPath("/Volumes/X", home: home) == "/Volumes/X", "outside home stays absolute")
check(Logic.absolutePath("~/Desktop/A", home: "/home/other") == "/home/other/Desktop/A", "~ expands on the other Mac")
check(Logic.absolutePath("~", home: home) == home, "bare ~")

check(Logic.storeDirectory(forChosen: "/home/someone/Sync") == "/home/someone/Sync/.ColorMyFolder", "list goes into a hidden folder in the chosen place")
check(Logic.storeDirectory(forChosen: "/home/someone/Sync/") == "/home/someone/Sync/.ColorMyFolder", "trailing slash")
check(Logic.storeDirectory(forChosen: "/home/someone/Sync/.ColorMyFolder") == "/home/someone/Sync/.ColorMyFolder", "choosing the hidden folder itself")

check(!Logic.needsApply(forced: false, lastFull: true, full: true, hasCustomIcon: true), "nothing changed — no redraw")
check(Logic.needsApply(forced: false, lastFull: false, full: true, hasCustomIcon: true), "folder filled up — redraw")
check(Logic.needsApply(forced: false, lastFull: true, full: true, hasCustomIcon: false), "icon flag missing (after a sync) — redraw")
check(Logic.needsApply(forced: true, lastFull: true, full: true, hasCustomIcon: true), "user's choice — redraw")

let login = Date(timeIntervalSince1970: 1_000_000)
check(Logic.startedWithLogin(launch: login.addingTimeInterval(38), login: login), "started 38 s after login — at login, no window")
check(!Logic.startedWithLogin(launch: login.addingTimeInterval(600), login: login), "started 10 min after login — by the user, window")
check(!Logic.startedWithLogin(launch: login.addingTimeInterval(-5), login: login), "started before this login — not at login")
check(!Logic.startedWithLogin(launch: login, login: nil), "login time unknown — not at login")

// Painting one pixel of a system-blue part
let top = Logic.Shade(h: 0.55, s: 0.62, b: 1.0), bottom = Logic.Shade(h: 0.55, s: 0.62, b: 0.75)
let black = Logic.Shade(h: 0, s: 0, b: 0.12), white = Logic.Shade(h: 0, s: 0, b: 0.97)
let red = Logic.Shade(h: 0.0, s: 0.8, b: 0.9)
check(Logic.paint(source: top, target: black, finish: nil, y: 0.3).b < 0.3, "black stays dark")
check(Logic.paint(source: bottom, target: white, finish: nil, y: 0.8).b > 0.7, "white stays light")
check(Logic.paint(source: bottom, target: white, finish: nil, y: 0.8).b < Logic.paint(source: top, target: white, finish: nil, y: 0.3).b, "white keeps the shading")
check(Logic.paint(source: top, target: black, finish: nil, y: 0.3).s == 0, "black has no tint")
check(Logic.paint(source: top, target: red, finish: nil, y: 0.3).h == 0.0, "a color takes the target hue")
let c1 = Logic.paint(source: top, target: white, finish: Logic.chrome, y: 0.15), c2 = Logic.paint(source: top, target: white, finish: Logic.chrome, y: 0.45)
check(abs(c1.b - c2.b) > 0.1 && c1.s < 0.1, "chrome is silver with reflection bands")

// existingLists on a real temporary folder tree
let fm = FileManager.default
let tmp = (NSTemporaryDirectory() as NSString).appendingPathComponent("cmf-check-\(ProcessInfo.processInfo.processIdentifier)")
let older = tmp + "/Desktop/Sync/.ColorMyFolder", newer = tmp + "/Docs/.ColorMyFolder", deep = tmp + "/Desktop/a/b/.ColorMyFolder"
for d in [older, newer, deep] { try! fm.createDirectory(atPath: d, withIntermediateDirectories: true) }
for d in [older, newer, deep] { fm.createFile(atPath: d + "/ColorMyFolder.json", contents: Data("{}".utf8)) }
try! fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: older + "/ColorMyFolder.json")
try! fm.createDirectory(atPath: tmp + "/Empty/.ColorMyFolder", withIntermediateDirectories: true)
let lists = Logic.existingLists(in: [tmp + "/Desktop", tmp + "/Docs", tmp + "/Missing"])
check(lists == [newer, older], "finds lists one level down, newest first")
check(!lists.contains(deep), "does not dig deeper than one level")
check(Logic.existingLists(in: [tmp + "/Empty"]).isEmpty, "a folder without the list file is not a list")
try? fm.removeItem(atPath: tmp)
check(Logic.setAsideName(date: Date(timeIntervalSince1970: 0)).hasPrefix("ColorMyFolder (before 19"), "old list gets a dated name")


// Color model by hand must match NSColor's
for (r, g, b) in [(0.9, 0.2, 0.3), (0.1, 0.6, 0.95), (0.5, 0.5, 0.5), (0.0, 0.0, 0.0), (0.3, 0.9, 0.1), (0.8, 0.1, 0.9)] {
    let mine = Logic.hsb(r: r, g: g, b: b)
    var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
    NSColor(deviceRed: r, green: g, blue: b, alpha: 1).getHue(&h, saturation: &s, brightness: &v, alpha: &a)
    let back = Logic.rgb(mine)
    check(abs(mine.h - Double(h)) < 1e-6 && abs(mine.s - Double(s)) < 1e-6 && abs(mine.b - Double(v)) < 1e-6
          && abs(back.r - r) < 1e-9 && abs(back.g - g) < 1e-9 && abs(back.b - b) < 1e-9,
          "hsb/rgb by hand = NSColor for (\(r), \(g), \(b))")
}

// Which FSEvents matter
let coloredSet: Set<String> = ["/h/Desktop/A"]
check(Logic.isRelevant(changedFolder: "/h/Desktop/A/", coloredFolders: coloredSet, listDirectory: "/h/Sync/.ColorMyFolder"), "a change inside a colored folder counts")
check(!Logic.isRelevant(changedFolder: "/h/Desktop/A/deep/er", coloredFolders: coloredSet, listDirectory: "/h/Sync/.ColorMyFolder"), "a change deeper inside does not")
check(Logic.isRelevant(changedFolder: "/h/Sync/.ColorMyFolder/", coloredFolders: coloredSet, listDirectory: "/h/Sync/.ColorMyFolder"), "a change in the list folder counts")
check(!Logic.isRelevant(changedFolder: "/h/Sync/.ColorMyFolderX", coloredFolders: coloredSet, listDirectory: "/h/Sync/.ColorMyFolder"), "a similar name is not the list folder")

// The list file
let storeTmp = (NSTemporaryDirectory() as NSString).appendingPathComponent("cmf-store-\(ProcessInfo.processInfo.processIdentifier)")
let listDir = URL(fileURLWithPath: storeTmp + "/.ColorMyFolder")
try! fm.createDirectory(at: listDir, withIntermediateDirectories: true)
let suite = "cmf-check-\(ProcessInfo.processInfo.processIdentifier)"
let defaults = UserDefaults(suiteName: suite)!
let store = Store(defaults: defaults, home: "/h")
store.directory = listDir
let listFile = listDir.appendingPathComponent(Store.fileName)
func fileText() -> String { (try? String(contentsOf: listFile, encoding: .utf8)) ?? "" }
func write(_ json: String) { try! json.write(to: listFile, atomically: true, encoding: .utf8) }

store.reload()
check(store.readable && store.data.palette.isEmpty, "no list file yet — an empty, writable list")
store.addToPalette(RGB(r: 1, g: 0, b: 0))
check(fileText().contains("\"r\" : 1"), "the first color is written")

write(#"{"palette":[{"r":1,"g":0,"b":0},{"r":0,"g":0,"b":1}],"folders":[]}"#)   // the other Mac added blue
store.addToPalette(RGB(r: 0, g: 1, b: 0))                                        // this Mac adds green, list in memory is old
store.reload()
check(store.data.palette.count == 3, "a change made on the other Mac a moment ago is kept")

write(#"{"format":2,"palette":[{"r":0.5,"g":0.5,"b":0.5,"finish":"chrome","gloss":0.7}],"folders":[{"path":"~/A","color":{"r":1,"g":1,"b":1},"note":"x"}]}"#)
store.addToPalette(RGB(r: 0, g: 0, b: 0))
let kept = fileText()
check(kept.contains("\"format\" : 2") && kept.contains("\"gloss\" : 0.7") && kept.contains("\"note\" : \"x\"") && kept.contains("chrome"),
      "fields from a newer version survive a save")
store.reload()
check(store.data.palette.first == RGB(r: 0.5, g: 0.5, b: 0.5, finish: "chrome"), "a color is the same color whatever else is stored with it")

write("{ not json")
let broken = fileText()
store.addToPalette(RGB(r: 0.2, g: 0.2, b: 0.2))
check(!store.readable && fileText() == broken, "an unreadable list is not overwritten")

try! fm.removeItem(at: listFile)
fm.createFile(atPath: listDir.appendingPathComponent(".\(Store.fileName).icloud").path, contents: Data())
store.addToPalette(RGB(r: 0.2, g: 0.2, b: 0.2))
check(!store.readable && !fm.fileExists(atPath: listFile.path), "a list still in iCloud is not replaced with a new one")

store.directory = URL(fileURLWithPath: storeTmp + "/Unmounted/.ColorMyFolder")
store.addToPalette(RGB(r: 0.2, g: 0.2, b: 0.2))
check(!store.readable, "a missing list folder (disk not mounted) is not an empty list")

try? fm.removeItem(atPath: storeTmp)
defaults.removePersistentDomain(forName: suite)

print(failures == 0 ? "ALL OK" : "FAILURES: \(failures)")
if failures > 0 { fatalError() }
