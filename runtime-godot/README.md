# Hermes Game Engine — Godot Racing Runtime

Primer vertical slice 3D del runtime comercial de carreras.

## Incluido

- `ArcadeCarController3D`: física arcade propia sobre `CharacterBody3D`.
- `TrackSpline`: circuito 3D procedural basado en `Curve3D`.
- Carretera procedural, bordillos rojo/blanco y guardrails.
- Cámara 3/4 con seguimiento, look-ahead y FOV dinámico.
- 5 rivales IA siguiendo la racing line.
- HUD de posición, vueltas y velocidad.
- Césped, iluminación y vegetación procedural.
- Controles: WASD/flechas; Space = turbo.

## Ejecutar

```powershell
godot --path runtime-godot --editor
```

o directamente:

```powershell
godot --path runtime-godot
```

## Validación headless

```powershell
godot --headless --path runtime-godot --editor --quit
godot --headless --path runtime-godot --quit-after 120
```

## Próximos módulos

- modelo de neumático/slip angle más avanzado;
- superficies físicas por material;
- pits, fuel, tire wear y damage;
- checkpoints/sectores y race rules;
- replays y cámaras TV;
- assets 3D originales de carros/entorno;
- Godot ↔ Hermes bridge y telemetría.
