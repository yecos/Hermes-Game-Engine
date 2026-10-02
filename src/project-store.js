const clone = (value) => JSON.parse(JSON.stringify(value));
const uid = (prefix = 'id') => `${prefix}-${globalThis.crypto?.randomUUID?.() ?? Math.random().toString(36).slice(2)}`;

export const ENTITY_PRESETS = {
  player: { name: 'Player', color: '#46e6ff', speed: 240, hp: 100, size: 30, behaviors: [] },
  enemy: { name: 'Enemy', color: '#ff5d7a', speed: 80, hp: 50, size: 28, behaviors: [] },
  npc: { name: 'NPC', color: '#b372ff', hp: 100, size: 28, behaviors: [] },
  coin: { name: 'Data Shard', color: '#ffd166', size: 18, behaviors: [] },
  obstacle: { name: 'Prop', color: '#566176', w: 72, h: 48, size: 30, behaviors: [] }
};

export const TILE_TYPES = [
  { index: 0, name: 'Void', color: '#0b1119' },
  { index: 1, name: 'Street', color: '#1a2632' },
  { index: 2, name: 'Sidewalk', color: '#384758' },
  { index: 3, name: 'Neon', color: '#1b9bad' }
];

export const BEHAVIOR_PRESETS = {
  patrol: { name: 'Patrol', kind: 'patrol', config: { distance: 90, speed: 1 } },
  chase: { name: 'Chase Player', kind: 'chase', config: { range: 240, speed: 95 } },
  spin: { name: 'Spin', kind: 'spin', config: { speed: 1.4 } },
  float: { name: 'Float', kind: 'float', config: { distance: 12, speed: 1.6 } },
  collectible: { name: 'Collectible', kind: 'collectible', config: { radius: 32, score: 1 } }
};

export function makeEntity(type, patch = {}) {
  const preset = ENTITY_PRESETS[type] ?? ENTITY_PRESETS.obstacle;
  return { id: uid(type), type, ...clone(preset), x: 320, y: 320, rotation: 0, ...patch, behaviors: clone(patch.behaviors ?? preset.behaviors ?? []) };
}

export function makeBehavior(kind, patch = {}) {
  const preset = BEHAVIOR_PRESETS[kind] ?? { name: kind, kind, config: {} };
  return { id: uid('behavior'), ...clone(preset), ...patch, config: { ...clone(preset.config ?? {}), ...(patch.config ?? {}) } };
}

function makeTilemap(width = 40, height = 23) {
  return {
    width,
    height,
    tiles: Array.from({ length: height }, (_, y) =>
      Array.from({ length: width }, (_, x) => y >= 16 && y <= 19 ? 1 : y === 15 || y === 20 ? 2 : ((x + y) % 13 === 0 ? 3 : 0))
    )
  };
}

export function makeScene(name = 'Main', patch = {}) {
  const scene = {
    id: uid('scene'),
    name,
    settings: { width: 1280, height: 736, tileSize: 32, night: true },
    tilemap: makeTilemap(),
    entities: []
  };
  return { ...scene, ...clone(patch), settings: { ...scene.settings, ...(patch.settings ?? {}) }, tilemap: patch.tilemap ? clone(patch.tilemap) : scene.tilemap, entities: clone(patch.entities ?? scene.entities) };
}

export function createProject() {
  const patrol = makeBehavior('patrol');
  const collectible = makeBehavior('collectible');
  const main = makeScene('Main');
  main.entities = [
    makeEntity('player', { x: 640, y: 430 }),
    makeEntity('npc', { name: 'Quest Fixer', x: 380, y: 365 }),
    makeEntity('enemy', { name: 'Drone 01', x: 850, y: 330, behaviors: [patrol.id] }),
    makeEntity('coin', { name: 'Shard A', x: 720, y: 520, behaviors: [collectible.id] }),
    makeEntity('obstacle', { name: 'Neon Kiosk', x: 260, y: 500 })
  ];
  return {
    version: '0.3.0',
    id: uid('project'),
    name: 'Cyber Medellín',
    currentSceneId: main.id,
    scenes: [main],
    behaviors: [patrol, collectible],
    assets: [],
    metadata: { engine: 'phaser-4.2.1', createdAt: new Date().toISOString() }
  };
}

export function migrateProject(raw) {
  if (!raw || typeof raw !== 'object') return createProject();
  if (raw.version === '0.3.0' && Array.isArray(raw.scenes)) return clone(raw);
  if (raw.version === '0.2.0') {
    const scene = makeScene(raw.scene === 'main' ? 'Main' : (raw.scene ?? 'Main'), {
      settings: raw.settings,
      tilemap: raw.tilemap,
      entities: (raw.entities ?? []).map((entity) => ({ ...entity, behaviors: entity.behaviors ?? [] }))
    });
    return {
      version: '0.3.0',
      id: raw.id ?? uid('project'),
      name: raw.name ?? 'Imported V0.2 Project',
      currentSceneId: scene.id,
      scenes: [scene],
      behaviors: [],
      assets: [],
      metadata: { migratedFrom: '0.2.0', migratedAt: new Date().toISOString() }
    };
  }
  return createProject();
}

export class ProjectStore extends EventTarget {
  constructor(project = createProject()) {
    super();
    this.project = migrateProject(project);
    this.selectedId = null;
    this.history = [];
    this.future = [];
    this.mode = 'edit';
    this.tool = 'select';
    this.activeTile = 1;
  }
  get activeScene() { return this.project.scenes.find((scene) => scene.id === this.project.currentSceneId) ?? this.project.scenes[0]; }
  get settings() { return this.activeScene.settings; }
  get tilemap() { return this.activeScene.tilemap; }
  get entities() { return this.activeScene.entities; }
  snapshot() { return clone(this.project); }
  emit(type, detail = {}) { this.dispatchEvent(new CustomEvent(type, { detail })); }
  checkpoint() { this.history.push(this.snapshot()); if (this.history.length > 60) this.history.shift(); this.future = []; }
  mutate(type, fn, detail = {}) { this.checkpoint(); fn(this.project); this.emit('change', { type, ...detail }); }
  select(id) { this.selectedId = id; this.emit('selection', { id, entity: this.getEntity(id) }); }
  getEntity(id) { return this.entities.find((entity) => entity.id === id) ?? null; }
  getBehavior(id) { return this.project.behaviors.find((behavior) => behavior.id === id) ?? null; }

  createEntity(type, patch = {}) {
    let created;
    this.mutate('entity:create', () => { created = makeEntity(type, patch); this.entities.push(created); }, { typeName: type });
    this.select(created.id);
    return clone(created);
  }
  updateEntity(idValue, patch, { checkpoint = true } = {}) {
    const entity = this.getEntity(idValue);
    if (!entity) throw new Error(`Entity not found: ${idValue}`);
    if (checkpoint) this.checkpoint();
    Object.assign(entity, patch);
    this.emit('change', { type: 'entity:update', id: idValue, patch: clone(patch) });
    return clone(entity);
  }
  deleteEntity(idValue) {
    this.mutate('entity:delete', () => { this.activeScene.entities = this.entities.filter((entity) => entity.id !== idValue); }, { id: idValue });
    if (this.selectedId === idValue) this.select(null);
  }

  createScene(name = `Scene ${this.project.scenes.length + 1}`, patch = {}) {
    let created;
    this.mutate('scene:create', (project) => { created = makeScene(name, patch); project.scenes.push(created); }, { name });
    this.switchScene(created.id);
    return clone(created);
  }
  switchScene(sceneId) {
    if (!this.project.scenes.some((scene) => scene.id === sceneId)) throw new Error(`Scene not found: ${sceneId}`);
    this.project.currentSceneId = sceneId;
    this.selectedId = null;
    this.emit('scene', { sceneId, scene: clone(this.activeScene) });
    this.emit('change', { type: 'scene:switch', full: true, sceneId });
    return clone(this.activeScene);
  }
  renameScene(sceneId, name) {
    const scene = this.project.scenes.find((item) => item.id === sceneId);
    if (!scene) throw new Error(`Scene not found: ${sceneId}`);
    this.checkpoint(); scene.name = name; this.emit('change', { type: 'scene:rename', sceneId, name });
  }
  deleteScene(sceneId) {
    if (this.project.scenes.length <= 1) throw new Error('A project must keep at least one scene');
    this.mutate('scene:delete', (project) => { project.scenes = project.scenes.filter((scene) => scene.id !== sceneId); }, { sceneId });
    if (this.project.currentSceneId === sceneId) this.switchScene(this.project.scenes[0].id);
  }

  createBehavior(kind, patch = {}) {
    let created;
    this.mutate('behavior:create', (project) => { created = makeBehavior(kind, patch); project.behaviors.push(created); }, { kind });
    return clone(created);
  }
  attachBehavior(entityId, behaviorId) {
    const entity = this.getEntity(entityId);
    if (!entity) throw new Error(`Entity not found: ${entityId}`);
    if (!this.getBehavior(behaviorId)) throw new Error(`Behavior not found: ${behaviorId}`);
    this.checkpoint();
    entity.behaviors = [...new Set([...(entity.behaviors ?? []), behaviorId])];
    this.emit('change', { type: 'behavior:attach', entityId, behaviorId });
    return clone(entity);
  }
  addBehavior(entityId, kind, config = {}) {
    const behavior = this.createBehavior(kind, { config });
    this.attachBehavior(entityId, behavior.id);
    return { behavior, entity: clone(this.getEntity(entityId)) };
  }
  detachBehavior(entityId, behaviorId) {
    const entity = this.getEntity(entityId);
    if (!entity) throw new Error(`Entity not found: ${entityId}`);
    this.checkpoint();
    entity.behaviors = (entity.behaviors ?? []).filter((idValue) => idValue !== behaviorId);
    this.emit('change', { type: 'behavior:detach', entityId, behaviorId });
  }

  addAsset(asset) {
    const normalized = { id: asset.id ?? uid('asset'), status: 'ready', createdAt: new Date().toISOString(), ...clone(asset) };
    this.checkpoint();
    this.project.assets.push(normalized);
    this.emit('change', { type: 'asset:add', asset: clone(normalized) });
    return clone(normalized);
  }

  paintTile(x, y, tileIndex, { checkpoint = true } = {}) {
    if (x < 0 || y < 0 || x >= this.tilemap.width || y >= this.tilemap.height) return false;
    if (checkpoint) this.checkpoint();
    this.tilemap.tiles[y][x] = tileIndex;
    this.emit('change', { type: 'tile:paint', x, y, tileIndex });
    return true;
  }
  fillTiles(tileIndex) {
    this.mutate('tile:fill', () => { this.activeScene.tilemap.tiles = this.tilemap.tiles.map((row) => row.map(() => tileIndex)); }, { tileIndex });
  }
  setNight(night) {
    this.mutate('world:night', () => { this.activeScene.settings.night = Boolean(night); }, { night: Boolean(night) });
  }
  setMode(mode) { this.mode = mode; this.emit('mode', { mode }); }
  setTool(tool) { this.tool = tool; this.emit('tool', { tool }); }
  setActiveTile(tile) { this.activeTile = Number(tile); this.setTool('tile'); this.emit('tile', { tile: this.activeTile }); }
  undo() { if (!this.history.length) return false; this.future.push(this.snapshot()); this.project = this.history.pop(); this.selectedId = null; this.emit('change', { type: 'history:undo', full: true }); return true; }
  redo() { if (!this.future.length) return false; this.history.push(this.snapshot()); this.project = this.future.pop(); this.selectedId = null; this.emit('change', { type: 'history:redo', full: true }); return true; }
  replace(project) { this.checkpoint(); this.project = migrateProject(project); this.selectedId = null; this.emit('change', { type: 'project:replace', full: true }); }
  serialize() { return JSON.stringify(this.project, null, 2); }
}
