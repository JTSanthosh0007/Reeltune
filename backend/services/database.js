const sqlite3 = require('sqlite3').verbose();
const path = require('path');

const dbPath = path.join(__dirname, '..', 'devices.db');
const db = new sqlite3.Database(dbPath);

db.serialize(() => {
  db.run(`
    CREATE TABLE IF NOT EXISTS devices (
      device_id TEXT PRIMARY KEY,
      fcm_token TEXT NOT NULL,
      platform TEXT NOT NULL,
      updated_at INTEGER NOT NULL
    )
  `);
});

module.exports = db;
