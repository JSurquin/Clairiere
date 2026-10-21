# Clairière

[![Open source, fully free](https://img.shields.io/badge/open%20source-fully%20free-2F7D46?style=for-the-badge)](LICENSE)
[![MIT license](https://img.shields.io/badge/license-MIT-brightgreen?style=for-the-badge)](LICENSE)
[![macOS 14 or later](https://img.shields.io/badge/macOS-14%2B-111210?style=for-the-badge)](https://github.com/JSurquin/Clairiere/releases)

[Français](README.md) · English

Clairière answers two questions: what is using your Mac's memory, and what is filling its disk. These are two different problems. Quitting an app frees memory, but it does not free disk space. To get disk space back, you have to remove files.

The app shows both, then lets you choose what goes. Nothing is removed until you have checked it and confirmed. Files go to the Trash, so you can still get them back.

It runs on Apple silicon Macs with macOS 14 or later. The code is under the [MIT license](LICENSE).

[Download the latest version](https://github.com/JSurquin/Clairiere/releases)

## Screenshots

The home screen summarizes the numbers without starting any heavy scan.

<img src="docs/screenshots/accueil.png" alt="Clairière home screen" width="860">

Each app has its own row. Quit asks it to close. Force quit closes it right away, including its icon in the menu bar.

<img src="docs/screenshots/memoire.png" alt="Memory tab" width="860">

In Cleanup, a row such as Caches can weigh several gigabytes. Click the arrow to see the folders inside it, from largest to smallest.

<img src="docs/screenshots/nettoyage.png" alt="Cleanup tab" width="860">

Storage shows the free space on the disk, and the iCloud files that still have a copy on the Mac.

<img src="docs/screenshots/stockage.png" alt="Storage tab" width="860">

## Tabs

| Tab | What it does |
| --- | --- |
| Home | A summary. It never starts a heavy scan by itself. |
| Memory | Running apps, and what each one uses. |
| Cleanup | Caches, logs, and the Mac's Trash. |
| Storage | Free disk space, and iCloud files you can remove from this Mac. |
| Apps | The size of each app, the files it leaves behind, and updates. |
| Startup | What opens with the Mac. You can turn items off and back on. |
| AI | Old files, sorted with a small model installed on the Mac. |

## Nothing leaves without your agreement

Every deletion goes through a list and then a confirmation. Most files go to the Trash. Emptying the Mac's Trash and deleting a Time Machine snapshot are permanent, and the app says so before doing either.

Removing an iCloud file only removes its copy on this Mac. The file stays in iCloud and comes back when you open it.

Finder, the Dock and macOS components are marked "leave open". Clairière does not touch them.

Clairière is not an antivirus, and it does not repair permissions.

## The AI tab

The AI tab looks at files that have not been opened for three months. It reads the name, the folder, the size and the date, without opening the content.

When you start the analysis, Clairière installs [Ollama](https://ollama.com) if it is missing, loads a small model, then unloads it from memory. If Ollama was already running, Clairière leaves it alone. If Clairière started it, Clairière quits it afterwards.

## Install

1. Download `Clairiere-macOS.zip` from [Releases](https://github.com/JSurquin/Clairiere/releases).
2. Open the archive, then drag Clairière into the Applications folder.
3. On first launch, right-click the app and choose Open.

This build is not notarized by Apple, so macOS asks you to confirm once.

## Build from source

You need macOS 14 and Swift 6. Xcode is not required.

```bash
git clone https://github.com/JSurquin/Clairiere.git
cd Clairiere
./build.sh
open dist/Clairiere.app
```

The script builds the app and puts it in `dist/`.

## Publish a release

In the [Actions](https://github.com/JSurquin/Clairiere/actions) tab, run the **Release** workflow with a version number such as `1.2.3`. It builds the app and creates the GitHub release.

You can also push a tag yourself:

```bash
git tag v1.2.3
git push origin v1.2.3
```

## Keyboard

| Shortcut | Action |
| --- | --- |
| ⌘1 to ⌘7 | Home, Memory, Cleanup, Storage, Apps, Startup, AI |
| ⌘F | Search |
| ↑ ↓ | Previous or next row |
| Return | Open details |
| Space | Check or uncheck |
| ⌘A / ⌘⇧A | Check all, uncheck all |
| ⌘Return | Row action |
| ⌘⇧Return | Force quit |
| ⌘O | Show in Finder |
| ⌘L | Free up memory |
| Escape | Close the dialog, the details, then the search |

## License

The code is under the [MIT license](LICENSE). You may use, modify and redistribute it, including in a paid project.
