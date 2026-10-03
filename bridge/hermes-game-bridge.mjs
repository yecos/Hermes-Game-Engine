import http from 'node:http';
import net from 'node:net';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const HOST = process.env.HGE_BRIDGE_HOST || '127.0.0.1';
const PORT = Number(process.env.HGE_BRIDGE_PORT || 8643);
const HERMES_URL = (process.env.HERMES_API_URL || 'http://127.0.0.1:8642').replace(/\/$/, '');
const allowedOrigins = new Set(
  (process.env.HGE_ALLOWED_ORIGINS ||
    'https://hermesgameengine.vercel.app,http://localhost:8080,http://127.0.0.1:8080')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean)
);

function defaultKeyPath() {
  if (process.platform === 'win32') {
    return path.join(process.env.LOCALAPPDATA || path.join(os.homedir(), 'AppData', 'Local'), 'hermes', 'hge-api-server-key.local');
  }
  return path.join(os.homedir(), '.hermes', 'hge-api-server-key.local');
}

function getHermesKey() {
  const keyPath = process.env.HERMES_API_SERVER_KEY_FILE || defaultKeyPath();
  return fs.readFileSync(keyPath, 'utf8').trim();
}

function originAllowed(origin) {
  if (!origin) return true;
  if (allowedOrigins.has(origin)) return true;

  try {
    const url = new URL(origin);
    return (
      url.protocol === 'https:' &&
      url.hostname.startsWith('hermesgameengine-') &&
      url.hostname.endsWith('.vercel.app')
    );
  } catch {
    return false;
  }
}

function corsHeaders(origin) {
  const headers = {
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, X-HGE-Bridge',
    'Access-Control-Allow-Private-Network': 'true',
    'Access-Control-Max-Age': '600',
    'Vary': 'Origin',
    'Cache-Control': 'no-store'
  };
  if (origin && originAllowed(origin)) headers['Access-Control-Allow-Origin'] = origin;
  return headers;
}

function sendJson(res, status, payload, origin = '') {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', ...corsHeaders(origin) });
  res.end(JSON.stringify(payload));
}

async function readJson(req, maxBytes = 2_000_000) {
  let size = 0;
  const chunks = [];
  for await (const chunk of req) {
    size += chunk.length;
    if (size > maxBytes) throw new Error('Request body too large');
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}');
}

async function hermesFetch(route, options = {}) {
  const key = getHermesKey();
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 90_000);
  try {
    const response = await fetch(HERMES_URL + route, {
      ...options,
      signal: controller.signal,
      headers: {
        Authorization: `Bearer ${key}`,
        ...(options.body ? { 'Content-Type': 'application/json' } : {}),
        ...(options.headers || {})
      }
    });
    const text = await response.text();
    let payload;
    try { payload = JSON.parse(text); } catch { payload = text; }
    if (!response.ok) {
      throw new Error(`Hermes ${route} returned ${response.status}: ${String(text).slice(0, 400)}`);
    }
    return payload;
  } finally {
    clearTimeout(timeout);
  }
}

function compactProject(project, activeScene) {
  const scenes = (project?.scenes || []).map((scene) => ({
    id: scene.id,
    name: scene.name,
    settings: scene.settings,
    tilemap: scene.tilemap ? {
      width: scene.tilemap.width,
      height: scene.tilemap.height
    } : undefined,
    entities: (scene.entities || []).map((entity) => ({
      id: entity.id,
      type: entity.type,
      name: entity.name,
      x: entity.x,
      y: entity.y,
      hp: entity.hp,
      speed: entity.speed,
      behaviors: entity.behaviors || []
    }))
  }));
  return {
    version: project?.version,
    id: project?.id,
    name: project?.name,
    currentSceneId: project?.currentSceneId,
    activeSceneId: activeScene?.id,
    scenes,
    behaviors: project?.behaviors || [],
    assets: (project?.assets || []).map((asset) => ({
      id: asset.id,
      kind: asset.kind,
      name: asset.name,
      status: asset.status
    }))
  };
}

function extractJsonObject(content) {
  const cleaned = String(content || '')
    .replace(/^\s*```(?:json)?\s*/i, '')
    .replace(/\s*```\s*$/i, '')
    .trim();
  try { return JSON.parse(cleaned); } catch {}
  const start = cleaned.indexOf('{');
  const end = cleaned.lastIndexOf('}');
  if (start >= 0 && end > start) return JSON.parse(cleaned.slice(start, end + 1));
  throw new Error('Hermes planner did not return valid JSON');
}

function validatePlan(plan, definitions) {
  if (!plan || typeof plan !== 'object' || !Array.isArray(plan.calls)) {
    throw new Error('Invalid planner payload');
  }
  const allowed = new Set((definitions || []).map((tool) => tool.name));
  if (plan.calls.length > 40) throw new Error('Planner returned too many calls');
  for (const call of plan.calls) {
    if (!call || !allowed.has(call.name)) throw new Error(`Unknown planned tool: ${call?.name || 'missing'}`);
    if (call.args != null && (typeof call.args !== 'object' || Array.isArray(call.args))) {
      throw new Error(`Invalid args for tool: ${call.name}`);
    }
  }
  return {
    message: typeof plan.message === 'string' ? plan.message : `Plan con ${plan.calls.length} acciones.`,
    calls: plan.calls.map((call) => ({ name: call.name, args: call.args || {} }))
  };
}

async function modelInfo() {
  const options = await hermesFetch('/api/model/options');
  return {
    model: options.model || 'hermes-agent',
    provider: options.provider || 'hermes'
  };
}

function godotCall(command) {
  return new Promise((resolve, reject) => {
    const socket = net.createConnection({ host: '127.0.0.1', port: 8650 });
    let buffer = '';
    const timeout = setTimeout(() => {
      socket.destroy();
      reject(new Error('Godot runtime bridge timeout'));
    }, 3000);

    socket.setEncoding('utf8');
    socket.on('connect', () => {
      socket.write(JSON.stringify(command) + '\n');
    });
    socket.on('data', (chunk) => {
      buffer += chunk;
      const newline = buffer.indexOf('\n');
      if (newline < 0) return;
      clearTimeout(timeout);
      const line = buffer.slice(0, newline).trim();
      socket.end();
      try {
        resolve(JSON.parse(line));
      } catch {
        reject(new Error('Godot runtime returned invalid JSON'));
      }
    });
    socket.on('error', (error) => {
      clearTimeout(timeout);
      reject(error);
    });
  });
}

async function buildGodotPlan(prompt) {
  const runtime = await godotCall({ command: 'telemetry' });
  const telemetry = runtime?.telemetry || {};

  const system = [
    'You are the live race engineer for Hermes Game Engine Godot runtime.',
    'Return ONLY one JSON object and no markdown.',
    'Allowed commands:',
    '{"command":"telemetry"}',
    '{"command":"reset_car"}',
    '{"command":"service_car"}',
    '{"command":"set_tuning","values":{"top_speed":number?,"acceleration":number?,"brake_force":number?,"lateral_grip":number?,"steering_rate":number?,"turbo_force":number?}}',
    '{"command":"asset_inventory"}',
    '{"command":"spawn_asset","asset":"grandstand|light_mast|paddock_tent|service_van|tire_stack|track_cone|tree_lush","x":number,"z":number,"scale":number?,"rotation":number?}',
    '{"command":"clear_runtime_assets"}',
    '{"command":"track_snapshot"}',
    '{"command":"set_track_point","index":integer,"x":number?,"z":number?,"bank":number?}',
    '{"command":"set_track_bank","index":integer,"bank":number}',
    '{"command":"replace_track","points":[{"x":number,"z":number,"bank":number?}, ...]}',
    '{"command":"reset_track"}',
    'Track rules: 6..24 points, x/z -65..65, bank -16..16 degrees, avoid adjacent points closer than about 7m.',
    'For spawn_asset use x/z inside -70..70, scale 0.35..2.5 and rotation in degrees.',
    'Do not place props directly on the racing line unless explicitly requested.',
    'Do not invent keys or commands.',
    'Only change tuning values when the user requests a driving change.',
    'Keep tuning changes conservative unless the user explicitly asks for a large change.',
    'CURRENT_TELEMETRY:',
    JSON.stringify(telemetry)
  ].join('\n');

  const response = await hermesFetch('/v1/chat/completions', {
    method: 'POST',
    body: JSON.stringify({
      model: 'hermes-agent',
      messages: [
        { role: 'system', content: system },
        { role: 'user', content: String(prompt || '') }
      ],
      stream: false
    })
  });

  const content = response?.choices?.[0]?.message?.content;
  const plan = extractJsonObject(content);
  const allowedCommands = new Set([
    'telemetry',
    'reset_car',
    'service_car',
    'set_tuning',
    'asset_inventory',
    'spawn_asset',
    'clear_runtime_assets',
    'track_snapshot',
    'set_track_point',
    'set_track_bank',
    'replace_track',
    'reset_track'
  ]);
  if (!allowedCommands.has(plan?.command)) {
    throw new Error(`Godot planner returned unsupported command: ${plan?.command || 'missing'}`);
  }

  if (plan.command === 'set_tuning') {
    if (!plan.values || typeof plan.values !== 'object' || Array.isArray(plan.values)) {
      throw new Error('Godot planner returned invalid tuning values');
    }
    const allowedKeys = new Set(['top_speed', 'acceleration', 'brake_force', 'lateral_grip', 'steering_rate', 'turbo_force']);
    for (const key of Object.keys(plan.values)) {
      if (!allowedKeys.has(key) || typeof plan.values[key] !== 'number') {
        throw new Error(`Godot planner returned invalid tuning key: ${key}`);
      }
    }
  }

  if (plan.command === 'spawn_asset') {
    const allowedAssets = new Set([
      'grandstand',
      'light_mast',
      'paddock_tent',
      'service_van',
      'tire_stack',
      'track_cone',
      'tree_lush'
    ]);
    if (!allowedAssets.has(plan.asset)) {
      throw new Error(`Godot planner returned invalid asset: ${plan.asset || 'missing'}`);
    }
    if (typeof plan.x !== 'number' || typeof plan.z !== 'number') {
      throw new Error('Godot planner must provide numeric x/z for spawn_asset');
    }
    plan.x = Math.max(-70, Math.min(70, plan.x));
    plan.z = Math.max(-70, Math.min(70, plan.z));
    if (plan.scale != null) plan.scale = Math.max(0.35, Math.min(2.5, Number(plan.scale)));
    if (plan.rotation != null) plan.rotation = Math.max(-360, Math.min(360, Number(plan.rotation)));
  }

  if (plan.command === 'set_track_point') {
    if (!Number.isInteger(plan.index)) throw new Error('set_track_point requires integer index');
    if (plan.x != null) plan.x = Math.max(-65, Math.min(65, Number(plan.x)));
    if (plan.z != null) plan.z = Math.max(-65, Math.min(65, Number(plan.z)));
    if (plan.bank != null) plan.bank = Math.max(-16, Math.min(16, Number(plan.bank)));
  }

  if (plan.command === 'set_track_bank') {
    if (!Number.isInteger(plan.index) || typeof plan.bank !== 'number') {
      throw new Error('set_track_bank requires integer index and numeric bank');
    }
    plan.bank = Math.max(-16, Math.min(16, plan.bank));
  }

  if (plan.command === 'replace_track') {
    if (!Array.isArray(plan.points) || plan.points.length < 6 || plan.points.length > 24) {
      throw new Error('replace_track requires 6..24 points');
    }
    plan.points = plan.points.map((point) => {
      if (!point || typeof point.x !== 'number' || typeof point.z !== 'number') {
        throw new Error('replace_track point requires numeric x/z');
      }
      return {
        x: Math.max(-65, Math.min(65, point.x)),
        z: Math.max(-65, Math.min(65, point.z)),
        bank: Math.max(-16, Math.min(16, Number(point.bank || 0)))
      };
    });
  }

  const result = await godotCall(plan);
  return { plan, result, telemetryBefore: telemetry };
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function runGodotTest(laps = 1, timeoutMs = 80_000) {
  await godotCall({ command: 'start_test_run', laps });
  const started = Date.now();

  while (Date.now() - started < timeoutMs) {
    await sleep(500);
    const status = await godotCall({ command: 'test_summary' });
    const test = status?.test || {};
    if (!test.running && test.summary && Object.keys(test.summary).length > 0) {
      return test.summary;
    }
  }

  await godotCall({ command: 'stop_test_run' }).catch(() => {});
  throw new Error('Godot automated test run timed out');
}

async function buildAutoBalancePlan(goal, summary) {
  const runtime = await godotCall({ command: 'telemetry' });
  const telemetry = runtime?.telemetry || {};

  const system = [
    'You are the vehicle dynamics engineer for Hermes Game Engine.',
    'Analyze the automated Godot test result and choose conservative tuning changes.',
    'Return ONLY one valid JSON object with no markdown.',
    'Required shape: {"command":"set_tuning","values":{},"reason":"short Spanish explanation"}',
    'Allowed values keys: top_speed, acceleration, brake_force, lateral_grip, steering_rate, turbo_force.',
    'Do not change a value unless the telemetry supports the change or the user goal explicitly asks for it.',
    'Prefer at most 3 tuning changes in one iteration.',
    'CURRENT_TELEMETRY:',
    JSON.stringify(telemetry),
    'TEST_SUMMARY:',
    JSON.stringify(summary)
  ].join('\n');

  const response = await hermesFetch('/v1/chat/completions', {
    method: 'POST',
    body: JSON.stringify({
      model: 'hermes-agent',
      messages: [
        { role: 'system', content: system },
        { role: 'user', content: String(goal || 'Balancea el carro para conducción arcade estable, rápida y controlable.') }
      ],
      stream: false
    })
  });

  const content = response?.choices?.[0]?.message?.content;
  const plan = extractJsonObject(content);
  if (plan?.command !== 'set_tuning' || !plan.values || typeof plan.values !== 'object' || Array.isArray(plan.values)) {
    throw new Error('Hermes auto-balance returned invalid plan');
  }

  const allowedKeys = new Set(['top_speed', 'acceleration', 'brake_force', 'lateral_grip', 'steering_rate', 'turbo_force']);
  const entries = Object.entries(plan.values);
  if (entries.length > 3) throw new Error('Hermes auto-balance attempted too many changes');

  for (const [key, value] of entries) {
    if (!allowedKeys.has(key) || typeof value !== 'number') {
      throw new Error(`Hermes auto-balance returned invalid tuning key: ${key}`);
    }
  }

  return {
    command: 'set_tuning',
    values: plan.values,
    reason: typeof plan.reason === 'string' ? plan.reason : ''
  };
}

async function autoBalanceGodot(goal, laps = 1) {
  const beforeTelemetry = await godotCall({ command: 'telemetry' });
  const beforeTest = await runGodotTest(laps);
  const plan = await buildAutoBalancePlan(goal, beforeTest);
  const applied = await godotCall(plan);
  const afterTest = await runGodotTest(1);
  const afterTelemetry = await godotCall({ command: 'telemetry' });

  return {
    goal,
    beforeTest,
    plan,
    applied,
    afterTest,
    beforeTelemetry: beforeTelemetry?.telemetry || {},
    afterTelemetry: afterTelemetry?.telemetry || {}
  };
}

async function buildPlan({ prompt, tools, project, activeScene }) {
  const state = compactProject(project, activeScene);
  const system = [
    'You are the planning brain for Hermes Game Engine.',
    'Do NOT execute tools yourself. Do NOT call terminal, search, browser, or any Hermes internal tool.',
    'Return ONLY one valid JSON object with no markdown and no surrounding commentary.',
    'Required shape: {"message":"short Spanish summary","calls":[{"name":"toolName","args":{}}]}',
    'Only use names in AVAILABLE_TOOLS. Never invent a tool name.',
    'Use entity and scene IDs from CURRENT_PROJECT when updating existing objects.',
    'Prefer a small, deterministic plan. If no action is needed, return calls: [].',
    'AVAILABLE_TOOLS:',
    JSON.stringify(tools || []),
    'CURRENT_PROJECT:',
    JSON.stringify(state)
  ].join('\n');

  const response = await hermesFetch('/v1/chat/completions', {
    method: 'POST',
    body: JSON.stringify({
      model: 'hermes-agent',
      messages: [
        { role: 'system', content: system },
        { role: 'user', content: String(prompt || '') }
      ],
      stream: false
    })
  });
  const content = response?.choices?.[0]?.message?.content;
  return validatePlan(extractJsonObject(content), tools);
}

const server = http.createServer(async (req, res) => {
  const origin = String(req.headers.origin || '');
  if (!originAllowed(origin)) {
    return sendJson(res, 403, { error: 'Origin not allowed' }, '');
  }

  if (req.method === 'OPTIONS') {
    res.writeHead(204, corsHeaders(origin));
    return res.end();
  }

  try {
    if (req.method === 'GET' && req.url === '/health') {
      const [health, info] = await Promise.all([
        hermesFetch('/health'),
        modelInfo()
      ]);
      return sendJson(res, 200, {
        ok: health?.status === 'ok',
        bridge: 'hermes-game-bridge',
        hermesVersion: health?.version,
        ...info
      }, origin);
    }

    if (req.method === 'POST' && req.url === '/plan') {
      if (req.headers['x-hge-bridge'] !== '1') {
        return sendJson(res, 400, { error: 'Missing bridge header' }, origin);
      }
      const body = await readJson(req);
      const plan = await buildPlan(body);
      const info = await modelInfo().catch(() => ({ model: 'hermes-agent', provider: 'hermes' }));
      return sendJson(res, 200, { ...plan, ...info }, origin);
    }

    if (req.method === 'GET' && req.url === '/godot/telemetry') {
      const result = await godotCall({ command: 'telemetry' });
      return sendJson(res, 200, result, origin);
    }

    if (req.method === 'GET' && req.url === '/godot/assets') {
      const result = await godotCall({ command: 'asset_inventory' });
      return sendJson(res, 200, result, origin);
    }

    if (req.method === 'GET' && req.url === '/godot/track') {
      const result = await godotCall({ command: 'track_snapshot' });
      return sendJson(res, 200, result, origin);
    }

    if (req.method === 'POST' && req.url === '/godot') {
      if (req.headers['x-hge-bridge'] !== '1') {
        return sendJson(res, 400, { error: 'Missing bridge header' }, origin);
      }
      const body = await readJson(req);
      const result = await godotCall(body);
      return sendJson(res, result?.ok === false ? 400 : 200, result, origin);
    }

    if (req.method === 'POST' && req.url === '/godot/plan') {
      if (req.headers['x-hge-bridge'] !== '1') {
        return sendJson(res, 400, { error: 'Missing bridge header' }, origin);
      }
      const body = await readJson(req);
      const execution = await buildGodotPlan(body.prompt);
      const info = await modelInfo().catch(() => ({ model: 'hermes-agent', provider: 'hermes' }));
      return sendJson(res, 200, { ok: true, ...execution, ...info }, origin);
    }

    if (req.method === 'POST' && req.url === '/godot/autobalance') {
      if (req.headers['x-hge-bridge'] !== '1') {
        return sendJson(res, 400, { error: 'Missing bridge header' }, origin);
      }
      const body = await readJson(req);
      const laps = Math.max(1, Math.min(2, Number(body.laps || 1)));
      const execution = await autoBalanceGodot(body.goal, laps);
      const info = await modelInfo().catch(() => ({ model: 'hermes-agent', provider: 'hermes' }));
      return sendJson(res, 200, { ok: true, ...execution, ...info }, origin);
    }

    return sendJson(res, 404, { error: 'Not found' }, origin);
  } catch (error) {
    return sendJson(res, 502, { error: error.message || String(error) }, origin);
  }
});

server.listen(PORT, HOST, () => {
  console.log(`Hermes Game Bridge listening on http://${HOST}:${PORT}`);
});
