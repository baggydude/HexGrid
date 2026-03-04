@tool
class_name ProceduralQuadGodray
extends Node3D

# Core Settings
@export_group("Grid Settings")
@export var grid_size: Vector2i = Vector2i(16, 16) : set = _set_grid_size
@export_range(0.1, 10.0, 0.1, "suffix:m") var quad_spacing: float = 10.0 : set = _set_spacing
@export_range(1, 100, 1) var layer_count: int = 1 : set = _set_layer_count
@export_range(0.01, 10.0, 0.01, "suffix:m") var layer_spacing: float = 0.5 : set = _set_layer_spacing

@export_group("Quad Settings")
@export_range(0.01, 10.0, 0.01, "suffix:m") var quad_width: float = 10.0 : set = _set_quad_size
@export_range(0.01, 10.0, 0.01, "suffix:m") var quad_height: float = 10.0 : set = _set_quad_size
@export var auto_stretch: bool = true : set = _set_auto_stretch
@export_range(0.1, 10.0, 0.1) var stretch_factor: float = 10.0 : set = _set_stretch_factor
@export_range(-180, 180, 0.1, "degrees") var yaw_control: float = 0.0 : set = _set_yaw_control
@export var auto_face_camera: bool = true : set = _set_auto_face_camera

@export_group("Variation")
@export var use_randomized_positioning: bool = true : set = _set_use_randomized
@export var poisson_disk_sampling: bool = true : set = _set_poisson_sampling
@export_range(0.1, 2.0, 0.01) var min_distance_factor: float = 0.8 : set = _set_distance_factor
@export_range(0.0, 90.0, 0.1, "degrees") var rotation_variation: float = 15.0 : set = _set_rotation_variation
@export_range(0.0, 1.0, 0.01) var scale_variation: float = 0.3 : set = _set_scale_variation
@export_range(0.0, 1.0, 0.01) var jitter_amount: float = 0.3 : set = _set_jitter_amount

@export_group("View Angle Fade")
@export var use_view_angle_fade: bool = true : set = _set_use_view_angle_fade
@export_range(0.0, 90.0, 1.0, "degrees") var fade_angle_start: float = 30.0 : set = _set_fade_angle_start
@export_range(0.0, 90.0, 1.0, "degrees") var fade_angle_end: float = 5.0 : set = _set_fade_angle_end
@export var debug_view_angle: bool = false : set = _set_debug_view_angle

@export_group("Advanced")
@export var adaptive_density: bool = false : set = _set_adaptive_density
@export_range(1.0, 10.0, 0.1) var density_multiplier: float = 2.0 : set = _set_density_multiplier
@export var godray_material: Material : set = _set_godray_material

@export_group("Debug")
@export var show_debug_info: bool = false : set = _set_show_debug_info
@export var regenerate_quads: bool = false : set = _regenerate_quads

# Core components
var sun_node: DirectionalLight3D
var multi_mesh_instance: MultiMeshInstance3D
var multi_mesh: MultiMesh
var quad_mesh: QuadMesh

# State tracking
var last_sun_direction := Vector3.ZERO
var last_camera_basis := Basis()
var needs_regeneration := true

# Configuration data
class GodrayConfig:
	var effective_grid_size: Vector2i
	var effective_spacing: float
	var layer_positions: Array[float] = []
	var rng_seed: int
	
	func _init():
		rng_seed = randi()
	
	func calculate_adaptive_params(base_grid: Vector2i, base_spacing: float, 
								  layer_count: int, layer_spacing: float, 
								  adaptive_density: bool, density_mult: float):
		if adaptive_density:
			effective_grid_size = Vector2i(int(base_grid.x * density_mult), int(base_grid.y * density_mult))
			effective_spacing = base_spacing / density_mult
		else:
			effective_grid_size = base_grid
			effective_spacing = base_spacing
		
		layer_positions.clear()
		for i in range(layer_count):
			layer_positions.append(i * layer_spacing)

var config := GodrayConfig.new()

func _ready():
	_initialize_components()
	_find_sun_node()
	_regenerate_geometry()
	# Ensure material is applied after components are ready
	if godray_material:
		_apply_material()

func _physics_process(_delta):
	if not sun_node or not is_inside_tree():
		return
	
	var sun_dir = -sun_node.global_transform.basis.z
	var camera = get_viewport().get_camera_3d()
	var cam_basis = camera.global_transform.basis if camera else Basis()
	
	if not sun_dir.is_equal_approx(last_sun_direction) or not cam_basis.is_equal_approx(last_camera_basis):
		_update_alignment()
		if is_inside_tree():
			call_deferred("_update_shader_parameters")  # NEW: Update shader parameters including godray direction
		last_sun_direction = sun_dir
		last_camera_basis = cam_basis

# Core functionality
func _initialize_components():
	quad_mesh = QuadMesh.new()
	multi_mesh = MultiMesh.new()
	# Ensure instance count is 0 before setting transform format
	multi_mesh.instance_count = 0
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	
	multi_mesh_instance = MultiMeshInstance3D.new()
	multi_mesh_instance.multimesh = multi_mesh
	multi_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(multi_mesh_instance)
	
	# Apply material immediately if we have one
	if godray_material:
		multi_mesh_instance.material_override = godray_material

func _find_sun_node():
	var scene_root = get_tree().current_scene if get_tree().current_scene else get_tree().root
	sun_node = _find_node_recursive(scene_root, "Sun", DirectionalLight3D)
	if not sun_node:
		sun_node = _find_node_recursive(scene_root, "", DirectionalLight3D)
	
	if show_debug_info:
		print("Godray: Sun node ", "found: " + sun_node.name if sun_node else "not found")

func _find_node_recursive(node: Node, target_name: String, target_type) -> Node:
	if (target_name.is_empty() or node.name == target_name) and is_instance_of(node, target_type):
		return node
	
	for child in node.get_children():
		var result = _find_node_recursive(child, target_name, target_type)
		if result:
			return result
	return null

func _regenerate_geometry():
	if not is_inside_tree():
		return
	
	# Clear instances before regenerating
	if multi_mesh:
		multi_mesh.instance_count = 0
	
	config.calculate_adaptive_params(grid_size, quad_spacing, layer_count, 
									layer_spacing, adaptive_density, density_multiplier)
	
	_update_quad_mesh()
	_generate_instances()
	_update_alignment()
	if is_inside_tree():
		call_deferred("_update_shader_parameters")  # NEW: Update shader parameters after regeneration
	needs_regeneration = false

# NEW: Function to update shader parameters
func _update_shader_parameters():
	# Safety check: ensure components are initialized
	if not multi_mesh_instance or not is_inside_tree():
		return
	
	var material = multi_mesh_instance.material_override if multi_mesh_instance.material_override else godray_material
	if not material or not material is ShaderMaterial:
		return
	
	var shader_material = material as ShaderMaterial
	
	# Update godray direction based on sun direction
	if sun_node:
		var godray_dir = -sun_node.global_transform.basis.z
		shader_material.set_shader_parameter("godray_direction", godray_dir)
	
	# Update view angle fade parameters
	shader_material.set_shader_parameter("use_view_angle_fade", use_view_angle_fade)
	shader_material.set_shader_parameter("fade_angle_start", fade_angle_start)
	shader_material.set_shader_parameter("fade_angle_end", fade_angle_end)
	shader_material.set_shader_parameter("debug_view_angle", debug_view_angle)

func _update_quad_mesh():
	var final_width = quad_width
	var final_height = quad_height
	
	if auto_stretch and sun_node:
		final_height *= stretch_factor
	
	quad_mesh.size = Vector2(final_width, final_height)
	multi_mesh.mesh = quad_mesh

func _generate_instances():
	var total_instances = config.effective_grid_size.x * config.effective_grid_size.y * layer_count
	multi_mesh.instance_count = total_instances
	
	var instance_idx = 0
	for layer in range(layer_count):
		if use_randomized_positioning:
			_generate_random_layer(layer, instance_idx)
		else:
			_generate_grid_layer(layer, instance_idx)
		instance_idx += config.effective_grid_size.x * config.effective_grid_size.y

func _generate_random_layer(layer: int, start_idx: int):
	var rng = RandomNumberGenerator.new()
	rng.seed = config.rng_seed + layer * 1000
	
	var area_size = Vector2(
		config.effective_grid_size.x * config.effective_spacing,
		config.effective_grid_size.y * config.effective_spacing
	)
	
	var positions = _generate_positions(area_size, config.effective_spacing * min_distance_factor, rng)
	var max_quads = config.effective_grid_size.x * config.effective_grid_size.y
	
	for i in range(min(positions.size(), max_quads)):
		_create_random_quad(positions[i], layer, start_idx + i, rng)

func _generate_positions(area_size: Vector2, min_dist: float, rng: RandomNumberGenerator) -> Array[Vector3]:
	if poisson_disk_sampling:
		return _poisson_disk_sampling(area_size, min_dist, rng)
	else:
		return _random_positioning(area_size, min_dist, rng)

func _poisson_disk_sampling(area_size: Vector2, min_dist: float, rng: RandomNumberGenerator) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	var active_list: Array[Vector2] = []
	var cell_size = min_dist / sqrt(2.0)
	var grid_size_2d = Vector2i(int(area_size.x / cell_size) + 1, int(area_size.y / cell_size) + 1)
	
	# Initialize spatial grid
	var grid = {}
	
	# Add first point
	var first = Vector2(rng.randf_range(-area_size.x * 0.5, area_size.x * 0.5),
					   rng.randf_range(-area_size.y * 0.5, area_size.y * 0.5))
	positions.append(Vector3(first.x, 0, first.y))
	active_list.append(first)
	
	var grid_pos = Vector2i(int((first.x + area_size.x * 0.5) / cell_size),
						   int((first.y + area_size.y * 0.5) / cell_size))
	grid[grid_pos] = 0
	
	while active_list.size() > 0:
		var point_idx = rng.randi() % active_list.size()
		var point = active_list[point_idx]
		var found = false
		
		for attempt in range(30):
			var angle = rng.randf_range(0, TAU)
			var distance = rng.randf_range(min_dist, min_dist * 2.0)
			var new_point = point + Vector2(cos(angle), sin(angle)) * distance
			
			if _is_valid_point(new_point, area_size, min_dist, positions, grid, cell_size):
				positions.append(Vector3(new_point.x, 0, new_point.y))
				active_list.append(new_point)
				var new_grid_pos = Vector2i(int((new_point.x + area_size.x * 0.5) / cell_size),
										   int((new_point.y + area_size.y * 0.5) / cell_size))
				grid[new_grid_pos] = positions.size() - 1
				found = true
				break
		
		if not found:
			active_list.remove_at(point_idx)
	
	return positions

func _is_valid_point(point: Vector2, area_size: Vector2, min_dist: float, 
					positions: Array[Vector3], grid: Dictionary, cell_size: float) -> bool:
	if abs(point.x) > area_size.x * 0.5 or abs(point.y) > area_size.y * 0.5:
		return false
	
	var grid_pos = Vector2i(int((point.x + area_size.x * 0.5) / cell_size),
						   int((point.y + area_size.y * 0.5) / cell_size))
	
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			var check_pos = grid_pos + Vector2i(dx, dy)
			if grid.has(check_pos):
				var existing_point = positions[grid[check_pos]]
				if point.distance_to(Vector2(existing_point.x, existing_point.z)) < min_dist:
					return false
	return true

func _random_positioning(area_size: Vector2, min_dist: float, rng: RandomNumberGenerator) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	var max_attempts = 1000
	var target_count = config.effective_grid_size.x * config.effective_grid_size.y
	
	for attempt in range(max_attempts):
		if positions.size() >= target_count:
			break
			
		var pos = Vector3(rng.randf_range(-area_size.x * 0.5, area_size.x * 0.5), 0,
						 rng.randf_range(-area_size.y * 0.5, area_size.y * 0.5))
		
		var valid = true
		for existing in positions:
			if Vector2(pos.x, pos.z).distance_to(Vector2(existing.x, existing.z)) < min_dist:
				valid = false
				break
		
		if valid:
			positions.append(pos)
	
	return positions

func _generate_grid_layer(layer: int, start_idx: int):
	var instance_idx = start_idx
	for x in range(config.effective_grid_size.x):
		for z in range(config.effective_grid_size.y):
			var pos = Vector3(
				(x - config.effective_grid_size.x * 0.5) * config.effective_spacing,
				config.layer_positions[layer],
				(z - config.effective_grid_size.y * 0.5) * config.effective_spacing
			)
			_create_standard_quad(pos, instance_idx)
			instance_idx += 1

func _create_random_quad(pos: Vector3, layer: int, instance_idx: int, rng: RandomNumberGenerator):
	pos.y = config.layer_positions[layer]
	
	# Apply variations
	pos += Vector3(
		rng.randf_range(-jitter_amount, jitter_amount) * config.effective_spacing,
		rng.randf_range(-jitter_amount * 0.5, jitter_amount * 0.5) * layer_spacing,
		rng.randf_range(-jitter_amount, jitter_amount) * config.effective_spacing
	)
	
	var transform = Transform3D()
	transform.origin = pos
	
	# Rotation variation - FIXED: Check for zero vectors before rotation
	if rotation_variation > 0:
		var rot = Vector3(
			rng.randf_range(-rotation_variation, rotation_variation),
			rng.randf_range(-rotation_variation, rotation_variation),
			rng.randf_range(-rotation_variation, rotation_variation)
		)
		
		# Safe rotation application
		if abs(rot.x) > 0.001:
			transform = transform.rotated(Vector3.RIGHT, deg_to_rad(rot.x))
		if abs(rot.y) > 0.001:
			transform = transform.rotated(Vector3.UP, deg_to_rad(rot.y))
		if abs(rot.z) > 0.001:
			transform = transform.rotated(Vector3.FORWARD, deg_to_rad(rot.z))
	
	# Scale variation
	if scale_variation > 0:
		var scale = 1.0 + rng.randf_range(-scale_variation, scale_variation)
		transform = transform.scaled(Vector3.ONE * scale)
	
	multi_mesh.set_instance_transform(instance_idx, transform)

func _create_standard_quad(pos: Vector3, instance_idx: int):
	# Add minor jitter to break patterns
	var jitter = Vector3(
		randf_range(-jitter_amount, jitter_amount) * config.effective_spacing,
		0,
		randf_range(-jitter_amount, jitter_amount) * config.effective_spacing
	)
	
	var transform = Transform3D()
	transform.origin = pos + jitter
	multi_mesh.set_instance_transform(instance_idx, transform)

func _update_alignment():
	if not sun_node or not multi_mesh or multi_mesh.instance_count == 0:
		return
	
	var sun_dir = -sun_node.global_transform.basis.z
	var basis = _calculate_alignment_basis(sun_dir)
	
	for i in range(multi_mesh.instance_count):
		var transform = multi_mesh.get_instance_transform(i)
		transform.basis = basis
		multi_mesh.set_instance_transform(i, transform)

func _calculate_alignment_basis(sun_dir: Vector3) -> Basis:
	# Step 1: Compute local up aligned with sun
	var quad_up = sun_dir.normalized()

	# Step 2: Base forward (before camera facing)
	var quad_forward = quad_up.cross(Vector3.RIGHT).normalized()
	if quad_forward.length() < 0.01:
		quad_forward = quad_up.cross(Vector3.FORWARD).normalized()

	# Step 3: Start basis aligned to sun
	var basis = Basis()
	basis.y = quad_up
	basis.z = quad_forward
	basis.x = basis.y.cross(basis.z).normalized()
	basis.z = basis.x.cross(basis.y).normalized()

	# Step 4: Rotate forward to align with camera's view direction, keeping up aligned with sun
	if auto_face_camera:
		var camera = get_viewport().get_camera_3d()
		if camera:
			# Use camera's forward direction instead of position-based vector
			var camera_forward = -camera.global_transform.basis.z.normalized()
			
			# Constrain rotation so that 'up' stays along sun
			var right = quad_up.cross(camera_forward).normalized()
			if right.length() > 0.001:
				var forward = right.cross(quad_up).normalized()
				basis.x = right
				basis.z = forward
				basis.y = quad_up

	# Step 5: Apply optional yaw control
	if abs(yaw_control) > 0.001:
		basis = Basis(quad_up, deg_to_rad(yaw_control)) * basis

	return basis
	
# Public API
func update_emission_strength(strength: float):
	var material = multi_mesh_instance.material_override if multi_mesh_instance.material_override else godray_material
	if material is ShaderMaterial:
		material.set_shader_parameter("emission_strength", strength)

func update_light_color(color: Color):
	var material = multi_mesh_instance.material_override if multi_mesh_instance.material_override else godray_material
	if material is ShaderMaterial:
		material.set_shader_parameter("light_color", color)

func update_emission_color(color: Color):
	var material = multi_mesh_instance.material_override if multi_mesh_instance.material_override else godray_material
	if material is ShaderMaterial:
		material.set_shader_parameter("emission_color", color)

func update_godray_colors(light_color: Color, emission_color: Color):
	var material = multi_mesh_instance.material_override if multi_mesh_instance.material_override else godray_material
	if material is ShaderMaterial:
		material.set_shader_parameter("light_color", light_color)
		material.set_shader_parameter("emission_color", emission_color)

# Setters (consolidated for efficiency)
func _set_grid_size(value: Vector2i): grid_size = value; _queue_regeneration()
func _set_spacing(value: float): quad_spacing = value; _queue_regeneration()
func _set_layer_count(value: int): layer_count = max(1, value); _queue_regeneration()
func _set_layer_spacing(value: float): layer_spacing = value; _queue_regeneration()
func _set_quad_size(value: float): _queue_regeneration()
func _set_auto_stretch(value: bool): auto_stretch = value; _queue_regeneration()
func _set_stretch_factor(value: float): stretch_factor = max(0.1, value); _queue_regeneration()
func _set_yaw_control(value: float): yaw_control = value; _queue_alignment()
func _set_auto_face_camera(value: bool): auto_face_camera = value; _queue_alignment()
func _set_use_randomized(value: bool): use_randomized_positioning = value; _queue_regeneration()
func _set_poisson_sampling(value: bool): poisson_disk_sampling = value; _queue_regeneration()
func _set_distance_factor(value: float): min_distance_factor = max(0.1, value); _queue_regeneration()
func _set_rotation_variation(value: float): rotation_variation = value; _queue_regeneration()
func _set_scale_variation(value: float): scale_variation = value; _queue_regeneration()
func _set_jitter_amount(value: float): jitter_amount = max(0.0, value); _queue_regeneration()
func _set_adaptive_density(value: bool): adaptive_density = value; _queue_regeneration()
func _set_density_multiplier(value: float): density_multiplier = max(1.0, value); _queue_regeneration()

# NEW: Setters for view angle fade parameters
func _set_use_view_angle_fade(value: bool): 
	use_view_angle_fade = value
	if is_inside_tree():
		call_deferred("_update_shader_parameters")

func _set_fade_angle_start(value: float): 
	fade_angle_start = max(value, fade_angle_end)  # Ensure start >= end
	if is_inside_tree():
		call_deferred("_update_shader_parameters")

func _set_fade_angle_end(value: float): 
	fade_angle_end = min(value, fade_angle_start)  # Ensure end <= start
	if is_inside_tree():
		call_deferred("_update_shader_parameters")

func _set_debug_view_angle(value: bool):
	debug_view_angle = value
	if is_inside_tree():
		call_deferred("_update_shader_parameters")

func _set_godray_material(value: Material):
	godray_material = value
	if is_inside_tree():
		call_deferred("_apply_material")

func _apply_material():
	if multi_mesh_instance and godray_material:
		multi_mesh_instance.material_override = godray_material
		# Update shader parameters after applying material
		if is_inside_tree():
			call_deferred("_update_shader_parameters")
		if show_debug_info:
			print("Godray: Material applied - ", godray_material.resource_path if godray_material.resource_path else "unnamed material")

func _set_show_debug_info(value: bool):
	show_debug_info = value
	if not value:
		last_sun_direction = Vector3.ZERO
		last_camera_basis = Basis()

func _regenerate_quads(value: bool):
	if value and is_inside_tree():
		_regenerate_geometry()

func _queue_regeneration():
	if is_inside_tree():
		# Clear instances first to prevent transform format errors
		if multi_mesh:
			multi_mesh.instance_count = 0
		call_deferred("_regenerate_geometry")

func _queue_alignment():
	if is_inside_tree():
		call_deferred("_update_alignment")

func _exit_tree():
	if multi_mesh:
		multi_mesh.instance_count = 0
