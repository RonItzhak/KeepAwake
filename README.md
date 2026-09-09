# Keep Awake

A macOS menu-bar extra that keeps the Mac awake with the lid closed (same
behavior as the old Desktop `Keep Awake - ON/OFF` scripts). Click the icon
to toggle. No Dock icon.

## Icons

- **Orange coffee cup** in the menu bar: keep-awake is **on**. Lid-close
  sleep is disabled, and AC system/disk sleep is set to never.
- **Moon with zzz**: keep-awake is **off**. Previous AC sleep values are
  restored.

The app icon (Finder, login items, Force Quit) is the coffee cup: caffeine,
stay awake.

## Use

- **Click** the menu-bar icon to toggle.
- **Right-click** (or Control-click) for Open at Login, Open Debug Log, Quit.

The first toggle that needs it asks for **Touch ID**. A successful unlock is
cached for 5 minutes (Apple's maximum reuse window), so repeat taps in that
window do not prompt. Changing `pmset` itself uses a one-time sudoers rule
for `/usr/bin/pmset` only, so you should not see the old admin-password
dialog.

Keep the Mac plugged in and give it airflow when the lid is closed under
load.

## Install

Download `KeepAwake-0.1.pkg` from
[Releases](https://github.com/RonItzhak/KeepAwake/releases) and double-click
it. That installs to `/Applications` and launches the menu-bar extra.

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
