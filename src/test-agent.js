const clone = (value) => JSON.parse(JSON.stringify(value));

export class SceneTestAgent {
  constructor(store) { this.store = store; }

  async run({ goal = 'Validate basic playability' } = {}) {
    const scene = clone(this.store.activeScene);
    const project = this.store.snapshot();
    const events = [];
    const issues = [];
    const warnings = [];
    const isRace = scene.settings?.gameMode === 'racing';
    const players = scene.entities.filter((entity) =>
      entity.type === 'player' || (entity.type === 'car' && entity.role === 'player')
    );

    events.push({ type: 'start', goal, sceneId: scene.id, sceneName: scene.name });

    if (players.length === 0) issues.push(
      isRace ? 'No player car exists in the racing scene.' : 'No player entity exists in the active scene.'
    );
    if (players.length > 1) warnings.push(`The scene contains ${players.length} player entities.`);

    if (isRace) {
      const rivals = scene.entities.filter((entity) => entity.type === 'car' && entity.role === 'ai');
      const boosts = scene.entities.filter((entity) => entity.type === 'boost');
      if (!scene.settings?.race?.track) issues.push('Racing scene is missing track configuration.');
      if (!scene.settings?.race?.laps) issues.push('Racing scene is missing lap configuration.');
      if (rivals.length < 1) issues.push('Racing scene needs at least one AI rival.');
      if (boosts.length < 1) warnings.push('Racing scene has no turbo pads.');
    }

    const ids = new Set();
    for (const entity of scene.entities) {
      if (ids.has(entity.id)) issues.push(`Duplicate entity id: ${entity.id}`);
      ids.add(entity.id);
      if (entity.x < 0 || entity.y < 0 || entity.x > scene.settings.width || entity.y > scene.settings.height) {
        issues.push(`${entity.name} is outside the scene bounds.`);
      }
      for (const behaviorId of entity.behaviors ?? []) {
        if (!project.behaviors.some((behavior) => behavior.id === behaviorId)) issues.push(`${entity.name} references missing behavior ${behaviorId}.`);
      }
    }

    const rows = scene.tilemap.tiles ?? [];
    if (rows.length !== scene.tilemap.height) issues.push('Tilemap height does not match the number of rows.');
    if (rows.some((row) => row.length !== scene.tilemap.width)) issues.push('One or more tilemap rows have the wrong width.');

    let simulatedSteps = 0;
    let visitedTargets = 0;
    if (players[0]) {
      const player = { x: players[0].x, y: players[0].y, speed: players[0].speed ?? 240 };
      const targets = scene.entities.filter((entity) => entity.type === 'coin' || (entity.behaviors ?? []).some((id) => project.behaviors.find((behavior) => behavior.id === id)?.kind === 'collectible'));
      for (const target of targets.slice(0, 12)) {
        let distance = Math.hypot(target.x - player.x, target.y - player.y);
        let guard = 0;
        while (distance > 28 && guard++ < 240) {
          const dx = target.x - player.x, dy = target.y - player.y;
          const length = Math.max(1, Math.hypot(dx, dy));
          player.x += dx / length * player.speed / 30;
          player.y += dy / length * player.speed / 30;
          distance = Math.hypot(target.x - player.x, target.y - player.y);
          simulatedSteps++;
        }
        if (distance <= 28) visitedTargets++;
        else warnings.push(`Autoplay could not reach ${target.name} in the simulation budget.`);
      }
    }

    const enemies = scene.entities.filter((entity) =>
      entity.type === 'enemy' || (entity.type === 'car' && entity.role === 'ai')
    );
    const status = issues.length ? 'fail' : warnings.length ? 'warn' : 'pass';
    const summary = status === 'pass'
      ? `Scene passed: ${scene.entities.length} entities, ${visitedTargets} collectible targets reached.`
      : `Scene finished with ${issues.length} issue(s) and ${warnings.length} warning(s).`;
    const result = {
      id: `test-${globalThis.crypto?.randomUUID?.() ?? Date.now()}`,
      projectId: project.id,
      sceneId: scene.id,
      status,
      summary,
      issues,
      warnings,
      events: [...events, { type: 'complete', status }],
      metrics: { entities: scene.entities.length, enemies: enemies.length, simulatedSteps, visitedTargets },
      createdAt: new Date().toISOString()
    };
    this.store.emit('test', result);
    return result;
  }
}
