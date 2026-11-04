export const betaRelease = {
  version: "1.0 Beta",
  tag: "v1.0.0-beta.1",
  date: "2026-11-04",
  repository: "https://github.com/Hqzdev/blot-releases",
  url: "https://github.com/Hqzdev/blot-releases/releases/tag/v1.0.0-beta.1",
};

export const releasePlatforms = [
  { id: "macos", name: "macOS", file: "Blot-1.0-Beta-macOS-arm64.dmg", format: "DMG", detail: "Your desktop workspace for agents, chats, files, and projects.", requirements: "Apple Silicon · macOS 26 or later", installation: "Open the DMG and drag Blot into Applications. This beta is ad hoc signed and is not notarized by Apple; macOS may require approval in System Settings → Privacy & Security." },
  { id: "ios", name: "iOS", file: "Blot-1.0-Beta-iOS.ipa", format: "IPA", detail: "Your agents and conversations on iPhone.", requirements: "iOS 26 or later · requires your own signing", installation: "This IPA is unsigned. Sign it with your own Apple developer identity using your sideloading tool before installing. It cannot be installed by tapping the downloaded file and is not an App Store or TestFlight release." },
  { id: "android", name: "Android", detail: "The Java Android application is in development." },
  { id: "windows", name: "Windows", detail: "The Windows application is in development." },
];

export function releaseDownload(platform) {
  const file = releasePlatforms.find(item => item.id === platform)?.file;
  return file ? `${betaRelease.repository}/releases/download/${betaRelease.tag}/${file}` : null;
}
