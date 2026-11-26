import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';

export class WebDatabaseMigrator {
  constructor(query, directory = new URL('../migrations/', import.meta.url)) {
    this.query = query;
    this.directory = directory;
  }

  async migrate() {
    const journal = JSON.parse(
      await readFile(new URL('meta/_journal.json', this.directory), 'utf8'),
    );
    await this.query('BEGIN');
    try {
      await this.query('SELECT pg_advisory_xact_lock(170112, 2)');
      const managed = await this.query(
        "SELECT to_regclass('blot_web.migrations') AS journal",
      );
      if (!managed.rows[0].journal) {
        const existing = await this.query(
          "SELECT table_schema, table_name FROM information_schema.tables WHERE table_schema IN ('identity','conversation','billing','ai') AND table_type = 'BASE TABLE'",
        );
        if (existing.rows.length)
          throw new Error(
            'Existing web schemas require an explicit migration baseline; no changes applied',
          );
      }
      await this.query('CREATE SCHEMA IF NOT EXISTS blot_web');
      await this.query(
        'CREATE TABLE IF NOT EXISTS blot_web.migrations (tag text PRIMARY KEY, hash text NOT NULL, applied_at timestamptz NOT NULL DEFAULT now())',
      );
      const applied = await this.query(
        'SELECT tag, hash FROM blot_web.migrations',
      );
      const hashes = new Map(applied.rows.map((row) => [row.tag, row.hash]));
      const files = await Promise.all(
        journal.entries.map(async (entry) => {
          const sql = await readFile(
            new URL(`${entry.tag}.sql`, this.directory),
            'utf8',
          );
          const hash = createHash('sha256').update(sql).digest('hex');
          if (hashes.has(entry.tag) && hashes.get(entry.tag) !== hash)
            throw new Error(
              'An applied web migration has changed; no changes applied',
            );
          return { tag: entry.tag, hash, sql };
        }),
      );
      const known = new Set(files.map((file) => file.tag));
      if ([...hashes.keys()].some((tag) => !known.has(tag)))
        throw new Error(
          'Database has newer web migrations; no changes applied',
        );
      const pending = files.filter((file) => !hashes.has(file.tag));
      for (const file of pending) {
        await this.query(file.sql);
        await this.query(
          'INSERT INTO blot_web.migrations(tag,hash) VALUES ($1,$2)',
          [file.tag, file.hash],
        );
      }
      await this.query('COMMIT');
      return pending.map((file) => file.tag);
    } catch (error) {
      await this.query('ROLLBACK');
      throw error;
    }
  }
}
