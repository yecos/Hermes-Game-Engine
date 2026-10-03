import fs from 'node:fs';
import { neon } from '@neondatabase/serverless';

const url = process.env.DATABASE_URL;
if (!url) throw new Error('DATABASE_URL is missing');

const sql = neon(url);
const schema = fs.readFileSync(new URL('../db/schema.sql', import.meta.url), 'utf8');
const statements = schema.split(';').map((s) => s.trim()).filter(Boolean);
for (const statement of statements) await sql.query(statement);

const result = await sql.query(
  "select count(*)::int as count from information_schema.tables where table_schema='public' and table_name like 'hge_%'"
);
console.log(`HGE_SCHEMA_OK tables=${result[0].count}`);
