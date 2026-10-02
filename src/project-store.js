const clone = (value) => JSON.parse(JSON.stringify(value));
const id = (prefix = 'entity') => `${prefix}-${globalThis.crypto?.randomUUID?.() ?? Math.random().toString(36).slice(2)}`;

export const ENTITY_PRESETS = {
  player: { name: 'Player', color: '#46e6ff', speed: 240, hp: 100, size: 30 },
  enemy: { name: 'Enemy', color: '#ff5d7a', speed: 80, hp: 50, size: 28 },
  npc: { name: 'NPC', color: '#b372ff', hp: 100, size: 28 },
  coin: { name: 'Data Shard', color: '#ffd166', size: 18 },
  obstacle: { name: 'Prop', color: '#566176', w: 72, h: 48, size: 30 }
};

export const TILE_TYPES = [
  { index: 0, name: 'Void', color: '#0b1119' },
  { index: 1, name: 'Street', color: '#1a2632' },
  { index: 2, name: 'Sidewalk', color: '#384758' },
  { index: 3, name: 'Neon', color: '#1b9bad' }
];

export function createProject() {
  const width = 40, height = 23;
  const tiles = Array.from({ length: height }, (_, y) =>
    Array.from({ length: width }, (_, x) => y >= 16 && y <= 19 ? 1 : y === 15 || y === 20 ? 2 : ((x + y) % 13 === 0 ? 3 : 0))
  );
  return {
    version: '0.2.0',
    name: 'Cyber Medellín',
    scene: 'main',
    settings: { width: 1280, height: 736, tileSize: 32, night: true },
    tilemap: { width, height, tiles },
    assets: { entities: Object.keys(ENTITY_PRESETS), tiles: TILE_TYPES },
    entities: [
      makeEntity('player', { x: 640, y: 430 }),
      makeEntity('npc', { name: 'Quest Fixer', x: 380, y: 365 }),
      makeEntity('enemy', { name: 'Drone 01', x: 850, y: 330 }),
      makeEntity('coin', { name: 'Shard A', x: 720, y: 520 }),
      makeEntity('obstacle', { name: 'Neon Kiosk', x: 260, y: 500 })
    ]
  };
}

export function makeEntity(type, patch = {}) {
  const preset = ENTITY_PRESETS[type] ?? ENTITY_PRESETS.obstacle;
  return { id: id(type), type, ...clone(preset), x: 320, y: 320, rotation: 0, ...patch };
}

export class ProjectStore extends EventTarget {
  constructor(project = createProject()) {
    super();
    this.project = clone(project);
    this.selectedId = null;
    this.history = [];
    this.future = [];
    this.mode = 'edit';
    this.tool = 'select';
    this.activeTile = 1;
  }
  snapshot() { return clone(this.project); }
  emit(type, detail = {}) { this.dispatchEvent(new CustomEvent(type, { detail })); }
  checkpoint() { this.history.push(this.snapshot()); if (this.history.length > 50) this.history.shift(); this.future = []; }
  mutate(type, fn, detail = {}) { this.checkpoint(); fn(this.project); this.emit('change', { type, ...detail }); }
  select(id) { this.selectedId = id; this.emit('selection', { id, entity: this.getEntity(id) }); }
  getEntity(id) { return this.project.entities.find((entity) => entity.id === id) ?? null; }
  createEntity(type, patch = {}) { let created; this.mutate('entity:create', (project) => { created = makeEntity(type, patch); project.entities.push(created); }, { typeName: type }); this.select(created.id); return clone(created); }
  updateEntity(idValue, patch, { checkpoint = true } = {}) {
    const apply = () => { const entity = this.getEntity(idValue); if (!entity) throw new Error(`Entity not found: ${idValue}`); Object.assign(entity, patch); this.emit('change', { type: 'entity:update', id: idValue, patch: clone(patch) }); };
    if (checkpoint) this.checkpoint(); apply(); return clone(this.getEntity(idValue));
  }
  deleteEntity(idValue) { this.mutate('entity:delete', (project) => { project.entities = project.entities.filter((entity) => entity.id !== idValue); }, { id: idValue }); if (this.selectedId === idValue) this.select(null); }
  paintTile(x, y, tileIndex, { checkpoint = true } = {}) {
    if (x < 0 || y < 0 || x >= this.project.tilemap.width || y >= this.project.tilemap.height) return false;
    if (checkpoint) this.checkpoint();
    this.project.tilemap.tiles[y][x] = tileIndex;
    this.emit('change', { type: 'tile:paint', x, y, tileIndex });
    return true;
  }
  fillTiles(tileIndex) { this.mutate('tile:fill', (project) => { project.tilemap.tiles = project.tilemap.tiles.map((row) => row.map(() => tileIndex)); }, { tileIndex }); }
  setNight(night) { this.mutate('world:night', (project) => { project.settings.night = Boolean(night); }, { night: Boolean(night) }); }
  setMode(mode) { this.mode = mode; this.emit('mode', { mode }); }
  setTool(tool) { this.tool = tool; this.emit('tool', { tool }); }
  setActiveTile(tile) { this.activeTile = Number(tile); this.setTool('tile'); this.emit('tile', { tile: this.activeTile }); }
  undo() { if (!this.history.length) return false; this.future.push(this.snapshot()); this.project = this.history.pop(); this.emit('change', { type: 'history:undo', full: true }); return true; }
  redo() { if (!this.future.length) return false; this.history.push(this.snapshot()); this.project = this.future.pop(); this.emit('change', { type: 'history:redo', full: true }); return true; }
  replace(project) { this.checkpoint(); this.project = clone(project); this.selectedId = null; this.emit('change', { type: 'project:replace', full: true }); }
  serialize() { return JSON.stringify(this.project, null, 2); }
}
