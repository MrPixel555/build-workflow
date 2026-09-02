from __future__ import annotations

import argparse
from pathlib import Path


MULLVAD_SOURCE_COMMIT = "75a5d3fb8abea0138d886e77c1ca891623250023"


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"expected one build-system anchor in {path}, found {count}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8", newline="\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("tor_browser_build", type=Path)
    parser.add_argument("patch", type=Path)
    args = parser.parse_args()

    root = args.tor_browser_build.resolve()
    patch = args.patch.resolve()
    if not patch.is_file():
        raise RuntimeError(f"patch not found: {patch}")

    firefox_dir = root / "projects/firefox"
    config = firefox_dir / "config"
    build = firefox_dir / "build"
    if not config.is_file() or not build.is_file():
        raise RuntimeError("unexpected tor-browser-build checkout")

    target_anchor = """  mullvadbrowser:\n    git_url: https://gitlab.torproject.org/tpo/applications/mullvad-browser.git\n    var:\n"""
    target_replacement = f"""  mullvadbrowser:\n    git_hash: '{MULLVAD_SOURCE_COMMIT}'\n    tag_gpg_id: 0\n    git_url: https://github.com/mullvad/mullvad-browser.git\n    var:\n"""
    replace_once(config, target_anchor, target_replacement)

    config_text = config.read_text(encoding="utf-8")
    if "filename: privacy-browser-source.patch" not in config_text:
        if not config_text.endswith("\n"):
            config_text += "\n"
        config_text += """  - filename: privacy-browser-source.patch\n    enable: '[% c(\"var/mullvad-browser\") %]'\n"""
        config.write_text(config_text, encoding="utf-8", newline="\n")

    build_anchor = """cd /var/tmp/build/[% project %]-[% c(\"version\") %]\ncp $rootdir/mozconfig ./\n\n"""
    build_replacement = """cd /var/tmp/build/[% project %]-[% c(\"version\") %]\ncp $rootdir/mozconfig ./\n\n[% IF c(\"var/mullvad-browser\") -%]\n  patch -p1 < $rootdir/privacy-browser-source.patch\n[% END -%]\n\n"""
    replace_once(build, build_anchor, build_replacement)

    destination = firefox_dir / "privacy-browser-source.patch"
    destination.write_bytes(patch.read_bytes())

    print(f"tor-browser-build configured for Mullvad commit {MULLVAD_SOURCE_COMMIT}")
    print(f"privacy patch copied to {destination}")


if __name__ == "__main__":
    main()
