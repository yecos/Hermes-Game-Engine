import { Pool } from '@neondatabase/serverless';

let pool;

export function getPool() {
  if (!process.env.DATABASE_URL) throw new Error('DATABASE_URL is not configured');
  if (!pool) pool = new Pool({ connectionString: process.env.DATABASE_URL, max: 2 });
  return pool;
}

export async function withClient(fn) {
  const client = await getPool().connect();
  try { return await fn(client); }
  finally { client.release(); }
}
