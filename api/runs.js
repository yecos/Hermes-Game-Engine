import { requireApiToken } from './_lib/auth.js';
import { getPool } from './_lib/db.js';

export default async function handler(req, res) {
  if (!requireApiToken(req, res)) return;
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });
  const run = req.body ?? {};
  const pool = getPool();
  try {
    if (run.runType === 'test') {
      await pool.query(
        `insert into hge_test_runs (id, project_id, scene_id, status, summary, events, metrics, created_at)
         values ($1,$2,$3,$4,$5,$6::jsonb,$7::jsonb,$8::timestamptz)
         on conflict (id) do nothing`,
        [run.id, run.projectId, run.sceneId ?? null, run.status ?? 'unknown', run.summary ?? null, JSON.stringify(run.events ?? []), JSON.stringify(run.metrics ?? {}), run.createdAt ?? new Date().toISOString()]
      );
    } else {
      await pool.query(
        `insert into hge_agent_runs (id, project_id, run_type, prompt, plan, result, status, started_at, finished_at)
         values ($1,$2,$3,$4,$5::jsonb,$6::jsonb,$7,$8::timestamptz,$9::timestamptz)
         on conflict (id) do nothing`,
        [run.id, run.projectId ?? null, run.runType ?? 'hermes', run.prompt ?? null, JSON.stringify(run.plan ?? []), JSON.stringify(run.result ?? {}), run.status ?? 'complete', run.startedAt ?? new Date().toISOString(), run.finishedAt ?? null]
      );
    }
    res.status(200).json({ ok: true });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
}
