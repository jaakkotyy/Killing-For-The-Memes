# Renders solid-shaded previews of chosen objects from the loaded .blend (Blender 2.81).
# Read-only: changes happen in memory and the file is never saved.
# Usage: blender -b file.blend --python preview_blend.py -- <out_prefix> <obj1,obj2,...>
import bpy, sys, math
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
out_prefix, names = argv[0], argv[1].split(",")

scene = bpy.context.scene
# Workbench/Eevee crash without a display in 2.81 background mode; Cycles CPU works.
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 24
scene.render.resolution_x = 700
scene.render.resolution_y = 700
scene.render.film_transparent = False

targets = [bpy.data.objects[n] for n in names]
for obj in scene.objects:
    obj.hide_render = obj not in targets
    # Simulation modifiers (smoke) are irrelevant for a shape preview and slow to evaluate.
    for mod in getattr(obj, "modifiers", []):
        if mod.type in ('SMOKE', 'FLUID'):
            mod.show_render = False

# Plain clay material and simple lighting, so missing textures don't matter.
clay = bpy.data.materials.new("PreviewClay")
clay.use_nodes = True
clay.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.75, 0.7, 0.65, 1)
clay.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.6
scene.view_layers[0].material_override = clay
world = bpy.data.worlds.new("PreviewWorld")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.12, 0.12, 0.14, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
scene.world = world
sun_data = bpy.data.lights.new("PreviewSun", 'SUN')
sun_data.energy = 4.0
sun = bpy.data.objects.new("PreviewSun", sun_data)
sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(-30))
scene.collection.objects.link(sun)

# Bounding box of all targets in world space.
corners = [t.matrix_world @ Vector(c) for t in targets for c in t.bound_box]
lo = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
hi = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
center = (lo + hi) / 2
size = max((hi - lo).length, 0.01)

cam_data = bpy.data.cameras.new("PreviewCam")
cam_data.lens = 50
cam = bpy.data.objects.new("PreviewCam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam

views = {"front": (0, -1, 0.15), "side": (1, 0, 0.15), "three_quarter": (0.8, -0.8, 0.35)}
for view_name, direction in views.items():
    d = Vector(direction).normalized()
    cam.location = center + d * size * 1.35
    cam.rotation_euler = (center - cam.location).to_track_quat('-Z', 'Y').to_euler()
    scene.render.filepath = "{}_{}.png".format(out_prefix, view_name)
    bpy.ops.render.render(write_still=True)
    print("WROTE", scene.render.filepath)
