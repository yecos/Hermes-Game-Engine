import { requireApiToken } from './_lib/auth.js';
import { withClient, getPool } from './_lib/db.js';

const json = (value) => value ?? {};
const projectRow = (row) => row ? row.snapshot : null;

export default async function handler(req, res) {
  if (!requireApiToken(req, res)) return;

  if (req.method === 'GET') {
    const id = String(req.query?.id ?? '');
    const pool = getPool();
    if (id) {
      const result = await pool.query('select snapshot from hge_projects where id = $1 limit 1', [id]);
      if (!result.rows[0]) return res.status(404).json({ error: 'Project not found' });
      return res.status(200).json({ project: projectRow(result.rows[0]) });
    }
    const result = await pool.query('select id, name, version, current_scene_id as "currentSceneId", updated_at as "updatedAt" from hge_projects order by updated_at desc limit 50');
    return res.status(200).json({ projects: result.rows });
  }

  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });
  const project = req.body?.project;
  if (!project?.id || !project?.name || !Array.isArray(project.scenes)) return res.status(400).json({ error: 'Invalid project payload' });

  try {
    await withClient(async (client) => {
      await client.query('begin');
      try {
        await client.query(
          `insert into hge_projects (id, name, version, current_scene_id, snapshot, metadata, updated_at)
           values ($1,$2,$3,$4,$5::jsonb,$6::jsonb,now())
           on conflict (id) do update set name=excluded.name, version=excluded.version, current_scene_id=excluded.current_scene_id,
             snapshot=excluded.snapshot, metadata=excluded.metadata, updated_at=now()`,
          [project.id, project.name, project.version ?? '0.3.0', project.currentSceneId ?? null, JSON.stringify(project), JSON.stringify(project.metadata ?? {})]
        );

        await client.query('delete from hge_entities where scene_id in (select id from hge_scenes where project_id = $1)', [project.id]);
        await client.query('delete from hge_scenes where project_id = $1', [project.id]);
        await client.query('delete from hge_behaviors where project_id = $1', [project.id]);

        for (let i = 0; i < project.scenes.length; i++) {
          const scene = project.scenes[i];
          await client.query(
            `insert into hge_scenes (id, project_id, name, sort_order, settings, tilemap, updated_at)
             values ($1,$2,$3,$4,$5::jsonb,$6::jsonb,now())`,
            [scene.id, project.id, scene.name, i, JSON.stringify(scene.settings ?? {}), JSON.stringify(scene.tilemap ?? {})]
          );
          for (const entity of scene.entities ?? []) {
            const { id, type, name, x, y, rotation, color, behaviors, ...props } = entity;
            await client.query(
              `insert into hge_entities (id, scene_id, type, name, x, y, rotation, color, props, behaviors, updated_at)
               values ($1,$2,$3,$4,$5,$6,$7,$8,$9::jsonb,$10::jsonb,now())`,
              [id, scene.id, type, name, x ?? 0, y ?? 0, rotation ?? 0, color ?? null, JSON.stringify(json(props)), JSON.stringify(behaviors ?? [])]
            );
          }
        }

        for (const behavior of project.behaviors ?? []) {
          await client.query(
            `insert into hge_behaviors (id, project_id, name, kind, config, updated_at)
             values ($1,$2,$3,$4,$5::jsonb,now())`,
            [behavior.id, project.id, behavior.name, behavior.kind, JSON.stringify(behavior.config ?? {})]
          );
        }
        await client.query('commit');
      } catch (error) {
        await client.query('rollback');
        throw error;
      }
    });
    res.status(200).json({ ok: true, project: { id: project.id, name: project.name, version: project.version } });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
}
