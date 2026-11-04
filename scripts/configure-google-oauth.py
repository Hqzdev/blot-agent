#!/usr/bin/env python3
"""Configure public native OAuth IDs; never accepts or stores a client secret."""
import argparse
import os
from pathlib import Path
import plistlib
import re
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CLIENT_ID = re.compile(r"[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com\Z")
BUNDLES = {"iOS": "yaroslavstrelkov.blot-agent.ios", "macOS": "yaroslavstrelkov.blot-agent"}
URL_NAME = "dev.blot.google-oauth"


def client(value, platform):
    if not CLIENT_ID.fullmatch(value):
        raise ValueError(f"{platform}: ожидается OAuth client ID вида NUMBER-ID.apps.googleusercontent.com")
    scheme = ".".join(reversed(value.split(".")))
    return {"ClientID": value, "BundleID": BUNDLES[platform], "RedirectURI": scheme + ":/oauthredirect"}


def atomic_plist(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as file:
        temporary = Path(file.name)
        try:
            plistlib.dump(value, file, sort_keys=False)
            file.flush()
            os.fsync(file.fileno())
        except BaseException:
            temporary.unlink(missing_ok=True)
            raise
    os.replace(temporary, path)


def validate(config, info):
    if config.get("Enabled") is False and config.get("Clients") == {}:
        return "Google OAuth выключен: зарегистрированные client IDs ещё не заданы."
    if config.get("Enabled") is not True or set(config.get("Clients", {})) != set(BUNDLES):
        raise ValueError("Конфигурация должна содержать обоих нативных клиентов")
    managed = [item for item in info.get("CFBundleURLTypes", []) if item.get("CFBundleURLName") == URL_NAME]
    expected_schemes = set()
    for platform in BUNDLES:
        stored = config["Clients"][platform]
        if stored != client(stored.get("ClientID", ""), platform):
            raise ValueError(f"{platform}: bundle ID или redirect URI не соответствует client ID")
        expected_schemes.add(stored["RedirectURI"].split(":", 1)[0])
    if len(managed) != 1 or set(managed[0].get("CFBundleURLSchemes", [])) != expected_schemes:
        raise ValueError("URL schemes в Info.plist не соответствуют OAuth-конфигурации")
    return "Google OAuth: оба client ID, bundle ID и redirect URI согласованы. Реальный вход требует проверки на устройствах."


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ios-client-id")
    parser.add_argument("--macos-client-id")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--disable", action="store_true")
    parser.add_argument("--config", type=Path, default=ROOT / "apps/shared/Resources/GoogleOAuth.plist")
    parser.add_argument("--info-plist", type=Path, default=ROOT / "apps/BackendInfo.plist")
    args = parser.parse_args()
    try:
        info = plistlib.loads(args.info_plist.read_bytes())
        if args.check:
            if args.ios_client_id or args.macos_client_id:
                raise ValueError("--check не принимает новые client IDs")
            print(validate(plistlib.loads(args.config.read_bytes()), info))
            return
        if args.disable:
            if args.ios_client_id or args.macos_client_id:
                raise ValueError("--disable не принимает client IDs")
            config = {"Enabled": False, "Clients": {}}
        else:
            if not args.ios_client_id or not args.macos_client_id:
                raise ValueError("Укажите --ios-client-id и --macos-client-id, либо --check / --disable")
            if args.ios_client_id == args.macos_client_id:
                raise ValueError("Mac и iPhone используют разные зарегистрированные bundle IDs и client IDs")
            config = {"Enabled": True, "Clients": {platform: client(value, platform) for platform, value in (
                ("iOS", args.ios_client_id), ("macOS", args.macos_client_id))}}
        types = [item for item in info.get("CFBundleURLTypes", []) if item.get("CFBundleURLName") != URL_NAME]
        if config["Enabled"]:
            types.append({"CFBundleURLName": URL_NAME, "CFBundleTypeRole": "Editor", "CFBundleURLSchemes": sorted(
                value["RedirectURI"].split(":", 1)[0] for value in config["Clients"].values())})
        if types:
            info["CFBundleURLTypes"] = types
        else:
            info.pop("CFBundleURLTypes", None)
        validate(config, info)
        atomic_plist(args.info_plist, info)
        atomic_plist(args.config, config)
        print(validate(config, info))
    except (ValueError, OSError, plistlib.InvalidFileException) as error:
        parser.exit(2, f"Ошибка конфигурации: {error}\n")


if __name__ == "__main__":
    main()
