# AKV VPN Client

AKV VPN Client is the official cross-platform application for the
[AKV VPN platform](https://github.com/Lujker/akv-vpn). It is a branded,
privacy-focused GPLv3 fork of
[Hiddify App](https://github.com/hiddify/hiddify-app), built with Flutter and
the Hiddify/sing-box networking core.

The client connects users to AKV-managed subscriptions. It includes AKV account
sign-in, server mirror failover, subscription discovery, and one-tap profile
activation without requiring users to enter a backend URL.

## Current capabilities

- Android, Windows, Linux, macOS, and iOS codebase from the upstream client.
- AKV branding, bundle identifiers, `akvvpn://` deep links, and AKV user agent.
- Email registration and sign-in through
  [`akv-vpn-controller`](https://github.com/Lujker/akv-vpn-controller).
- Persistent multi-device sessions and an in-app list of AKV subscriptions.
- One-tap import of an AKV-managed subscription.
- Built-in primary endpoint and mirror failover.
- No Sentry analytics or crash-reporting SDK in the AKV fork.
- VLESS, REALITY, XHTTP, TUN, and other transports provided by the upstream
  networking core.

## Place in the platform

```text
AKV VPN Client
   | account, plans, subscriptions
   v
akv-vpn-controller
   | generated subscription
   v
akv-vpn-vps nodes
```

The parent [`akv-vpn`](https://github.com/Lujker/akv-vpn) repository pins the
compatible client, controller, node, mail, and shared-contract revisions.

## Build

The repository currently pins the Flutter and Hiddify Core versions documented
in [the private build guide](docs/private/BUILD_RU.md). Clone recursively:

```bash
git clone --recurse-submodules git@github.com:Lujker/akv-vpn-app.git
cd akv-vpn-app
```

Common preparation follows the upstream Makefile:

```bash
make android-apk-prepare CHANNEL=prod
make android-apk-release CHANNEL=prod
```

AKV-specific helpers are available for tested platforms:

```bash
bash scripts/build_android.sh
```

```powershell
.\scripts\build_windows.ps1
```

Windows must be built on Windows; macOS/iOS require macOS and Apple signing
assets. See [BUILD_RU.md](docs/private/BUILD_RU.md) for platform details.

## Development notes

- The active AKV branch is currently `akv-v4.1.2`.
- Do not advance nested Hiddify Core submodules independently; select a tested
  parent Hiddify Core revision first.
- Account tokens and HWID still require migration from `SharedPreferences` to
  platform secure storage before production release.
- Android has been validated on a physical device. Windows, Linux, macOS, and
  iOS release artifacts still require the roadmap validation matrix.

## Documentation

- [AKV fork changes and implementation journal](docs/private/AKV_CHANGES_RU.md)
- [Platform build guide](docs/private/BUILD_RU.md)
- [Documentation index](docs/README.md)
- [AKV Platform Roadmap](https://github.com/Lujker/akv-vpn/blob/main/docs/road-map.md)
- [AKV VPN Controller](https://github.com/Lujker/akv-vpn-controller)
- [AKV VPN Node](https://github.com/Lujker/akv-vpn-vps)
- [Archived upstream landing page](docs/archive/upstream-hiddify-readme.md)

## License and attribution

This repository remains licensed under GPLv3. AKV-specific work does not remove
the licenses, notices, or attribution requirements of Hiddify App, Hiddify
Core, sing-box, and other upstream dependencies. See [LICENSE.md](LICENSE.md)
and [CONTRIBUTING.md](CONTRIBUTING.md).
