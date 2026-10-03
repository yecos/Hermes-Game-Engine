import { BehaviorEngine } from './behavior-engine.js';

const TILE_COLORS = ['#0b1119', '#1a2632', '#384758', '#1b9bad'];

export class PhaserRuntime {
  constructor(store, parent = 'gameMount') {
    this.store = store;
    this.parent = parent;
    this.objects = new Map();
    this.loadingAssets = new Set();
    this.ready = false;
    this.dragCheckpoint = false;
    this.lastPaintKey = '';
    this.behaviors = new BehaviorEngine(store);
    this.store.addEventListener('change', (event) => this.onStoreChange(event.detail));
    this.store.addEventListener('mode', () => this.onModeChange());
    this.store.addEventListener('selection', () => this.decorateSelection());
    this.store.addEventListener('tool', () => this.refreshInteractivity());
  }

  start() {
    const settings = this.store.settings;
    const runtime = this;
    class EditorScene extends Phaser.Scene {
      constructor() { super('HermesEditorScene'); }
      create() { runtime.scene = this; runtime.createScene(); }
      update(time, delta) { runtime.update(time, delta / 1000); }
    }
    this.game = new Phaser.Game({
      type: Phaser.AUTO,
      parent: this.parent,
      width: settings.width,
      height: settings.height,
      backgroundColor: '#05070d',
      pixelArt: false,
      antialias: true,
      scene: [EditorScene],
      input: { mouse: { preventDefaultWheel: true } },
      scale: { mode: Phaser.Scale.FIT, autoCenter: Phaser.Scale.CENTER_BOTH }
    });
    return this;
  }

  createScene() {
    this.createTilesetTexture();
    this.rebuildTilemap();
    this.syncEntities();
    this.bindSceneInput();
    // Gameplay keys must not be captured globally; otherwise W/A/S/D
    // and Space stop working inside editor inputs and the Hermes prompt.
    this.keys = this.scene.input.keyboard.addKeys({
      up: Phaser.Input.Keyboard.KeyCodes.W,
      down: Phaser.Input.Keyboard.KeyCodes.S,
      left: Phaser.Input.Keyboard.KeyCodes.A,
      right: Phaser.Input.Keyboard.KeyCodes.D,
      arrowUp: Phaser.Input.Keyboard.KeyCodes.UP,
      arrowDown: Phaser.Input.Keyboard.KeyCodes.DOWN,
      arrowLeft: Phaser.Input.Keyboard.KeyCodes.LEFT,
      arrowRight: Phaser.Input.Keyboard.KeyCodes.RIGHT,
      boost: Phaser.Input.Keyboard.KeyCodes.SPACE
    }, false);
    this.applyWorldAppearance();
    this.ready = true;
    window.dispatchEvent(new CustomEvent('hge:runtime-ready'));
  }

  createTilesetTexture() {
    if (this.scene.textures.exists('hge-tiles')) return;
    const texture = this.scene.textures.createCanvas('hge-tiles', 128, 32);
    const ctx = texture.context;
    TILE_COLORS.forEach((color, index) => {
      const x = index * 32;
      ctx.fillStyle = color; ctx.fillRect(x, 0, 32, 32);
      ctx.strokeStyle = index === 3 ? '#46e6ff55' : '#ffffff0b'; ctx.strokeRect(x + 0.5, 0.5, 31, 31);
      if (index === 1) { ctx.fillStyle = '#d9c77344'; ctx.fillRect(x, 15, 32, 2); }
      if (index === 3) { ctx.fillStyle = '#46e6ff66'; ctx.fillRect(x + 4, 4, 24, 3); }
    });
    texture.refresh();
  }

  rebuildTilemap() {
    this.tileLayer?.destroy();
    this.tilemap?.destroy();
    const size = this.store.settings.tileSize;
    this.tilemap = this.scene.make.tilemap({ data: this.store.tilemap.tiles, tileWidth: size, tileHeight: size });
    this.tileset = this.tilemap.addTilesetImage('hge-tiles', 'hge-tiles', size, size, 0, 0, 0);
    this.tileLayer = this.tilemap.createLayer(0, this.tileset, 0, 0);
    this.tileLayer.setDepth(-10);
  }

  bindSceneInput() {
    const paint = (pointer) => {
      if (this.store.mode !== 'edit' || this.store.tool !== 'tile') return;
      const size = this.store.settings.tileSize;
      const x = Math.floor(pointer.worldX / size), y = Math.floor(pointer.worldY / size);
      const key = `${x}:${y}:${this.store.activeTile}`;
      if (key === this.lastPaintKey) return;
      this.lastPaintKey = key;
      this.store.paintTile(x, y, this.store.activeTile);
    };
    this.scene.input.on('pointerdown', paint);
    this.scene.input.on('pointermove', (pointer) => { if (pointer.isDown) paint(pointer); else this.lastPaintKey = ''; });
    this.scene.input.on('pointerup', () => { this.lastPaintKey = ''; });
  }

  assetFor(entity) {
    return entity.assetId ? this.store.project.assets.find((asset) => asset.id === entity.assetId) : null;
  }

  textureKey(assetId) { return `hge-asset-${assetId}`; }

  ensureAssetTexture(asset) {
    const url = asset?.publicUrl ?? asset?.url;
    if (!asset || !url) return;
    const key = this.textureKey(asset.id);
    if (this.scene.textures.exists(key) || this.loadingAssets.has(key)) return;
    this.loadingAssets.add(key);
    this.scene.load.image(key, url);
    this.scene.load.once(`filecomplete-image-${key}`, () => {
      this.loadingAssets.delete(key);
      for (const entity of this.store.entities.filter((item) => item.assetId === asset.id)) this.recreateEntityObject(entity);
    });
    this.scene.load.once('loaderror', () => this.loadingAssets.delete(key));
    this.scene.load.start();
  }

  makeVisual(entity) {
    const asset = this.assetFor(entity);
    const key = asset && this.textureKey(asset.id);
    if (asset && key && this.scene.textures.exists(key)) {
      const image = this.scene.add.image(0, 0, key);
      const max = Math.max(entity.w ?? 72, entity.h ?? 72, 72);
      const scale = Math.min(max / Math.max(image.width || 1, image.height || 1), 1.5);
      image.setScale(scale);
      return image;
    }
    if (asset) this.ensureAssetTexture(asset);

    const color = Phaser.Display.Color.HexStringToColor(entity.color ?? '#ffffff').color;
    if (entity.type === 'enemy') return this.scene.add.triangle(0, 0, 0, -20, 22, 18, -22, 18, color);
    if (entity.type === 'coin') return this.scene.add.star(0, 0, 4, 7, 13, color);
    if (entity.type === 'obstacle') return this.scene.add.rectangle(0, 0, entity.w ?? 72, entity.h ?? 48, color);
    return this.scene.add.circle(0, 0, entity.size ? entity.size / 2 : 15, color);
  }

  createEntityObject(entity) {
    const container = this.scene.add.container(entity.x, entity.y).setDepth(10);
    const visual = this.makeVisual(entity);
    const label = this.scene.add.text(0, 30, entity.name, { fontFamily: 'system-ui', fontSize: '12px', color: '#dfe9f8', backgroundColor: '#06080dbb', padding: { x: 4, y: 2 } }).setOrigin(0.5, 0);
    container.add([visual, label]);
    container.setSize(Math.max(entity.w ?? 64, 64), Math.max(entity.h ?? 64, 64));
    container.setInteractive(new Phaser.Geom.Rectangle(-container.width / 2, -container.height / 2, container.width, container.height), Phaser.Geom.Rectangle.Contains);
    container.setData('entityId', entity.id);
    container.on('pointerdown', (_pointer, _localX, _localY, event) => {
      if (this.store.mode === 'edit' && this.store.tool === 'select') { event?.stopPropagation?.(); this.store.select(entity.id); }
    });
    container.on('dragstart', () => {
      if (this.store.mode !== 'edit' || this.store.tool !== 'select') return;
      this.store.checkpoint(); this.dragCheckpoint = true; this.store.select(entity.id);
    });
    container.on('drag', (_pointer, dragX, dragY) => {
      if (this.store.mode !== 'edit' || this.store.tool !== 'select') return;
      const x = Phaser.Math.Clamp(dragX, 20, this.store.settings.width - 20);
      const y = Phaser.Math.Clamp(dragY, 20, this.store.settings.height - 20);
      container.setPosition(x, y);
      this.store.updateEntity(entity.id, { x: Math.round(x), y: Math.round(y) }, { checkpoint: false });
    });
    container.on('dragend', () => { this.dragCheckpoint = false; });
    this.scene.input.setDraggable(container);
    this.objects.set(entity.id, container);
    return container;
  }

  recreateEntityObject(entity) {
    const old = this.objects.get(entity.id);
    const runtimePos = old ? { x: old.x, y: old.y } : null;
    old?.destroy(true);
    this.objects.delete(entity.id);
    const object = this.createEntityObject(entity);
    if (runtimePos && this.store.mode === 'play') object.setPosition(runtimePos.x, runtimePos.y);
    this.decorateSelection();
  }

  syncEntity(entity) {
    const object = this.objects.get(entity.id) ?? this.createEntityObject(entity);
    if (this.store.mode === 'edit') object.setPosition(entity.x, entity.y);
    object.setRotation(entity.rotation ?? 0);
    object.list[1]?.setText?.(entity.name);
    object.setVisible(true);
    if (entity.assetId) this.ensureAssetTexture(this.assetFor(entity));
  }

  syncEntities() {
    const ids = new Set(this.store.entities.map((entity) => entity.id));
    for (const [id, object] of this.objects) {
      if (!ids.has(id)) { object.destroy(true); this.objects.delete(id); }
    }
    this.store.entities.forEach((entity) => this.syncEntity(entity));
    this.decorateSelection();
    this.refreshInteractivity();
  }

  rebuildScene() {
    for (const object of this.objects.values()) object.destroy(true);
    this.objects.clear();
    this.behaviors.reset();
    this.rebuildTilemap();
    this.syncEntities();
    this.applyWorldAppearance();
  }

  decorateSelection() {
    for (const [id, object] of this.objects) {
      const selected = id === this.store.selectedId && this.store.mode === 'edit';
      object.setScale(selected ? 1.08 : 1);
      object.setAlpha(selected ? 1 : 0.94);
    }
  }

  refreshInteractivity() {
    if (!this.scene) return;
    const enabled = this.store.mode === 'edit' && this.store.tool === 'select';
    for (const object of this.objects.values()) if (object.input) object.input.draggable = enabled;
  }

  onStoreChange(detail) {
    if (!this.scene) return;
    if (detail.type === 'tile:paint') this.tileLayer?.putTileAt(detail.tileIndex, detail.x, detail.y);
    else if (detail.type === 'tile:fill') this.rebuildTilemap();
    else if (detail.full || detail.type.startsWith('scene:')) this.rebuildScene();
    else this.syncEntities();
    if (detail.type === 'world:night') this.applyWorldAppearance();
  }

  onModeChange() {
    if (!this.scene) return;
    this.behaviors.reset();
    this.syncEntities();
    this.refreshInteractivity();
    this.decorateSelection();
  }

  applyWorldAppearance() {
    if (!this.scene) return;
    this.scene.cameras.main.setBackgroundColor(this.store.settings.night ? '#03050a' : '#142131');
    this.tileLayer?.setAlpha(this.store.settings.night ? 0.82 : 1);
  }

  isTypingInEditor() {
    const active = document.activeElement;
    if (!active) return false;
    const tag = active.tagName?.toLowerCase();
    return tag === 'input' || tag === 'textarea' || tag === 'select' || active.isContentEditable;
  }

  update(time, dt) {
    if (!this.scene || this.store.mode !== 'play') return;
    const player = this.store.entities.find((entity) => entity.type === 'player');
    const playerObject = player && this.objects.get(player.id);
    if (playerObject && !this.isTypingInEditor()) {
      let dx = 0, dy = 0;
      if (this.keys.left.isDown || this.keys.arrowLeft.isDown) dx--;
      if (this.keys.right.isDown || this.keys.arrowRight.isDown) dx++;
      if (this.keys.up.isDown || this.keys.arrowUp.isDown) dy--;
      if (this.keys.down.isDown || this.keys.arrowDown.isDown) dy++;
      if (dx || dy) {
        const length = Math.hypot(dx, dy), boost = this.keys.boost.isDown ? 1.6 : 1;
        playerObject.x = Phaser.Math.Clamp(playerObject.x + dx / length * (player.speed ?? 240) * boost * dt, 20, this.store.settings.width - 20);
        playerObject.y = Phaser.Math.Clamp(playerObject.y + dy / length * (player.speed ?? 240) * boost * dt, 20, this.store.settings.height - 20);
      }
    }
    const context = { time, player: playerObject, onCollect: (entity, behavior) => window.dispatchEvent(new CustomEvent('hge:collect', { detail: { entity, behavior } })) };
    for (const entity of this.store.entities) {
      if (entity.type === 'player') continue;
      const object = this.objects.get(entity.id);
      if (object) this.behaviors.update(entity, object, context, dt);
    }
  }

  screenToWorld(clientX, clientY) {
    const rect = this.game.canvas.getBoundingClientRect();
    return { x: (clientX - rect.left) * this.store.settings.width / rect.width, y: (clientY - rect.top) * this.store.settings.height / rect.height };
  }

  dropAsset(type, clientX, clientY) {
    const pos = this.screenToWorld(clientX, clientY);
    return this.store.createEntity(type, { x: Math.round(pos.x), y: Math.round(pos.y) });
  }
}
