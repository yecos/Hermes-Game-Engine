# Hermes Game Engine — Godot Racing Runtime

Runtime 3D de carreras arcade conectado a Hermes.

## V4 — GLB/GLTF, terreno, shaders y dirección visual

### Pipeline de assets 3D

Blender 4.4 genera assets originales y reproducibles:

- gt_car.glb
- tree_lush.glb
- grandstand.glb
- paddock_tent.glb
- light_mast.glb
- service_van.glb
- tire_stack.glb
- track_cone.glb

Generador:

~~~
"C:\Program Files\Blender Foundation\Blender 4.4\blender.exe" --background --python tools\generate_assets_blender.py -- runtime-godot\assets\generated
~~~

El pack completo es ligero y no usa contenido de terceros.

### AssetLibrary

AssetLibrary3D:

- carga GLB/GLTF;
- encuentra nodos por nombre;
- detecta Wheel_FL, Wheel_FR, Wheel_RL y Wheel_RR;
- recolorea materiales BodyPaint, BodyDark y Accent;
- aplica clearcoat al body paint;
- mantiene fallback procedural si falta un asset.

Los seis coches de carrera usan el mismo GT GLB y cambian de color por equipo.

### Terreno y elevación

TerrainBuilder3D genera un terreno ondulado de 150 × 150 m.

La misma función de altura se usa para terreno, puntos Curve3D, coche, off-road, skid marks y props colocados por Hermes. La pista ya no es completamente plana.

### Shaders

WorldMaterials3D incluye shader procedural de asfalto, ruido fino, variación de rubber/racing line, shader procedural de césped y material mejorado de curb.

### Render

V4 usa Forward+ con ProceduralSky, filmic tonemapping, ajustes de saturation/contrast, SSAO y SSIL cuando están disponibles, glow moderado, niebla ligera, luz solar cálida y reflections desde el sky.

### Props

El circuito carga GLB reales para vegetación, paddock, graderías, tents, light masts, service van, tire stacks y cones. Los elementos procedurales V3 siguen como fallback.

## Hermes colocando assets

Whitelist segura:

- grandstand
- light_mast
- paddock_tent
- service_van
- tire_stack
- track_cone
- tree_lush

Comandos TCP:

~~~
{"command":"asset_inventory"}
{"command":"spawn_asset","asset":"paddock_tent","x":-28,"z":51,"scale":1,"rotation":180}
{"command":"clear_runtime_assets"}
~~~

Hermes Game Bridge expone GET /godot/assets, POST /godot y POST /godot/plan.

Prueba confirmada con gpt-5.6-luna: Hermes recibió la instrucción de colocar una carpa a x -28 / z 51, produjo spawn_asset y Godot confirmó runtime_spawned = 1.

## Tests V4

~~~
npm test
node --check bridge\hermes-game-bridge.mjs
godot --headless --path runtime-godot --script tests\asset_smoke.gd
godot --headless --path runtime-godot --script tests\orientation_smoke.gd
godot --headless --path runtime-godot --editor --quit
~~~

Confirmado:

- 8 GLB cargables;
- 4 wheel pivots;
- materiales BodyPaint y Accent;
- coche orientado a Godot forward (-Z);
- vuelta automática sobre pista elevada: ~11.72 s;
- 0% off-road;
- 0 damage.

## V3 preservado

Siguen activos fuel, tire wear, damage, pits, sectores, replay TV, skid marks, smoke, sparks, audio procedural, test-driver, Hermes live tuning y Hermes auto-balance.

## Próximo salto

- curvas con banking;
- pit lane físicamente independiente;
- runoff/gravel;
- editor Hermes de puntos Curve3D;
- generación/importación automática de nuevos GLB;
- LOD;
- optimización de sombras;
- championship;
- multiplayer autoritativo.
