import assert from 'node:assert/strict';
import { X509Certificate } from 'node:crypto';
import { mkdtemp, rm } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);

test('the deployed Node bundle loads the Supabase root CA with verification enabled', async () => {
  const output = await mkdtemp(join(tmpdir(), 'blot-database-tls-'));
  const nextWebpack = require('next/dist/compiled/webpack/webpack');
  nextWebpack.init();
  try {
    await new Promise<void>((resolve, reject) => {
      nextWebpack.webpack({
        mode: 'production',
        optimization: { minimize: false },
        target: 'node',
        module: { parser: { javascript: { url: 'relative' } } },
        entry: fileURLToPath(new URL('../../packages/database/src/tls.mjs', import.meta.url)),
        output: { path: output, filename: 'tls.cjs', library: { type: 'commonjs2' } },
      }, (error: Error | null, stats: { hasErrors(): boolean; toString(): string }) => {
        if (error || stats.hasErrors()) reject(error ?? new Error(stats.toString()));
        else resolve();
      });
    });
    const { databaseTLS } = require(join(output, 'tls.cjs'));
    const { ssl } = databaseTLS('postgres://test.pooler.supabase.com/db');
    assert.equal(ssl.rejectUnauthorized, true);
    const ca = new X509Certificate(ssl.ca);
    assert.equal(ca.ca, true);
    assert.equal(ca.fingerprint256, '80:70:25:AD:50:D4:ED:21:9D:2C:9C:7D:29:9C:00:4F:82:4E:B0:0C:F7:F6:5A:FE:F6:07:D0:7B:72:E6:CA:FA');
    assert.deepEqual(databaseTLS('postgres://localhost/db'), {});
  } finally {
    await rm(output, { recursive: true, force: true });
  }
});
