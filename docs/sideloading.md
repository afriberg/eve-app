# Getting this app onto your iPhone for free (no Apple Developer Program)

This is the **free** path: no $99/year Apple Developer Program, no App Store
Connect, no App Store involvement of any kind. It uses a **free Apple ID**
(the same kind of Apple ID you already use for iCloud/iMessage — no payment
tier) plus a Windows or Linux computer to sign the build locally.

The trade-off for not paying: apps signed with a free Apple ID must be
**re-signed every 7 days**, or iOS refuses to launch them. This is an Apple
platform limit, not something this project can remove. If that's more
friction than you want long-term, `docs/testflight.md` covers the paid
alternative (90-day builds, no PC needed at all, $99/year).

## How it works

1. `.github/workflows/sideload-build.yml` (GitHub's macOS runner, same as
   the regular CI) builds the app **unsigned** — `CODE_SIGNING_ALLOWED=NO`
   — and packages it as `EVE-unsigned.ipa`, uploaded as a workflow
   artifact. No Apple account is involved in this step at all.
2. You download that `.ipa` to your Windows/Linux PC.
3. A local sideloading tool (AltStore or Sideloadly, below) re-signs the
   `.ipa` using your free Apple ID's on-the-fly developer certificate, and
   pushes it to your iPhone. This is the same mechanism Xcode itself uses
   for "Run on device" with a free account — these tools just don't require
   Xcode or a Mac.

Neither tool needs your Apple ID password stored anywhere in this
repository or in CI — you sign in locally, once, in the tool itself.

## Option A: Sideloadly (verified working — recommended)

**This is the confirmed path**: `EVE-unsigned.ipa` from the CI workflow,
installed via Sideloadly on Windows, launched successfully on a physical
iPhone. [Sideloadly](https://sideloadly.io) officially supports Windows and
macOS, not Linux. It drives everything from the PC over USB, which avoids a
document-import step on the iPhone itself that AltStore's iOS app can be
finicky about with a fully unsigned `.ipa`.

1. Install Sideloadly, connect the iPhone over USB.
2. Enter your free Apple ID, drag `EVE-unsigned.ipa` in, click Start.
3. On the iPhone: **Settings → General → VPN & Device Management** →
   trust the developer certificate the first time.
4. There is no auto-refresh — repeat this step within 7 days to keep the
   app working. A calendar reminder is the simplest way to not get caught
   out by this.

There's no need to also install AltStore — Sideloadly alone is enough for
ongoing use. The only reason to consider AltStore (Option B) is if the
weekly manual re-sign becomes annoying and you'd rather it happen in the
background automatically.

## Option B: AltStore (optional — auto-refresh, but flakier import)

AltStore's desktop component ("AltServer") officially supports **Windows
and macOS**. There is no first-party Linux build. Check
[altstore.io](https://altstore.io) for the current supported platforms
before relying on this, since sideloading tooling changes over time and
this project can't track it for you.

In practice, AltStore's iOS-side import of a fully unsigned `.ipa` (via
**My Apps → +**) has failed with "The data couldn't be read because it
isn't in the correct format" even though the same file installs fine via
Sideloadly — the `.ipa` itself was verified structurally valid (zip
integrity, `Payload/EVE.app` layout, valid arm64 Mach-O binary, valid
`Info.plist`), so this looks like an AltStore-side import quirk rather than
a broken build. If you still want AltStore's auto-refresh convenience:

1. Install AltServer on your PC and the AltStore companion app on your
   iPhone (via AltServer's "Install AltStore" menu, with the iPhone
   connected over USB or on the same Wi-Fi network).
2. Sign into AltStore with your free Apple ID when prompted.
3. In AltStore on the iPhone, use **My Apps → +** and pick the downloaded
   `EVE-unsigned.ipa`. If this fails with the error above, stick with
   Sideloadly (Option A) — there is no known fix confirmed yet.
4. **Auto-refresh**: if the import does work, AltStore refreshes the
   signature automatically in the background as long as AltServer is
   running on your PC and the iPhone is reachable on the same network at
   least once every 7 days.

## If your PC is Linux and AltServer-Linux doesn't work for you

The realistic fallback is a Windows VM (or a spare/borrowed Windows
machine) purely for the few minutes it takes to run Sideloadly or
AltServer each week — the build itself always comes from GitHub's macOS
runner either way, so the VM never needs Xcode or heavy tooling.

## Connecting to a real EVE Voice Gateway

The build above installs and launches, but can't actually reach a Gateway
until it's built with that deployment's pinned root CA (see
`EVE/Resources/EVERootCA-README.md`). Add a repository secret
**`EVE_ROOT_CA_PEM`** (Settings → Secrets and variables → Actions) containing
the PEM text printed by `eve-os`'s `scripts/eve-gateway-tls-init.sh`
(`eve-gateway-root-ca.crt`) — paste it exactly as printed, including the
`-----BEGIN CERTIFICATE-----`/`-----END CERTIFICATE-----` lines. It's a
public certificate (no private key), safe to store as a secret but not
sensitive enough to need extra caution beyond that.

`sideload-build.yml` converts it to the DER format iOS actually requires
(`SecCertificateCreateWithData` rejects PEM) and writes it to
`EVE/Resources/EVERootCA.cer` before building — never committed, generated
fresh in CI each run. If the secret isn't set, the build still succeeds but
the app throws `rootCertificateNotBundled` at runtime and refuses to reach
any Gateway (fail-closed by design, not a bug).

## First install caveats

- **Trust the developer certificate** on the iPhone the first time
  (Settings → General → VPN & Device Management) or the app won't open.
- **Free accounts can have only a handful of sideloaded apps active at
  once** (Apple limits free-account provisioning to a small number of
  App IDs per 7-day rolling window) — shouldn't matter for a single
  personal app, but worth knowing if you sideload other things too.
- Siri/App Intents entitlements this app uses are the basic
  `AppIntent`/App Shortcuts kind, which work under free-account signing.
  Push notifications (not used by this app) would not.

## Running it

Repository → Actions → **"Sideload build (free, no paid account)"** → Run
workflow. Takes a few minutes. Download the `EVE-unsigned-ipa` artifact
from the finished run, then follow Option A above.

## Status

Verified end-to-end on a physical iPhone via Sideloadly: build → download →
install → app launches. This confirms the free, no-Apple-Developer-Program
path works. Milestone 1's actual voice/microphone/Siri functionality is
still foundation-only (see `docs/roadmap.md`) — this only confirms the app
*installs and launches*, not that voice features work yet.
