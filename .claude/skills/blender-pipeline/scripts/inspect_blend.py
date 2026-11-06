# Read-only inspection of the currently loaded .blend (Blender 2.81). Never saves.
import bpy

print("=== FILE", bpy.data.filepath)
scene = bpy.context.scene
print("scene:", scene.name, "unit_scale:", scene.unit_settings.scale_length, "fps:", scene.render.fps,
      "frames:", scene.frame_start, "-", scene.frame_end)

depsgraph = bpy.context.evaluated_depsgraph_get()
total_eval_tris = 0
for obj in bpy.data.objects:
    line = "OBJ {:<30} type={:<9} parent={:<18}".format(obj.name, obj.type, obj.parent.name if obj.parent else "-")
    line += " dims=({:.2f},{:.2f},{:.2f})".format(*obj.dimensions)
    if obj.type == 'MESH':
        me = obj.data
        base_tris = sum(len(p.vertices) - 2 for p in me.polygons)
        line += " verts={} base_tris={}".format(len(me.vertices), base_tris)
        try:
            ev = obj.evaluated_get(depsgraph)
            em = ev.to_mesh()
            ev_tris = sum(len(p.vertices) - 2 for p in em.polygons)
            ev.to_mesh_clear()
            line += " eval_tris={}".format(ev_tris)
            total_eval_tris += ev_tris
        except Exception as exc:
            line += " eval_err={}".format(exc)
        if obj.modifiers:
            mods = []
            for m in obj.modifiers:
                desc = m.type
                for attr in ("levels", "render_levels", "sculpt_levels", "ratio", "total_levels"):
                    if hasattr(m, attr):
                        desc += " {}={}".format(attr, getattr(m, attr))
                if m.type == 'ARMATURE' and m.object:
                    desc += " rig=" + m.object.name
                mods.append(desc)
            line += " mods=[" + "; ".join(mods) + "]"
        if me.shape_keys:
            line += " shape_keys={}".format(len(me.shape_keys.key_blocks))
        line += " vgroups={}".format(len(obj.vertex_groups))
        line += " mats=[" + ", ".join(s.material.name if s.material else "-" for s in obj.material_slots) + "]"
        line += " uv_layers={}".format(len(me.uv_layers))
    elif obj.type == 'ARMATURE':
        line += " bones={}".format(len(obj.data.bones))
        line += " sample=[" + ", ".join(b.name for b in list(obj.data.bones)[:12]) + "]"
    if obj.animation_data and obj.animation_data.action:
        line += " action=" + obj.animation_data.action.name
    print(line)

print("TOTAL eval_tris:", total_eval_tris)
for action in bpy.data.actions:
    print("ACTION {} frames={} fcurves={}".format(action.name, tuple(action.frame_range), len(action.fcurves)))
for img in bpy.data.images:
    print("IMAGE {} size={} packed={} path={}".format(img.name, tuple(img.size), img.packed_file is not None, img.filepath))
for mat in bpy.data.materials:
    nodes = [n.type for n in mat.node_tree.nodes] if mat.use_nodes and mat.node_tree else []
    print("MAT {} users={} nodes={}".format(mat.name, mat.users, sorted(set(nodes))))
print("COUNTS meshes={} objects={} images={} actions={} cameras={} lights={}".format(
    len(bpy.data.meshes), len(bpy.data.objects), len(bpy.data.images), len(bpy.data.actions),
    len(bpy.data.cameras), len(bpy.data.lights)))
