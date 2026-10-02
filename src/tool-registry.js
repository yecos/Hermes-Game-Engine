export const TOOL_DEFINITIONS = [
  { name: 'createEntity', description: 'Create an entity in the active scene.', input: { type: 'string', x: 'number?', y: 'number?', name: 'string?' } },
  { name: 'updateEntity', description: 'Patch entity properties.', input: { id: 'string', patch: 'object' } },
  { name: 'deleteEntity', description: 'Delete one entity from the active scene.', input: { id: 'string' } },
  { name: 'createScene', description: 'Create and switch to a new scene.', input: { name: 'string' } },
  { name: 'switchScene', description: 'Switch the active scene.', input: { sceneId: 'string' } },
  { name: 'addBehavior', description: 'Create and attach a behavior to an entity.', input: { entityId: 'string', kind: 'string', config: 'object?' } },
  { name: 'detachBehavior', description: 'Detach a behavior from an entity.', input: { entityId: 'string', behaviorId: 'string' } },
  { name: 'paintTile', description: 'Paint a tile in the active scene.', input: { x: 'number', y: 'number', tileIndex: 'number' } },
  { name: 'fillTiles', description: 'Fill the active tilemap.', input: { tileIndex: 'number' } },
  { name: 'setNight', description: 'Toggle night rendering in the active scene.', input: { night: 'boolean' } },
  { name: 'generateAsset', description: 'Generate a sprite/tile asset through the configured AI asset provider.', input: { kind: 'string', prompt: 'string', name: 'string?' } },
  { name: 'testScene', description: 'Run the autonomous scene test agent.', input: { goal: 'string?' } },
  { name: 'inspectScene', description: 'Return the active scene.', input: {} },
  { name: 'inspectProject', description: 'Return the complete project.', input: {} }
];

export class ToolRegistry {
  constructor(store, services = {}) { this.store = store; this.services = services; }
  definitions() { return TOOL_DEFINITIONS; }
  async execute(name, args = {}) {
    switch (name) {
      case 'createEntity': return this.store.createEntity(args.type ?? 'obstacle', args);
      case 'updateEntity': return this.store.updateEntity(args.id, args.patch ?? {});
      case 'deleteEntity': this.store.deleteEntity(args.id); return { ok: true };
      case 'createScene': return this.store.createScene(args.name ?? 'AI Scene');
      case 'switchScene': return this.store.switchScene(args.sceneId);
      case 'addBehavior': return this.store.addBehavior(args.entityId, args.kind, args.config ?? {});
      case 'detachBehavior': this.store.detachBehavior(args.entityId, args.behaviorId); return { ok: true };
      case 'paintTile': return { ok: this.store.paintTile(args.x, args.y, args.tileIndex) };
      case 'fillTiles': this.store.fillTiles(args.tileIndex); return { ok: true };
      case 'setNight': this.store.setNight(args.night); return { night: this.store.settings.night };
      case 'generateAsset':
        if (!this.services.generateAsset) throw new Error('Asset generation service is not configured');
        return this.services.generateAsset(args);
      case 'testScene':
        if (!this.services.testScene) throw new Error('Test agent is not configured');
        return this.services.testScene(args);
      case 'inspectScene': return structuredClone(this.store.activeScene);
      case 'inspectProject': return this.store.snapshot();
      default: throw new Error(`Unknown tool: ${name}`);
    }
  }
}
