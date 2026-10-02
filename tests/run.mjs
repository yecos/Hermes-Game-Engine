import assert from 'node:assert/strict';
import { ProjectStore, createProject, migrateProject } from '../src/project-store.js';
import { ToolRegistry } from '../src/tool-registry.js';
import { SceneTestAgent } from '../src/test-agent.js';

if (!globalThis.CustomEvent) globalThis.CustomEvent = class CustomEvent extends Event { constructor(type, init = {}) { super(type); this.detail = init.detail; } };

const store = new ProjectStore(createProject());
const testAgent = new SceneTestAgent(store);
const tools = new ToolRegistry(store, { testScene: (args) => testAgent.run(args), generateAsset: async () => ({ ok: true }) });

assert.equal(store.project.version, '0.3.0');
assert.equal(store.project.scenes.length, 1);
const mainId = store.activeScene.id;

const boss = await tools.execute('createScene', { name: 'Boss Arena' });
assert.equal(store.project.scenes.length, 2);
assert.equal(store.activeScene.id, boss.id);
assert.equal(store.activeScene.name, 'Boss Arena');

const player = await tools.execute('createEntity', { type: 'player', name: 'Tester', x: 100, y: 100 });
const enemy = await tools.execute('createEntity', { type: 'enemy', name: 'Boss', x: 300, y: 100 });
const behavior = await tools.execute('addBehavior', { entityId: enemy.id, kind: 'chase', config: { range: 500, speed: 120 } });
assert.equal(store.getEntity(enemy.id).behaviors.length, 1);
assert.equal(behavior.behavior.kind, 'chase');

await tools.execute('paintTile', { x: 2, y: 3, tileIndex: 3 });
assert.equal(store.tilemap.tiles[3][2], 3);
await tools.execute('setNight', { night: false });
assert.equal(store.settings.night, false);

const test = await tools.execute('testScene', { goal: 'Validate boss arena' });
assert.equal(test.status, 'pass');
assert.ok(test.metrics.entities >= 2);

await tools.execute('switchScene', { sceneId: mainId });
assert.equal(store.activeScene.id, mainId);
assert.ok(store.undo());
assert.ok(store.redo());

const oldV2 = {
  version: '0.2.0',
  name: 'Legacy',
  scene: 'main',
  settings: { width: 1280, height: 736, tileSize: 32, night: true },
  tilemap: { width: 1, height: 1, tiles: [[0]] },
  entities: [{ id: 'p', type: 'player', name: 'P', x: 0, y: 0, color: '#fff' }]
};
const migrated = migrateProject(oldV2);
assert.equal(migrated.version, '0.3.0');
assert.equal(migrated.scenes.length, 1);
assert.deepEqual(migrated.scenes[0].entities[0].behaviors, []);

JSON.parse(store.serialize());
assert.equal(player.type, 'player');
console.log('Hermes Game Engine V0.3 tests: OK');
