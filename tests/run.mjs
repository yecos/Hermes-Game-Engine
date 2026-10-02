import assert from 'node:assert/strict';
import { ProjectStore, createProject } from '../src/project-store.js';
import { ToolRegistry } from '../src/tool-registry.js';

if (!globalThis.CustomEvent) globalThis.CustomEvent = class CustomEvent extends Event { constructor(type, init = {}) { super(type); this.detail = init.detail; } };

const store = new ProjectStore(createProject());
const tools = new ToolRegistry(store);
const initial = store.project.entities.length;
const enemy = await tools.execute('createEntity', { type: 'enemy', x: 100, y: 100, name: 'Test Drone' });
assert.equal(store.project.entities.length, initial + 1);
assert.equal(enemy.name, 'Test Drone');
await tools.execute('updateEntity', { id: enemy.id, patch: { hp: 12 } });
assert.equal(store.getEntity(enemy.id).hp, 12);
await tools.execute('paintTile', { x: 2, y: 3, tileIndex: 3 });
assert.equal(store.project.tilemap.tiles[3][2], 3);
await tools.execute('setNight', { night: false });
assert.equal(store.project.settings.night, false);
assert.ok(store.undo());
assert.equal(store.project.settings.night, true);
assert.ok(store.redo());
assert.equal(store.project.settings.night, false);
const scene = await tools.execute('inspectScene');
assert.equal(scene.version, '0.2.0');
assert.equal(JSON.parse(store.serialize()).version, '0.2.0');
console.log('Hermes Game Engine V0.2 tests: OK');
