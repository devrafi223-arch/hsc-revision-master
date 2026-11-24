// Applies scripts/schema.sql to the live Postgres and prints table counts.
// Usage: POSTGRES_URL=<url> node scripts/apply-schema.mjs
// (In CI/ops the URL is passed via env only — never printed, never committed.)
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import pg from 'pg';

const { Client } = pg;
const here = dirname(fileURLToPath(import.meta.url));
const sql = readFileSync(join(here, 'schema.sql'), 'utf8');
const connectionString =
  process.env.DATABASE_URL_POOLED ||
  process.env.POSTGRES_URL ||
  process.env.DATABASE_URL;

if (!connectionString) {
  console.error('ERROR: set POSTGRES_URL (or DATABASE_URL_POOLED / DATABASE_URL).');
  process.exit(1);
}

const client = new Client({ connectionString, ssl: { rejectUnauthorized: false } });
await client.connect();
await client.query(sql);

const { rows } = await client.query(
  `SELECT table_name FROM information_schema.tables
    WHERE table_schema = 'public' AND table_type = 'BASE TABLE' ORDER BY table_name`,
);
console.log('tables:', rows.map((r) => r.table_name).join(', '));
for (const { table_name } of rows) {
  const c = await client.query(`SELECT count(*)::int AS n FROM "${table_name}"`);
  console.log(`${table_name}: ${c.rows[0].n} rows`);
}
await client.end();
console.log('schema OK');
