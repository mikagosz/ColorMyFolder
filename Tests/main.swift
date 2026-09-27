import Foundation
// Headless check of the pure logic — run with Tests/check.sh
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

print(failures == 0 ? "ALL OK" : "FAILURES: \(failures)")
if failures > 0 { fatalError() }
