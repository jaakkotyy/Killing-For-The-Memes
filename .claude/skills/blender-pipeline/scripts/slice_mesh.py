# Prints horizontal cross-sections of a mesh object (Blender 2.81+), read-only. Use it to
# measure joint landmarks: limbs show up as separate clusters along the lateral axis.
# Usage: blender -b file.blend --python slice_mesh.py -- <object> [step=0.1] [lateral=y]
import sys
import bpy

argv = sys.argv[sys.argv.index("--") + 1:]
name = argv[0]
step = float(argv[1]) if len(argv) > 1 else 0.1
lateral = argv[2] if len(argv) > 2 else "y"
obj = bpy.data.objects[name]
verts = [obj.matrix_world @ v.co for v in obj.data.vertices]
lo = min(v.z for v in verts)
hi = max(v.z for v in verts)
print("SLICE %s z %.3f..%.3f (height %.3f)" % (name, lo, hi, hi - lo))


def side(v):
	return getattr(v, lateral)


z = hi
while z > lo - step:
	band = sorted((v for v in verts if abs(v.z - z) < step / 2 and side(v) >= -1e-4), key=side)
	if band:
		clusters = [[band[0]]]
		for a, b in zip(band, band[1:]):
			if side(b) - side(a) > step * 1.2:
				clusters.append([])
			clusters[-1].append(b)
		parts = []
		for c in clusters:
			n = len(c)
			parts.append("[%s %.2f..%.2f centre=(%.2f,%.2f,%.2f)]" % (
				lateral, side(c[0]), side(c[-1]),
				sum(v.x for v in c) / n, sum(v.y for v in c) / n, sum(v.z for v in c) / n))
		print("z=%.2f %s" % (z, " ".join(parts)))
	z -= step
