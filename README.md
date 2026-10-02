# Hermes Game Engine — AI Studio V0.1

Prototipo funcional de un motor de videojuegos 2D web controlable por lenguaje natural.

## Qué funciona ahora
- Editor visual 2D en navegador con Canvas.
- Jerarquía de entidades e inspector editable.
- Player, enemigos, NPCs, monedas y objetos.
- Play/Edit mode y movimiento con WASD/flechas.
- Hermes Copilot: crea/modifica la escena con prompts.
- Comandos soportados: nivel cyberpunk, enemigos, monedas, NPCs, objetos, modo noche/día, velocidad y limpiar escena.
- Guardado en localStorage y exportación a JSON.
- Sin dependencias externas: basta servir la carpeta por HTTP.

## Ejecutar
```bash
python3 -m http.server 8080
# abrir http://localhost:8080
```

## Arquitectura objetivo
La V0.1 usa Canvas puro para validar el concepto sin dependencias. La siguiente etapa migra el runtime a Phaser, el editor a Next.js/React, proyectos a PostgreSQL/Neon y conecta Hermes como agente real mediante un contrato de tools estable.

### Contrato de tools propuesto
- createEntity(type, props)
- updateEntity(id, patch)
- deleteEntity(id)
- createScene(name)
- setWorldTheme(theme)
- addBehavior(entityId, behavior)
- runGame()
- inspectScene()
- saveProject()
- publishGame()

## Roadmap
1. Phaser runtime + tilemaps y físicas.
2. Undo/redo, drag & drop, gizmos y asset browser.
3. Adaptador Hermes real con modelo activo del gateway.
4. Generación de sprites/tiles/audio con IA.
5. Neon: usuarios, proyectos, versiones, escenas y assets.
6. Multiplayer con Colyseus/WebSockets.
7. Test agent: IA juega y corrige bugs.
8. Publicación de cada juego a URL independiente.
