export function providerAvatarURL(value, provider) {
  if (typeof value !== "string" || value.length > 2048) return null;
  try {
    const url = new URL(value);
    const google = url.hostname === "googleusercontent.com" || url.hostname.endsWith(".googleusercontent.com")
      || url.hostname === "ggpht.com" || url.hostname.endsWith(".ggpht.com");
    if (url.protocol !== "https:" || url.username || url.password || url.hash || url.port
        || !(provider === "google" ? google : provider === "yandex" && url.hostname === "avatars.yandex.net")) return null;
    return url.href;
  } catch { return null; }
}

export function yandexAvatarURL(profile) {
  const id = profile.default_avatar_id;
  if (profile.is_avatar_empty !== false || typeof id !== "string" || (id.length > 255 || !/^[A-Za-z0-9_-]+(?:\/[A-Za-z0-9_-]+)*$/.test(id))) return null;
  return providerAvatarURL(`https://avatars.yandex.net/get-yapic/${id}/islands-200`, "yandex");
}
