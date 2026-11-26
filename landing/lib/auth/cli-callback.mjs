export function isCliCallback(clientID, redirectURI) {
  if (clientID !== "blot-cli" || typeof redirectURI !== "string") return false;
  const match = /^http:\/\/127\.0\.0\.1:([1-9][0-9]{0,4})\/oauth\/blot$/.exec(redirectURI);
  return Boolean(match && Number(match[1]) >= 1024 && Number(match[1]) <= 65535);
}
