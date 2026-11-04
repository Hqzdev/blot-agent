import { createHash, createHmac, randomBytes, randomInt, scrypt, timingSafeEqual } from "node:crypto";
import { promisify } from "node:util";
import { AuthError } from "../auth/errors.mjs";

const derive = promisify(scrypt);
export const randomToken = () => randomBytes(32).toString("base64url");
export const digest = value => createHash("sha256").update(value).digest("hex");
export const validToken = value => typeof value === "string" && /^[A-Za-z0-9_-]{43}$/.test(value);
export const validID = value => typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
export function equal(a, b) {
  const left = Buffer.from(a), right = Buffer.from(b);
  return left.length === right.length && timingSafeEqual(left, right);
}
export function emailAddress(value) {
  if (typeof value !== "string" || value.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)) throw new AuthError("invalid_email");
  return value.toLowerCase();
}
export function passwordValue(value) {
  if (typeof value !== "string" || value.length < 8 || value.length > 128) throw new AuthError("invalid_password");
  return value;
}

export class PasswordHasher {
  #dummy;
  async hash(password) {
    const salt = randomBytes(16).toString("hex");
    const key = await derive(password, salt, 32, { N: 65536, r: 8, p: 2, maxmem: 128 * 1024 * 1024 });
    return `scrypt$${salt}$${key.toString("hex")}`;
  }
  async matches(password, hash) {
    this.#dummy ??= this.hash(randomToken());
    const saved = hash || await this.#dummy;
    const [, salt, expected] = saved.split("$");
    const key = await derive(password, salt, 32, { N: 65536, r: 8, p: 2, maxmem: 128 * 1024 * 1024 });
    return equal(key.toString("hex"), expected) && Boolean(hash);
  }
}

export class EmailCodeSecurity {
  #secret;
  constructor(secret) {
    if (!secret || secret.length < 32) throw new AuthError("web_session_unconfigured", 503);
    this.#secret = secret;
  }
  code() { return randomInt(1_000_000).toString().padStart(6, "0"); }
  hash(id, code) { return createHmac("sha256", this.#secret).update(`${id}:${code}`).digest("hex"); }
}

export class AccountRateLimiter {
  #database;
  constructor(database) { this.#database = database; }
  async check(key, limit, seconds) {
    // Only keyed digests persist; emails and IP addresses are absent from rate-limit records.
    const result = await this.#database.query(`
      INSERT INTO blot_auth_rates(key, count, expires_at) VALUES ($1, 1, now() + $2 * interval '1 second')
      ON CONFLICT(key) DO UPDATE SET
        count = CASE WHEN blot_auth_rates.expires_at <= now() THEN 1 ELSE blot_auth_rates.count + 1 END,
        expires_at = CASE WHEN blot_auth_rates.expires_at <= now() THEN EXCLUDED.expires_at ELSE blot_auth_rates.expires_at END
      RETURNING count`, [digest(key), seconds]);
    if (result.rows[0].count > limit) throw new AuthError(seconds === 60 ? "challenge_cooldown" : "rate_limited", 429);
  }
}
