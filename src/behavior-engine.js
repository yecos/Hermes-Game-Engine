export class BehaviorEngine {
  constructor(store) {
    this.store = store;
    this.origins = new Map();
    this.collected = new Set();
  }
  reset() { this.origins.clear(); this.collected.clear(); }
  origin(entity, object) {
    if (!this.origins.has(entity.id)) this.origins.set(entity.id, { x: object.x, y: object.y });
    return this.origins.get(entity.id);
  }
  update(entity, object, context, dt) {
    const definitions = (entity.behaviors ?? []).map((id) => this.store.getBehavior(id)).filter(Boolean);
    for (const behavior of definitions) {
      const cfg = behavior.config ?? {};
      const origin = this.origin(entity, object);
      if (behavior.kind === 'patrol') {
        const distance = Number(cfg.distance ?? 90);
        const speed = Number(cfg.speed ?? 1);
        object.x = origin.x + Math.sin(context.time * 0.001 * speed) * distance;
      } else if (behavior.kind === 'chase' && context.player) {
        const range = Number(cfg.range ?? 240);
        const speed = Number(cfg.speed ?? 95);
        const dx = context.player.x - object.x, dy = context.player.y - object.y;
        const length = Math.hypot(dx, dy);
        if (length > 1 && length <= range) {
          object.x += dx / length * speed * dt;
          object.y += dy / length * speed * dt;
        }
      } else if (behavior.kind === 'spin') {
        object.rotation += Number(cfg.speed ?? 1.4) * dt;
      } else if (behavior.kind === 'float') {
        object.y = origin.y + Math.sin(context.time * 0.001 * Number(cfg.speed ?? 1.6)) * Number(cfg.distance ?? 12);
      } else if (behavior.kind === 'collectible' && context.player && !this.collected.has(entity.id)) {
        const radius = Number(cfg.radius ?? 32);
        if (Math.hypot(context.player.x - object.x, context.player.y - object.y) <= radius) {
          this.collected.add(entity.id);
          object.setVisible(false);
          context.onCollect?.(entity, behavior);
        }
      }
    }
  }
}
