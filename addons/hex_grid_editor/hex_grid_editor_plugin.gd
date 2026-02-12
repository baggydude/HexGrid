@tool
extends EditorPlugin

## Hex Grid Editor Plugin
## Provides toolbar and mouse interaction for painting hex brushes (scene-based)

const HexGrid3DScript := preload("res://addons/hex_grid_editor/hex_grid_3d.gd")
const ToolbarScene := preload("res://addons/hex_grid_editor/hex_grid_editor_toolbar.gd")

var _edited_grid: HexGrid3D = null
var _toolbar: HexGridEditorToolbar = null
var _toolbar_container: Control = null
var _is_painting: bool = false
var _last_painted_coord: Vector2i = Vector2i(-99999, -99999)

# Ghost preview in the 3D viewport (instantiated scene)
var _preview_instance: Node3D = null
var _preview_material: StandardMaterial3D = null


func _enter_tree() -> void:
	# Create toolbar container with background
	_toolbar_container = PanelContainer.new()
	_toolbar_container.visible = false
	_toolbar_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Create toolbar
	_toolbar = HexGridEditorToolbar.new()
	_toolbar.brush_selected.connect(_on_brush_selected)
	_toolbar.variation_changed.connect(_on_variation_changed)
	_toolbar.tool_changed.connect(_on_tool_changed)
	_toolbar_container.add_child(_toolbar)

	# Add to the spatial editor area (below the 3D viewport toolbar)
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_BOTTOM, _toolbar_container)

	# Create ghost preview material - subtle transparency to indicate preview
	_preview_material = StandardMaterial3D.new()
	_preview_material.albedo_color = Color(1, 1, 1, 0.5)
	_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func _exit_tree() -> void:
	if _toolbar_container and is_instance_valid(_toolbar_container):
		remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_BOTTOM, _toolbar_container)
		_toolbar_container.queue_free()
		_toolbar_container = null
		_toolbar = null

	_cleanup_preview()


func _handles(object: Object) -> bool:
	return object is HexGrid3D


func _edit(object: Object) -> void:
	if object is HexGrid3D:
		_edited_grid = object
		_toolbar.set_brush_palette(_edited_grid.brush_palette)
		_rebuild_ghost_preview()
	else:
		_edited_grid = null
		_cleanup_preview()


func _make_visible(visible: bool) -> void:
	if _toolbar_container and is_instance_valid(_toolbar_container):
		_toolbar_container.visible = visible

	if not visible:
		_cleanup_preview()
	elif _edited_grid:
		_rebuild_ghost_preview()


func _setup_preview() -> void:
	_cleanup_preview()

	var brush := _toolbar.get_selected_brush()
	if not brush or brush.variations.is_empty():
		return

	var variation_index := _toolbar.get_variation_index()
	var idx := clampi(variation_index, 0, brush.variations.size() - 1)
	var scene: PackedScene = brush.variations[idx]
	if not scene:
		return

	_preview_instance = scene.instantiate()
	_clear_owners(_preview_instance)
	_apply_ghost_material(_preview_instance)

	if _edited_grid:
		_edited_grid.add_child(_preview_instance)
		_preview_instance.visible = false


func _cleanup_preview() -> void:
	if _preview_instance and is_instance_valid(_preview_instance):
		_preview_instance.queue_free()
		_preview_instance = null


func _apply_ghost_material(node: Node) -> void:
	# Hide particles and lights in ghost preview
	if node is GPUParticles3D or node is CPUParticles3D:
		node.visible = false
	elif node is Light3D:
		node.visible = false
	elif node is GeometryInstance3D:
		(node as GeometryInstance3D).material_override = _preview_material
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_apply_ghost_material(child)


static func _clear_owners(node: Node) -> void:
	node.owner = null
	for child in node.get_children():
		_clear_owners(child)


func _rebuild_ghost_preview() -> void:
	var was_visible := _preview_instance.visible if (_preview_instance and is_instance_valid(_preview_instance)) else false
	var old_pos := _preview_instance.position if (_preview_instance and is_instance_valid(_preview_instance)) else Vector3.ZERO
	var old_rot := _preview_instance.rotation_degrees.y if (_preview_instance and is_instance_valid(_preview_instance)) else 0.0

	_setup_preview()

	if _preview_instance and was_visible:
		_preview_instance.position = old_pos
		_preview_instance.rotation_degrees.y = old_rot
		_preview_instance.visible = true


func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	if not _edited_grid or not _toolbar or not is_instance_valid(_toolbar):
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if not _toolbar_container or not _toolbar_container.visible:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	# Handle key input
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_R:
			if event.shift_pressed:
				_toolbar.rotate_tile(-60.0)
			else:
				_toolbar.rotate_tile(60.0)
			_update_preview_rotation()
			return EditorPlugin.AFTER_GUI_INPUT_STOP

		# Handle variation cycling (V key)
		if event.pressed and event.keycode == KEY_V:
			_toolbar.cycle_variation()
			_rebuild_ghost_preview()
			return EditorPlugin.AFTER_GUI_INPUT_STOP

		# Handle height adjustment keys (+ and -)
		if event.pressed:
			if event.keycode == KEY_EQUAL or event.keycode == KEY_KP_ADD:
				_toolbar.adjust_height(HexGridEditorToolbar.HEIGHT_STEP)
				_update_preview_scale()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			elif event.keycode == KEY_MINUS or event.keycode == KEY_KP_SUBTRACT:
				_toolbar.adjust_height(-HexGridEditorToolbar.HEIGHT_STEP)
				_update_preview_scale()
				return EditorPlugin.AFTER_GUI_INPUT_STOP

	# Handle mouse input
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton

		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				_is_painting = true
				_last_painted_coord = Vector2i(-99999, -99999)

				# Determine tool based on modifiers
				if mouse_event.alt_pressed:
					_toolbar.set_tool(HexGridEditorToolbar.ToolMode.PICK)
				elif mouse_event.shift_pressed:
					_toolbar.set_tool(HexGridEditorToolbar.ToolMode.ERASE)

				var result := _handle_paint(viewport_camera, mouse_event.position)
				if result:
					return EditorPlugin.AFTER_GUI_INPUT_STOP
			else:
				_is_painting = false
				_last_painted_coord = Vector2i(-99999, -99999)

	if event is InputEventMouseMotion:
		var motion_event := event as InputEventMouseMotion

		# Update preview position
		_update_preview(viewport_camera, motion_event.position)

		# Handle dragging paint
		if _is_painting:
			var result := _handle_paint(viewport_camera, motion_event.position)
			if result:
				return EditorPlugin.AFTER_GUI_INPUT_STOP

	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _handle_paint(camera: Camera3D, screen_pos: Vector2) -> bool:
	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)

	# Raycast against Y=0 plane (grid plane)
	var plane := Plane(Vector3.UP, 0)
	var grid_transform := _edited_grid.global_transform
	plane = grid_transform * plane

	var intersection := plane.intersects_ray(ray_origin, ray_dir)
	if intersection == null:
		return false

	var local_pos := _edited_grid.to_local(intersection)
	var axial_coord := HexMath.world_to_axial(local_pos, _edited_grid.hex_size, _edited_grid.pointy_top)

	# Check bounds
	if not _edited_grid.is_in_bounds(axial_coord):
		return false

	# Skip if same as last painted (for drag painting)
	if axial_coord == _last_painted_coord:
		return true

	_last_painted_coord = axial_coord

	var undo_redo := get_undo_redo()

	match _toolbar.get_tool():
		HexGridEditorToolbar.ToolMode.PAINT:
			var brush := _toolbar.get_selected_brush()
			if brush and not brush.variations.is_empty():
				var rotation := _toolbar.get_tile_rotation()
				var height_scale := _toolbar.get_height()
				var variation_index := _toolbar.get_variation_index()

				# Store old state for undo
				var old_data := _edited_grid.get_tile_at(axial_coord)

				undo_redo.create_action("Paint Hex Brush")
				undo_redo.add_do_method(_edited_grid, "place_brush", axial_coord, brush, variation_index, rotation, height_scale)

				if old_data.is_empty():
					undo_redo.add_undo_method(_edited_grid, "remove_tile", axial_coord)
				else:
					undo_redo.add_undo_method(_edited_grid, "place_brush", axial_coord,
						old_data.get("brush_resource"),
						old_data.get("variation_index", 0),
						old_data.get("rotation_degrees", 0.0),
						old_data.get("height_scale", 1.0))

				undo_redo.commit_action()
				return true

		HexGridEditorToolbar.ToolMode.ERASE:
			if _edited_grid.has_tile_at(axial_coord):
				var old_data := _edited_grid.get_tile_at(axial_coord)

				undo_redo.create_action("Erase Hex Brush")
				undo_redo.add_do_method(_edited_grid, "remove_tile", axial_coord)
				undo_redo.add_undo_method(_edited_grid, "place_brush", axial_coord,
					old_data.get("brush_resource"),
					old_data.get("variation_index", 0),
					old_data.get("rotation_degrees", 0.0),
					old_data.get("height_scale", 1.0))
				undo_redo.commit_action()
				return true

		HexGridEditorToolbar.ToolMode.PICK:
			if _edited_grid.has_tile_at(axial_coord):
				var cell_data := _edited_grid.get_tile_at(axial_coord)
				var brush: HexBrushResource = cell_data.get("brush_resource")
				var variation_index: int = cell_data.get("variation_index", 0)
				var rotation: float = cell_data.get("rotation_degrees", 0.0)
				var height_scale: float = cell_data.get("height_scale", 1.0)

				# Find and select the brush in palette
				for i in range(_edited_grid.brush_palette.size()):
					if _edited_grid.brush_palette[i] == brush:
						_toolbar.select_brush(i)
						_toolbar.set_variation_index(variation_index)
						_toolbar.set_tile_rotation(rotation)
						_toolbar.set_height(height_scale)
						_toolbar.set_tool(HexGridEditorToolbar.ToolMode.PAINT)
						_rebuild_ghost_preview()
						_update_preview_scale()
						break
				return true

	return false


func _update_preview(camera: Camera3D, screen_pos: Vector2) -> void:
	if not _preview_instance or not _edited_grid:
		return

	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)

	# Raycast against grid plane
	var plane := Plane(Vector3.UP, 0)
	var grid_transform := _edited_grid.global_transform
	plane = grid_transform * plane

	var intersection := plane.intersects_ray(ray_origin, ray_dir)
	if intersection == null:
		_preview_instance.visible = false
		return

	var local_pos := _edited_grid.to_local(intersection)
	var axial_coord := HexMath.world_to_axial(local_pos, _edited_grid.hex_size, _edited_grid.pointy_top)

	if not _edited_grid.is_in_bounds(axial_coord):
		_preview_instance.visible = false
		return

	var brush := _toolbar.get_selected_brush()
	if not brush or brush.variations.is_empty() or _toolbar.get_tool() != HexGridEditorToolbar.ToolMode.PAINT:
		_preview_instance.visible = false
		return

	_preview_instance.visible = true

	var world_pos := HexMath.axial_to_world(axial_coord, _edited_grid.hex_size, _edited_grid.pointy_top)

	# Place scene at hex center on the grid plane
	_preview_instance.position = Vector3(world_pos.x, 0, world_pos.z)

	_update_preview_rotation()

	# Update Base child Y scale for height preview
	var height_scale := _toolbar.get_height()
	var base_node := _preview_instance.find_child("Base", true, false) as MeshInstance3D
	if base_node:
		base_node.scale.y = height_scale


func _update_preview_rotation() -> void:
	if not _preview_instance:
		return
	_preview_instance.rotation_degrees.y = _toolbar.get_tile_rotation()


func _update_preview_scale() -> void:
	if not _preview_instance or not _edited_grid:
		return

	var height_scale := _toolbar.get_height()

	# Update Base child Y scale for height
	var base_node := _preview_instance.find_child("Base", true, false) as MeshInstance3D
	if base_node:
		base_node.scale.y = height_scale


func _on_brush_selected(_index: int) -> void:
	_rebuild_ghost_preview()


func _on_variation_changed(_variation_index: int) -> void:
	_rebuild_ghost_preview()


func _on_tool_changed(tool_mode: HexGridEditorToolbar.ToolMode) -> void:
	if _preview_instance:
		_preview_instance.visible = (tool_mode == HexGridEditorToolbar.ToolMode.PAINT)
