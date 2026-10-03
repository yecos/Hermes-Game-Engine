# V7.2 — Collision Physics + AI Driver Personalities

## Collision solver

V7.2 keeps the V7.1 driving model and replaces the old collision-speed clamp with impulse physics.

### Car ↔ car

- action/reaction impulse
- mass-aware response
- conservation of linear momentum
- restitution
- tangential friction
- yaw impulse from contact point
- damage based on impact speed/impulse
- continuous rubbing is treated as one contact, not hundreds of new impacts

Reference test:

- 1000 kg car at 10 m/s into 2000 kg stationary car:
  - light car after impact: ~2.13 m/s
  - heavy car after impact: ~3.93 m/s
  - momentum error: 0
- equal masses:
  - ~4.10 / 5.90 m/s after impact
- wall impact:
  - normal rebound ~-1.0 m/s
  - scraping velocity retained ~1.36 m/s
  - off-center yaw ~56.9 deg/s

### Static objects

StaticBody3D is treated as infinite mass:
- car reacts
- barrier/object does not move
- angled impacts preserve tangential motion
- repeated wall contact loses bounce and becomes a scrape

### Dynamic rigid objects

RigidBody3D receives the opposite impulse using its actual mass.

## AI drivers

All AI cars inherit ArcadeCarController3D and therefore use the same:
- vehicle mass
- tires and friction circle
- slip angle
- yaw physics
- engine torque
- automatic gearbox
- brakes
- collision solver
- damage

Only their requested inputs and race decisions differ.

### Driver profiles

1. Smooth
   - minimal slip
   - clean lines
   - conservative throttle

2. Balanced
   - general race style
   - occasional small slides

3. Late Braker
   - shorter lookahead
   - later braking
   - more trail-brake rotation

4. Drifter
   - weight-transfer initiation
   - stronger turn-in
   - sustained throttle after rear breakaway
   - active countersteer from actual yaw/slip

5. Aggressive
   - higher corner commitment
   - larger line variation
   - higher tolerated slip

Measured race sample:
- Smooth: peak drift 0.00, peak slip ~2.8°
- Balanced: peak drift ~0.59, drift time ~0.26 s
- Late Braker: peak drift ~0.67, drift time ~1.41 s
- Drifter: peak drift ~0.88, peak slip ~21.6°, drift time ~3.43 s
- Aggressive: peak drift ~0.92, peak slip ~20.9°, drift time ~3.50 s

## Traffic

AI now responds to:
- relative speed
- gap
- lateral overlap
- passing side

Low-speed traffic prefers changing line instead of deadlocking.
Emergency braking only activates on a short gap with positive closing speed.

## Tests

```powershell
godot --headless --path runtime-godot --script tests\collision_physics_smoke.gd
godot --headless --path runtime-godot --script tests\driving_physics_smoke.gd
godot --headless --path runtime-godot --editor --quit
npm test
```
