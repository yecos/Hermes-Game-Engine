CREATE TABLE IF NOT EXISTS hge_projects (
  id text PRIMARY KEY,
  name text NOT NULL,
  version text NOT NULL DEFAULT '0.3.0',
  current_scene_id text,
  snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS hge_scenes (
  id text PRIMARY KEY,
  project_id text NOT NULL REFERENCES hge_projects(id) ON DELETE CASCADE,
  name text NOT NULL,
  sort_order integer NOT NULL DEFAULT 0,
  settings jsonb NOT NULL DEFAULT '{}'::jsonb,
  tilemap jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS hge_entities (
  id text PRIMARY KEY,
  scene_id text NOT NULL REFERENCES hge_scenes(id) ON DELETE CASCADE,
  type text NOT NULL,
  name text NOT NULL,
  x double precision NOT NULL DEFAULT 0,
  y double precision NOT NULL DEFAULT 0,
  rotation double precision NOT NULL DEFAULT 0,
  color text,
  props jsonb NOT NULL DEFAULT '{}'::jsonb,
  behaviors jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS hge_behaviors (
  id text PRIMARY KEY,
  project_id text NOT NULL REFERENCES hge_projects(id) ON DELETE CASCADE,
  name text NOT NULL,
  kind text NOT NULL,
  config jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS hge_assets (
  id text PRIMARY KEY,
  project_id text NOT NULL REFERENCES hge_projects(id) ON DELETE CASCADE,
  kind text NOT NULL,
  name text NOT NULL,
  prompt text,
  provider text,
  model text,
  storage_key text,
  public_url text,
  status text NOT NULL DEFAULT 'pending',
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS hge_agent_runs (
  id text PRIMARY KEY,
  project_id text REFERENCES hge_projects(id) ON DELETE CASCADE,
  run_type text NOT NULL,
  prompt text,
  plan jsonb NOT NULL DEFAULT '[]'::jsonb,
  result jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'pending',
  started_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz
);

CREATE TABLE IF NOT EXISTS hge_test_runs (
  id text PRIMARY KEY,
  project_id text NOT NULL REFERENCES hge_projects(id) ON DELETE CASCADE,
  scene_id text REFERENCES hge_scenes(id) ON DELETE SET NULL,
  status text NOT NULL,
  summary text,
  events jsonb NOT NULL DEFAULT '[]'::jsonb,
  metrics jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS hge_scenes_project_idx ON hge_scenes(project_id, sort_order);
CREATE INDEX IF NOT EXISTS hge_entities_scene_idx ON hge_entities(scene_id);
CREATE INDEX IF NOT EXISTS hge_assets_project_idx ON hge_assets(project_id, created_at DESC);
CREATE INDEX IF NOT EXISTS hge_agent_runs_project_idx ON hge_agent_runs(project_id, started_at DESC);
CREATE INDEX IF NOT EXISTS hge_test_runs_project_idx ON hge_test_runs(project_id, created_at DESC);
