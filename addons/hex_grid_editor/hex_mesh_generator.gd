@tool
class_name HexMeshGenerator
extends RefCounted

## Utility for generating hex prism meshes

## Generate a hex prism mesh
static func create_hex_prism(
	hex_size: float = 1.0,
	height: float = 0.1,
	pointy_top: bool = true
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# For pointy-top: first vertex points up (-Z direction, angle = -PI/2)
	# For flat-top: first vertex points right (+X direction, angle = 0)
	var angle_offset := -PI / 2.0 if pointy_top else 0.0
	var corners_top: Array[Vector3] = []
	var corners_bottom: Array[Vector3] = []
	
	# Generate corner positions
	for i in range(6):
		var angle := angle_offset + i * PI / 3.0
		var x := hex_size * cos(angle)
		var z := hex_size * sin(angle)
		corners_top.append(Vector3(x, height, z))
		corners_bottom.append(Vector3(x, 0, z))
	
	# Top face
	st.set_normal(Vector3.UP)
	for i in range(6):
		st.add_vertex(Vector3(0, height, 0))
		st.add_vertex(corners_top[i])
		st.add_vertex(corners_top[(i + 1) % 6])
	
	# Bottom face
	st.set_normal(Vector3.DOWN)
	for i in range(6):
		st.add_vertex(Vector3(0, 0, 0))
		st.add_vertex(corners_bottom[(i + 1) % 6])
		st.add_vertex(corners_bottom[i])
	
	# Side faces
	for i in range(6):
		var next := (i + 1) % 6
		var edge_dir := (corners_top[next] - corners_top[i]).normalized()
		var normal := edge_dir.cross(Vector3.UP).normalized()
		st.set_normal(normal)
		
		# First triangle
		st.add_vertex(corners_bottom[i])
		st.add_vertex(corners_top[i])
		st.add_vertex(corners_top[next])
		
		# Second triangle
		st.add_vertex(corners_bottom[i])
		st.add_vertex(corners_top[next])
		st.add_vertex(corners_bottom[next])
	
	st.generate_normals()
	return st.commit()


## Generate a flat hex mesh (no height)
static func create_hex_flat(
	hex_size: float = 1.0,
	pointy_top: bool = true
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# For pointy-top: first vertex points up (-Z direction, angle = -PI/2)
	# For flat-top: first vertex points right (+X direction, angle = 0)
	var angle_offset := -PI / 2.0 if pointy_top else 0.0
	var corners: Array[Vector3] = []
	
	for i in range(6):
		var angle := angle_offset + i * PI / 3.0
		var x := hex_size * cos(angle)
		var z := hex_size * sin(angle)
		corners.append(Vector3(x, 0, z))
	
	st.set_normal(Vector3.UP)
	for i in range(6):
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(corners[i])
		st.add_vertex(corners[(i + 1) % 6])
	
	return st.commit()
