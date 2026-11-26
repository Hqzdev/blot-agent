export const webBasePath = '/app';
export function webPath(path: string): string {
  return path === webBasePath ||
    path.startsWith(`${webBasePath}/`) ||
    path.startsWith(`${webBasePath}?`)
    ? path
    : `${webBasePath}${path.startsWith('/') ? path : `/${path}`}`;
}
