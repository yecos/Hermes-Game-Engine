import { getPool } from './_lib/db.js';

export default async function handler(_req, res) {
  if (!process.env.DATABASE_URL) return res.status(503).json({ ok: false, database: false });
  try {
    const pool = getPool();
    const result = await pool.query('select current_database() as database, now() as now');
    res.status(200).json({ ok: true, database: result.rows[0]?.database, storage: Boolean(process.env.AWS_ENDPOINT_URL_S3) });
  } catch (error) {
    res.status(503).json({ ok: false, error: error.message });
  }
}
