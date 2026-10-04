# CursorWasher

[English](README.en.md) · [Русский](README.md)

## Why

Touched something unpleasant with your cursor and now want to give it a good scrub with soap? One click, and your cursor is as good as new. With a clean cursor, you can touch your own files and pet your designs again.

[Grab the macOS installer](https://github.com/Oladii/CursorWasher/releases/latest/download/CursorWasher-Installer.dmg) · [Download for Windows](https://github.com/Oladii/CursorWasher/releases/latest/download/CursorWasher.zip)

Separate source downloads: [macOS](https://github.com/Oladii/CursorWasher/releases/latest/download/CursorWasher-macOS-Sources.zip) · [Windows](https://github.com/Oladii/CursorWasher/releases/latest/download/CursorWasher-Windows-Sources.zip)

![Little bucket for washing your cursor](media/cursor-washer.gif)

## How to launch on macOS

![macOS warning when opening CursorWasher](https://cdsassets.apple.com/live/7WUAS350/images/macos/sequoia/locale/ru-ru/macos-sequoia-app-not-opened-could-not-verify-free-from-malware.png)

I'm just a country boy, so the bucket doesn't have a Developer ID signature yet, which means macOS will block the downloaded app. [Apple's instructions for allowing it to open](https://support.apple.com/en-ie/102445).

## What it can do

- Wash your cursor.
- Lift your spirits.
- Keep the bucket on top of all windows or leave it on the desktop.

## What it cannot do

- Buy beer.
- Do anything useful.

## Installation

The installer in the exported project is `App/CursorWasher-Installer.dmg`. Download the installer from the [releases page](https://github.com/Oladii/CursorWasher/releases).

1. Open the DMG.
2. Drag `CursorWasher` to the `Applications` folder in the window that opens.
3. Launch the app from Applications.
4. Set it to launch at login if you need the bucket often.

Requires macOS 13 or later. Running on Intel has not been tested.

## Building

If you'd like to build the bucket yourself (why?), download the source code.

You'll need Apple's developer tools with Swift and the macOS SDK.

```sh
bash scripts/package.sh
```

This builds the app and an installer DMG in `Build/`.

To build only the app:

```sh
bash scripts/build.sh
```
