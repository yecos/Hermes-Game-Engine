import { ProjectStore, createProject, migrateProject, ENTITY_PRESETS, TILE_TYPES, BEHAVIOR_PRESETS } from './project-store.js';
import { ToolRegistry } from './tool-registry.js';
import { PhaserRuntime } from './phaser-runtime.js';
import { HermesAgent } from './hermes-agent.js';
import { CloudClient } from './cloud-client.js';
import { AssetGenerator } from './asset-generator.js';
import { SceneTestAgent } from './test-agent.js';

const savedV3 = localStorage.getItem('hge:project:v03');
const savedV2 = localStorage.getItem('hge:project:v02');
let initialProject = createProject();
try {
  const raw = savedV3 ?? savedV2;
  if (raw) initialProject = migrateProject(JSON.parse(raw));
} catch {}

const store = new ProjectStore(initialProject);
const cloud = new CloudClient();
const testAgent = new SceneTestAgent(store);
const assetGenerator = new AssetGenerator(store, cloud);
const tools = new ToolRegistry(store, {
  generateAsset: (args) => assetGenerator.generate(args),
  testScene: (args) => testAgent.run(args)
});
const runtime = new PhaserRuntime(store).start();
const agent = new HermesAgent(store, tools, {
  onRun: (run) => cloud.logRun(run).catch(() => {})
});

const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];
const escapeHtml = (value) => String(value).replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' })[char]);
const tree = $('#sceneTree');
const inspector = $('#inspector');
const consoleLog = $('#consoleLog');
const chat = $('#chatHistory');

function log(message, type = 'ok') {
  const row = document.createElement('div');
  row.className = `log-${type}`;
  row.textContent = `[${new Date().toLocaleTimeString()}] ${message}`;
  consoleLog.prepend(row);
}

function renderScenes() {
  const list = $('#sceneList');
  list.innerHTML = '';
  for (const scene of store.project.scenes) {
    const item = document.createElement('button');
    item.className = `scene-item ${store.project.currentSceneId === scene.id ? 'active' : ''}`;
    item.innerHTML = `<span>◇</span><b>${escapeHtml(scene.name)}</b><small>${scene.entities.length}</small>`;
    item.onclick = () => store.switchScene(scene.id);
    list.appendChild(item);
  }
  $('#currentSceneName').textContent = store.activeScene.name;
}

function renderTree() {
  tree.innerHTML = '';
  for (const entity of store.entities) {
    const item = document.createElement('button');
    item.className = `tree-item ${store.selectedId === entity.id ? 'active' : ''}`;
    item.innerHTML = `<span class="entity-dot" style="background:${entity.color}"></span><span>${escapeHtml(entity.name)}</span><small>${entity.type}</small>`;
    item.onclick = () => store.select(entity.id);
    tree.appendChild(item);
  }
  $('#entityCount').textContent = `${store.entities.length} entities`;
}

function behaviorButtons(entity) {
  const attached = (entity.behaviors ?? []).map((id) => store.getBehavior(id)).filter(Boolean);
  return `
    <div class="behavior-box">
      <label>Behaviors</label>
      <div class="behavior-list">
        ${attached.length ? attached.map((behavior) => `<button class="behavior-tag" data-remove-behavior="${behavior.id}" title="Quitar">${escapeHtml(behavior.name)} ×</button>`).join('') : '<small>Sin behaviors</small>'}
      </div>
      <div class="behavior-add">
        ${Object.entries(BEHAVIOR_PRESETS).map(([kind, preset]) => `<button data-add-behavior="${kind}">+${escapeHtml(preset.name)}</button>`).join('')}
      </div>
    </div>`;
}

function renderInspector() {
  const entity = store.getEntity(store.selectedId);
  if (!entity) {
    inspector.innerHTML = '<div class="empty-state">Selecciona una entidad o arrastra un asset a la escena.</div>';
    $('#selectedType').textContent = '—';
    return;
  }
  $('#selectedType').textContent = entity.type.toUpperCase();
  inspector.innerHTML = `
    <div class="field"><label>Nombre</label><input data-key="name" value="${escapeHtml(entity.name)}"></div>
    <div class="field-pair">
      <div class="field"><label>X</label><input data-key="x" type="number" value="${Math.round(entity.x)}"></div>
      <div class="field"><label>Y</label><input data-key="y" type="number" value="${Math.round(entity.y)}"></div>
    </div>
    <div class="field"><label>Color</label><input data-key="color" type="color" value="${entity.color}"></div>
    ${entity.hp !== undefined ? `<div class="field"><label>HP</label><input data-key="hp" type="number" value="${entity.hp}"></div>` : ''}
    ${entity.speed !== undefined ? `<div class="field"><label>Velocidad</label><input data-key="speed" type="number" value="${entity.speed}"></div>` : ''}
    ${behaviorButtons(entity)}
    <button class="danger-btn" id="deleteEntity">Eliminar entidad</button>`;
  inspector.querySelectorAll('input').forEach((input) => input.addEventListener('change', () => {
    const key = input.dataset.key;
    const value = input.type === 'number' ? Number(input.value) : input.value;
    store.updateEntity(entity.id, { [key]: value });
  }));
  inspector.querySelectorAll('[data-add-behavior]').forEach((button) => button.onclick = () => {
    store.addBehavior(entity.id, button.dataset.addBehavior);
    renderInspector();
    log(`Behavior añadido a ${entity.name}`, 'ai');
  });
  inspector.querySelectorAll('[data-remove-behavior]').forEach((button) => button.onclick = () => {
    store.detachBehavior(entity.id, button.dataset.removeBehavior);
    renderInspector();
  });
  $('#deleteEntity').onclick = () => { store.deleteEntity(entity.id); log(`Eliminado: ${entity.name}`, 'warn'); };
}

function createGeneratedAssetCard(asset) {
  const card = document.createElement('button');
  card.className = 'asset-card generated';
  card.draggable = true;
  const url = asset.publicUrl ?? asset.url;
  card.innerHTML = `${url ? `<img src="${escapeHtml(url)}" alt="">` : '<span class="asset-icon">✦</span>'}<b>${escapeHtml(asset.name ?? 'AI Asset')}</b><small>${escapeHtml(asset.kind ?? 'asset')}</small>`;
  card.onclick = () => store.createEntity('obstacle', { x: 640, y: 370, name: asset.name ?? 'AI Asset', assetId: asset.id, color: '#46e6ff' });
  card.addEventListener('dragstart', (event) => { event.dataTransfer.setData('text/hge-generated-asset', asset.id); event.dataTransfer.effectAllowed = 'copy'; });
  return card;
}

function renderAssets() {
  const list = $('#assetBrowser');
  list.innerHTML = '';
  for (const [type, preset] of Object.entries(ENTITY_PRESETS)) {
    const card = document.createElement('button');
    card.className = 'asset-card';
    card.draggable = true;
    card.innerHTML = `<span class="asset-icon" style="--asset:${preset.color}">${type === 'player' ? '◆' : type === 'enemy' ? '▲' : type === 'coin' ? '✦' : type === 'npc' ? '●' : '▰'}</span><b>${preset.name}</b><small>${type}</small>`;
    card.onclick = () => store.createEntity(type, { x: 640, y: 370 });
    card.addEventListener('dragstart', (event) => { event.dataTransfer.setData('text/hge-asset', type); event.dataTransfer.effectAllowed = 'copy'; });
    list.appendChild(card);
  }
  for (const asset of store.project.assets.slice().reverse()) list.appendChild(createGeneratedAssetCard(asset));
}

function renderTiles() {
  const palette = $('#tilePalette');
  palette.innerHTML = '';
  for (const tile of TILE_TYPES) {
    const button = document.createElement('button');
    button.className = `tile-chip ${store.activeTile === tile.index && store.tool === 'tile' ? 'active' : ''}`;
    button.innerHTML = `<span style="background:${tile.color}"></span>${tile.name}`;
    button.onclick = () => { store.setActiveTile(tile.index); renderTiles(); renderMode(); };
    palette.appendChild(button);
  }
}

function renderMode() {
  $('#modeLabel').textContent = store.mode === 'play' ? 'PLAY MODE' : store.tool === 'tile' ? 'TILE PAINT' : 'EDIT MODE';
  $('#playBtn').textContent = store.mode === 'play' ? '■ Detener' : '▶ Jugar';
  $('#selectTool').classList.toggle('active', store.tool === 'select');
  $('#tileTool').classList.toggle('active', store.tool === 'tile');
  $('#statusMode').textContent = `${store.mode.toUpperCase()} · ${store.tool.toUpperCase()} · ${store.activeScene.name}`;
}

function renderAll() { renderScenes(); renderTree(); renderInspector(); renderAssets(); renderTiles(); renderMode(); }

store.addEventListener('change', (event) => {
  if (event.detail.type !== 'entity:update' || !runtime.dragCheckpoint) renderInspector();
  renderScenes(); renderTree();
  if (event.detail.type.startsWith('asset:')) renderAssets();
  $('#dirtyState').textContent = '● modified';
});
store.addEventListener('selection', () => { renderTree(); renderInspector(); });
store.addEventListener('scene', () => { renderAll(); log(`Escena activa: ${store.activeScene.name}`); });
store.addEventListener('tool', () => { renderMode(); renderTiles(); });
store.addEventListener('mode', renderMode);
store.addEventListener('test', (event) => {
  const result = event.detail;
  log(`Test agent: ${result.summary}`, result.status === 'fail' ? 'warn' : 'ai');
});

$('#selectTool').onclick = () => store.setTool('select');
$('#tileTool').onclick = () => store.setTool('tile');
$('#undoBtn').onclick = () => { if (store.undo()) { renderAll(); log('Undo aplicado.'); } };
$('#redoBtn').onclick = () => { if (store.redo()) { renderAll(); log('Redo aplicado.'); } };
$('#playBtn').onclick = () => { store.setMode(store.mode === 'play' ? 'edit' : 'play'); log(store.mode === 'play' ? 'Juego ejecutándose. WASD/flechas + espacio.' : 'Volviste al editor.'); };
$('#newBtn').onclick = () => { store.replace(createProject()); store.select(null); renderAll(); log('Proyecto nuevo creado.', 'warn'); };
$('#addSceneBtn').onclick = () => {
  const name = window.prompt('Nombre de la nueva escena', `Scene ${store.project.scenes.length + 1}`);
  if (name) { store.createScene(name); renderAll(); }
};
$('#saveBtn').onclick = () => {
  localStorage.setItem('hge:project:v03', store.serialize());
  $('#dirtyState').textContent = '● saved local';
  log('Proyecto guardado localmente.');
};
$('#cloudConfigBtn').onclick = () => {
  const token = window.prompt('Token privado del API cloud. No se guarda en el repositorio.', cloud.token);
  if (token !== null) { cloud.setToken(token); log(token ? 'Token cloud guardado en este navegador.' : 'Token cloud eliminado.', 'ai'); }
};
$('#cloudSaveBtn').onclick = async () => {
  try {
    const result = await cloud.saveProject(store.snapshot());
    $('#dirtyState').textContent = '● saved cloud';
    log(`Guardado en Neon: ${result.project?.name ?? store.project.name}`, 'ai');
  } catch (error) { log(`Cloud save: ${error.message}`, 'warn'); }
};
$('#cloudLoadBtn').onclick = async () => {
  try {
    const list = await cloud.listProjects();
    if (!list.projects?.length) return log('No hay proyectos cloud todavía.', 'warn');
    const options = list.projects.map((project) => `${project.id} — ${project.name}`).join('\n');
    const id = window.prompt(`ID del proyecto a cargar:\n\n${options}`, store.project.id);
    if (!id) return;
    const result = await cloud.loadProject(id.trim());
    store.replace(result.project);
    renderAll();
    log(`Cargado desde Neon: ${result.project.name}`, 'ai');
  } catch (error) { log(`Cloud load: ${error.message}`, 'warn'); }
};
$('#exportBtn').onclick = () => {
  const blob = new Blob([store.serialize()], { type: 'application/json' });
  const link = document.createElement('a'); link.href = URL.createObjectURL(blob); link.download = 'hermes-game-project-v03.json'; link.click(); URL.revokeObjectURL(link.href);
  log('Proyecto exportado a JSON.');
};
$('#importInput').onchange = async (event) => {
  const file = event.target.files?.[0]; if (!file) return;
  try { store.replace(JSON.parse(await file.text())); renderAll(); log(`Importado: ${file.name}`); } catch { log('No pude importar ese JSON.', 'warn'); }
  event.target.value = '';
};
$('#connectHermes').onclick = () => {
  const endpoint = window.prompt('Endpoint HTTP de Hermes. Recibe {prompt, tools, project, activeScene} y devuelve {message, calls}.', agent.endpoint);
  if (endpoint === null) return;
  agent.setEndpoint(endpoint);
  $('#agentMode').textContent = agent.endpoint ? 'HERMES GATEWAY' : 'LOCAL PLANNER';
  log(agent.endpoint ? `Hermes conectado: ${agent.endpoint}` : 'Usando planner local.', 'ai');
};
$('#generateAssetBtn').onclick = async () => {
  const prompt = window.prompt('Describe el sprite o tile que quieres generar', 'robot cyberpunk pixel art, transparent background');
  if (!prompt) return;
  $('#agentBusy').classList.add('visible');
  try {
    const asset = await assetGenerator.generate({ kind: 'sprite', prompt, name: prompt.slice(0, 32) });
    renderAssets();
    log(`Asset generado: ${asset.name} · ${asset.provider ?? 'provider'}`, 'ai');
  } catch (error) { log(error.message, 'warn'); }
  finally { $('#agentBusy').classList.remove('visible'); }
};
$('#testBtn').onclick = async () => {
  const result = await testAgent.run({ goal: 'Autoplay and structural validation' });
  cloud.logRun({ ...result, runType: 'test', result: result }).catch(() => {});
  const details = [...result.issues, ...result.warnings].join('\n') || 'Sin problemas detectados.';
  window.alert(`${result.summary}\n\n${details}`);
};

function addMessage(text, who = 'ai') {
  const message = document.createElement('div');
  message.className = `message ${who}`;
  message.innerHTML = `<span>${who === 'user' ? 'Y' : 'H'}</span><p>${escapeHtml(text)}</p>`;
  chat.appendChild(message); chat.scrollTop = chat.scrollHeight;
}

async function submitPrompt(text) {
  if (!text.trim()) return;
  addMessage(text, 'user'); log(`Prompt: ${text}`, 'ai'); $('#agentBusy').classList.add('visible');
  try {
    const result = await agent.run(text);
    addMessage(result.message, 'ai');
    renderAll();
    log(`Hermes ejecutó ${result.calls.length} tool call${result.calls.length === 1 ? '' : 's'}.`, 'ai');
  } catch (error) { addMessage(`Error del agente: ${error.message}`, 'ai'); log(error.message, 'warn'); }
  finally { $('#agentBusy').classList.remove('visible'); }
}

$('#promptForm').onsubmit = (event) => { event.preventDefault(); const input = $('#promptInput'); const value = input.value; input.value = ''; submitPrompt(value); };
$$('[data-prompt]').forEach((button) => button.onclick = () => submitPrompt(button.dataset.prompt));

window.addEventListener('hge:runtime-ready', () => {
  const canvas = runtime.game.canvas;
  canvas.addEventListener('dragover', (event) => { event.preventDefault(); event.dataTransfer.dropEffect = 'copy'; });
  canvas.addEventListener('drop', (event) => {
    event.preventDefault();
    const type = event.dataTransfer.getData('text/hge-asset');
    const assetId = event.dataTransfer.getData('text/hge-generated-asset');
    if (type) {
      const entity = runtime.dropAsset(type, event.clientX, event.clientY);
      log(`Asset colocado: ${entity.name}`);
    } else if (assetId) {
      const asset = store.project.assets.find((item) => item.id === assetId);
      if (asset) {
        const pos = runtime.screenToWorld(event.clientX, event.clientY);
        store.createEntity('obstacle', { x: Math.round(pos.x), y: Math.round(pos.y), name: asset.name ?? 'AI Asset', assetId: asset.id, color: '#46e6ff' });
      }
    }
  });
  log(`Phaser ${Phaser.VERSION} listo · multi-scene + behaviors activos.`, 'ok');
});

window.addEventListener('hge:collect', (event) => log(`Collectible: ${event.detail.entity.name}`, 'ai'));

renderAll();
$('#agentMode').textContent = agent.endpoint ? 'HERMES GATEWAY' : 'LOCAL PLANNER';
log('Hermes Game Engine V0.3 inicializando…', 'ai');
cloud.health().then(() => { $('#cloudState').textContent = 'NEON READY'; $('#cloudState').classList.add('online'); }).catch(() => { $('#cloudState').textContent = 'LOCAL'; });
