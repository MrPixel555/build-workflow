from __future__ import annotations

import argparse
from pathlib import Path


UPSTREAM_REF = "mullvad-browser-153.1.0esr-16.0-1"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"expected exactly one anchor in {path}, found {count}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8", newline="\n")


def append_once(path: Path, marker: str, content: str) -> None:
    text = path.read_text(encoding="utf-8")
    if marker in text:
        return
    if not text.endswith("\n"):
        text += "\n"
    path.write_text(text + "\n" + content.rstrip() + "\n", encoding="utf-8", newline="\n")


def patch_profile(root: Path) -> None:
    path = root / "browser/app/profile/000-mullvad-browser.js"
    block = r'''// Privacy Browser strict networking and data-minimization defaults.
pref("network.proxy.type", 1);
pref("network.proxy.socks", "127.0.0.1");
pref("network.proxy.socks_port", 10808);
pref("network.proxy.socks_version", 5);
pref("network.proxy.socks5_remote_dns", true);
pref("network.proxy.no_proxies_on", "");
pref("network.proxy.share_proxy_settings", true);
pref("network.proxy.failover_direct", false, locked);
pref("network.proxy.allow_bypass", false, locked);

// Do not create a second DNS path outside the configured SOCKS5 tunnel.
pref("network.trr.mode", 5);
pref("network.trr.uri", "");
pref("network.trr.default_provider_uri", "");
pref("network.trr.custom_uri", "");

// Disable UDP-oriented browser transports in strict mode.
pref("media.peerconnection.enabled", false);
pref("media.navigator.enabled", false);
pref("network.http.http3.enable", false);
pref("network.http.http3.enable_0rtt", false);
pref("network.webtransport.enabled", false);

// Prevent public pages from probing local services or LAN topology.
pref("network.lna.enabled", true);
pref("network.lna.blocking", true);
pref("network.lna.allow_top_level_navigation", false);
pref("network.lna.websocket.enabled", true);
pref("network.lna.local-network-to-localhost.skip-checks", false);

// Explicitly keep location/network/device surfaces closed in the strict profile.
pref("geo.enabled", false, locked);
pref("dom.netinfo.enabled", false, locked);
pref("dom.webmidi.enabled", false, locked);
pref("dom.vr.enabled", false, locked);
pref("security.webauth.webauthn", false, locked);
pref("dom.webgpu.enabled", false, locked);
pref("device.sensors.enabled", false);
pref("dom.gamepad.enabled", false);
pref("dom.battery.enabled", false);

// Minimize navigation-origin disclosure. This is intentionally stricter than Mullvad defaults.
pref("network.http.sendRefererHeader", 0);
pref("network.http.referer.defaultPolicy", 0);
pref("network.http.referer.defaultPolicy.pbmode", 0);
pref("network.http.referer.XOriginPolicy", 2);
pref("network.http.referer.XOriginTrimmingPolicy", 2);

// Keep the anonymity-set defaults unless the user explicitly provides coherent overrides.
pref("privacy.identity.timezone_override", "");
pref("privacy.identity.useragent_override", "");
pref("privacy.identity.platform_override", "");
pref("privacy.identity.oscpu_override", "");
pref("privacy.identity.appversion_override", "");
pref("privacy.identity.buildid_override", "");
'''
    append_once(path, "privacy.identity.timezone_override", block)


def patch_rfp(root: Path) -> None:
    path = root / "toolkit/components/resistfingerprinting/nsRFPService.cpp"
    old = '''/* static */\nvoid nsRFPService::GetSpoofedUserAgent(nsACString& userAgent,\n                                       bool aAndroidDesktopMode /* = false */) {\n  // This function generates the spoofed value of User Agent.\n'''
    new = '''/* static */\nvoid nsRFPService::GetSpoofedUserAgent(nsACString& userAgent,\n                                       bool aAndroidDesktopMode /* = false */) {\n  nsAutoCString override;\n  if (NS_SUCCEEDED(Preferences::GetCString(\n          "privacy.identity.useragent_override", override)) &&\n      !override.IsEmpty()) {\n    userAgent.Assign(override);\n    return;\n  }\n\n  // This function generates the spoofed value of User Agent.\n'''
    replace_once(path, old, new)

    old = '''/* static */\nnsCString nsRFPService::GetSpoofedJSTimeZone() {\n  return "Atlantic/Reykjavik"_ns;\n}\n'''
    new = '''/* static */\nnsCString nsRFPService::GetSpoofedJSTimeZone() {\n  nsAutoCString override;\n  if (NS_SUCCEEDED(Preferences::GetCString(\n          "privacy.identity.timezone_override", override)) &&\n      !override.IsEmpty()) {\n    return override;\n  }\n  return "Atlantic/Reykjavik"_ns;\n}\n'''
    replace_once(path, old, new)


def patch_navigator(root: Path) -> None:
    path = root / "dom/base/Navigator.cpp"

    old = '''    if (nsContentUtils::ShouldResistFingerprinting(GetDocShell(),\n                                                   RFPTarget::NavigatorOscpu)) {\n      aOSCPU.AssignLiteral(SPOOFED_OSCPU);\n      return;\n    }\n'''
    new = '''    if (nsContentUtils::ShouldResistFingerprinting(GetDocShell(),\n                                                   RFPTarget::NavigatorOscpu)) {\n      nsAutoString override;\n      if (NS_SUCCEEDED(Preferences::GetString(\n              "privacy.identity.oscpu_override", override)) &&\n          !override.IsEmpty()) {\n        aOSCPU = std::move(override);\n      } else {\n        aOSCPU.AssignLiteral(SPOOFED_OSCPU);\n      }\n      return;\n    }\n'''
    replace_once(path, old, new)

    old = '''  // navigator.platform is the same for default and spoofed values. The\n  // "general.platform.override" pref should override the default platform,\n  // but the spoofed platform should override the pref.\n  if (aUsePrefOverriddenValue &&\n      !ShouldResistFingerprinting(aCallerDoc, RFPTarget::NavigatorPlatform)) {\n'''
    new = '''  // navigator.platform is the same for default and spoofed values. The\n  // "general.platform.override" pref should override the default platform,\n  // but the spoofed platform should override the pref.\n  if (aUsePrefOverriddenValue &&\n      ShouldResistFingerprinting(aCallerDoc, RFPTarget::NavigatorPlatform)) {\n    nsAutoString override;\n    if (NS_SUCCEEDED(Preferences::GetString(\n            "privacy.identity.platform_override", override)) &&\n        !override.IsEmpty()) {\n      aPlatform = std::move(override);\n      return NS_OK;\n    }\n  }\n\n  if (aUsePrefOverriddenValue &&\n      !ShouldResistFingerprinting(aCallerDoc, RFPTarget::NavigatorPlatform)) {\n'''
    replace_once(path, old, new)

    old = '''    if (ShouldResistFingerprinting(aCallerDoc,\n                                   RFPTarget::NavigatorAppVersion)) {\n      aAppVersion.AssignLiteral(SPOOFED_APPVERSION);\n      return NS_OK;\n    }\n'''
    new = '''    if (ShouldResistFingerprinting(aCallerDoc,\n                                   RFPTarget::NavigatorAppVersion)) {\n      nsAutoString override;\n      if (NS_SUCCEEDED(Preferences::GetString(\n              "privacy.identity.appversion_override", override)) &&\n          !override.IsEmpty()) {\n        aAppVersion = std::move(override);\n      } else {\n        aAppVersion.AssignLiteral(SPOOFED_APPVERSION);\n      }\n      return NS_OK;\n    }\n'''
    replace_once(path, old, new)

    old = '''    if (nsContentUtils::ShouldResistFingerprinting(\n            GetDocShell(), RFPTarget::NavigatorBuildID)) {\n      aBuildID.AssignLiteral(LEGACY_BUILD_ID);\n      return;\n    }\n'''
    new = '''    if (nsContentUtils::ShouldResistFingerprinting(\n            GetDocShell(), RFPTarget::NavigatorBuildID)) {\n      nsAutoString override;\n      if (NS_SUCCEEDED(Preferences::GetString(\n              "privacy.identity.buildid_override", override)) &&\n          !override.IsEmpty()) {\n        aBuildID = std::move(override);\n      } else {\n        aBuildID.AssignLiteral(LEGACY_BUILD_ID);\n      }\n      return;\n    }\n'''
    replace_once(path, old, new)


def patch_branding(root: Path) -> None:
    path = root / "browser/config/mozconfigs/mullvad-browser"
    marker = "MOZ_APP_BASENAME=PrivacyBrowser"
    text = path.read_text(encoding="utf-8")
    if marker in text:
        return
    text = text.replace("export MOZ_APP_BASENAME=MullvadBrowser", "export MOZ_APP_BASENAME=PrivacyBrowser")
    text = text.replace('mk_add_options MOZ_APP_DISPLAYNAME="Mullvad Browser"', 'mk_add_options MOZ_APP_DISPLAYNAME="Privacy Browser"')
    text = text.replace("ac_add_options --with-user-appdir=Mullvad", "ac_add_options --with-user-appdir=PrivacyBrowser")
    text = text.replace("ac_add_options --with-distribution-id=net.mullvad", "ac_add_options --with-distribution-id=org.privacybrowser")
    path.write_text(text, encoding="utf-8", newline="\n")


def apply(root: Path) -> None:
    required = [
        root / "browser/app/profile/000-mullvad-browser.js",
        root / "toolkit/components/resistfingerprinting/nsRFPService.cpp",
        root / "dom/base/Navigator.cpp",
        root / "browser/config/mozconfigs/mullvad-browser",
    ]
    missing = [str(path) for path in required if not path.exists()]
    if missing:
        raise RuntimeError("missing upstream source files: " + ", ".join(missing))
    patch_profile(root)
    patch_rfp(root)
    patch_navigator(root)
    patch_branding(root)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    apply(args.source.resolve())
    print(f"privacy patch applied to {args.source.resolve()} from {UPSTREAM_REF}")


if __name__ == "__main__":
    main()
