#!/usr/bin/env python3
"""Run shared core tests and a real Keychain check in an isolated, signed iPhone host."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / ".build"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device-udid", help="Required only if several paired physical iPhones are available")
    parser.add_argument("--team", help="Defaults to the existing BlotIOS signing team")
    args = parser.parse_args()
    BUILD.mkdir(exist_ok=True)
    inventory = BUILD / "apple-v1-iphone-inventory.json"
    subprocess.run(["xcrun", "devicectl", "list", "devices", "--json-output", str(inventory)], check=True, stdout=subprocess.DEVNULL)
    devices = json.loads(inventory.read_bytes()).get("result", {}).get("devices", [])
    available = [device for device in devices if device.get("deviceProperties", {}).get("bootState") == "booted"
                 and device.get("deviceProperties", {}).get("developerModeStatus") == "enabled"
                 and device.get("connectionProperties", {}).get("transportType") != "sameMachine"
                 and device.get("hardwareProperties", {}).get("deviceType") == "iPhone"]
    if args.device_udid:
        available = [device for device in available if device.get("hardwareProperties", {}).get("udid") == args.device_udid]
    if len(available) != 1:
        parser.error("Нужен один доступный доверенный iPhone в Developer Mode; при нескольких задайте --device-udid")
    device = available[0]
    team = args.team
    if not team:
        settings = subprocess.check_output(["xcodebuild", "-project", "apps/Blot.xcodeproj", "-scheme", "BlotIOS", "-showBuildSettings", "-json"], cwd=ROOT, text=True, stderr=subprocess.DEVNULL)
        team = json.loads(settings)[0]["buildSettings"].get("DEVELOPMENT_TEAM")
    if not team:
        parser.error("Укажите --team с вашей действующей Apple Development team")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    result_path = BUILD / ("apple-v1-iphone-" + stamp + ".xcresult")
    log_path = BUILD / "apple-v1-iphone-tests.log"
    command = ["xcodebuild", "-project", "apps/verification/BlotWorkspaceVerification.xcodeproj", "-scheme", "BlotWorkspaceVerification",
               "-destination", "platform=iOS,id=" + device["hardwareProperties"]["udid"], "-derivedDataPath", str(BUILD / "apple-v1-iphone"),
               "-resultBundlePath", str(result_path), "-allowProvisioningUpdates", "DEVELOPMENT_TEAM=" + team, "CODE_SIGN_STYLE=Automatic", "test"]
    print("Running isolated shared-core and Keychain checks on physical iPhone.", flush=True)
    with log_path.open("w") as output:
        result = subprocess.run(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT)
    if result.returncode:
        print("iPhone checks did not complete; inspect .build/apple-v1-iphone-tests.log", file=sys.stderr)
        return result.returncode
    summary = json.loads(subprocess.check_output(["xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result_path)], text=True))
    (BUILD / "apple-v1-iphone-summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n")
    passed = summary.get("passedTests", 0)
    failed = summary.get("failedTests", 0)
    if passed < 35 or failed or summary.get("skippedTests", 0):
        raise RuntimeError("Expected all 34 shared tests and the signed Keychain test to pass")
    evidence = {"checkedAt": datetime.now(timezone.utc).isoformat(), "result": "PASS", "physicalDevice": True,
                "osVersion": device.get("deviceProperties", {}).get("osVersionNumber"), "passedTests": passed, "failedTests": failed,
                "hostBundleID": "yaroslavstrelkov.blot-agent.workspace-verification", "resultBundle": str(result_path.relative_to(ROOT)),
                "productUIAcceptance": False, "externalModel": False, "google": False}
    (BUILD / "apple-v1-iphone-evidence.json").write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n")
    print(f"PASS: {passed} tests on a physical iPhone. Product UI/Google/model acceptance remains separate.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
