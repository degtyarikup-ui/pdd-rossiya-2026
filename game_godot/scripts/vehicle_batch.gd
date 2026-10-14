## Cache a single indexed NPC mesh from the garage model. One asset, two render modes.
class_name VehicleBatch
extends RefCounted

## New models tag actual indicator faces, so headlamps never become turn halos.
static func lenses(mesh: Mesh) -> Array[Dictionary]:
	var bins := {}
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var roles: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
		if roles.size() != vertices.size(): continue
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(vertices.size()))
		for i in range(0, indices.size(), 3):
			var a := indices[i]; var b := indices[i+1]; var c := indices[i+2]
			if roles[a].x > .5 or absf(roles[a].y-3.0) > .05: continue
			var centre := (vertices[a]+vertices[b]+vertices[c])/3.0
			var side := "L" if centre.x > 0 else "R"
			var key := side + ("front" if centre.z > 0 else "rear")
			if not bins.has(key): bins[key] = {"side":side,"box":AABB(vertices[a],Vector3.ZERO)}
			for point in [vertices[a],vertices[b],vertices[c]]: bins[key].box=bins[key].box.expand(point)
	var result: Array[Dictionary] = []
	for bin in bins.values(): result.append({"side":bin.side,"p":bin.box.get_center()})
	return result

static func bake(root: Node3D) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var indices := PackedInt32Array()
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var cursor: Node = mi
		while cursor != root and cursor != null:
			if cursor is Node3D: xf = cursor.transform * xf
			cursor = cursor.get_parent()
		var normal_frame := xf.basis.inverse().transposed()
		for surface in mi.mesh.get_surface_count():
			var a := mi.mesh.surface_get_arrays(surface)
			var points: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			var cs: PackedColorArray = a[Mesh.ARRAY_COLOR] if a[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			var uvs: PackedVector2Array = a[Mesh.ARRAY_TEX_UV] if a[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var pivots: PackedVector2Array = a[Mesh.ARRAY_TEX_UV2] if a[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
			var mat := mi.mesh.surface_get_material(surface) as BaseMaterial3D
			var generated: bool = mat != null and (mat.resource_name == "baked" or (mat.resource_name == "lens" and not pivots.is_empty() and pivots[0].y > 1.0))
			var offset := vertices.size()
			for i in points.size():
				vertices.append(xf * points[i])
				normals.append((normal_frame * ns[i]).normalized())
				var colour := cs[i] if cs.size() == points.size() else (mat.albedo_color if mat != null else Color.WHITE)
				var pivot := pivots[i] if generated else Vector2.ZERO
				var tex := uvs[i] if generated else Vector2.ZERO
				if not generated:
					colour.a = 1.0 if mat != null and mat.resource_name == "paint" else 0.0
				if pivot.x > .5:
					var centre := xf * Vector3(0, tex.y, tex.x)
					tex = Vector2(centre.z, centre.y)
				uv.append(tex); uv2.append(pivot); colours.append(colour)
			var source_indices: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			if source_indices.is_empty(): source_indices = PackedInt32Array(range(points.size()))
			for index in source_indices: indices.append(offset + index)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = indices
	var material := StandardMaterial3D.new()
	material.resource_name = "baked"
	material.vertex_color_use_as_albedo = true
	var importer := ImporterMesh.new()
	importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, material)
	importer.generate_lods(60.0, 25.0, [])
	return importer.get_mesh()
