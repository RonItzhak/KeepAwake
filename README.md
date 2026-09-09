# Keep Awake

A macOS menu-bar extra that keeps the Mac awake with the lid closed (same
behavior as the old Desktop `Keep Awake - ON/OFF` scripts). Click the icon
to toggle. No Dock icon.

## Icons

- **Orange coffee cup** in the menu bar: keep-awake is **on**. Lid-close
  sleep is disabled, and system/disk sleep is set to never on AC and battery.
- **Moon with zzz**: keep-awake is **off**. Previous sleep values are restored.

The app icon (Finder, login items, Force Quit) is the coffee cup: caffeine,
stay awake.

## Use

- **Click** the menu-bar icon to toggle.
- **Right-click** (or Control-click) for Open at Login, Open Debug Log, Quit.
- **Open Keep Awake from Applications** (double-click, even if it is already
  running) to show a control window. Use that when the menu-bar icon is
  hidden behind the extra-items chevron.

The first toggle that needs it asks for **Touch ID**. A successful unlock is
cached for 5 minutes (Apple's maximum reuse window), so repeat taps in that
window do not prompt. The installer (or a one-time admin prompt) installs a
sudoers rule so `/usr/bin/pmset` does not need a password after that.

Keep the Mac plugged in and give it airflow when the lid is closed under
load.

## Install

Download `KeepAwake-0.1.2.pkg` from
[Releases](https://github.com/RonItzhak/KeepAwake/releases) and double-click
it. That installs to `/Applications`, allows admin users to run `pmset`
without a password, and launches the menu-bar extra.

The package is ad-hoc signed. If Gatekeeper blocks it: right-click the pkg,
choose Open, then Open anyway.

## Build

Requires macOS 14+ and a Swift toolchain (Xcode).

```sh
./build.sh          # install to ~/Applications/KeepAwake.app
./build.sh --launch # install and launch
./make-release.sh   # build a pkg under dist/
```

## Debug log

`~/Library/Logs/KeepAwake.log`

Or right-click the menu-bar icon and choose **Open Debug Log**.
