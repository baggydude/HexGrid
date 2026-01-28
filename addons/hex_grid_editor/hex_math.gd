@tool
class_name HexMath
extends RefCounted

## Utility class for hex grid coordinate math
## Supports both pointy-top and flat-top orientations
##
## Pointy-top: hex has a vertex pointing up (rows are straight horizontally)
## Flat-top: hex has a flat edge on top (columns are straight vertically)

## Convert axial coordinates to world position
static func axial_to_world(axial: Vector2i, hex_size: float, pointy_top: bool) -> Vector3:
	var q := float(axial.x)
	var r := float(axial.y)
	var x: float
	var z: float
	
	# hex_size is the distance from center to vertex (outer radius)
	# For pointy-top: width = sqrt(3) * size, height = 2 * size
	# For flat-top: width = 2 * size, height = sqrt(3) * size
	
	if pointy_top:
		# Pointy-top: vertices point up/down
		# Horizontal spacing: sqrt(3) * size
		# Vertical spacing: 1.5 * size (3/4 of height)
		x = hex_size * sqrt(3.0) * (q + r / 2.0)
		z = hex_size * 1.5 * r
	else:
		# Flat-top: flat edges on top/bottom
		# Horizontal spacing: 1.5 * size
		# Vertical spacing: sqrt(3) * size
		x = hex_size * 1.5 * q
		z = hex_size * sqrt(3.0) * (r + q / 2.0)
	
	return Vector3(x, 0, z)


## Convert world position to axial coordinates
static func world_to_axial(world_pos: Vector3, hex_size: float, pointy_top: bool) -> Vector2i:
	var q: float
	var r: float
	
	if pointy_top:
		q = (sqrt(3.0) / 3.0 * world_pos.x - 1.0 / 3.0 * world_pos.z) / hex_size
		r = (2.0 / 3.0 * world_pos.z) / hex_size
	else:
		q = (2.0 / 3.0 * world_pos.x) / hex_size
		r = (-1.0 / 3.0 * world_pos.x + sqrt(3.0) / 3.0 * world_pos.z) / hex_size
	
	return axial_round(Vector2(q, r))


## Round fractional axial coordinates to nearest hex
static func axial_round(axial: Vector2) -> Vector2i:
	var q := axial.x
	var r := axial.y
	var s := -q - r
	
	var rq := round(q)
	var rr := round(r)
	var rs := round(s)
	
	var q_diff := abs(rq - q)
	var r_diff := abs(rr - r)
	var s_diff := abs(rs - s)
	
	if q_diff > r_diff and q_diff > s_diff:
		rq = -rr - rs
	elif r_diff > s_diff:
		rr = -rq - rs
	
	return Vector2i(int(rq), int(rr))


## Get offset coordinates from axial (useful for rectangular grids)
static func axial_to_offset(axial: Vector2i, pointy_top: bool) -> Vector2i:
	if pointy_top:
		# Odd-r offset
		var col := axial.x + (axial.y - (axial.y & 1)) / 2
		var row := axial.y
		return Vector2i(col, row)
	else:
		# Odd-q offset
		var col := axial.x
		var row := axial.y + (axial.x - (axial.x & 1)) / 2
		return Vector2i(col, row)


## Get axial coordinates from offset
static func offset_to_axial(offset: Vector2i, pointy_top: bool) -> Vector2i:
	if pointy_top:
		# Odd-r offset
		var q := offset.x - (offset.y - (offset.y & 1)) / 2
		var r := offset.y
		return Vector2i(q, r)
	else:
		# Odd-q offset
		var q := offset.x
		var r := offset.y - (offset.x - (offset.x & 1)) / 2
		return Vector2i(q, r)


## Check if offset coordinates are within grid bounds
static func is_in_bounds(offset: Vector2i, width: int, height: int) -> bool:
	return offset.x >= 0 and offset.x < width and offset.y >= 0 and offset.y < height


## Get all axial coordinates within a rectangular grid
static func get_grid_coords(width: int, height: int, pointy_top: bool) -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	for row in range(height):
		for col in range(width):
			coords.append(offset_to_axial(Vector2i(col, row), pointy_top))
	return coords


## Get the 6 neighboring hex coordinates
static func get_neighbors(axial: Vector2i) -> Array[Vector2i]:
	var directions: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
		Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)
	]
	var neighbors: Array[Vector2i] = []
	for dir in directions:
		neighbors.append(axial + dir)
	return neighbors


## Calculate distance between two hexes
static func distance(a: Vector2i, b: Vector2i) -> int:
	return (abs(a.x - b.x) + abs(a.x + a.y - b.x - b.y) + abs(a.y - b.y)) / 2
