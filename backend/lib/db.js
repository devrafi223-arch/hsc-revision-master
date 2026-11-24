// Shared Postgres pool for Vercel serverless functions.
// Uses the pooled connection string when available (best for serverless),
// falls back to the direct URL. Prisma Postgres requires SSL.
const { Pool } = require('pg');

let pool = null;

function getPool() {
  if (pool) return pool;
  const connectionString =
    process.env.DATABASE_URL_POOLED ||
    process.env.POSTGRES_URL ||
    process.env.DATABASE_URL;
  if (!connectionString) {
    throw Object.assign(new Error('DATABASE_URL / POSTGRES_URL is not set'), {
      code: 'DB_NOT_CONFIGURED',
    });
  }
  pool = new Pool({
    connectionString,
    ssl: { rejectUnauthorized: false },
    max: 5,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 10000,
  });
  pool.on('error', (err) => console.error('[db] idle pool error', err.message));
  return pool;
}

async function query(text, params) {
  const client = getPool();
  return client.query(text, params);
}

module.exports = { getPool, query };
