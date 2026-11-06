# PS2 Card Manager (mymc_web)
[Try the fork](https://warksmith.github.io/mymc_web/)

[![Alt Text](HomePage.png)](https://warksmith.github.io/mymc_web/)
A retro-styled web interface for managing PlayStation 2 memory card images (`.ps2` and `.mcd`). Browse, import, export, convert, and transfer saves directly in your browser. This fork adds raw PS2 MCD support for SD2PSX and similar devices. PS1 MCD cards are a different format and are not supported.

Original project and hosted version: [BAD-AL/mymc_web](https://github.com/BAD-AL/mymc_web), [original website](https://bad-al.github.io/mymc_web/).

mymc was originally ported to [dart_mymc](https://github.com/BAD-AL/dart_mymc) for use in the [NFL2K5Tool_web](https://bad-al.github.io/nfl2k5tool_web/) gamesave editor and I thought it would be cool to add a web interface for easier card management.
You can still obtain the original mymc [python code here](https://github.com/ps2dev/mymc).

## 🎮 For Users

### Features
- **Manage Cards**: Create formatted `.ps2` or `.mcd` cards (1, 2, 4, 8, 16, 32, 64, or 128 MB) or load existing images of either format. 8 MB is recommended for game compatibility.
- **Convert Cards**: Download either format from either slot. Conversion preserves every 512-byte data page, including saves, filesystem metadata, and unallocated space.
- **Export Entire Contents**: Download a ZIP of every live file and folder, including root files, hidden/system directories, nested folders, and empty folders.
- **File Browser**: Cards open in a folder-and-file list with breadcrumbs, filtering, sizes, modified dates, and checkboxes. Download individual files, folders, or selected items. Switch to **Save icons** for the original PS2-style view.
- **Save Management**: Import saves (`.max`, `.psu`) or export them to various formats.
- **Dual Slot Support**: Load two cards at once to quickly copy saves between them.
- **Hosted Library**: Access a curated collection of save packs directly from our server.
- **No Installation**: Runs entirely in your web browser—no software to install.


### How to Use
1. **Load a Card**: Click on an empty **Slot 1** or **Slot 2** and select "Load from Computer" to pick your `.ps2` or `.mcd` file, or drag and drop the file onto either slot.
2. **Browse**: Click a loaded slot to open **Files**. Click folder names to open them; use the path breadcrumbs or **Up** to return. Filter the current folder by name. **Save icons** switches to the original view.
3. **Copy or Export Saves**: Use **Save actions** beside a top-level folder for PSU/MAX export, copying to the other loaded slot, or deleting a save. These actions are also available by clicking a save in **Save icons**.
4. **Importing**: Drag and drop `.zip`, `.max` or `.psu` save files onto a card to add them.
5. **Create a Card**: Click "Create New", choose `.mcd` or `.ps2`, then choose a size. Import any saves you want and use "Export Card" to download it.
6. **Convert or Export**: Click "Export Card" on the main screen. Choose `.ps2` for PCSX2, `.mcd` for SD2PSX, or `.zip` for all files and folders. To convert PS2 → MCD or MCD → PS2, load the source and download the other format.
7. **Download Files**: In **Files**, use **Download** beside a file for its original bytes, or **Download ZIP** beside a folder for that folder and its contents. Check multiple items and use **Download selected as ZIP**. ZIPs retain paths relative to the card root; navigating or changing the filter clears the selection.
8. **Export Everything**: **Export all as ZIP** is always available at the top of the card view. It includes the entire card, regardless of your current folder, filter, or selection.

The format is detected from the image header and size, regardless of its extension. Raw MCD uses 512-byte pages (8 MB = 8,388,608 bytes). PS2 export adds 16 spare bytes per page, with regenerated ECC (8 MB = 8,650,752 bytes). Merely renaming a file does not perform this conversion. Images must already be formatted; malformed or truncated images are rejected.

ZIP is a file-content export, not a full-fidelity card backup: it does not preserve PS2 filesystem attributes, allocation, or deleted data. Keep an image export for that purpose. Save-folder ZIP import supports the usual layout `SAVE_DIRECTORY/filename`; arbitrary nested filesystem archives are intended for extraction on your computer.

### Navigation
- **Keyboard (Files)**: Use Tab/Shift+Tab to move between controls, Enter to open folders or activate buttons, Space to toggle checkboxes, and Alt+Up or Backspace to go up a folder. Escape returns to the card slots. Typing and Backspace work normally in the filter.
- **Keyboard (Save icons and card slots)**: Use Arrow keys to navigate, Enter to select, and Backspace/Esc to go back.
~~-  **Controller**: Support for standard gamepads is included for a true console experience.~~

---

## 🛠 For Developers

This project is built using **Dart** and the **dart_mymc** library. It is designed as a single-page application (SPA) with no external UI frameworks, utilizing raw HTML/CSS and the Canvas API for the 3D background.

### Tech Stack
- **Language**: Dart
- **Library**: [dart_mymc](https://github.com/BAD-AL/dart_mymc) (Git dependency)
- **Frontend**: Vanilla HTML5, CSS3, and `package:web`.
- **Icons/Fonts**: Custom SVG generation and `EmotionEngine` TTF font.

The Dart language was chosen for it's ability to compile to native, wasm, JavaScript and it's modern feel.

### Getting Started
1. **Prerequisites**: Install [Dart SDK 3.11.0](https://dart.dev/get-dart), matching CI and the committed production build.
2. **Setup**:
   ```bash
   dart pub get
   ```
3. **Test and analyze the card support**:
   ```bash
   dart analyze lib test tool web/file_browser.dart
   dart test
   ```
4. **Build (Production)**:
   ```bash
   dart run tool/build.dart
   ```
   This compiles `web/main.dart`, copies the web assets into `docs/`, and preserves the hosted save library in `docs/saves/`. Commit the regenerated `docs/` files together with source changes. CI verifies tests, compilation, and that the committed site is current.
5. **Preview**: Serve `docs/` with a static HTTP server, for example `python -m http.server 8080 --directory docs`, then open `http://localhost:8080`. All card processing and downloads happen locally in the browser.

### GitHub Pages for this fork

This keeps the original project's static `docs/` publishing layout; no server or secrets are needed.

1. Push `mcd-card-support` to `Warksmith/mymc_web`.
2. In the fork's **Settings → Pages**, choose **Deploy from a branch**.
3. Select **mcd-card-support** and **/docs**, then save. After merging, switch the publishing branch to **main**, still using **/docs**.
4. GitHub will publish the site at **https://warksmith.github.io/mymc_web/**. Relative asset and save-library URLs work under the repository subpath.

See [GitHub's branch publishing instructions](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site). The validation workflow does not change Pages settings or create bot commits.

### Conversion implementation

The `dart_mymc` dependency is pinned because `lib/card_image.dart` uses its page ECC and directory APIs for conversion, file browsing, and recursive export. The test suite checks every supported size, byte-preserving round trips, save editing/copying, ECC vectors, file reading/listing, selected and full ZIP contents, and invalid inputs. Hardware compatibility still needs a check on your particular device and games.

#### Special Thanks to
1. Ross Ridge for mymc (python)
2. caol64 for the Icon rendering logic [ps2mc-browser](https://github.com/caol64/ps2mc-browser)
