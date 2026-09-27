## ColorMyFolder

**Any color for any folder — in the macOS folder look.**

A small macOS app that colors individual folders in Finder with any color you pick,
not just the seven tag colors.

[![Xcode 27+](https://img.shields.io/badge/Xcode-27%2B-147EFB?logo=xcode&logoColor=white)](https://developer.apple.com/xcode/)
[![macOS 26+](https://img.shields.io/badge/macOS-26%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

<a href="https://github.com/sponsors/mikagosz"><img src="https://img.shields.io/badge/Sponsor-GitHub%20Sponsors-EA4AAA?logo=githubsponsors&logoColor=white" width="350" alt="Sponsor on GitHub Sponsors"></a>

macOS lets you tint folders in only two ways: one of seven tag colors per folder, or one
system-wide folder color in *System Settings → Appearance* that changes every folder at once.
ColorMyFolder gives a single folder its own color, and keeps it looking like a real macOS
folder: the same gradient and shading, and the paper sheet that appears only when the folder
has something in it.

> The interface is in English and Polish and follows the language of your system.

---

## How to use it

1. In Finder, right-click a folder (or several) → **Quick Actions → ColorMyFolder**.
   The same item is also under **Services**.
2. Click one of your saved color dots, or pick any color with **Other Color** and click
   **Color Folder**.
3. **Save Dot** keeps the current color in the palette; right-click a dot → **Delete Dot**
   removes it. **Restore System Look** gives the folder back its normal icon.

The window stays open until you close it or pick a color, so a stray click on the desktop
does not dismiss it.

## How it works

- The icon is built from the same parts Finder uses for its own folders — the back flap, the
  front flap and the paper sheet from macOS itself — with the flaps recolored so the
  system gradient and shading stay intact. Nothing is drawn from scratch.
- The finished icon is set as the folder's custom icon.
- ColorMyFolder runs in the background (no Dock icon) and starts at login. It watches the
  colored folders and redraws an icon only when a folder goes from empty to non-empty or
  back, so the paper sheet behaves like Finder's own.

## Your colors on more than one Mac

On first launch ColorMyFolder asks where to keep its list of saved colors and colored
folders (one JSON file). Choose a folder you sync between your Macs — iCloud Drive, Syncthing
or anything else — and every Mac gets the same dots and the same colored folders. Paths are
stored relative to your home folder, so different account names are fine. If a sync tool
carries the folder's icon file but not the Finder flag that turns it on, ColorMyFolder on the
other Mac simply redraws the icon.

Opening the app again (from Finder or Spotlight) lets you move the list somewhere else.

## Requirements

- macOS 26 or later
- Xcode 27 to build

## Installing

There is no prebuilt download yet — you build the app from source:

```bash
git clone https://github.com/mikagosz/ColorMyFolder.git
cd ColorMyFolder
./build.sh
```

The script runs the logic check, builds the app, installs it to `~/Applications`, adds the
quick action and starts ColorMyFolder. It signs the app ad hoc, which is all you need for an
app you built yourself. To install into a different folder, put its path on the first line of
a file named `.install-dir` in the project folder.

The logic check can also be run on its own, without Xcode: `./Tests/check.sh`.

## First launch

- ColorMyFolder asks where to keep its list of colors and colored folders. Pick any folder;
  choose a synced one if you use more than one Mac (see above).
- macOS shows a notification that a login item was added — ColorMyFolder has to run in the
  background to switch the paper sheet when folders fill up or empty. You can turn it off in
  *System Settings → General → Login Items*.
- If the ColorMyFolder item in Finder shows a generic document icon instead of the palette,
  relaunch Finder: hold Option, right-click Finder in the Dock and choose **Relaunch**.

## Uninstalling

1. Give your folders their normal look back with **Restore System Look** (the custom icon stays
   on a folder otherwise).
2. Quit ColorMyFolder in Activity Monitor and remove it from *System Settings → General → Login Items*.
3. Delete `ColorMyFolder.app` and `~/Library/Services/ColorMyFolder.workflow`, and the list file
   `ColorMyFolder.json` from the folder you chose on first launch.

## Privacy

ColorMyFolder never connects to the network. It reads and writes only the folders you color,
its own list file in the folder you chose, and its quick action in `~/Library/Services`.

## Licence

The source code is released under the [MIT licence](LICENSE).

The application artwork is not covered by it — see [NOTICE](NOTICE). The folder parts and the
`paintpalette` symbol are Apple's; they are read from macOS at run time and are not part of
this repository.
