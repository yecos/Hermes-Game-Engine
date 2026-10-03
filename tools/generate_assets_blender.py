import bpy
import math
import os
import sys

OUT = os.path.abspath(sys.argv[sys.argv.index("--") + 1]) if "--" in sys.argv else os.getcwd()
os.makedirs(OUT, exist_ok=True)

def clear_scene():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for collection in (bpy.data.meshes, bpy.data.curves, bpy.data.cameras, bpy.data.lights, bpy.data.materials):
        for block in list(collection):
            try:
                collection.remove(block)
            except Exception:
                pass

def make_material(name, color, metallic=0.0, roughness=0.5):
    m = bpy.data.materials.new(name=name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*color[:3], color[3] if len(color) > 3 else 1.0)
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
    m.diffuse_color = (*color[:3], color[3] if len(color) > 3 else 1.0)
    return m

def add_beveled_cube(name, dims, loc, mat, bevel=0.06, rot=(0,0,0), parent=None):
    bpy.ops.mesh.primitive_cube_add(location=loc, rotation=rot)
    o = bpy.context.object
    o.name = name
    o.dimensions = dims
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel > 0:
        mod = o.modifiers.new(name="SoftBevel", type='BEVEL')
        mod.width = bevel
        mod.segments = 3
        mod.limit_method = 'ANGLE'
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier=mod.name)
    o.data.materials.append(mat)
    if parent:
        o.parent = parent
    return o

def add_cylinder(name, radius, depth, loc, mat, rot=(0,0,0), parent=None, vertices=24, bevel=0.03):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc, rotation=rot)
    o = bpy.context.object
    o.name = name
    if bevel > 0:
        mod = o.modifiers.new(name="SoftBevel", type='BEVEL')
        mod.width = bevel
        mod.segments = 2
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier=mod.name)
    o.data.materials.append(mat)
    if parent:
        o.parent = parent
    return o

def add_icosphere(name, radius, loc, mat, parent=None, scale=(1,1,1)):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=radius, location=loc)
    o = bpy.context.object
    o.name = name
    o.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(mat)
    if parent:
        o.parent = parent
    return o

def add_cone(name, radius1, radius2, depth, loc, mat, parent=None, vertices=20):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius1, radius2=radius2, depth=depth, location=loc)
    o = bpy.context.object
    o.name = name
    o.data.materials.append(mat)
    if parent:
        o.parent = parent
    return o

def export_glb(name):
    path = os.path.join(OUT, name + ".glb")
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format='GLB',
        export_apply=True,
        export_yup=True,
        export_texcoords=True,
        export_normals=True,
        export_materials='EXPORT'
    )
    print("EXPORTED", path)

def root_empty(name):
    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)
    return root

def build_car():
    clear_scene()
    root = root_empty("GT_Car_Master")
    body = make_material("BodyPaint", (0.90,0.035,0.06,1), 0.48, 0.18)
    body_dark = make_material("BodyDark", (0.42,0.015,0.025,1), 0.35, 0.24)
    accent = make_material("Accent", (0.96,0.95,0.90,1), 0.16, 0.22)
    carbon = make_material("Carbon", (0.012,0.016,0.022,1), 0.12, 0.32)
    glass = make_material("Glass", (0.025,0.07,0.11,1), 0.42, 0.10)
    tire = make_material("Tire", (0.008,0.009,0.012,1), 0.0, 0.88)
    rim = make_material("Rim", (0.38,0.42,0.48,1), 0.85, 0.20)
    lamp = make_material("Headlight", (1.0,0.82,0.48,1), 0.1, 0.12)
    tail = make_material("Taillight", (0.80,0.015,0.03,1), 0.12, 0.18)

    # Blender: X width, Y length, Z height. Front is -Y.
    add_beveled_cube("Body_Main", (1.58,2.95,0.36), (0,0,0.47), body, 0.12, parent=root)
    add_beveled_cube("Body_Nose", (1.46,0.84,0.22), (0,-1.28,0.48), body_dark, 0.11, rot=(math.radians(5),0,0), parent=root)
    add_beveled_cube("Body_Rear", (1.50,0.72,0.24), (0,1.23,0.50), body_dark, 0.08, parent=root)
    add_beveled_cube("Cabin", (1.14,1.16,0.47), (0,-0.07,0.82), glass, 0.12, rot=(0,0,0), parent=root)
    add_beveled_cube("Roof", (1.02,0.78,0.09), (0,-0.02,1.085), body_dark, 0.06, parent=root)
    add_beveled_cube("Stripe", (0.22,2.50,0.04), (0,-0.03,0.69), accent, 0.02, parent=root)
    add_beveled_cube("Splitter", (1.68,0.30,0.075), (0,-1.55,0.24), carbon, 0.03, parent=root)
    add_beveled_cube("Diffuser", (1.56,0.33,0.075), (0,1.52,0.25), carbon, 0.03, parent=root)
    add_beveled_cube("Skirt_L", (0.12,2.22,0.15), (-0.82,0.08,0.31), carbon, 0.03, parent=root)
    add_beveled_cube("Skirt_R", (0.12,2.22,0.15), (0.82,0.08,0.31), carbon, 0.03, parent=root)

    # Fender shoulders.
    for sx in (-1,1):
        add_beveled_cube(f"Fender_F_{sx}", (0.20,0.72,0.27), (0.77*sx,-0.94,0.51), body_dark, 0.07, parent=root)
        add_beveled_cube(f"Fender_R_{sx}", (0.20,0.72,0.27), (0.77*sx,0.95,0.51), body_dark, 0.07, parent=root)
        add_beveled_cube(f"Mirror_{sx}", (0.24,0.28,0.12), (0.82*sx,-0.42,0.78), body_dark, 0.06, parent=root)

    # Rear wing and uprights.
    add_beveled_cube("Wing", (1.66,0.34,0.08), (0,1.40,1.03), carbon, 0.025, parent=root)
    add_beveled_cube("WingPost_L", (0.08,0.08,0.42), (-0.55,1.32,0.82), carbon, 0.018, parent=root)
    add_beveled_cube("WingPost_R", (0.08,0.08,0.42), (0.55,1.32,0.82), carbon, 0.018, parent=root)

    # Lights.
    add_beveled_cube("Headlight_L", (0.44,0.055,0.10), (-0.43,-1.49,0.52), lamp, 0.018, parent=root)
    add_beveled_cube("Headlight_R", (0.44,0.055,0.10), (0.43,-1.49,0.52), lamp, 0.018, parent=root)
    add_beveled_cube("Taillight_L", (0.42,0.055,0.09), (-0.44,1.49,0.50), tail, 0.018, parent=root)
    add_beveled_cube("Taillight_R", (0.42,0.055,0.09), (0.44,1.49,0.50), tail, 0.018, parent=root)

    # Exhausts.
    add_cylinder("Exhaust_L", 0.085, 0.28, (-0.31,1.58,0.31), carbon, rot=(math.radians(90),0,0), parent=root, vertices=16)
    add_cylinder("Exhaust_R", 0.085, 0.28, (0.31,1.58,0.31), carbon, rot=(math.radians(90),0,0), parent=root, vertices=16)

    wheel_defs = [
        ("Wheel_FL",(-0.86,-0.94,0.30)),
        ("Wheel_FR",(0.86,-0.94,0.30)),
        ("Wheel_RL",(-0.86,0.96,0.30)),
        ("Wheel_RR",(0.86,0.96,0.30)),
    ]
    for name, loc in wheel_defs:
        pivot = root_empty(name)
        pivot.location = loc
        pivot.parent = root
        add_cylinder(name+"_Tire", 0.315, 0.26, (0,0,0), tire, rot=(0,math.radians(90),0), parent=pivot, vertices=28, bevel=0.025)
        add_cylinder(name+"_Rim", 0.185, 0.275, (0,0,0), rim, rot=(0,math.radians(90),0), parent=pivot, vertices=20, bevel=0.018)
        add_cylinder(name+"_Hub", 0.065, 0.29, (0,0,0), carbon, rot=(0,math.radians(90),0), parent=pivot, vertices=16, bevel=0.01)

    export_glb("gt_car")

def build_tree():
    clear_scene()
    root = root_empty("Tree_Lush")
    trunk = make_material("Bark",(0.20,0.095,0.04,1),0.0,0.86)
    leaf1 = make_material("LeavesA",(0.055,0.34,0.07,1),0.0,0.88)
    leaf2 = make_material("LeavesB",(0.10,0.48,0.11,1),0.0,0.84)
    add_cylinder("Trunk",0.28,2.8,(0,0,1.4),trunk,parent=root,vertices=12,bevel=0.04)
    add_icosphere("Crown_A",1.45,(0,0,3.25),leaf1,parent=root,scale=(1.0,0.9,1.15))
    add_icosphere("Crown_B",1.10,(0.78,0.18,3.35),leaf2,parent=root,scale=(0.85,0.75,1.0))
    add_icosphere("Crown_C",1.05,(-0.72,-0.10,3.45),leaf2,parent=root,scale=(0.85,0.8,0.95))
    export_glb("tree_lush")

def build_grandstand():
    clear_scene()
    root = root_empty("Grandstand")
    metal=make_material("Metal",(0.18,0.21,0.25,1),0.5,0.38)
    concrete=make_material("Concrete",(0.55,0.57,0.58,1),0.0,0.82)
    blue=make_material("SeatBlue",(0.04,0.30,0.78,1),0.0,0.62)
    yellow=make_material("SeatYellow",(0.95,0.63,0.04,1),0.0,0.64)
    add_beveled_cube("Base",(10.5,5.8,1.0),(0,0,0.5),concrete,0.12,parent=root)
    for row in range(4):
        add_beveled_cube(f"Step_{row}",(10.0,1.35,0.46),(0,-1.8+row*1.0,1.15+row*0.48),concrete,0.04,parent=root)
        for col in range(10):
            mat=blue if (row+col)%2==0 else yellow
            add_beveled_cube(f"Seat_{row}_{col}",(0.72,0.58,0.34),(-4.25+col*0.94,-1.8+row*1.0,1.55+row*0.48),mat,0.06,parent=root)
    add_beveled_cube("Roof",(11.2,4.0,0.20),(0,0.95,4.1),metal,0.08,rot=(math.radians(-4),0,0),parent=root)
    for x in (-4.8,4.8):
        add_beveled_cube("RoofPost",(.18,.18,4.0),(x,1.15,2.0),metal,0.03,parent=root)
    export_glb("grandstand")

def build_tent():
    clear_scene()
    root=root_empty("PaddockTent")
    red=make_material("Fabric",(0.82,0.04,0.06,1),0.0,0.58)
    metal=make_material("Frame",(0.65,0.68,0.70,1),0.6,0.28)
    add_beveled_cube("Roof",(4.8,3.5,0.28),(0,0,2.7),red,0.08,rot=(0,math.radians(0),math.radians(2)),parent=root)
    for x in (-2.1,2.1):
        for y in (-1.45,1.45):
            add_beveled_cube("Post",(0.10,0.10,2.65),(x,y,1.33),metal,0.02,parent=root)
    export_glb("paddock_tent")

def build_light():
    clear_scene()
    root=root_empty("LightMast")
    metal=make_material("Metal",(0.32,0.35,0.38,1),0.72,0.26)
    lamp=make_material("Lamp",(0.96,0.88,0.62,1),0.12,0.18)
    add_cylinder("Pole",0.15,7.0,(0,0,3.5),metal,parent=root,vertices=16,bevel=0.02)
    add_beveled_cube("Crossbar",(3.2,0.16,0.16),(0,0,6.85),metal,0.03,parent=root)
    for x in (-1.2,-0.4,0.4,1.2):
        add_beveled_cube("FloodLight",(0.52,0.34,0.32),(x,-0.16,6.63),lamp,0.05,rot=(math.radians(12),0,0),parent=root)
    export_glb("light_mast")

def build_van():
    clear_scene()
    root=root_empty("ServiceVan")
    body=make_material("VanBody",(0.88,0.90,0.93,1),0.16,0.25)
    accent=make_material("VanAccent",(0.04,0.30,0.78,1),0.18,0.25)
    glass=make_material("VanGlass",(0.025,0.07,0.11,1),0.4,0.10)
    tire=make_material("VanTire",(0.01,0.012,0.015,1),0.0,0.9)
    add_beveled_cube("Main",(2.0,4.2,1.65),(0,0,1.15),body,0.18,parent=root)
    add_beveled_cube("Cabin",(1.90,1.35,1.30),(0,-1.55,1.34),body,0.16,rot=(math.radians(5),0,0),parent=root)
    add_beveled_cube("Windshield",(1.55,0.06,0.62),(0,-2.24,1.58),glass,0.03,parent=root)
    add_beveled_cube("Stripe",(2.03,3.2,0.15),(0,0.35,1.05),accent,0.03,parent=root)
    for x in (-1.02,1.02):
        for y in (-1.35,1.30):
            add_cylinder("VanWheel",0.38,0.24,(x,y,0.42),tire,rot=(0,math.radians(90),0),parent=root,vertices=20)
    export_glb("service_van")

def build_tire_stack():
    clear_scene()
    root=root_empty("TireStack")
    rubber=make_material("Rubber",(0.012,0.014,0.016,1),0.0,0.92)
    band=make_material("Band",(0.85,0.06,0.06,1),0.0,0.62)
    for i in range(4):
        mat = band if i==2 else rubber
        add_cylinder(f"Tire_{i}",0.42,0.24,(0,0,0.13+i*0.23),mat,parent=root,vertices=24,bevel=0.04)
    export_glb("tire_stack")

def build_cone():
    clear_scene()
    root=root_empty("TrackCone")
    orange=make_material("ConeOrange",(1.0,0.26,0.03,1),0.0,0.65)
    white=make_material("ConeWhite",(0.95,0.94,0.88,1),0.0,0.68)
    add_beveled_cube("Base",(0.58,0.58,0.08),(0,0,0.04),orange,0.04,parent=root)
    add_cone("Cone",0.22,0.055,0.58,(0,0,0.36),orange,parent=root,vertices=20)
    add_cylinder("Band",0.145,0.10,(0,0,0.40),white,parent=root,vertices=20,bevel=0.01)
    export_glb("track_cone")

builders = [
    build_car,
    build_tree,
    build_grandstand,
    build_tent,
    build_light,
    build_van,
    build_tire_stack,
    build_cone,
]

for builder in builders:
    builder()

print("HGE_ASSET_GENERATION_OK")
