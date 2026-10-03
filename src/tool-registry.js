export const SUPPORTED_ENTITY_TYPES = ['player', 'enemy', 'npc', 'coin', 'obstacle', 'car', 'boost'];
export const SUPPORTED_BEHAVIOR_KINDS = ['patrol', 'chase', 'spin', 'float', 'collectible'];
export const SUPPORTED_ASSET_KINDS = ['sprite', 'tile'];

export const TOOL_DEFINITIONS = [
  {
    name: 'createRaceGame',
    description: 'Create a complete playable top-down arcade racing game: circuit, player car, AI rivals, turbo pads, laps, race position and HUD. Prefer this tool whenever the user asks for a car/racing game.',
    input: {
      name: 'string?',
      aiCount: 'number? 1-9',
      laps: 'number? 1-9',
      theme: 'string?',
      difficulty: 'easy|medium|hard?'
    }
  },
  {
    name: 'createEntity',
    description: 'Create an entity. type is REQUIRED and must be one of: player, enemy, npc, coin, obstacle, car, boost.',
    input: { type: 'player|enemy|npc|coin|obstacle|car|boost', x: 'number?', y: 'number?', name: 'string?' }
  },
  { name: 'updateEntity', description: 'Patch properties on an existing entity. Use an existing entity id.', input: { id: 'string', patch: 'object' } },
  { name: 'deleteEntity', description: 'Delete one entity from the active scene.', input: { id: 'string' } },
  { name: 'createScene', description: 'Create and switch to a new scene.', input: { name: 'string' } },
  { name: 'switchScene', description: 'Switch the active scene. Use an existing scene id.', input: { sceneId: 'string' } },
  {
    name: 'addBehavior',
    description: 'Attach a supported generic behavior. kind must be one of: patrol, chase, spin, float, collectible. Do NOT invent racing behaviors; racing logic is built into createRaceGame.',
    input: { entityId: 'string', kind: 'patrol|chase|spin|float|collectible', config: 'object?' }
  },
  { name: 'detachBehavior', description: 'Detach a behavior from an entity.', input: { entityId: 'string', behaviorId: 'string' } },
  { name: 'paintTile', description: 'Paint one tile. tileIndex must be 0, 1, 2, or 3.', input: { x: 'number', y: 'number', tileIndex: '0|1|2|3' } },
  { name: 'fillTiles', description: 'Fill the active tilemap. tileIndex must be 0, 1, 2, or 3.', input: { tileIndex: '0|1|2|3' } },
  { name: 'setNight', description: 'Toggle night rendering.', input: { night: 'boolean' } },
  {
    name: 'generateAsset',
    description: 'Generate an image asset. kind must be sprite or tile.',
    input: { kind: 'sprite|tile', prompt: 'string', name: 'string?' }
  },
  { name: 'testScene', description: 'Run the autonomous scene test agent.', input: { goal: 'string?' } },
  { name: 'inspectScene', description: 'Return the active scene.', input: {} },
  { name: 'inspectProject', description: 'Return the complete project.', input: {} }
];

function assertOneOf(value, allowed, label) {
  if (!allowed.includes(value)) throw new Error(`${label} must be one of: ${allowed.join(', ')}`);
}

function assertTileIndex(value) {
  if (![0, 1, 2, 3].includes(Number(value))) throw new Error('tileIndex must be 0, 1, 2, or 3');
}

export class ToolRegistry {
  constructor(store, services = {}) {
    this.store = store;
    this.services = services;
  }

  definitions() {
    return TOOL_DEFINITIONS;
  }

  async execute(name, args = {}) {
    switch (name) {
      case 'createRaceGame':
        return this.store.createRaceGame(args);

      case 'createEntity':
        assertOneOf(args.type, SUPPORTED_ENTITY_TYPES, 'createEntity.type');
        return this.store.createEntity(args.type, args);

      case 'updateEntity':
        return this.store.updateEntity(args.id, args.patch ?? {});

      case 'deleteEntity':
        this.store.deleteEntity(args.id);
        return { ok: true };

      case 'createScene':
        return this.store.createScene(args.name ?? 'AI Scene');

      case 'switchScene':
        return this.store.switchScene(args.sceneId);

      case 'addBehavior':
        assertOneOf(args.kind, SUPPORTED_BEHAVIOR_KINDS, 'addBehavior.kind');
        return this.store.addBehavior(args.entityId, args.kind, args.config ?? {});

      case 'detachBehavior':
        this.store.detachBehavior(args.entityId, args.behaviorId);
        return { ok: true };

      case 'paintTile':
        assertTileIndex(args.tileIndex);
        return { ok: this.store.paintTile(args.x, args.y, Number(args.tileIndex)) };

      case 'fillTiles':
        assertTileIndex(args.tileIndex);
        this.store.fillTiles(Number(args.tileIndex));
        return { ok: true };

      case 'setNight':
        this.store.setNight(args.night);
        return { night: this.store.settings.night };

      case 'generateAsset':
        assertOneOf(args.kind, SUPPORTED_ASSET_KINDS, 'generateAsset.kind');
        if (!this.services.generateAsset) throw new Error('Asset generation service is not configured');
        return this.services.generateAsset(args);

      case 'testScene':
        if (!this.services.testScene) throw new Error('Test agent is not configured');
        return this.services.testScene(args);

      case 'inspectScene':
        return structuredClone(this.store.activeScene);

      case 'inspectProject':
        return this.store.snapshot();

      default:
        throw new Error(`Unknown tool: ${name}`);
    }
  }
}
