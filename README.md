# Score Tools Overlay

A lightweight local iOS overlay for educational testing of saved score values inside an authorized debug build.

This project builds a native iOS dynamic library, `DebugOverlay.dylib`, that adds a floating **MENU** button inside the app. The menu opens a clean **Score Tools** panel where you can check, update, reset, and undo local saved score values.

---

## Disclaimer

This project is provided for **educational, research, and local debugging purposes only**.

It is intended for:

* Learning how iOS dynamic libraries work
* Understanding local app save files
* Testing authorized debug builds
* Experimenting with local SQLite save data
* Building internal developer tools

This project is **not intended for**:

* Cheating in online games
* Modifying multiplayer systems
* Submitting fake leaderboard scores
* Bypassing in-app purchases
* Disabling advertisements
* Unlocking paid content
* Modifying apps you do not own or have permission to test

Only use this with apps, IPAs, and devices that you own, created yourself, or are explicitly authorized to modify.

---

## Features

* Floating in-app `MENU` button
* Sleek modern **Score Tools** panel
* Custom score input
* Quick score presets:

  * `1K`
  * `5K`
  * `10K`
* Current saved score display
* `SAVE + RELOAD` action
* `CHECK` score action
* `RESET SCORE` shortcut
* `UNDO` last change
* Pass-through touch handling so the app remains clickable
* Automatic backup before score changes
* Local-only SQLite editing

## How It Works

The overlay reads and updates a local SQLite save database inside the app container.

Expected database path:

```text
Documents/jsb.sqlite
```

Expected table:

```text
data
```

Expected row key:

```text
fangkuaipintu
```

The row contains JSON save data. The overlay updates these local fields:

```json
{
  "high_cord": 9999,
  "current_cord": 9999
}
```

When you tap **SAVE + RELOAD**, the overlay:

1. Locates the local app `Documents` folder.
2. Finds `jsb.sqlite`.
3. Copies the database to a temporary patch file.
4. Opens the copied database with SQLite.
5. Reads the `fangkuaipintu` save profile.
6. Parses the saved JSON data.
7. Updates `high_cord` and `current_cord`.
8. Verifies the new value.
9. Creates a backup of the original database.
10. Removes old SQLite sidecar files:

    * `jsb.sqlite-wal`
    * `jsb.sqlite-shm`
11. Replaces the original database with the patched database.
12. Closes the app so the updated save can be loaded on next launch.

---

## Why Reload Is Needed

Many apps load saved data into memory when they start.

That means editing the local database while the app is already running may not instantly update the on-screen value. The saved data is changed, but the app may continue using the old value from memory.

The **SAVE + RELOAD** button solves this by saving the score and then closing the app. When you reopen the app, it reloads the updated save file.

---

## Project Structure

```text
DebugOverlay/
├── Makefile
└── Tweak.xm
```

### `Makefile`

Defines how Theos builds the overlay as a normal dynamic library.

### `Tweak.xm`

Contains the overlay code:

* Floating menu button
* Score Tools panel UI
* Touch pass-through logic
* SQLite read/write logic
* Score presets
* Save, check, reset, and undo actions

---

## Requirements

* macOS
* Xcode Command Line Tools
* Theos
* `ldid`
* Sideloadly or another signing/injection workflow
* A clean IPA you own or are authorized to modify
* iPhone or iPad for testing

---

## Installation Options

There are several ways to use this project.

---

## Option 1: Use the Included IPA

Use this option if the repository includes a prebuilt debug IPA.

### Steps

1. Download the included IPA from the repo.
2. Open Sideloadly.
3. Drag the IPA into Sideloadly.
4. Connect your iPhone or iPad.
5. Sign in with your Apple ID if prompted.
6. Click **Start**.
7. Wait for the install to finish.
8. Open the app on your device.
9. Wait a few seconds for the floating `MENU` button to appear.

Tap `MENU` to open **Score Tools**.

---

## Option 2: Build the Overlay Yourself

Use this option if you want to compile `DebugOverlay.dylib` from source.

### Build

```bash
cd ~/Desktop/PuzzleDebugBuild/DebugOverlay
make clean
make
```

After a successful build, the dylib will be created here:

```text
.theos/obj/debug/DebugOverlay.dylib
```

Copy it somewhere easy to select:

```bash
cp .theos/obj/debug/DebugOverlay.dylib ~/Desktop/DebugOverlay.dylib
```

You can now inject `DebugOverlay.dylib` into an authorized IPA.

---

## Option 3: Inject the Library with Sideloadly

This is the easiest way to inject the dylib.

### Files Needed

```text
Clean IPA: PuzzleGame_original.ipa
Dylib: DebugOverlay.dylib
```

### Recommended Sideloadly Settings

```text
Inject dylibs/frameworks: ON
Cydia Substrate: OFF
Substitute: OFF
Sideload Spoofer: OFF
Use automatic Bundle ID: OFF
Remove limitation on supported devices: ON
```

### Steps

1. Open Sideloadly.
2. Select your clean IPA.
3. Enable **Inject dylibs/frameworks**.
4. Add `DebugOverlay.dylib`.
5. Make sure **Cydia Substrate** is off.
6. Make sure **Substitute** is off.
7. Click **Start**.
8. Install the app to your device.

When the app opens, the overlay should appear after a short delay.

---

## Option 4: Manual Injection

Use this method if you want to inject the dylib yourself without relying on Sideloadly’s injection feature.

### 1. Create a Work Folder

```bash
cd ~/Desktop/PuzzleDebugBuild
rm -rf work
mkdir work
cd work
unzip ../PuzzleGame_original.ipa
```

### 2. Find the App Folder

Your extracted IPA should contain a `Payload` folder.

Example:

```text
Payload/fangkuaipintu-mobile.app
```

Set the app folder and executable name:

```bash
APP_DIR="Payload/fangkuaipintu-mobile.app"
APP_EXE="fangkuaipintu-mobile"
```

### 3. Copy the Dylib Into the App

```bash
mkdir -p "$APP_DIR/Frameworks"
cp ../DebugOverlay/.theos/obj/debug/DebugOverlay.dylib "$APP_DIR/Frameworks/DebugOverlay.dylib"
```

### 4. Inject the Dylib Load Command

```bash
insert_dylib --strip-codesig \
"@executable_path/Frameworks/DebugOverlay.dylib" \
"$APP_DIR/$APP_EXE" \
"$APP_DIR/${APP_EXE}_patched"
```

Replace the original executable:

```bash
mv "$APP_DIR/${APP_EXE}_patched" "$APP_DIR/$APP_EXE"
chmod +x "$APP_DIR/$APP_EXE"
```

### 5. Verify the Dylib Was Added

```bash
otool -L "$APP_DIR/$APP_EXE" | grep DebugOverlay
```

You should see:

```text
@executable_path/Frameworks/DebugOverlay.dylib
```

### 6. Repack the IPA

```bash
zip -qry ../PuzzleGame_Debug.ipa Payload
```

The repacked IPA will be created here:

```text
~/Desktop/PuzzleDebugBuild/PuzzleGame_Debug.ipa
```

You can now sign and install this IPA with your preferred signing tool.

---

## Which Method Should You Use?

Use the included IPA if you just want to test quickly.

Use the build method if you want to modify the menu, change the UI, or add more local debug tools.

Use Sideloadly injection if you want the simplest way to combine your clean IPA with the dylib.

Use manual injection if you want full control over how the dylib is added to the app binary.

---

## Usage

1. Launch the app.
2. Wait for the floating `MENU` button.
3. Tap `MENU`.
4. Choose a preset or type a custom score.
5. Tap **SAVE + RELOAD**.
6. The app closes.
7. Reopen the app.
8. The new saved score should load.

---

## Button Guide

| Button          | What It Does                          |
| --------------- | ------------------------------------- |
| `1K`            | Sets the input field to `1000`        |
| `5K`            | Sets the input field to `5000`        |
| `10K`           | Sets the input field to `10000`       |
| `SAVE + RELOAD` | Saves the score and closes the app    |
| `CHECK`         | Reads the current saved score         |
| `RESET SCORE`   | Sets the input field to `0`           |
| `UNDO`          | Restores the most recent backup       |
| `MENU`          | Opens or closes the Score Tools panel |

---

## Backup and Undo

Before every saved score change, the overlay creates a backup of the original database:

```text
jsb.sqlite.backup_<timestamp>
```

The **UNDO** button restores the most recent backup.

This helps you safely recover the last score before a test change.

---

## Touch Handling

The overlay uses a custom pass-through window.

Only these areas capture touch input:

* Floating `MENU` button
* Open **Score Tools** panel

Everything else passes through to the app underneath. This keeps the original app usable while the overlay is active.

---

## Troubleshooting

### The app opens but I cannot tap the game

Make sure the overlay uses the pass-through window code. Touches outside the menu should return `nil` so the app underneath receives them.

### The score saves but does not update immediately

This is expected. The app may cache the score in memory. Tap **SAVE + RELOAD**, then reopen the app.

### The score file is not found

Open the app normally first and make sure it creates a save file. Then reopen the overlay and tap **CHECK**.

### The overlay does not appear

Try waiting a few seconds after app launch. The overlay is created after a short delay to let the app finish loading.

### The app crashes on launch

Check the following:

* Use the original clean IPA.
* Do not double-inject the dylib.
* Keep **Cydia Substrate** off.
* Keep **Substitute** off.
* Rebuild the dylib with `make clean && make`.
* Confirm the dylib was added to the app binary.

### Build fails

Run:

```bash
cd ~/Desktop/PuzzleDebugBuild/DebugOverlay
make clean
make
```

If it still fails, confirm Theos and Xcode Command Line Tools are installed correctly.

---

## Safety Notes

This project modifies local saved data only. It should not be used to interfere with online features, paid content, advertising systems, multiplayer systems, or public leaderboards.

Use it responsibly and only in environments where you have permission.

---

## License

This project is provided for educational use. Add your preferred license here if you plan to publish it.

Example:

```text
MIT License
```
