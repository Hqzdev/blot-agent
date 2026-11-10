#!/usr/bin/env python3
"""Host production iOS presentation code in an isolated signed XCTest app."""
import argparse
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device-udid", required=True)
    parser.add_argument("--team", help="Defaults to the BlotIOS signing team")
    args = parser.parse_args()
    team = args.team
    if not team:
        settings = subprocess.check_output(["xcodebuild", "-project", "apps/Blot.xcodeproj", "-scheme", "BlotIOS",
                                            "-showBuildSettings", "-json"], cwd=ROOT, stderr=subprocess.DEVNULL)
        team = json.loads(settings)[0]["buildSettings"].get("DEVELOPMENT_TEAM")
    if not team:
        parser.error("Configure the BlotIOS signing team or pass --team")
    directory = ROOT / ".build/ios-chat-lifecycle"
    project = directory / "BlotWorkspaceVerification.xcodeproj"
    schemes = project / "xcshareddata/xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)
    source = ROOT / "apps/verification/BlotWorkspaceVerification.xcodeproj"
    text = (source / "project.pbxproj").read_text()
    paths = {"WorkspaceHost": ROOT / "apps/verification/WorkspaceHost",
             "WorkspaceDeviceTests": ROOT / "apps/verification/WorkspacePresentationTests",
             "../../packages/BlotWorkspace": ROOT / "packages/BlotWorkspace",
             "../../packages/BlotDomain": ROOT / "packages/BlotDomain"}
    for before, after in paths.items():
        text = text.replace('"' + before + '"', '"' + str(after) + '"')
    text = text.replace("fileSystemSynchronizedGroups = (D40000000000000000000009, D4000000000000000000000A,);",
                        "fileSystemSynchronizedGroups = (D40000000000000000000022, D40000000000000000000023, D4000000000000000000000A,);")
    text = text.replace("packageReferences = (D4000000000000000000001C, D4000000000000000000001D,);",
                        "packageReferences = (D4000000000000000000001C, D4000000000000000000001D, D40000000000000000000025, D40000000000000000000026, D4000000000000000000002B, D4000000000000000000002E,);")
    text = text.replace("packageProductDependencies = (D4000000000000000000001E, D4000000000000000000001F,);",
                        "packageProductDependencies = (D4000000000000000000001E, D4000000000000000000001F, D40000000000000000000027, D40000000000000000000028, D4000000000000000000002C, D4000000000000000000002F,);")
    text = text.replace("files = (D40000000000000000000020, D40000000000000000000021,);",
                        "files = (D40000000000000000000020, D40000000000000000000021, D40000000000000000000029, D4000000000000000000002A, D4000000000000000000002D, D40000000000000000000030,);")
    # Product presentation sources use the same isolation and Swift mode as BlotIOS.
    text = text.replace('BUNDLE_LOADER = "$(TEST_HOST)";', 'SWIFT_VERSION = 5.0; SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor; BUNDLE_LOADER = "$(TEST_HOST)";')
    additions = f'''
        D40000000000000000000022 = {{ isa = PBXFileSystemSynchronizedRootGroup; path = "{ROOT}/apps/ios/BlotIOS"; sourceTree = "<absolute>"; exceptions = (D40000000000000000000024,); }};
        D40000000000000000000023 = {{ isa = PBXFileSystemSynchronizedRootGroup; path = "{ROOT}/apps/shared"; sourceTree = "<absolute>"; }};
        D40000000000000000000024 = {{ isa = PBXFileSystemSynchronizedBuildFileExceptionSet; target = D40000000000000000000005; membershipExceptions = (BlotIOSApp.swift,); }};
        D40000000000000000000025 = {{ isa = XCLocalSwiftPackageReference; relativePath = "{ROOT}/packages/BlotAPI"; }};
        D40000000000000000000026 = {{ isa = XCLocalSwiftPackageReference; relativePath = "{ROOT}/packages/BlotDesign"; }};
        D40000000000000000000027 = {{ isa = XCSwiftPackageProductDependency; package = D40000000000000000000025; productName = BlotAPI; }};
        D40000000000000000000028 = {{ isa = XCSwiftPackageProductDependency; package = D40000000000000000000026; productName = BlotDesign; }};
        D40000000000000000000029 = {{ isa = PBXBuildFile; productRef = D40000000000000000000027; }};
        D4000000000000000000002A = {{ isa = PBXBuildFile; productRef = D40000000000000000000028; }};
        D4000000000000000000002E = {{ isa = XCLocalSwiftPackageReference; relativePath = "{ROOT}/packages/BlotWidgetSupport"; }};
        D4000000000000000000002F = {{ isa = XCSwiftPackageProductDependency; package = D4000000000000000000002E; productName = BlotWidgetSupport; }};
        D40000000000000000000030 = {{ isa = PBXBuildFile; productRef = D4000000000000000000002F; }};
'''
    additions += f'''
        D4000000000000000000002B = {{ isa = XCLocalSwiftPackageReference; relativePath = "{ROOT}/packages/BlotAppleIntegrations"; }};
        D4000000000000000000002C = {{ isa = XCSwiftPackageProductDependency; package = D4000000000000000000002B; productName = BlotAppleIntegrations; }};
        D4000000000000000000002D = {{ isa = PBXBuildFile; productRef = D4000000000000000000002C; }};
'''
    text = text.replace("\tobjects = {", "\tobjects = {" + additions)
    (project / "project.pbxproj").write_text(text)
    scheme = "BlotWorkspaceVerification.xcscheme"
    (schemes / scheme).write_bytes((source / "xcshareddata/xcschemes" / scheme).read_bytes())
    with (directory / "tests.log").open("w") as log:
        result = subprocess.run(["xcodebuild", "-project", str(project), "-scheme", "BlotWorkspaceVerification",
                                 "-destination", "platform=iOS,id=" + args.device_udid,
                                 "-derivedDataPath", str(directory / "DerivedData"), "DEVELOPMENT_TEAM=" + team,
                                 "-allowProvisioningUpdates", "test"], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    print("PASS" if result.returncode == 0 else "FAIL", directory / "tests.log")
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
