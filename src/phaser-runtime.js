const TILE_COLORS = ['#0b1119', '#1a2632', '#384758', '#1b9bad'];

export class PhaserRuntime {
  constructor(store, parent = 'gameMount') {
    this.store = store;
    this.parent = parent;
    this.objects = new Map();
    this.ready = false;
    this.dragCheckpoint = false;
    this.playSnapshot = null;
    this.lastPaintKey = '';
    this.store.addEventListener('change', (event) => this.onStoreChange(event.detail));
    this.store.addEventListener('mode', () => this.onModeChange());
    this.store.addEventListener('selection', () => this.decorateSelection());
    this.store.addEventListener('tool', () => this.refreshInteractivity());
  }

  start() {
    const settings = this.store.project.settings;
    const runtime = this;
    class EditorScene extends Phaser.Scene {
      constructor() { super('HermesEditorScene'); }
      create() { runtime.scene = this; runtime.createScene(); }
      update(_time, delta) { runtime.update(delta / 1000); }
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
    this.keys = this.scene.input.keyboard.addKeys({
      up: Phaser.Input.Keyboard.KeyCodes.W,
      down: Phaser.Input.Keyboard.KeyCodes.S,
      left: Phaser.Input.Keyboard.KeyCodes.A,
      right: Phaser.Input.Keyboard.KeyCodes.D,
      boost: Phaser.Input.Keyboard.KeyCodes.SPACE
    });
    this.cursors = this.scene.input.keyboard.createCursorKeys();
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
      ctx.fillStyle = color;
      ctx.fillRect(x, 0, 32, 32);
      ctx.strokeStyle = index === 3 ? '#46e6ff55' : '#ffffff0b';
      ctx.strokeRect(x + 0.5, 0.5, 31, 31);
      if (index === 1) {
        ctx.fillStyle = '#d9c77344';
        ctx.fillRect(x, 15, 32, 2);
      }
      if (index === 3) {
        ctx.fillStyle = '#46e6ff66';
        ctx.fillRect(x + 4, 4, 24, 3);
      }
    });
    texture.refresh();
  }

  rebuildTilemap() {
    this.tileLayer?.destroy();
    this.tilemap?.destroy();
    const project = this.store.project;
    const tileSize = project.settings.tileSize;
    this.tilemap = this.scene.make.tilemap({ data: project.tilemap.tiles, tileWidth: tileSize, tileHeight: tileSize });
    this.tileset = this.tilemap.addTilesetImage('hge-tiles', 'hge-tiles', tileSize, tileSize, 0, 0, 0);
    this.tileLayer = this.tilemap.createLayer(0, this.tileset, 0, 0);
    this.tileLayer.setDepth(-10);
  }

  bindSceneInput() {
    const paint = (pointer) => {
      if (this.store.mode !== 'edit' || this.store.tool !== 'tile') return;
      const size = this.store.project.settings.tileSize;
      const x = Math.floor(pointer.worldX / size);
      const y = Math.floor(pointer.worldY / size);
      const key = `${x}:${y}:${this.store.activeTile}`;
      if (key === this.lastPaintKey) return;
      this.lastPaintKey = key;
      this.store.paintTile(x, y, this.store.activeTile);
    };
    this.scene.input.on('pointerdown', paint);
    this.scene.input.on('pointermove', (pointer) => { if (pointer.isDown) paint(pointer); else this.lastPaintKey = ''; });
    this.scene.input.on('pointerup', () => { this.lastPaintKey = ''; });
  }

  createEntityObject(entity) {
    const scene = this.scene;
    const container = scene.add.container(entity.x, entity.y).setDepth(10);
    let shape;
    if (entity.type === 'enemy') shape = scene.add.triangle(0, 0, 0, -20, 22, 18, -22, 18, Phaser.Display.Color.HexStringToColor(entity.color).color);
    else if (entity.type === 'coin') shape = scene.add.star(0, 0, 4, 7, 13, Phaser.Display.Color.HexStringToColor(entity.color).color);
    else if (entity.type === 'obstacle') shape = scene.add.rectangle(0, 0, entity.w ?? 72, entity.h ?? 48, Phaser.Display.Color.HexStringToColor(entity.color).color);
    else shape = scene.add.circle(0, 0, entity.size ? entity.size / 2 : 15, Phaser.Display.Color.HexStringToColor(entity.color).color);
    const label = scene.add.text(0, 30, entity.name, { fontFamily: 'system-ui', fontSize: '12px', color: '#dfe9f8', backgroundColor: '#06080dbb', padding: { x: 4, y: 2 } }).setOrigin(0.5, 0);
    container.add([shape, label]);
    container.setSize(Math.max(entity.w ?? 56, 56), Math.max(entity.h ?? 56, 56));
    container.setInteractive(new Phaser.Geom.Rectangle(-container.width / 2, -container.height / 2, container.width, container.height), Phaser.Geom.Rectangle.Contains);
    container.setData('entityId', entity.id);
    container.on('pointerdown', (_pointer, _localX, _localY, event) => {
      if (this.store.mode === 'edit' && this.store.tool === 'select') {
        event?.stopPropagation?.();
        this.store.select(entity.id);
      }
    });
    container.on('dragstart', () => {
      if (this.store.mode !== 'edit' || this.store.tool !== 'select') return;
      this.store.checkpoint();
      this.dragCheckpoint = true;
      this.store.select(entity.id);
    });
    container.on('drag', (_pointer, dragX, dragY) => {
      if (this.store.mode !== 'edit' || this.store.tool !== 'select') return;
      const width = this.store.project.settings.width, height = this.store.project.settings.height;
      const x = Phaser.Math.Clamp(dragX, 20, width - 20);
      const y = Phaser.Math.Clamp(dragY, 20, height - 20);
      container.setPosition(x, y);
      this.store.updateEntity(entity.id, { x: Math.round(x), y: Math.round(y) }, { checkpoint: false });
    });
    container.on('dragend', () => { this.dragCheckpoint = false; });
    this.scene.input.setDraggable(container);
    this.objects.set(entity.id, container);
    this.decorateSelection();
    return container;
  }

  syncEntity(entity) {
    const object = this.objects.get(entity.id) ?? this.createEntityObject(entity);
    if (this.store.mode === 'edit') object.setPosition(entity.x, entity.y);
    object.setRotation(entity.rotation ?? 0);
    const label = object.list[1];
    if (label?.setText) label.setText(entity.name);
    object.setVisible(true);
  }

  syncEntities() {
    const ids = new Set(this.store.project.entities.map((entity) => entity.id));
    for (const [id, object] of this.objects) {
      if (!ids.has(id)) { object.destroy(true); this.objects.delete(id); }
    }
    this.store.project.entities.forEach((entity) => this.syncEntity(entity));
    this.decorateSelection();
    this.refreshInteractivity();
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
    for (const object of this.objects.values()) {
      if (object.input) object.input.draggable = enabled;
    }
  }

  onStoreChange(detail) {
    if (!this.scene) return;
    if (detail.type === 'tile:paint') {
      this.tileLayer?.putTileAt(detail.tileIndex, detail.x, detail.y);
    } else if (detail.type === 'tile:fill' || detail.full || detail.type === 'project:replace') {
      this.rebuildTilemap();
      this.syncEntities();
    } else {
      this.syncEntities();
    }
    if (detail.type === 'world:night') this.applyWorldAppearance();
  }

  onModeChange() {
    if (!this.scene) return;
    if (this.store.mode === 'play') {
      this.playSnapshot = new Map(this.store.project.entities.map((entity) => [entity.id, { x: entity.x, y: entity.y }]));
    } else {
      this.syncEntities();
      this.playSnapshot = null;
    }
    this.refreshInteractivity();
    this.decorateSelection();
  }

  applyWorldAppearance() {
    if (!this.scene) return;
    this.scene.cameras.main.setBackgroundColor(this.store.project.settings.night ? '#03050a' : '#142131');
    if (this.tileLayer) this.tileLayer.setAlpha(this.store.project.settings.night ? 0.82 : 1);
  }

  update(dt) {
    if (!this.scene || this.store.mode !== 'play') return;
    const player = this.store.project.entities.find((entity) => entity.type === 'player');
    const playerObject = player && this.objects.get(player.id);
    if (playerObject) {
      let dx = 0, dy = 0;
      if (this.keys.left.isDown || this.cursors.left.isDown) dx -= 1;
      if (this.keys.right.isDown || this.cursors.right.isDown) dx += 1;
      if (this.keys.up.isDown || this.cursors.up.isDown) dy -= 1;
      if (this.keys.down.isDown || this.cursors.down.isDown) dy += 1;
      if (dx || dy) {
        const length = Math.hypot(dx, dy);
        const boost = this.keys.boost.isDown ? 1.6 : 1;
        playerObject.x = Phaser.Math.Clamp(playerObject.x + dx / length * (player.speed ?? 240) * boost * dt, 20, this.store.project.settings.width - 20);
        playerObject.y = Phaser.Math.Clamp(playerObject.y + dy / length * (player.speed ?? 240) * boost * dt, 20, this.store.project.settings.height - 20);
      }
    }
    const now = this.scene.time.now;
    this.store.project.entities.filter((entity) => entity.type === 'enemy').forEach((entity, index) => {
      const object = this.objects.get(entity.id); if (!object) return;
      object.x = entity.x + Math.sin(now / 850 + index) * 34;
      object.y = entity.y + Math.cos(now / 1100 + index) * 18;
    });
  }

  screenToWorld(clientX, clientY) {
    const canvas = this.game.canvas;
    const rect = canvas.getBoundingClientRect();
    return {
      x: (clientX - rect.left) * this.store.project.settings.width / rect.width,
      y: (clientY - rect.top) * this.store.project.settings.height / rect.height
    };
  }

  dropAsset(type, clientX, clientY) {
    const pos = this.screenToWorld(clientX, clientY);
    return this.store.createEntity(type, { x: Math.round(pos.x), y: Math.round(pos.y) });
  }
}
