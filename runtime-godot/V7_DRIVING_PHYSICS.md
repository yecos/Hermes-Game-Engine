# V7 — Driving Physics

La conducción V7 reemplaza el movimiento arcade basado en velocidad objetivo por un modelo dinámico de fuerzas en el plano.

## Chasis

- masa: 1160 kg
- distancia entre ejes: 2.62 m
- centro de gravedad configurable
- inercia de yaw
- transferencia longitudinal de carga
- drag aerodinámico
- resistencia a la rodadura
- grip diferente para asfalto y off-road

## Neumáticos

Cada frame calcula:

- slip angle delantero
- slip angle trasero
- fuerza lateral delantera
- fuerza lateral trasera
- círculo de fricción combinado con aceleración/frenado
- saturación independiente por eje
- vehicle slip angle
- yaw rate
- aceleración lateral y longitudinal

Las fuerzas laterales usan una saturación no lineal con tanh para evitar transiciones bruscas.

## Derrape

El derrape no se activa por animación. Aparece cuando el eje trasero entra en saturación y el vehículo acumula ángulo de deriva.

La asistencia arcade permite un drift fuerte pero controlable:

- ventana objetivo de slip: hasta ~30°
- límite de yaw dependiente de grip y velocidad
- ESC suave
- recuperación con lift + contravolante
- skid marks, humo y audio dependen de drift_intensity

Prueba controlada V7:

- entrada: ~86 km/h, 82% throttle, 68% steering
- máximo slip: ~32.7°
- máximo yaw: ~64.6°/s
- recuperación: ~3.2° después de lift + countersteer

## Transmisión

Caja automática R + 5 velocidades:

- relaciones: 3.20 / 2.25 / 1.70 / 1.35 / 1.10
- final drive: 4.10
- rueda: 0.31 m
- ralentí: 1050 rpm
- corte: 7600 rpm
- torque máximo: 335 Nm
- torque real depende de RPM
- clutch/torque cut durante cada cambio
- downshift con sincronización de RPM
- S frena y después engrana R
- W desde reversa frena y vuelve a 1ª

Tiempos de upshift medidos:

- 1 → 2: ~0.242 s
- 2 → 3: ~0.208 s
- 3 → 4: ~0.183 s
- 4 → 5: ~0.175 s

Métricas de referencia:

- 0–100 km/h: ~7.08 s
- velocidad máxima simulada: ~172.8 km/h

## Runtime validation

El test-driver completó una vuelta con la física nueva:

- lap: ~22.69 s
- damage: 0%
- off-road: 0%
- average slip: 0.037
- tire remaining: 100%

## Test

```powershell
godot --headless --path runtime-godot --script tests\driving_physics_smoke.gd
```
