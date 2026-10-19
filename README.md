# SlackHarder

English | [简体中文](README.zh-CN.md)

A native macOS desktop overlay built with Swift and AppKit, with no third-party dependencies. Requires macOS 13 or later; building from source also requires a Swift 6 toolchain.

## Download and install

Download `SlackHarder-<version>-macOS-universal.zip` from [GitHub Releases](https://github.com/hibiki-ovo/SlackHarder/releases/latest). It supports both Apple Silicon and Intel Macs. Extract the archive and drag `SlackHarder.app` into Applications.

The free distribution uses ad hoc signing and is not notarized by Apple. If macOS blocks the app, verify the download source, then go to **System Settings → Privacy & Security → Open Anyway**. Managed devices may restrict this option. Grant SlackHarder access under **Privacy & Security → Accessibility** on first launch. If access stops working after an update, remove the old permission entry and add the app again.

Use the fish icon in the menu bar to control the app. No Dock icon is shown. The interface supports English and Simplified Chinese and follows your macOS language preference, with English as the fallback. You can set an app-specific language under **System Settings → General → Language & Region → Applications**, then restart SlackHarder.

## Run from source

```sh
git clone https://github.com/hibiki-ovo/SlackHarder.git
cd SlackHarder
swift run SlackHarder
```

Switch between “Automatic Mode” and “Manual Mode” from the fish icon in the menu bar. The app starts in “Automatic Mode” and shows the overlay after you select a target window.

## Opacity

Adjust the “Overlay Opacity” slider from 0% to 100%. The setting is saved automatically and shared by both modes. By default, clicks pass through the overlay to the app beneath it.

## Manual mode

- Toggle visibility with “Show Overlay / Hide Overlay”.
- Enable “Edit Overlay (Move / Resize)” to drag the title bar or resize the edges. Click-through resumes when editing ends.
- Position and size are saved automatically. Use “Move Overlay to Current Screen” to recover an off-screen overlay.

## Automatic mode

- Select a target window and click “Attach”. The overlay follows the window as it moves and resizes. Click the attached-window menu item to choose another target.
- The overlay hides when you switch to another window, hide the app, or minimize the window. It reappears when you return to the target window.
- Use either mouse side button (forward or back), or “Mouse Side Button: Hide / Restore”, to hide or restore all windows of the target app.
- Choose “Detach” to stop following the window, or switch to manual mode to restore your manual layout. Select a target again after restarting.

Accessibility permission is required on first use (see installation instructions). Click “Refresh List” if the window list is out of date.

Mouse side buttons may also trigger browser navigation. If your mouse driver maps them to keyboard shortcuts, switch them back to standard side buttons. Some games, custom-drawn windows, and full-screen setups may not be compatible.

## Build and test

```sh
swift build
swift test
```

You can open `Package.swift` in Xcode. Accessibility permissions, mouse input, and window interactions require manual testing on a Mac.

## Package and publish

```sh
bash scripts/package.sh 0.1.0
```

This creates `dist/SlackHarder-0.1.0-macOS-universal.zip` and a SHA-256 checksum file. The archive contains a universal `.app` with an ad hoc signature; no paid developer membership is required.

Pushing a version tag such as `v0.1.0` to GitHub triggers GitHub Actions to test, package, and publish a release. Use a new version number and tag for each subsequent release.

With GitHub CLI installed and authenticated via `gh auth login` using an account with repository write access, you can also run:

```sh
bash scripts/publish.sh 0.1.0
```

The script clones the remote repository into a temporary directory, copies the current source, commits it, and pushes a version tag. It preserves remote history and does not force-push. GitHub Actions must be enabled for the repository.
