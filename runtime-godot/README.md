# Hermes Game Engine — Godot Racing Runtime

Runtime 3D comercial de carreras arcade para Hermes Game Engine.

## Incluido

- `ArcadeCarController3D`: física arcade propia sobre `CharacterBody3D`.
- `TrackSpline`: circuito procedural 3D basado en `Curve3D`.
- Carretera, bordillos rojo/blanco, guardrails visuales y colisiones físicas.
- Cámara 3/4 con seguimiento, look-ahead y FOV dinámico.
- 5 rivales IA siguiendo la racing line.
- HUD con posición, vueltas, sectores, tiempos, velocidad, fuel, tires y damage.
- Fuel consumption, tire wear, damage y servicio de pits.
- Slip telemetry, skid marks, humo de derrape y suspensión visual.
- Audio procedural de motor con `AudioStreamGenerator`.
- Pit complex, gradas, césped, iluminación y vegetación procedural.
- Controles: WASD/flechas; Space = turbo; E = pit service.
- Bridge TCP local Godot en `127.0.0.1:8650`.
- Hermes puede leer telemetría y cambiar tuning en vivo.

## Hermes ↔ Godot

El runtime escucha comandos JSON por TCP, una línea por comando.

Comandos soportados:

```json
{"command":"telemetry"}
{"command":"reset_car"}
{"command":"service_car"}
{"command":"set_tuning","values":{"lateral_grip":16,"acceleration":26}}
```

El Hermes Game Bridge expone además:

- `GET /godot/telemetry`
- `POST /godot`
- `POST /godot/plan`

`/godot/plan` usa el modelo activo de Hermes para traducir lenguaje natural a un comando de tuning seguro y limitado.

Ejemplo:

> Haz que el carro tenga un poco más de agarre, pero no cambies la velocidad máxima.

Hermes puede responder con:

```json
{"command":"set_tuning","values":{"lateral_grip":16}}
```

## Ejecutar

```powershell
godot --path runtime-godot
```

Editor:

```powershell
godot --path runtime-godot --editor
```

## Validación

```powershell
godot --headless --path runtime-godot --editor --quit
npm test
node --check bridge/hermes-game-bridge.mjs
```

## Próximos módulos

- superficies físicas por material;
- pit lane completo con entrada/salida dedicada;
- checkpoints físicos y penalizaciones;
- replays y cámaras TV;
- modelos 3D originales de mayor detalle;
- audio de neumáticos/impactos/ambiente;
- telemetría por vuelta para auto-balance de Hermes;
- multiplayer autoritativo.
