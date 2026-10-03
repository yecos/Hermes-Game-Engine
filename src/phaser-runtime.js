import { BehaviorEngine } from './behavior-engine.js';

const TILE_COLORS = ['#0b1119', '#1a2632', '#384758', '#1b9bad'];
const TAU = Math.PI * 2;

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

    this.raceState = new Map();
    this.raceGraphics = null;
    this.raceHud = [];
    this.raceFinished = false;

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

    // Gameplay keys must never capture typing in editor fields.
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
    this.applyGameMode();
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

    const size = this.store.settings.tileSize;
    this.tilemap = this.scene.make.tilemap({
      data: this.store.tilemap.tiles,
      tileWidth: size,
      tileHeight: size
    });
    this.tileset = this.tilemap.addTilesetImage('hge-tiles', 'hge-tiles', size, size, 0, 0, 0);
    this.tileLayer = this.tilemap.createLayer(0, this.tileset, 0, 0);
    this.tileLayer.setDepth(-10);
  }

  bindSceneInput() {
    const paint = (pointer) => {
      if (this.store.mode !== 'edit' || this.store.tool !== 'tile') return;
      if (this.store.settings.gameMode === 'racing') return;

      const size = this.store.settings.tileSize;
      const x = Math.floor(pointer.worldX / size);
      const y = Math.floor(pointer.worldY / size);
      const key = `${x}:${y}:${this.store.activeTile}`;
      if (key === this.lastPaintKey) return;

      this.lastPaintKey = key;
      this.store.paintTile(x, y, this.store.activeTile);
    };

    this.scene.input.on('pointerdown', paint);
    this.scene.input.on('pointermove', (pointer) => {
      if (pointer.isDown) paint(pointer);
      else this.lastPaintKey = '';
    });
    this.scene.input.on('pointerup', () => { this.lastPaintKey = ''; });
  }

  assetFor(entity) {
    return entity.assetId
      ? this.store.project.assets.find((asset) => asset.id === entity.assetId)
      : null;
  }

  textureKey(assetId) {
    return `hge-asset-${assetId}`;
  }

  ensureAssetTexture(asset) {
    const url = asset?.publicUrl ?? asset?.url;
    if (!asset || !url) return;

    const key = this.textureKey(asset.id);
    if (this.scene.textures.exists(key) || this.loadingAssets.has(key)) return;

    this.loadingAssets.add(key);
    this.scene.load.image(key, url);
    this.scene.load.once(`filecomplete-image-${key}`, () => {
      this.loadingAssets.delete(key);
      for (const entity of this.store.entities.filter((item) => item.assetId === asset.id)) {
        this.recreateEntityObject(entity);
      }
    });
    this.scene.load.once('loaderror', () => this.loadingAssets.delete(key));
    this.scene.load.start();
  }

  makeCarVisual(entity, color) {
    const visual = this.scene.add.container(0, 0);
    const body = this.scene.add
      .rectangle(0, 0, entity.w ?? 30, entity.h ?? 54, color)
      .setStrokeStyle(2, 0xffffff, 0.7);
    const hood = this.scene.add.rectangle(0, -19, 19, 9, color, 1);
    const canopy = this.scene.add.rectangle(0, -5, 20, 19, 0x14202a, 0.96);
    const rear = this.scene.add.rectangle(0, 20, 21, 6, 0x11151a, 0.9);
    const nose = this.scene.add.rectangle(0, -25, 12, 4, 0xffffff, 0.72);

    const wheelColor = 0x08090c;
    const wheels = [
      this.scene.add.rectangle(-18, -15, 7, 14, wheelColor),
      this.scene.add.rectangle(18, -15, 7, 14, wheelColor),
      this.scene.add.rectangle(-18, 15, 7, 14, wheelColor),
      this.scene.add.rectangle(18, 15, 7, 14, wheelColor)
    ];

    visual.add([...wheels, body, hood, canopy, rear, nose]);
    return visual;
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

    if (entity.type === 'car') return this.makeCarVisual(entity, color);

    if (entity.type === 'boost') {
      const visual = this.scene.add.container(0, 0);
      const pad = this.scene.add
        .rectangle(0, 0, entity.w ?? 58, entity.h ?? 26, 0x0e3943, 0.97)
        .setStrokeStyle(2, 0x52f5ff, 0.95);
      const arrow1 = this.scene.add.triangle(-12, 0, -8, -8, 7, 0, -8, 8, 0x52f5ff, 0.95);
      const arrow2 = this.scene.add.triangle(10, 0, -8, -8, 7, 0, -8, 8, 0x52f5ff, 0.95);
      visual.add([pad, arrow1, arrow2]);
      return visual;
    }

    if (entity.type === 'enemy') {
      return this.scene.add.triangle(0, 0, 0, -20, 22, 18, -22, 18, color);
    }

    if (entity.type === 'coin') {
      return this.scene.add.star(0, 0, 4, 7, 13, color);
    }

    if (entity.type === 'obstacle') {
      return this.scene.add.rectangle(0, 0, entity.w ?? 72, entity.h ?? 48, color);
    }

    return this.scene.add.circle(0, 0, entity.size ? entity.size / 2 : 15, color);
  }

  createEntityObject(entity) {
    const container = this.scene.add.container(entity.x, entity.y).setDepth(10);
    const visual = this.makeVisual(entity);
    const labelY = entity.type === 'car' ? 38 : 30;
    const label = this.scene.add
      .text(0, labelY, entity.name, {
        fontFamily: 'system-ui',
        fontSize: '12px',
        color: '#dfe9f8',
        backgroundColor: '#06080dbb',
        padding: { x: 4, y: 2 }
      })
      .setOrigin(0.5, 0);

    container.add([visual, label]);
    container.setSize(Math.max(entity.w ?? 64, 64), Math.max(entity.h ?? 64, 64));
    container.setInteractive(
      new Phaser.Geom.Rectangle(-container.width / 2, -container.height / 2, container.width, container.height),
      Phaser.Geom.Rectangle.Contains
    );
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
    if (runtimePos && this.store.mode === 'play') {
      object.setPosition(runtimePos.x, runtimePos.y);
    }

    this.decorateSelection();
  }

  syncEntity(entity) {
    const object = this.objects.get(entity.id) ?? this.createEntityObject(entity);

    if (this.store.mode === 'edit') {
      object.setPosition(entity.x, entity.y);
      object.setRotation(entity.rotation ?? 0);
    }

    object.list[1]?.setText?.(entity.name);
    object.setVisible(true);

    if (entity.assetId) this.ensureAssetTexture(this.assetFor(entity));
  }

  syncEntities() {
    const ids = new Set(this.store.entities.map((entity) => entity.id));

    for (const [id, object] of this.objects) {
      if (!ids.has(id)) {
        object.destroy(true);
        this.objects.delete(id);
      }
    }

    this.store.entities.forEach((entity) => this.syncEntity(entity));
    this.decorateSelection();
    this.refreshInteractivity();
    this.updateEntityLabels();
  }

  rebuildScene() {
    for (const object of this.objects.values()) object.destroy(true);
    this.objects.clear();

    this.behaviors.reset();
    this.raceState.clear();
    this.raceFinished = false;
    this.clearRaceDecorations();

    this.rebuildTilemap();
    this.syncEntities();
    this.applyWorldAppearance();
    this.applyGameMode();
  }

  decorateSelection() {
    for (const [id, object] of this.objects) {
      const selected = id === this.store.selectedId && this.store.mode === 'edit';
      object.setScale(selected ? 1.08 : 1);
      object.setAlpha(selected ? 1 : 0.96);
    }
  }

  refreshInteractivity() {
    if (!this.scene) return;

    const enabled = this.store.mode === 'edit' && this.store.tool === 'select';
    for (const object of this.objects.values()) {
      if (object.input) object.input.draggable = enabled;
    }
  }

  updateEntityLabels() {
    const racing = this.store.settings.gameMode === 'racing';
    for (const entity of this.store.entities) {
      const object = this.objects.get(entity.id);
      const label = object?.list?.[1];
      if (!label?.setVisible) continue;
      const hideDuringRacePlay = racing && this.store.mode === 'play' && (entity.type === 'car' || entity.type === 'boost');
      label.setVisible(!hideDuringRacePlay);
    }
  }

  onStoreChange(detail) {
    if (!this.scene) return;

    if (detail.type === 'tile:paint') {
      this.tileLayer?.putTileAt(detail.tileIndex, detail.x, detail.y);
    } else if (detail.type === 'tile:fill') {
      this.rebuildTilemap();
    } else if (detail.full || detail.type.startsWith('scene:') || detail.type === 'race:create') {
      this.rebuildScene();
    } else {
      this.syncEntities();
    }

    if (detail.type === 'world:night') this.applyWorldAppearance();
  }

  onModeChange() {
    if (!this.scene) return;

    this.behaviors.reset();

    if (this.store.settings.gameMode === 'racing') {
      if (this.store.mode === 'play') this.resetRaceState();
      else this.restoreRaceObjectsToStore();
    } else {
      this.syncEntities();
    }

    this.refreshInteractivity();
    this.decorateSelection();
    this.updateEntityLabels();
    this.updateRaceHud();
  }

  applyWorldAppearance() {
    if (!this.scene) return;

    if (this.store.settings.gameMode === 'racing') {
      this.scene.cameras.main.setBackgroundColor('#5f9f46');
      this.tileLayer?.setVisible(false);
      return;
    }

    this.scene.cameras.main.setBackgroundColor(this.store.settings.night ? '#03050a' : '#142131');
    this.tileLayer?.setVisible(true);
    this.tileLayer?.setAlpha(this.store.settings.night ? 0.82 : 1);
  }

  clearRaceDecorations() {
    this.raceGraphics?.destroy();
    this.raceGraphics = null;

    for (const item of this.raceHud) item.destroy?.();
    this.raceHud = [];
  }

  applyGameMode() {
    if (!this.scene) return;

    this.clearRaceDecorations();

    if (this.store.settings.gameMode !== 'racing') {
      this.raceState.clear();
      return;
    }

    this.drawRaceTrack();
    this.resetRaceState();
    this.createRaceHud();
    this.updateEntityLabels();
  }

  raceConfig() {
    return this.store.settings.race;
  }

  trackGeometry() {
    const track = this.raceConfig()?.track;
    if (!track) return null;

    return {
      ...track,
      centerRx: track.rx - track.roadWidth / 2,
      centerRy: track.ry - track.roadWidth / 2,
      innerRx: track.rx - track.roadWidth,
      innerRy: track.ry - track.roadWidth
    };
  }

  drawRaceTrack() {
    const track = this.trackGeometry();
    if (!track) return;

    const g = this.scene.add.graphics().setDepth(-8);
    this.raceGraphics = g;

    // Grass base.
    g.fillStyle(0x639f48, 1);
    g.fillRect(0, 0, this.store.settings.width, this.store.settings.height);

    // Decorative darker grass bands.
    g.fillStyle(0x4f8a3e, 0.42);
    for (let y = 0; y < this.store.settings.height; y += 72) {
      g.fillRect(0, y, this.store.settings.width, 34);
    }

    // Road body.
    g.fillStyle(0x4a4f57, 1);
    g.fillEllipse(track.cx, track.cy, track.rx * 2, track.ry * 2);

    // Outer dark edge.
    g.lineStyle(8, 0x2c3036, 1);
    g.strokeEllipse(track.cx, track.cy, track.rx * 2, track.ry * 2);

    // Inner grass island.
    g.fillStyle(0x69a94d, 1);
    g.fillEllipse(track.cx, track.cy, track.innerRx * 2, track.innerRy * 2);

    // Inner dark edge.
    g.lineStyle(8, 0x2d3238, 1);
    g.strokeEllipse(track.cx, track.cy, track.innerRx * 2, track.innerRy * 2);

    // Center racing line.
    g.lineStyle(3, 0xf3e7a4, 0.32);
    g.strokeEllipse(track.cx, track.cy, track.centerRx * 2, track.centerRy * 2);

    // Arcade curbs around both edges.
    const curbCount = 48;
    for (let i = 0; i < curbCount; i++) {
      const angle = (i / curbCount) * TAU;
      const color = i % 2 === 0 ? 0xf5f3ef : 0xe74747;

      const ox = track.cx + (track.rx - 6) * Math.cos(angle);
      const oy = track.cy + (track.ry - 6) * Math.sin(angle);
      g.fillStyle(color, 1);
      g.fillCircle(ox, oy, 6);

      const ix = track.cx + (track.innerRx + 6) * Math.cos(angle);
      const iy = track.cy + (track.innerRy + 6) * Math.sin(angle);
      g.fillCircle(ix, iy, 6);
    }

    // Start / finish checker stripe at the bottom.
    const startY = track.cy + track.centerRy;
    const stripeWidth = track.roadWidth - 18;
    const stripeX = track.cx - stripeWidth / 2;
    const cell = 12;

    for (let row = 0; row < 2; row++) {
      for (let x = 0; x < stripeWidth; x += cell) {
        const even = (Math.floor(x / cell) + row) % 2 === 0;
        g.fillStyle(even ? 0xffffff : 0x111111, 0.95);
        g.fillRect(stripeX + x, startY - 12 + row * 12, cell, 12);
      }
    }

    // Trees / bushes outside and inside the circuit for the arcade look.
    const foliage = [
      [90, 90], [160, 145], [1115, 95], [1190, 175], [90, 625], [1160, 620],
      [640, 305], [530, 350], [745, 380], [645, 430], [430, 260], [860, 285]
    ];

    for (let i = 0; i < foliage.length; i++) {
      const [x, y] = foliage[i];
      const radius = 18 + (i % 3) * 5;
      g.fillStyle(i % 2 ? 0x2f733e : 0x397f43, 1);
      g.fillCircle(x, y, radius);
      g.fillStyle(0x72b550, 0.9);
      g.fillCircle(x - radius * 0.25, y - radius * 0.25, radius * 0.65);
    }
  }

  createRaceHud() {
    const baseStyle = {
      fontFamily: 'system-ui, sans-serif',
      color: '#ffffff',
      stroke: '#10151a',
      strokeThickness: 5
    };

    this.raceHud = [
      this.scene.add.text(26, 22, '1st', { ...baseStyle, fontSize: '44px', fontStyle: 'bold' }).setDepth(1000),
      this.scene.add.text(28, 74, 'LAP 1/3', { ...baseStyle, fontSize: '18px', fontStyle: 'bold' }).setDepth(1000),
      this.scene.add.text(1060, 24, '0 km/h', { ...baseStyle, fontSize: '26px', fontStyle: 'bold' }).setDepth(1000),
      this.scene.add.text(1060, 60, 'WASD / ARROWS\nSPACE = TURBO', { ...baseStyle, fontSize: '12px', color: '#dce6ef' }).setDepth(1000),
      this.scene.add.text(640, 24, '', { ...baseStyle, fontSize: '30px', fontStyle: 'bold' }).setOrigin(0.5, 0).setDepth(1000)
    ];

    this.updateRaceHud();
  }

  normalizedRaceAngle(x, y, track) {
    let angle = Math.atan2(
      (y - track.cy) / Math.max(1, track.centerRy),
      (x - track.cx) / Math.max(1, track.centerRx)
    );
    if (angle < 0) angle += TAU;
    return angle;
  }

  progressFromAngle(angle, track) {
    const start = track.startAngle ?? Math.PI / 2;
    return (start - angle + TAU) % TAU;
  }

  resetRaceState() {
    this.raceState.clear();
    this.raceFinished = false;

    const track = this.trackGeometry();
    if (!track) return;

    for (const entity of this.store.entities.filter((item) => item.type === 'car')) {
      const object = this.objects.get(entity.id);
      if (!object) continue;

      object.setPosition(entity.x, entity.y);
      object.setRotation(entity.rotation ?? 0);

      const angle = this.normalizedRaceAngle(entity.x, entity.y, track);
      const progress = this.progressFromAngle(angle, track);

      this.raceState.set(entity.id, {
        speed: 0,
        angle,
        lap: 0,
        progress,
        lastProgress: progress,
        totalProgress: progress,
        finished: false
      });
    }

    this.updateRaceHud();
  }

  restoreRaceObjectsToStore() {
    for (const entity of this.store.entities) {
      const object = this.objects.get(entity.id);
      if (!object) continue;
      object.setPosition(entity.x, entity.y);
      object.setRotation(entity.rotation ?? 0);
      object.setVisible(true);
    }
    this.raceState.clear();
    this.raceFinished = false;
    this.updateRaceHud();
  }

  isTypingInEditor() {
    const active = document.activeElement;
    if (!active) return false;
    const tag = active.tagName?.toLowerCase();
    return tag === 'input' || tag === 'textarea' || tag === 'select' || active.isContentEditable;
  }

  isOnRaceTrack(x, y, track) {
    const dx = x - track.cx;
    const dy = y - track.cy;

    const outer = (dx * dx) / (track.rx * track.rx) + (dy * dy) / (track.ry * track.ry);
    const inner = (dx * dx) / (track.innerRx * track.innerRx) + (dy * dy) / (track.innerRy * track.innerRy);

    return outer <= 1 && inner >= 1;
  }

  nudgeToTrack(object, track) {
    const angle = this.normalizedRaceAngle(object.x, object.y, track);
    const tx = track.cx + track.centerRx * Math.cos(angle);
    const ty = track.cy + track.centerRy * Math.sin(angle);

    object.x += (tx - object.x) * 0.035;
    object.y += (ty - object.y) * 0.035;
  }

  updateLapState(state, progress, totalLaps) {
    if (state.lastProgress > 5.4 && progress < 0.8) {
      state.lap += 1;
      if (state.lap >= totalLaps) state.finished = true;
    } else if (state.lastProgress < 0.8 && progress > 5.4 && state.lap > 0) {
      state.lap -= 1;
    }

    state.progress = progress;
    state.lastProgress = progress;
    state.totalProgress = state.lap * TAU + progress;
  }

  updatePlayerCar(entity, object, state, track, dt) {
    const canDrive = !this.isTypingInEditor();

    const throttle = canDrive && (this.keys.up.isDown || this.keys.arrowUp.isDown);
    const brake = canDrive && (this.keys.down.isDown || this.keys.arrowDown.isDown);
    const steerLeft = canDrive && (this.keys.left.isDown || this.keys.arrowLeft.isDown);
    const steerRight = canDrive && (this.keys.right.isDown || this.keys.arrowRight.isDown);
    const turbo = canDrive && this.keys.boost.isDown;

    const maxSpeed = Number(entity.maxSpeed ?? 465);
    const acceleration = Number(entity.acceleration ?? 700);
    const braking = Number(entity.brake ?? 840);

    if (throttle) state.speed += acceleration * dt;
    if (brake) state.speed -= braking * dt;

    if (!throttle && !brake) {
      state.speed *= Math.pow(Number(entity.grip ?? 0.986), dt * 60);
      if (Math.abs(state.speed) < 1.5) state.speed = 0;
    }

    const turboMax = turbo ? maxSpeed * 1.2 : maxSpeed;
    if (turbo && state.speed > 0) state.speed += 230 * dt;

    state.speed = Phaser.Math.Clamp(state.speed, -maxSpeed * 0.32, turboMax);

    const steer = (steerRight ? 1 : 0) - (steerLeft ? 1 : 0);
    const steeringAmount = Number(entity.steering ?? 3.05);
    const speedFactor = Phaser.Math.Clamp(Math.abs(state.speed) / Math.max(1, maxSpeed), 0.08, 1);

    if (steer !== 0 && Math.abs(state.speed) > 4) {
      object.rotation += steer * steeringAmount * speedFactor * dt * Math.sign(state.speed);
    }

    object.x += Math.sin(object.rotation) * state.speed * dt;
    object.y -= Math.cos(object.rotation) * state.speed * dt;

    if (!this.isOnRaceTrack(object.x, object.y, track)) {
      state.speed *= Math.pow(0.91, dt * 60);
      this.nudgeToTrack(object, track);
    }

    for (const pad of this.store.entities.filter((item) => item.type === 'boost')) {
      const padObject = this.objects.get(pad.id);
      if (!padObject) continue;
      if (Phaser.Math.Distance.Between(object.x, object.y, padObject.x, padObject.y) < 48) {
        state.speed = Math.min(turboMax, state.speed + 320 * dt);
      }
    }

    object.x = Phaser.Math.Clamp(object.x, 10, this.store.settings.width - 10);
    object.y = Phaser.Math.Clamp(object.y, 10, this.store.settings.height - 10);

    const angle = this.normalizedRaceAngle(object.x, object.y, track);
    const progress = this.progressFromAngle(angle, track);
    this.updateLapState(state, progress, this.raceConfig()?.laps ?? 3);
  }

  updateAiCar(entity, object, state, track, dt, index) {
    if (state.finished) return;

    const skill = Number(entity.aiSkill ?? 1);
    const lane = ((index % 3) - 1) * 15;
    const angularSpeed = 0.78 * skill;

    state.angle = (state.angle - angularSpeed * dt + TAU) % TAU;

    const rx = track.centerRx + lane;
    const ry = track.centerRy + lane * 0.5;

    object.x = track.cx + rx * Math.cos(state.angle);
    object.y = track.cy + ry * Math.sin(state.angle);
    object.rotation = Math.atan2(rx * Math.sin(state.angle), ry * Math.cos(state.angle));

    state.speed = 335 * skill;
    const progress = this.progressFromAngle(state.angle, track);
    this.updateLapState(state, progress, this.raceConfig()?.laps ?? 3);
  }

  ordinal(value) {
    const mod10 = value % 10;
    const mod100 = value % 100;
    if (mod10 === 1 && mod100 !== 11) return `${value}st`;
    if (mod10 === 2 && mod100 !== 12) return `${value}nd`;
    if (mod10 === 3 && mod100 !== 13) return `${value}rd`;
    return `${value}th`;
  }

  updateRaceHud() {
    if (!this.raceHud.length) return;

    const player = this.store.entities.find((entity) => entity.type === 'car' && entity.role === 'player');
    const state = player && this.raceState.get(player.id);
    const laps = this.raceConfig()?.laps ?? 3;

    if (this.store.mode !== 'play' || !state) {
      this.raceHud[0].setText('ARCADE GP');
      this.raceHud[1].setText(`LAPS ${laps}`);
      this.raceHud[2].setText('PRESS PLAY');
      this.raceHud[4].setText('');
      return;
    }

    const standings = [...this.raceState.entries()]
      .sort((a, b) => b[1].totalProgress - a[1].totalProgress);
    const place = Math.max(1, standings.findIndex(([id]) => id === player.id) + 1);

    const kmh = Math.max(0, Math.round(Math.abs(state.speed) * 0.72));
    const displayedLap = Math.min(laps, state.lap + 1);

    this.raceHud[0].setText(this.ordinal(place));
    this.raceHud[1].setText(`LAP ${displayedLap}/${laps}`);
    this.raceHud[2].setText(`${kmh} km/h`);

    if (state.finished && !this.raceFinished) {
      this.raceFinished = true;
      this.raceHud[4].setText(`FINISH · ${this.ordinal(place)}`);
    }
  }

  updateRace(time, dt) {
    const track = this.trackGeometry();
    if (!track) return;

    const cars = this.store.entities.filter((entity) => entity.type === 'car');
    const player = cars.find((entity) => entity.role === 'player');

    for (let i = 0; i < cars.length; i++) {
      const entity = cars[i];
      const object = this.objects.get(entity.id);
      if (!object) continue;

      let state = this.raceState.get(entity.id);
      if (!state) {
        const angle = this.normalizedRaceAngle(object.x, object.y, track);
        const progress = this.progressFromAngle(angle, track);
        state = {
          speed: 0,
          angle,
          lap: 0,
          progress,
          lastProgress: progress,
          totalProgress: progress,
          finished: false
        };
        this.raceState.set(entity.id, state);
      }

      if (entity.role === 'player') this.updatePlayerCar(entity, object, state, track, dt);
      else this.updateAiCar(entity, object, state, track, dt, i);
    }

    // Keep turbo pads visually alive.
    for (const pad of this.store.entities.filter((entity) => entity.type === 'boost')) {
      const object = this.objects.get(pad.id);
      if (!object) continue;
      object.setAlpha(0.72 + Math.sin(time * 0.008 + pad.x) * 0.22);
      object.setScale(1 + Math.sin(time * 0.006 + pad.y) * 0.04);
    }

    if (player) this.updateRaceHud();
  }

  update(time, dt) {
    if (!this.scene || this.store.mode !== 'play') return;

    if (this.store.settings.gameMode === 'racing') {
      this.updateRace(time, dt);
      return;
    }

    const player = this.store.entities.find((entity) => entity.type === 'player');
    const playerObject = player && this.objects.get(player.id);

    if (playerObject && !this.isTypingInEditor()) {
      let dx = 0;
      let dy = 0;

      if (this.keys.left.isDown || this.keys.arrowLeft.isDown) dx--;
      if (this.keys.right.isDown || this.keys.arrowRight.isDown) dx++;
      if (this.keys.up.isDown || this.keys.arrowUp.isDown) dy--;
      if (this.keys.down.isDown || this.keys.arrowDown.isDown) dy++;

      if (dx || dy) {
        const length = Math.hypot(dx, dy);
        const boost = this.keys.boost.isDown ? 1.6 : 1;
        playerObject.x = Phaser.Math.Clamp(
          playerObject.x + dx / length * (player.speed ?? 240) * boost * dt,
          20,
          this.store.settings.width - 20
        );
        playerObject.y = Phaser.Math.Clamp(
          playerObject.y + dy / length * (player.speed ?? 240) * boost * dt,
          20,
          this.store.settings.height - 20
        );
      }
    }

    const context = {
      time,
      player: playerObject,
      onCollect: (entity, behavior) => {
        window.dispatchEvent(new CustomEvent('hge:collect', { detail: { entity, behavior } }));
      }
    };

    for (const entity of this.store.entities) {
      if (entity.type === 'player') continue;
      const object = this.objects.get(entity.id);
      if (object) this.behaviors.update(entity, object, context, dt);
    }
  }

  screenToWorld(clientX, clientY) {
    const rect = this.game.canvas.getBoundingClientRect();
    return {
      x: (clientX - rect.left) * this.store.settings.width / rect.width,
      y: (clientY - rect.top) * this.store.settings.height / rect.height
    };
  }

  dropAsset(type, clientX, clientY) {
    const pos = this.screenToWorld(clientX, clientY);
    return this.store.createEntity(type, {
      x: Math.round(pos.x),
      y: Math.round(pos.y)
    });
  }
}
