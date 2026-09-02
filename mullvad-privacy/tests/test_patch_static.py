from __future__ import annotations

import argparse
from pathlib import Path


REQUIRED_PREFS = {
    'pref("privacy.network.fail_closed", true, locked);',
    'pref("network.proxy.type", 1, locked);',
    'pref("network.proxy.socks", "127.0.0.1");',
    'pref("network.proxy.socks5_remote_dns", true);',
    'pref("network.proxy.failover_direct", false, locked);',
    'pref("network.proxy.allow_bypass", false, locked);',
    'pref("network.trr.mode", 5);',
    'pref("media.peerconnection.enabled", false);',
    'pref("media.navigator.enabled", false);',
    'pref("network.http.http3.enable", false);',
    'pref("network.webtransport.enabled", false);',
    'pref("network.lna.blocking", true);',
    'pref("network.lna.websocket.enabled", true);',
    'pref("network.lna.local-network-to-localhost.skip-checks", false);',
    'pref("geo.enabled", false, locked);',
    'pref("dom.netinfo.enabled", false, locked);',
    'pref("network.http.sendRefererHeader", 0);',
    'pref("privacy.identity.timezone_override", "");',
    'pref("privacy.identity.useragent_override", "");',
}


def require(text: str, needle: str, label: str) -> None:
    if needle not in text:
        raise AssertionError(f"missing {label}: {needle}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    root = args.source.resolve()

    profile = (root / "browser/app/profile/000-mullvad-browser.js").read_text(encoding="utf-8")
    for pref in sorted(REQUIRED_PREFS):
        require(profile, pref, "strict preference")

    proxy = (root / "netwerk/base/nsProtocolProxyService.cpp").read_text(encoding="utf-8")
    require(proxy, 'Preferences::GetBool("privacy.network.fail_closed", false)', "fail-closed preference")
    require(proxy, 'IsStrictLoopbackHost(proxy->Host())', "callback loopback proxy enforcement")
    require(proxy, 'NS_ERROR_PROXY_CONNECTION_REFUSED', "direct connection rejection")
    require(proxy, 'strictDirectAllowed ? NS_OK : NS_ERROR_PROXY_CONNECTION_REFUSED', "direct-mode fail closed")
    require(proxy, 'strictFailClosed && !IsStrictLoopbackHost(*host)', "manual proxy loopback enforcement")

    rfp = (root / "toolkit/components/resistfingerprinting/nsRFPService.cpp").read_text(encoding="utf-8")
    require(rfp, '"privacy.identity.useragent_override"', "RFP UA override")
    require(rfp, '"privacy.identity.timezone_override"', "RFP timezone override")
    require(rfp, 'return "Atlantic/Reykjavik"_ns;', "Mullvad timezone fallback")

    navigator = (root / "dom/base/Navigator.cpp").read_text(encoding="utf-8")
    for pref in (
        '"privacy.identity.platform_override"',
        '"privacy.identity.oscpu_override"',
        '"privacy.identity.appversion_override"',
        '"privacy.identity.buildid_override"',
    ):
        require(navigator, pref, "navigator override")

    mozconfig = (root / "browser/config/mozconfigs/mullvad-browser").read_text(encoding="utf-8")
    require(mozconfig, "MOZ_APP_BASENAME=PrivacyBrowser", "application basename")
    require(mozconfig, 'MOZ_APP_DISPLAYNAME="Privacy Browser"', "application display name")

    base_profile = (root / "browser/app/profile/001-base-profile.js").read_text(encoding="utf-8")
    for inherited in (
        'pref("privacy.resistFingerprinting", true, locked);',
        'pref("privacy.resistFingerprinting.letterboxing", true);',
        'pref("privacy.firstparty.isolate", true);',
        'pref("browser.privatebrowsing.autostart", true);',
        'pref("toolkit.telemetry.enabled", false, locked);',
        'pref("datareporting.policy.dataSubmissionEnabled", false);',
    ):
        require(base_profile, inherited, "upstream privacy invariant")

    print("privacy patch static validation: PASS")


if __name__ == "__main__":
    main()
