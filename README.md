# Hermes Game Engine — V0.3

Motor/editor 2D web **AI-first** construido sobre Phaser 4.2.1. V0.3 añade persistencia cloud en Neon, escenas múltiples, behaviors declarativos, generación de assets y un agente autónomo de testing.

## Qué trae V0.3

- Multi-scene: cada escena conserva su tilemap, entidades e iluminación.
- Behaviors sin código: Patrol, Chase Player, Spin, Float y Collectible.
- Hermes Tool Registry ampliado para crear escenas, behaviors, assets y tests.
- Agente de testing headless que valida estructura y simula navegación hacia objetivos.
- Persistencia local + API cloud en Neon.
- Esquema normalizado para proyectos, escenas, entidades, behaviors, assets y runs.
- Generación de sprites/tiles mediante un endpoint Hermes configurable.
- Fallback SVG local para que el flujo de assets sea utilizable sin proveedor externo.
- Neon Object Storage preparado con el bucket `hge-assets`.
- Registro de ejecuciones de Hermes y del test agent.
- Migración automática de proyectos V0.2 a V0.3.
- CI en GitHub Actions.

## Backend Neon

La base dedicada es `hermes_game_engine`. El runtime nunca expone la cadena de conexión al navegador: las operaciones cloud pasan por `/api/*`.

Tablas esperadas:

- `hge_projects`
- `hge_scenes`
- `hge_entities`
- `hge_behaviors`
- `hge_assets`
- `hge_agent_runs`
- `hge_test_runs`

Los secretos se configuran como variables de entorno; usa `.env.example` como referencia.

## Ejecutar

Para probar solo el editor estático:

```bash
npm run static
```

Para probar frontend + API Vercel:

```bash
npm install
cp .env.example .env.local
# completa DATABASE_URL y HGE_API_TOKEN
npm run dev
```

Tests:

```bash
npm test
```

## Tools que Hermes puede ejecutar

- `createEntity`
- `updateEntity`
- `deleteEntity`
- `createScene`
- `switchScene`
- `addBehavior`
- `detachBehavior`
- `paintTile`
- `fillTiles`
- `setNight`
- `generateAsset`
- `testScene`
- `inspectScene`
- `inspectProject`

Hermes recibe el proyecto, la escena activa y la definición de tools; devuelve una lista de tool calls. La IA nunca necesita reescribir el estado del juego directamente.

## Assets IA

`POST /api/assets/generate` usa `HERMES_ASSET_ENDPOINT` si está configurado. El proveedor puede devolver una URL o bytes base64. Si las credenciales S3 de Neon Object Storage están configuradas, el resultado se copia al bucket `hge-assets` y la fila queda registrada en `hge_assets`.

Sin proveedor remoto, el endpoint y el cliente tienen fallbacks para validar el flujo completo sin gastar generación.

## Arquitectura

```text
Hermes / planner
      │
      ▼
ToolRegistry ────── AssetGenerator
      │                  │
      ▼                  ▼
ProjectStore ─────── Cloud API
      │                  │
      ├── scenes          ├── Lakebase Postgres
      ├── entities        └── Neon Object Storage
      └── behaviors
      │
      ▼
PhaserRuntime
      │
      └── BehaviorEngine

SceneTestAgent ──► reports / hge_test_runs
```

## Hermes local bridge

El editor web puede detectar automáticamente un Hermes Agent que esté corriendo en la misma máquina. El bridge se mantiene local y nunca publica la clave del API server en Vercel ni en el navegador.

Requisitos de Hermes:

```yaml
platforms:
  api_server:
    enabled: true
    host: 127.0.0.1
    port: 8642

platform_toolsets:
  api_server: []
```

El bridge se inicia con:

```bash
npm run bridge
```

y escucha únicamente en `127.0.0.1:8643`. Sus rutas son:

- `GET /health` — verifica Hermes y devuelve el proveedor/modelo activos.
- `POST /plan` — recibe el estado del proyecto y devuelve `{message,calls}`.

En Windows puede registrarse como tarea de inicio de sesión. El navegador conecta al bridge local, el bridge llama al API server de Hermes y Hermes usa el modelo efectivo de su perfil activo. No se fija un proveedor/modelo dentro del Game Engine.

## Próximo objetivo

V0.4: autenticación multiusuario, sprites renderizados como texturas Phaser, editor visual de behaviors, colaboración/multiplayer y un test agent con navegación/capturas sobre el runtime real.
