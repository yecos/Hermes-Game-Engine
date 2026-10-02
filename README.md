# Hermes Game Engine — V0.2

Motor/editor 2D web **AI-first**. Esta versión migra el runtime del prototipo Canvas a **Phaser 4.2.1** y convierte la integración de IA en un contrato de tools ejecutables.

## V0.2

- Runtime Phaser 4.2.1 fijado por versión.
- Tilemap real de Phaser, editable en tiempo de ejecución.
- Selección y drag & drop de entidades dentro de la escena.
- Asset Browser con drag desde el panel hacia el canvas.
- Inspector editable para posición, nombre, color, HP y velocidad.
- Modos `EDIT`, `TILE PAINT` y `PLAY`.
- WASD/flechas + espacio en modo Play.
- Undo / redo de cambios del proyecto.
- Guardado local, importación y exportación JSON.
- Hermes Tool Registry estable.
- Adaptador Hermes HTTP opcional con planner local como fallback.

## Ejecutar

No requiere build para la V0.2:

```bash
python3 -m http.server 8080
# http://localhost:8080
```

Phaser se carga desde CDN en una versión fijada. Los tests del núcleo no dependen del navegador:

```bash
npm test
```

## Contrato Hermes

`src/tool-registry.js` expone actualmente:

- `createEntity(type, x?, y?, name?)`
- `updateEntity(id, patch)`
- `deleteEntity(id)`
- `paintTile(x, y, tileIndex)`
- `fillTiles(tileIndex)`
- `setNight(night)`
- `inspectScene()`

El editor puede usar un endpoint Hermes real. El endpoint recibe:

```json
{
  "prompt": "crea tres drones",
  "tools": [],
  "project": {}
}
```

Y debe responder:

```json
{
  "message": "Creé tres drones.",
  "calls": [
    { "name": "createEntity", "args": { "type": "enemy", "name": "Drone 1" } }
  ]
}
```

La UI ejecuta esas calls a través del mismo `ToolRegistry`; el modelo no escribe directamente el estado del juego.

## Arquitectura

```text
Editor DOM
   │
ProjectStore ── history / JSON / selection
   │                 │
   │                 └── ToolRegistry ← HermesAgent ← Hermes Gateway
   │
PhaserRuntime
   ├── TilemapLayer
   ├── Game Objects
   ├── Drag & Drop
   └── Play Mode
```

## Próximo objetivo V0.3

Persistencia de proyectos en Neon, generación de sprites/tiles por IA, escenas múltiples, scripting de comportamientos y un agente de testing que juegue el nivel y reporte errores.
