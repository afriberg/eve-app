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

## Option A: AltStore (recommended — supports auto refresh)

AltStore's desktop component ("AltServer") officially supports **Windows
and macOS**. There is no first-party Linux build; if your PC is Linux,
either use the community `AltServer-Linux` project or fall back to Option B
below. Check [altstore.io](https://altstore.io) for the current supported
platforms before relying on this, since sideloading tooling changes over
time and this project can't track it for you.

1. Install AltServer on your PC and the AltStore companion app on your
   iPhone (via AltServer's "Install AltStore" menu, with the iPhone
   connected over USB or on the same Wi-Fi network).
2. Sign into AltStore with your free Apple ID when prompted.
3. In AltStore on the iPhone, use **My Apps → +** and pick the downloaded
   `EVE-unsigned.ipa`. AltStore signs and installs it.
4. **Auto-refresh**: as long as AltServer is running on your PC and the
   iPhone is reachable on the same network at least once every 7 days,
   AltStore refreshes the signature automatically in the background — no
   manual reinstall needed. If AltServer is only running occasionally,
   open AltStore on the phone while it's running to trigger a refresh
   before the 7 days run out.

## Option B: Sideloadly (Windows and macOS; simplest one-off installs)

[Sideloadly](https://sideloadly.io) officially supports Windows and macOS,
not Linux.

1. Install Sideloadly, connect the iPhone over USB.
2. Enter your free Apple ID, drag `EVE-unsigned.ipa` in, click Start.
3. On the iPhone: **Settings → General → VPN & Device Management** →
   trust the developer certificate the first time.
4. There is no auto-refresh — repeat this step within 7 days to keep the
   app working. A calendar reminder is the simplest way to not get caught
   out by this.

## If your PC is Linux and AltServer-Linux doesn't work for you

The realistic fallback is a Windows VM (or a spare/borrowed Windows
machine) purely for the few minutes it takes to run Sideloadly or
AltServer each week — the build itself always comes from GitHub's macOS
runner either way, so the VM never needs Xcode or heavy tooling.

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
from the finished run, then follow Option A or B above.

## What isn't verified yet

This workflow has not been run end-to-end (this environment has no way to
sideload onto a physical iPhone). If the unsigned build step fails, the
most likely cause is a project setting that implicitly requires signing —
treat it as a normal CI debugging pass.
