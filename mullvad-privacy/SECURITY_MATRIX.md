# Privacy Browser security matrix

Pinned Mullvad source commit: `75a5d3fb8abea0138d886e77c1ca891623250023`.

| Surface | Policy | Enforcement / notes |
|---|---|---|
| Public IPv4 / IPv6 | Tunnel only | Manual SOCKS5 + Gecko fail-closed + Windows Defender Firewall process kill switch. Browser direct IPv4 except loopback is blocked; browser IPv6 is blocked. |
| DNS | Remote through SOCKS5 | SOCKS5 remote DNS enabled. Browser DoH/TRR provider disabled. DNS prefetch inherited disabled. |
| WebRTC / STUN | Disabled | `media.peerconnection.enabled=false`; Mullvad/MinGW also disables WebRTC at build level where applicable. |
| QUIC / HTTP/3 | Disabled | Prevents a UDP alternative transport from bypassing the intended TCP SOCKS path. |
| WebTransport | Disabled | Strict mode. |
| Localhost / LAN probing | Blocked for web content | Local Network Access blocking enabled, including WebSocket checks. Browser itself may reach the configured local SOCKS endpoint. |
| Geolocation | Disabled | Location API disabled/locked. |
| Network Information API | Disabled | Prevents exposing effective connection type/downlink/network hints. |
| Mobile-network information | Not exposed by browser API | Network Information is disabled; site still sees properties of the public exit network. |
| ISP / ASN | Exit network only | A destination can derive ISP/ASN from the exit IP. This cannot be hidden from that destination except by choosing another exit IP/network. |
| Browser timezone | Standardized by default; optional override | Empty override preserves Mullvad/RFP default. Manual IANA timezone override is available. |
| Windows system timezone | Optional manual setting | Launcher can call `tzutil` before startup. This changes the host OS timezone and requires elevation. |
| User-Agent / browser version | Standardized by default; optional override | Empty values preserve Mullvad/RFP anonymity set. A separate numeric version field can generate a coherent Windows Firefox-style UA. |
| `navigator.platform` | Standardized by default; optional override | RFP-aware source patch. |
| `navigator.oscpu` | Standardized by default; optional override | RFP-aware source patch. |
| `navigator.appVersion` | Standardized by default; optional override | RFP-aware source patch. |
| `navigator.buildID` | Standardized by default; optional override | RFP-aware source patch. |
| Screen/window geometry | Standardized | Mullvad RFP + letterboxing inherited. |
| Canvas | RFP protected | Mullvad/Base Browser inherited protections. |
| WebGL / graphics | RFP protected | Prefer common Mullvad fingerprint instead of arbitrary spoofing. WebGPU is disabled in strict profile. |
| Fonts | Restricted/standardized | Mullvad/Base Browser RFP/font protections inherited. |
| Hardware concurrency / CPU hints | RFP standardized | Inherited from Mullvad/Base Browser. |
| Sensors | Disabled | Device sensor pref disabled. |
| Battery API | Disabled | Strict profile. |
| Gamepad | Disabled | Strict profile. |
| Web MIDI | Disabled/locked | Strict profile. |
| VR | Disabled/locked | Strict profile. |
| WebAuthn | Disabled/locked in strict profile | Reduces hardware/authenticator fingerprinting surface; this breaks passkey/WebAuthn sites. |
| Referrer | Disabled by default | `NoReferrer=true`; configurable to a less strict trimmed policy. |
| Cookies / site storage correlation | Minimized, not magically eliminated | Mullvad private browsing, first-party isolation and cookie protections are inherited. Logging into the same account can still identify/correlate the user. |
| Advertising/device identifiers | Browser-side identifiers minimized | Telemetry/data reporting disabled; OS advertising IDs are not deliberately exposed. Sites can still create first-party identifiers while a session/account exists. |
| Probabilistic fingerprint identifiers | Reduced | RFP, letterboxing, common defaults and disabled high-entropy APIs. Custom identity overrides may reduce the anonymity set and should be used coherently. |
| Browser telemetry / usage reporting | Disabled | Mullvad/Base Browser telemetry and data submission protections inherited. |
| Local browsing history persistence | Minimized | Private browsing autostart and disk-cache/history hardening inherited. |
| Activity inside a destination service | Visible to that service | The service necessarily receives requests needed to provide its pages/API. No browser can make a service serve a request while preventing that same service from observing the request. |
| Destination server logs | Not browser-controllable | A remote server may retain IP, timestamps, URLs, account activity and request metadata. The browser can minimize what it sends, but cannot force deletion/non-logging on an unrelated server. |
| TLS / HTTP implementation fingerprint | Common Mullvad/Firefox family | Keeping the upstream engine and transport stack avoids a unique custom protocol implementation. |

## Acceptance tests

A release is not considered leak-tested until all of these are satisfied on Windows 10 x64 with the intended tunnel client:

1. Tunnel available: HTTPS works and browser TCP peers are loopback only.
2. Tunnel unavailable: Internet browsing fails closed; no direct non-loopback browser connection appears.
3. Windows firewall kill-switch rules target only the Privacy Browser executable and cover all non-loopback IPv4 plus all IPv6.
4. Browser profile confirms SOCKS5 remote DNS, no DoH provider, WebRTC off, HTTP/3 off and WebTransport off.
5. Runtime process observation reports zero direct non-loopback TCP endpoints.
6. Browser-facing leak pages report no local/public ISP address from the current physical connection.
7. DNS leak tests show resolvers associated with the tunnel/exit path, not the current physical ISP.
8. Browser identity inspection matches the selected profile consistently: timezone, UA/version, platform, OSCPU, appVersion and buildID.
9. RFP/letterboxing remains enabled when custom identity fields are blank.
10. Turning off the tunnel while pages are actively loading does not create fallback traffic.
