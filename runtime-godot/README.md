# Hermes Game Engine — Godot Racing Runtime

Runtime 3D de carreras arcade conectado a Hermes.

## V3 — Visual, replay y auto-balance

### Visual

- Coche GT procedural compartido por jugador y rivales.
- Carrocería por capas, splitter, diffuser, side skirts, fenders, spoiler, mirrors, headlights, taillights, exhausts, tires y rims.
- Cámara 3/4 más baja, FOV cerrado, look-ahead y zoom dinámico.
- Trackside festival con banners, tents, crowds, tire stacks y cones.
- Pit complex, gradas, árboles, césped y guardrails.
- Skid marks, humo de derrape y chispas de impactos.

### Física y carrera

- Física arcade propia con `CharacterBody3D`.
- Fuel consumption.
- Tire wear.
- Damage.
- Pit service.
- Slip telemetry.
- Guardrails con colisión.
- Sectores S1/S2/S3.
- Lap timing y best lap.
- Rivales IA sobre racing line.

### Audio

- Motor procedural con `AudioStreamGenerator`.
- Tire squeal procedural.
- Gravel/off-road noise.
- Impact noise.

### Replay TV

- Buffer de ~12 segundos.
- Replay real del coche.
- Cámaras TV automáticas alrededor del circuito.
- `R` inicia replay si ya existe suficiente historial.

### Test-driver automático

Godot puede conducir el coche usando la física real.

Comandos TCP:

```json
{"command":"start_test_run","laps":1}
{"command":"test_summary"}
{"command":"stop_test_run"}
```

Resumen de ejemplo:

```json
{
  "best_lap_seconds": 11.717,
  "average_speed_kmh": 86.5,
  "max_speed_kmh": 100.6,
  "average_slip": 0.009,
  "offroad_ratio": 0.0,
  "fuel_used_liters": 0.13
}
```

## Hermes ↔ Godot

Godot escucha localmente en:

```text
127.0.0.1:8650
```

Hermes Game Bridge:

```text
127.0.0.1:8643
```

Rutas:

- `GET /godot/telemetry`
- `POST /godot`
- `POST /godot/plan`
- `POST /godot/autobalance`

### Live tuning

Ejemplo:

> Haz que el carro tenga más agarre, pero no cambies la velocidad máxima.

Hermes traduce eso a un comando seguro:

```json
{
  "command": "set_tuning",
  "values": {
    "lateral_grip": 16
  }
}
```

### Auto-balance

`POST /godot/autobalance` ejecuta:

```text
vuelta automática
      ↓
telemetría real
      ↓
Hermes / gpt-5.6-luna
      ↓
tuning limitado
      ↓
segunda vuelta automática
      ↓
comparación antes/después
```

Prueba V3 confirmada:

```text
BEFORE
lap              11.717 s
avg speed         86.5 km/h
max speed        100.6 km/h
avg slip           0.009
off-road           0%

HERMES
lateral_grip      14 → 15
steering_rate   2.35 → 2.40
top_speed          unchanged

AFTER
lap              11.719 s
avg speed         86.5 km/h
max speed        101.1 km/h
avg slip           0.009
off-road           0%
```

## Controles

- W / ↑: acelerar
- S / ↓: frenar / reversa
- A/D o ←/→: dirección
- Space: turbo
- E: pit service
- R: replay

## Ejecutar

```powershell
godot --path runtime-godot
```

## Validación

```powershell
npm test
node --check bridge/hermes-game-bridge.mjs
godot --headless --path runtime-godot --editor --quit
```

## Próximos hitos

- circuitos con elevación real;
- física de superficies diferenciadas;
- racing line optimizada por telemetría;
- audio de ambiente/crowd;
- modelos externos GLTF/GLB;
- championship flow;
- multiplayer autoritativo;
- Hermes creando y modificando `Curve3D` directamente.
