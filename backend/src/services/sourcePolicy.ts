const BLOCKED_HOSTS = new Set([
  "localhost",
  "127.0.0.1",
  "0.0.0.0",
  "::1",
  "[::1]"
]);

const PRIVATE_IP_PATTERNS = [
  /^10\./,
  /^127\./,
  /^169\.254\./,
  /^172\.(1[6-9]|2[0-9]|3[0-1])\./,
  /^192\.168\./
];

export function parseRecipeURL(rawURL: string): URL | null {
  try {
    const url = new URL(rawURL);
    const protocol = url.protocol.toLowerCase();
    if (protocol !== "https:" && protocol !== "http:") {
      return null;
    }

    if (!url.hostname || isBlockedHost(url.hostname)) {
      return null;
    }

    return url;
  } catch {
    return null;
  }
}

export function isURLAllowedByWhitelist(url: URL, whitelist: readonly string[]): boolean {
  const host = url.hostname.toLowerCase();
  if (isBlockedHost(host)) {
    return false;
  }

  if (!whitelist.length) {
    return false;
  }

  return whitelist.some((allowedDomain) => {
    const domain = allowedDomain.toLowerCase();
    return host === domain || host.endsWith(`.${domain}`);
  });
}

function isBlockedHost(hostname: string): boolean {
  const normalized = hostname.toLowerCase();
  if (BLOCKED_HOSTS.has(normalized)) {
    return true;
  }

  if (PRIVATE_IP_PATTERNS.some((pattern) => pattern.test(normalized))) {
    return true;
  }

  return false;
}
