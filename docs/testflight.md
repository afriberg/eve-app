# Getting this app onto a physical iPhone without a Mac

This is the **paid** path ($99/year Apple Developer Program). If you'd rather not pay and have a Windows/Linux PC available, see [`docs/sideloading.md`](sideloading.md) for a free alternative — the trade-off there is a manual/automatic re-sign every 7 days instead of Apple's 90-day TestFlight builds.

No Mac is required anywhere in this path. Xcode itself only ever runs on GitHub's macOS CI runner — the same one already building and testing this app on every push (`.github/workflows/ci.yml`). This document covers `.github/workflows/testflight.yml`, which extends that same idea to produce a real, installable build.

## TestFlight is not the App Store

They're separate Apple systems. TestFlight is Apple's beta-distribution mechanism:

- **Internal testing** (what this is set up for) — you add yourself (and anyone else on your Apple Developer account) as an internal tester in App Store Connect. Builds appear in their TestFlight app within minutes. **No App Review, no public listing, nothing visible to anyone outside the testers you explicitly added.**
- **External testing** — inviting testers outside your account. Needs a one-time, lightweight Beta App Review. Not set up here, and `fastlane/Fastfile`'s `beta` lane explicitly passes `distribute_external: false` so a build can never accidentally reach this tier.
- **App Store release** — the actual public listing. A completely separate, manual step ("Submit for Review" in App Store Connect) that nothing in this repository or its CI ever does. Internal TestFlight builds never require this and never risk triggering it.

So: this path gets the app onto your iPhone, privately, without ever touching the public App Store.

## One-time Apple-side setup (all web-based, no Xcode)

1. **Apple Developer Program membership** (developer.apple.com, $99/year) — required for any of this, including TestFlight-only distribution. This is Apple's requirement, not something this project can work around.
2. **Register the App ID** `pw.friberg.eve` at developer.apple.com → Certificates, IDs & Profiles → Identifiers. Enable the capabilities this app actually uses (Siri/App Intents needs nothing extra here — see `docs/ios-integrations.md`).
3. **Create the app record** in App Store Connect (appstoreconnect.apple.com) → Apps → New App, same bundle ID (`pw.friberg.eve`), platform iOS. This alone does not publish anything.
4. **Add yourself as an internal tester**: App Store Connect → your app → TestFlight tab → Internal Testing → add your Apple ID (the same one you'll use on your iPhone).
5. **Create an App Store Connect API key**: App Store Connect → Users and Access → Integrations → App Store Connect API → Generate API Key. Download the `.p8` file **immediately** — Apple only lets you download it once. Note the Key ID and Issuer ID shown next to it.
6. **Find your Team ID**: developer.apple.com → Membership (or the same page as step 5) — a short alphanumeric string, not a secret, but still kept out of this repo (see `project.yml`'s `DEVELOPMENT_TEAM` comment).

## GitHub secrets to add

Repository → Settings → Secrets and variables → Actions → New repository secret:

| Secret | Value |
|---|---|
| `APPLE_TEAM_ID` | Team ID from step 6 |
| `APP_STORE_CONNECT_API_KEY_ID` | Key ID from step 5 |
| `APP_STORE_CONNECT_API_ISSUER_ID` | Issuer ID from step 5 |
| `APP_STORE_CONNECT_API_KEY_CONTENT` | The `.p8` file's contents, base64-encoded: `base64 -i AuthKey_XXXXXXXXXX.p8 \| pbcopy` (macOS) or `base64 -w0 AuthKey_XXXXXXXXXX.p8` (Linux/Windows WSL) — paste the output, not the raw file |

None of these are ever committed to the repository. `.github/workflows/testflight.yml` only reads them as CI environment variables at run time.

## Running it

Repository → Actions → "TestFlight (internal only)" → Run workflow. It's `workflow_dispatch`-only (manual) on purpose — it never fires on an ordinary push, unlike `ci.yml`. Takes roughly 10-20 minutes (archive build + upload + Apple's processing).

Once it finishes, open the **TestFlight app** on your iPhone (install it from the App Store first if you don't have it — TestFlight itself is Apple's own app, that's the one and only App Store install involved here), sign in with the Apple ID you added as an internal tester, and the build appears there to install.

## What isn't verified yet

This workflow itself has not been run — it depends on Apple account credentials that only exist once you complete the setup above, which this environment cannot do on your behalf. The specific `fastlane`/`xcodebuild` automatic-signing flags (`-allowProvisioningUpdates` combined with an App Store Connect API key) are the current standard approach, but if the first run fails on a signing error, that's the most likely place to look — check the Action's log and treat it as a normal CI debugging pass, not a sign the whole approach is wrong.
