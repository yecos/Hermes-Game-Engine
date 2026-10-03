# V5 — Hermes Track Editor

V5 convierte la pista de Godot en un sistema editable por Hermes.

## Incluido

- Curve3D reconstruible en runtime.
- 6–24 puntos de control.
- Límites x/z de -65 a 65 m.
- Banking por punto de -16° a 16°.
- Interpolación de banking a lo largo de la pista.
- Altura lateral correcta sobre curvas peraltadas.
- Visual del coche inclinado según banking.
- Runoff/grava a ambos lados.
- Pit lane independiente que sale y vuelve a entrar a la recta.
- Guardrails reconstruidos automáticamente.
- Start line reconstruida automáticamente.
- LOD por distancia para props GLB.

## Comandos Godot

```json
{"command":"track_snapshot"}
{"command":"set_track_point","index":2,"x":-18,"z":-37,"bank":12}
{"command":"set_track_bank","index":2,"bank":12}
{"command":"replace_track","points":[{"x":-40,"z":-10,"bank":0}]}
{"command":"reset_track"}
```

replace_track exige entre 6 y 24 puntos y rechaza puntos consecutivos demasiado cercanos.

## Hermes Game Bridge

- GET /godot/track
- POST /godot
- POST /godot/plan

Hermes puede modificar el circuito en lenguaje natural.

Prueba confirmada:

> Haz la curva del punto 2 más peraltada. Pon banking 12° sin cambiar la posición.

Resultado:

```text
punto 2:
bank 7° → 12°
x/z sin cambios
```

Después de reconstruir la pista se completó una vuelta automática:

```text
lap             11.725 s
avg speed       86.5 km/h
max speed      100.6 km/h
off-road         0%
damage           0%
```

## Tests

```powershell
npm test
node --check bridge\hermes-game-bridge.mjs
godot --headless --path runtime-godot --script tests\track_editor_smoke.gd
godot --headless --path runtime-godot --script tests\asset_smoke.gd
godot --headless --path runtime-godot --editor --quit
```
