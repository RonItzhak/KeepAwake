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

Download `KeepAwake-0.1.3.pkg` from
[Releases](https://github.com/RonItzhak/KeepAwake/releases) and double-click
it. That installs to `/Applications`, allows admin users to run `pmset`
without a password, and launches the menu-bar extra.

The package is ad-hoc signed. If Gatekeeper blocks it: right-click the pkg,
choose Open, then Open anyway.

## Updates

Install the latest `.pkg` over the existing copy. The installer quits a
running Keep Awake, replaces `/Applications/KeepAwake.app`, and launches
the new build. Keep-awake on/off is left as it was.

Use **Check for Updates…** in the menu or control window to compare with
GitHub Releases.

## Requirements

To **run** the app: macOS 14 or later on Apple Silicon, plus Touch ID or
Apple Watch to toggle (cached for 5 minutes after a success). An admin
account is needed once, so the installer can add a passwordless `pmset`
sudoers rule.

To **build** it: the same Mac, plus Xcode or the Command Line Tools
(`swiftc`, `make`, `codesign`, `pkgbuild`). There is no Xcode project and
no Swift packages; `./build.sh` compiles the sources directly. The
compiler target is `arm64-apple-macos14`, so Intel Macs are out.

## Build

```sh
make            # install to ~/Applications/KeepAwake.app
make launch     # install and launch
make pkg        # build a pkg under dist/
make clean
```

The same steps as `./build.sh`, `./build.sh --launch`, and `./make-release.sh`.

## Debug log

`~/Library/Logs/KeepAwake.log`

Or right-click the menu-bar icon and choose **Open Debug Log**.

## License

[MIT](LICENSE)
