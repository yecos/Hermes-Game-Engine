export const TOOL_DEFINITIONS = [
  { name: 'createEntity', description: 'Create a game entity.', input: { type: 'string', x: 'number?', y: 'number?', name: 'string?' } },
  { name: 'updateEntity', description: 'Patch entity properties.', input: { id: 'string', patch: 'object' } },
  { name: 'deleteEntity', description: 'Delete one entity.', input: { id: 'string' } },
  { name: 'paintTile', description: 'Paint a tile in the active tilemap.', input: { x: 'number', y: 'number', tileIndex: 'number' } },
  { name: 'fillTiles', description: 'Fill the complete tilemap.', input: { tileIndex: 'number' } },
  { name: 'setNight', description: 'Toggle night rendering.', input: { night: 'boolean' } },
  { name: 'inspectScene', description: 'Return the current project state.', input: {} }
];

export class ToolRegistry {
  constructor(store) { this.store = store; }
  definitions() { return TOOL_DEFINITIONS; }
  async execute(name, args = {}) {
    switch (name) {
      case 'createEntity': return this.store.createEntity(args.type ?? 'obstacle', args);
      case 'updateEntity': return this.store.updateEntity(args.id, args.patch ?? {});
      case 'deleteEntity': this.store.deleteEntity(args.id); return { ok: true };
      case 'paintTile': return { ok: this.store.paintTile(args.x, args.y, args.tileIndex) };
      case 'fillTiles': this.store.fillTiles(args.tileIndex); return { ok: true };
      case 'setNight': this.store.setNight(args.night); return { night: this.store.project.settings.night };
      case 'inspectScene': return this.store.snapshot();
      default: throw new Error(`Unknown tool: ${name}`);
    }
  }
}
