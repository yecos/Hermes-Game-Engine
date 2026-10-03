import http from 'node:http';
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

    return sendJson(res, 404, { error: 'Not found' }, origin);
  } catch (error) {
    return sendJson(res, 502, { error: error.message || String(error) }, origin);
  }
});

server.listen(PORT, HOST, () => {
  console.log(`Hermes Game Bridge listening on http://${HOST}:${PORT}`);
});
