import { ProjectStore, createProject, ENTITY_PRESETS, TILE_TYPES } from './project-store.js';
import { ToolRegistry } from './tool-registry.js';
import { PhaserRuntime } from './phaser-runtime.js';
import { HermesAgent } from './hermes-agent.js';

const saved = localStorage.getItem('hge:project:v02');
let initialProject = createProject();
try { if (saved) { const parsed = JSON.parse(saved); if (parsed.version === '0.2.0') initialProject = parsed; } } catch {}

const store = new ProjectStore(initialProject);
const tools = new ToolRegistry(store);
const runtime = new PhaserRuntime(store).start();
const agent = new HermesAgent(store, tools);

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

function renderTree() {
  tree.innerHTML = '';
  for (const entity of store.project.entities) {
    const item = document.createElement('button');
    item.className = `tree-item ${store.selectedId === entity.id ? 'active' : ''}`;
    item.innerHTML = `<span class="entity-dot" style="background:${entity.color}"></span><span>${escapeHtml(entity.name)}</span><small>${entity.type}</small>`;
    item.onclick = () => store.select(entity.id);
    tree.appendChild(item);
  }
  $('#entityCount').textContent = `${store.project.entities.length} entities`;
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
    <button class="danger-btn" id="deleteEntity">Eliminar entidad</button>`;
  inspector.querySelectorAll('input').forEach((input) => input.addEventListener('change', () => {
    const key = input.dataset.key;
    const value = input.type === 'number' ? Number(input.value) : input.value;
    store.updateEntity(entity.id, { [key]: value });
  }));
  $('#deleteEntity').onclick = () => { store.deleteEntity(entity.id); log(`Eliminado: ${entity.name}`, 'warn'); };
}

function renderAssets() {
  const list = $('#assetBrowser');
  list.innerHTML = '';
  for (const [type, preset] of Object.entries(ENTITY_PRESETS)) {
    const card = document.createElement('button');
    card.className = 'asset-card';
    card.draggable = true;
    card.dataset.asset = type;
    card.innerHTML = `<span class="asset-icon" style="--asset:${preset.color}">${type === 'player' ? '◆' : type === 'enemy' ? '▲' : type === 'coin' ? '✦' : type === 'npc' ? '●' : '▰'}</span><b>${preset.name}</b><small>${type}</small>`;
    card.onclick = () => store.createEntity(type, { x: 640, y: 370 });
    card.addEventListener('dragstart', (event) => { event.dataTransfer.setData('text/hge-asset', type); event.dataTransfer.effectAllowed = 'copy'; });
    list.appendChild(card);
  }
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
  $('#statusMode').textContent = `${store.mode.toUpperCase()} · ${store.tool.toUpperCase()}`;
}

function renderAll() { renderTree(); renderInspector(); renderTiles(); renderMode(); }

store.addEventListener('change', (event) => {
  if (event.detail.type !== 'entity:update' || !runtime.dragCheckpoint) renderInspector();
  renderTree();
  $('#dirtyState').textContent = '● modified';
});
store.addEventListener('selection', () => { renderTree(); renderInspector(); });
store.addEventListener('tool', () => { renderMode(); renderTiles(); });
store.addEventListener('mode', renderMode);

$('#selectTool').onclick = () => store.setTool('select');
$('#tileTool').onclick = () => store.setTool('tile');
$('#undoBtn').onclick = () => { if (store.undo()) log('Undo aplicado.'); };
$('#redoBtn').onclick = () => { if (store.redo()) log('Redo aplicado.'); };
$('#playBtn').onclick = () => { store.setMode(store.mode === 'play' ? 'edit' : 'play'); log(store.mode === 'play' ? 'Juego ejecutándose. WASD/flechas + espacio.' : 'Volviste al editor.'); };
$('#newBtn').onclick = () => { store.replace(createProject()); store.select(null); log('Proyecto nuevo creado.', 'warn'); };
$('#saveBtn').onclick = () => { localStorage.setItem('hge:project:v02', store.serialize()); $('#dirtyState').textContent = '● saved'; log('Proyecto guardado en este navegador.'); };
$('#exportBtn').onclick = () => {
  const blob = new Blob([store.serialize()], { type: 'application/json' });
  const link = document.createElement('a'); link.href = URL.createObjectURL(blob); link.download = 'hermes-game-project-v02.json'; link.click(); URL.revokeObjectURL(link.href);
  log('Proyecto exportado a JSON.');
};
$('#importInput').onchange = async (event) => {
  const file = event.target.files?.[0]; if (!file) return;
  try { store.replace(JSON.parse(await file.text())); log(`Importado: ${file.name}`); } catch { log('No pude importar ese JSON.', 'warn'); }
  event.target.value = '';
};
$('#connectHermes').onclick = () => {
  const current = agent.endpoint || '';
  const endpoint = window.prompt('Endpoint HTTP de Hermes. Debe recibir {prompt, tools, project} y devolver {message, calls}. Déjalo vacío para usar el planner local.', current);
  if (endpoint === null) return;
  agent.setEndpoint(endpoint);
  $('#agentMode').textContent = agent.endpoint ? 'HERMES GATEWAY' : 'LOCAL PLANNER';
  log(agent.endpoint ? `Hermes conectado: ${agent.endpoint}` : 'Usando planner local.', 'ai');
};

function addMessage(text, who = 'ai') {
  const message = document.createElement('div');
  message.className = `message ${who}`;
  message.innerHTML = `<span>${who === 'user' ? 'Y' : 'H'}</span><p>${escapeHtml(text)}</p>`;
  chat.appendChild(message); chat.scrollTop = chat.scrollHeight;
}

async function submitPrompt(text) {
  if (!text.trim()) return;
  addMessage(text, 'user'); log(`Prompt: ${text}`, 'ai');
  $('#agentBusy').classList.add('visible');
  try {
    const result = await agent.run(text);
    addMessage(result.message, 'ai');
    log(`Hermes ejecutó ${result.calls.length} tool call${result.calls.length === 1 ? '' : 's'}.`, 'ai');
  } catch (error) {
    addMessage(`Error del agente: ${error.message}`, 'ai'); log(error.message, 'warn');
  } finally { $('#agentBusy').classList.remove('visible'); }
}

$('#promptForm').onsubmit = (event) => { event.preventDefault(); const input = $('#promptInput'); const value = input.value; input.value = ''; submitPrompt(value); };
$$('[data-prompt]').forEach((button) => button.onclick = () => submitPrompt(button.dataset.prompt));

window.addEventListener('hge:runtime-ready', () => {
  const canvas = runtime.game.canvas;
  canvas.addEventListener('dragover', (event) => { event.preventDefault(); event.dataTransfer.dropEffect = 'copy'; });
  canvas.addEventListener('drop', (event) => {
    event.preventDefault();
    const type = event.dataTransfer.getData('text/hge-asset');
    if (type) { const entity = runtime.dropAsset(type, event.clientX, event.clientY); log(`Asset colocado: ${entity.name}`); }
  });
  log(`Phaser ${Phaser.VERSION} listo. Tilemap real + drag & drop activos.`, 'ok');
});

renderAssets(); renderAll();
$('#agentMode').textContent = agent.endpoint ? 'HERMES GATEWAY' : 'LOCAL PLANNER';
log('Hermes Game Engine V0.2 inicializando…', 'ai');
