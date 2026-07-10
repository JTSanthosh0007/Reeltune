const { Pool } = require('pg');

// Use Render's Internal Database URL (or external if local)
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
  max: 20, // Connection pool size
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

pool.on('error', (err) => {
  console.error('[DB] Unexpected error on idle client', err);
});

// Initialize tables
async function initDb() {
  if (!process.env.DATABASE_URL) {
    console.warn('[DB] DATABASE_URL is not set. Skipping Postgres initialization.');
    return;
  }
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS devices (
        device_id TEXT PRIMARY KEY,
        fcm_token TEXT NOT NULL,
        platform TEXT NOT NULL,
        updated_at BIGINT NOT NULL
      );
    `);
    console.log('[DB] PostgreSQL initialized successfully.');
  } catch (err) {
    console.error('[DB] Initialization failed:', err.message);
  }
}

initDb();

module.exports = {
  query: (text, params) => pool.query(text, params),
  pool
};
