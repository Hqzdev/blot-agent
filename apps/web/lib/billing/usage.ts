import { randomUUID } from 'node:crypto';
import { DatabaseConnectionProvider } from '@teya/database/connection';

const limits = {
  free: [100000, 400000],
  premium: [250000, 1250000],
  super: [500000, 2500000],
  ultra: [1000000, 5000000],
} as const;
const durations = [5, 168] as const;
const database = () => new DatabaseConnectionProvider().get().client;
const listed = (owner: string) =>
  (process.env.BLOT_QUOTA_PILOT_IDS ?? '')
    .toLowerCase()
    .split(',')
    .some((id) => id.trim() === owner.toLowerCase());

export async function pilot(owner: string) {
  if (listed(owner)) return true;
  const [row] =
    await database()`SELECT 1 FROM billing.quota_pilots WHERE user_id=${owner}`;
  return !!row;
}

export class QuotaExceeded extends Error {
  constructor(readonly resetsAt: Date) {
    super(
      'Лимит использования исчерпан. Доступ восстановится ' +
        resetsAt.toISOString(),
    );
  }
}
async function policy(owner: string) {
  const sql = database();
  const [row] = await sql`SELECT
    (SELECT plan FROM billing.test_subscriptions WHERE user_id=${owner} AND valid_until>now()) AS test,
    (SELECT plan FROM billing.subscriptions WHERE user_id=${owner} AND status='active'
      AND (valid_until IS NULL OR valid_until>now())) AS live`;
  const test = (await pilot(owner)) && !!row.test;
  const plan = (test ? row.test : row.live) ?? 'free';
  return {
    plan,
    test,
    caps: limits[plan as keyof typeof limits] ?? limits.ultra,
  };
}
export async function usageOverview(owner: string) {
  const { plan, test, caps } = await policy(owner);
  const rows =
    await database()`SELECT hours, used, starts_at + hours * interval '1 hour' AS ends
    FROM billing.usage_windows WHERE user_id=${owner} AND starts_at + hours * interval '1 hour' > now()`;
  return {
    plan,
    test,
    enforced: await pilot(owner),
    windows: durations.map((hours, i) => {
      const row = rows.find((r) => r.hours === hours);
      return {
        hours,
        percent: Math.min(
          100,
          Math.floor((Number(row?.used ?? 0) * 100) / caps[i]),
        ),
        resetsAt: row?.ends ?? null,
      };
    }),
  };
}
export async function reserveUsage(owner: string, amount: number) {
  const { caps } = await policy(owner);
  const id = randomUUID();
  await database().begin(async (sql) => {
    await sql`SELECT pg_advisory_xact_lock(hashtextextended(${owner},27))`;
    const starts: Date[] = [];
    const blocked: Date[] = [];
    for (const [i, hours] of durations.entries()) {
      const [row] =
        await sql`INSERT INTO billing.usage_windows AS w (user_id,hours,starts_at,used)
        VALUES (${owner},${hours},date_trunc('milliseconds',now()),${amount})
        ON CONFLICT(user_id,hours) DO UPDATE SET
        starts_at=CASE WHEN w.starts_at+w.hours*interval '1 hour'<=now() THEN date_trunc('milliseconds',now()) ELSE w.starts_at END,
        used=CASE WHEN w.starts_at+w.hours*interval '1 hour'<=now() THEN EXCLUDED.used ELSE w.used+EXCLUDED.used END
        RETURNING used,starts_at,starts_at+hours*interval '1 hour' AS ends`;
      starts.push(row.starts_at);
      if (Number(row.used) > caps[i]) blocked.push(row.ends);
    }
    if (blocked.length)
      throw new QuotaExceeded(
        new Date(Math.max(...blocked.map((d) => d.getTime()))),
      );
    await sql`INSERT INTO billing.usage_reservations(id,user_id,short_start,week_start,amount)
      VALUES (${id},${owner},${starts[0]},${starts[1]},${amount})`;
  });
  return id;
}
export async function settleUsage(owner: string, id: string, actual: number) {
  await database().begin(async (sql) => {
    await sql`SELECT pg_advisory_xact_lock(hashtextextended(${owner},27))`;
    const [r] =
      await sql`DELETE FROM billing.usage_reservations WHERE user_id=${owner} AND id=${id} RETURNING *`;
    if (!r) return;
    await sql`UPDATE billing.usage_windows SET used=used+${actual - Number(r.amount)}
      WHERE user_id=${owner} AND ((hours=5 AND starts_at=${r.short_start}) OR (hours=168 AND starts_at=${r.week_start}))`;
  });
}
