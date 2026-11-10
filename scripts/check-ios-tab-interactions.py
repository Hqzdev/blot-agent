#!/usr/bin/env python3
"""Tap the installed iOS app on a physical device and audit navigation feedback."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def sign_runner(products, bundle_id, team, identity):
    profiles = Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles"
    for path in profiles.glob("*.mobileprovision"):
        profile = plistlib.loads(subprocess.check_output(
            ["security", "cms", "-D", "-i", str(path)], stderr=subprocess.DEVNULL))
        if profile["Entitlements"].get("application-identifier") == team + "." + bundle_id:
            break
    else:
        raise RuntimeError("No existing development profile for " + bundle_id)
    identities = subprocess.check_output(["security", "find-identity", "-v", "-p", "codesigning"], text=True)
    identity = identity.upper()
    assert identity in identities, "Signing identity is unavailable"
    assert identity in [hashlib.sha1(cert).hexdigest().upper() for cert in profile["DeveloperCertificates"]], \
        "Signing identity is not included in the verification profile"
    runner = products / "Debug-iphoneos/BlotTabUITests-Runner.app"
    info = runner / "Info.plist"
    metadata = plistlib.loads(info.read_bytes())
    metadata["CFBundleIdentifier"] = bundle_id
    info.write_bytes(plistlib.dumps(metadata))
    shutil.copy2(path, runner / "embedded.mobileprovision")
    entitlements = products / "runner-entitlements.plist"
    entitlements.write_bytes(plistlib.dumps(profile["Entitlements"]))
    children = [p for p in runner.rglob("*") if p.suffix in (".framework", ".xctest", ".dylib")]
    for child in sorted(children, key=lambda p: len(p.parts), reverse=True):
        subprocess.run(["codesign", "--force", "--sign", identity, str(child)], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["codesign", "--force", "--sign", identity, "--entitlements", str(entitlements),
                    str(runner)], check=True, stdout=subprocess.DEVNULL)
    configuration = next(products.glob("*.xctestrun"))
    metadata = plistlib.loads(configuration.read_bytes())
    metadata["BlotTabUITests"]["TestHostBundleIdentifier"] = bundle_id
    configuration.write_bytes(plistlib.dumps(metadata))
    return configuration


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device-udid", required=True)
    parser.add_argument("--team")
    parser.add_argument("--signing-identity", required=True, help="SHA-1 of the installed app's trusted signing certificate")
    parser.add_argument("--runner-bundle-id", default="yaroslavstrelkov.blot-agent.workspace-verification",
                        help="Existing dedicated verification app profile; this test replaces that app")
    args = parser.parse_args()
    team = args.team
    if not team:
        settings = subprocess.check_output(
            ["xcodebuild", "-project", "apps/Blot.xcodeproj", "-scheme", "BlotIOS",
             "-showBuildSettings", "-json"], cwd=ROOT, stderr=subprocess.DEVNULL)
        team = json.loads(settings)[0]["buildSettings"]["DEVELOPMENT_TEAM"]
    directory = ROOT / ".build/ios-tab-ui"
    project = directory / "BlotTabUITests.xcodeproj"
    schemes = project / "xcshareddata/xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)
    sources = ROOT / "apps/verification/WorkspaceUITests"
    text = f'''// !$*UTF8*$!
{{
 archiveVersion = 1; classes = {{}}; objectVersion = 77;
 objects = {{
  A10000000000000000000001 = {{ isa = PBXProject; attributes = {{ LastUpgradeCheck = 2700; }}; buildConfigurationList = A10000000000000000000009; compatibilityVersion = "Xcode 16.0"; developmentRegion = en; knownRegions = (en, Base,); mainGroup = A10000000000000000000002; productRefGroup = A10000000000000000000003; projectDirPath = ""; projectRoot = ""; targets = (A10000000000000000000004,); }};
  A10000000000000000000002 = {{ isa = PBXGroup; children = (A10000000000000000000005, A10000000000000000000003,); sourceTree = "<group>"; }};
  A10000000000000000000003 = {{ isa = PBXGroup; name = Products; children = (A10000000000000000000006,); sourceTree = "<group>"; }};
  A10000000000000000000004 = {{ isa = PBXNativeTarget; buildConfigurationList = A1000000000000000000000A; buildPhases = (A10000000000000000000007,A10000000000000000000008,); buildRules = (); dependencies = (); fileSystemSynchronizedGroups = (A10000000000000000000005,); name = BlotTabUITests; productName = BlotTabUITests; productReference = A10000000000000000000006; productType = "com.apple.product-type.bundle.ui-testing"; }};
  A10000000000000000000005 = {{ isa = PBXFileSystemSynchronizedRootGroup; path = "{sources}"; sourceTree = "<absolute>"; }};
  A10000000000000000000006 = {{ isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = BlotTabUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};
  A10000000000000000000007 = {{ isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};
  A10000000000000000000008 = {{ isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};
  A10000000000000000000009 = {{ isa = XCConfigurationList; buildConfigurations = (A1000000000000000000000B,); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug; }};
  A1000000000000000000000A = {{ isa = XCConfigurationList; buildConfigurations = (A1000000000000000000000C,); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug; }};
  A1000000000000000000000B = {{ isa = XCBuildConfiguration; name = Debug; buildSettings = {{ CLANG_ENABLE_MODULES = YES; IPHONEOS_DEPLOYMENT_TARGET = 26.0; SDKROOT = iphoneos; SWIFT_VERSION = 5.0; SWIFT_OPTIMIZATION_LEVEL = "-Onone"; }}; }};
  A1000000000000000000000C = {{ isa = XCBuildConfiguration; name = Debug; buildSettings = {{ CODE_SIGN_STYLE = Automatic; DEVELOPMENT_TEAM = {team}; GENERATE_INFOPLIST_FILE = YES; PRODUCT_NAME = "$(TARGET_NAME)"; PRODUCT_BUNDLE_IDENTIFIER = "yaroslavstrelkov.blot-agent.tab-ui-tests"; SUPPORTED_PLATFORMS = iphoneos; TARGETED_DEVICE_FAMILY = 1; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks @loader_path/Frameworks"; }}; }};
 }};
 rootObject = A10000000000000000000001;
}}
'''
    (project / "project.pbxproj").write_text(text)
    reference = '<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="A10000000000000000000004" BuildableName="BlotTabUITests.xctest" BlueprintName="BlotTabUITests" ReferencedContainer="container:BlotTabUITests.xcodeproj"/>'
    (schemes / "BlotTabUITests.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
 <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">{reference}</BuildActionEntry></BuildActionEntries></BuildAction>
 <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB"><Testables><TestableReference skipped="NO" parallelizable="NO">{reference}</TestableReference></Testables></TestAction>
</Scheme>''')
    log_path = directory / "tests.log"
    derived = directory / "DerivedData"
    with (directory / "build.log").open("w") as log:
        result = subprocess.run(
            ["xcodebuild", "-project", str(project), "-scheme", "BlotTabUITests",
             "-destination", "platform=iOS,id=" + args.device_udid,
             "-derivedDataPath", str(derived), "CODE_SIGNING_ALLOWED=NO", "build-for-testing"],
            cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        print("FAIL", directory / "build.log")
        return result.returncode
    configuration = sign_runner(derived / "Build/Products", args.runner_bundle_id, team, args.signing_identity)
    with log_path.open("w") as log:
        result = subprocess.run(
            ["xcodebuild", "test-without-building", "-xctestrun", str(configuration),
             "-destination", "platform=iOS,id=" + args.device_udid, "-derivedDataPath", str(derived)],
            cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        print("FAIL", log_path)
        return result.returncode
    trace_path = directory / "tab-interactions.json"
    subprocess.run(
        ["xcrun", "devicectl", "device", "copy", "from", "--device", args.device_udid,
         "--domain-type", "appDataContainer", "--domain-identifier", "yaroslavstrelkov.blot-agent.ios",
         "--source", "Library/Caches/tab-interactions.json", "--destination", str(trace_path)],
        check=True, stdout=subprocess.DEVNULL)
    expected = re.search(r'BLOT_TAB_UI_EXPECTED_COUNTS=(\{[^\r\n]+\})', log_path.read_text())
    assert expected, "UI test did not publish its input counts"
    expected = json.loads(expected.group(1))
    trace = json.loads(trace_path.read_text())
    assert dict(Counter(event["route"] for event in trace["taps"])) == expected, trace
    assert [event["sequence"] for event in trace["taps"]] == list(range(1, sum(expected.values()) + 1)), trace
    assert trace["feedback"] == trace["taps"], "Feedback requests must match physical taps exactly"
    assert dict(Counter(event["route"] for event in trace["playbacks"])) == expected, "Every tap must reach its mounted icon"
    for route, count in expected.items():
        assert [event["sequence"] for event in trace["playbacks"] if event["route"] == route] == list(range(1, count + 1)), trace
    print("PASS:", len(trace["taps"]), "physical taps,", len(trace["playbacks"]), "icon activations,", len(trace["feedback"]), "feedback requests")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
