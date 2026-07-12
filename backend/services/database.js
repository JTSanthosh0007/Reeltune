const { Pool } = require('pg');
const sqlite3 = require('sqlite3').verbose();
const path = require('path');

let pool = null;
let sqliteDb = null;
const usePostgres = !!process.env.DATABASE_URL;

if (usePostgres) {
  pool = new Pool({
    connectionString: process.env.DATABASE_URL,
    ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
    max: 20, // Connection pool size
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 2000,
  });

  pool.on('error', (err) => {
    console.error('[DB] Unexpected error on idle client', err);
  });
} else {
  console.log('[DB] DATABASE_URL is not set. Using local SQLite database fallback...');
  const dbPath = path.join(__dirname, '..', 'reeltune_local.db');
  sqliteDb = new sqlite3.Database(dbPath, (err) => {
    if (err) {
      console.error('[DB] Failed to open local SQLite database:', err.message);
    } else {
      console.log('[DB] Local SQLite database opened successfully.');
    }
  });
}

// Initialize tables
async function initDb() {
  if (usePostgres) {
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
  } else {
    sqliteDb.serialize(() => {
      sqliteDb.run(`
        CREATE TABLE IF NOT EXISTS devices (
          device_id TEXT PRIMARY KEY,
          fcm_token TEXT NOT NULL,
          platform TEXT NOT NULL,
          updated_at INTEGER NOT NULL
        );
      `, (err) => {
        if (err) {
          console.error('[DB] SQLite devices table creation failed:', err.message);
        } else {
          console.log('[DB] SQLite devices table initialized successfully.');
        }
      });
    });
  }
}

initDb();

function query(text, params) {
  if (usePostgres) {
    return pool.query(text, params);
  } else {
    return new Promise((resolve, reject) => {
      // Map postgres style parameterized queries ($1, $2, ...) to SQLite style (?)
      const sql = text.replace(/\$\d+/g, '?');
      sqliteDb.all(sql, params || [], (err, rows) => {
        if (err) {
          reject(err);
        } else {
          resolve({ rows });
        }
      });
    });
  }
}

module.exports = {
  query,
  pool
};
