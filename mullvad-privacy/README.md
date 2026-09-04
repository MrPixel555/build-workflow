# Mullvad Privacy Browser v1

Target upstream: `mullvad/mullvad-browser` branch/tag `mullvad-browser-153.1.0esr-16.0-1`.

This branch contains a reproducible privacy-hardening patchset and Windows control scripts. It does not modify `main`.

## Security model

- Browser network is forced through a local SOCKS5 endpoint (default `127.0.0.1:10808`).
- The selected tunnel engine is Xray Core. The current Windows deployment may use v2rayN as the Xray front end/controller, while the browser remains coupled only to the fail-closed local SOCKS5 endpoint rather than to a specific GUI client.
- SOCKS5 remote DNS is enabled.
- Direct proxy failover and proxy bypass are disabled.
- DoH is disabled so DNS is not sent to Mullvad or the local ISP outside the tunnel.
- WebRTC and getUserMedia are disabled in strict mode.
- HTTP/3/QUIC and WebTransport are disabled in strict mode.
- Local Network Access is hardened to prevent web content from probing localhost/LAN.
- Geolocation, Network Information, Web MIDI, WebVR, WebAuthn, WebGPU and telemetry remain disabled/hardened.
- RFP, letterboxing, first-party isolation and private browsing remain enabled from Mullvad/Base Browser.
- Browser-exposed timezone and selected identity values can be overridden through dedicated privacy prefs. Empty values preserve Mullvad defaults.
- Windows system timezone can be changed by the launcher.
- Windows Defender Firewall kill switch blocks the browser process from every IPv4 destination outside `127.0.0.0/8` and blocks all IPv6, leaving the local Xray SOCKS endpoint reachable.

## Important limits

A destination service necessarily sees the public exit IP used to connect to it and can keep its own server logs. A browser cannot force a remote service not to log requests. ISP/ASN data is derived from the exit IP; it is hidden only by routing through the selected tunnel. This project minimizes identifiers and prevents browser-side/direct-network leaks, but does not make remote logging technically impossible.

## Build execution

The full Windows Firefox/Mullvad cross-build is too slow for the standard GitHub-hosted runner used by this private repository. That runner is limited to a small CPU/RAM allocation and a six-hour hosted-job execution ceiling. The final compile workflow therefore runs only by manual dispatch on a self-hosted Linux x64 runner carrying the `mullvad-builder` label. The workflow dynamically selects RBM parallelism from the runner CPU/RAM, streams a live heartbeat plus the latest RBM log tail, and uploads diagnostic logs even on ordinary build failures.

A successful prebuilt Firefox dependency artifact from workflow run `33782129324` is reused when still available. If it is unavailable or expired, the self-hosted job rebuilds missing dependencies locally rather than returning to the hosted six-hour ceiling.

## Files

- `tools/apply_privacy_patch.py`: patches the exact upstream source tree.
- `windows/PrivacyBrowser.ps1`: writes profile prefs, applies/removes the Windows firewall kill switch, optionally changes the system timezone, and launches the browser.
- `config/privacy-browser.example.json`: runtime configuration.
- `tests/test_patch_static.py`: verifies critical source anchors and the resulting patch.
- `.github/workflows/mullvad-privacy-validate.yml`: clones the exact upstream source and runs patch/static validation on every push to this branch.
- `.github/workflows/mullvad-privacy-build.yml`: manually dispatched self-hosted Windows cross-build with reusable dependency artifacts and live RBM diagnostics.

## Custom identity prefs

Empty string means use the normal Mullvad/RFP value.

- `privacy.identity.timezone_override`
- `privacy.identity.useragent_override`
- `privacy.identity.platform_override`
- `privacy.identity.oscpu_override`
- `privacy.identity.appversion_override`
- `privacy.identity.buildid_override`

Changing many values away from the common Mullvad fingerprint can make a browser more unique. For maximum anonymity-set protection, keep identity overrides empty unless a coherent profile is required.