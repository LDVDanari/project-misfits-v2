// MySQL / MariaDB connection for the store tables (db/pmv2_store.sql).
// Point it at the same database your FiveM server uses.
import mysql from 'mysql2/promise';

let pool = null;

export function dbReady() {
  return Boolean(process.env.DATABASE_URL || (process.env.DB_HOST && process.env.DB_USER && process.env.DB_NAME));
}

export function getPool() {
  if (!dbReady()) throw new Error('Store database is not configured.');
  if (!pool) {
    const common = {
      waitForConnections: true,
      connectionLimit: Number(process.env.DB_POOL_SIZE || 5),
      charset: 'utf8mb4',
      timezone: 'Z',
      supportBigNumbers: true,
      bigNumberStrings: false,
      ...(String(process.env.DB_SSL || '').toLowerCase() === 'true' ? { ssl: { rejectUnauthorized: true } } : {})
    };
    pool = process.env.DATABASE_URL
      ? mysql.createPool({ uri: process.env.DATABASE_URL, ...common })
      : mysql.createPool({
          host: process.env.DB_HOST,
          port: Number(process.env.DB_PORT || 3306),
          user: process.env.DB_USER,
          password: process.env.DB_PASSWORD || '',
          database: process.env.DB_NAME,
          ...common
        });
  }
  return pool;
}

export async function query(sql, params = []) {
  const [rows] = await getPool().execute(sql, params);
  return rows;
}

// Runs fn(conn) inside a transaction. Rolls back if fn throws.
export async function withTransaction(fn) {
  const conn = await getPool().getConnection();
  try {
    await conn.beginTransaction();
    const result = await fn(conn);
    await conn.commit();
    return result;
  } catch (e) {
    try { await conn.rollback(); } catch { /* connection already gone */ }
    throw e;
  } finally {
    conn.release();
  }
}

export const isDuplicate = e => e && (e.code === 'ER_DUP_ENTRY' || e.errno === 1062);
