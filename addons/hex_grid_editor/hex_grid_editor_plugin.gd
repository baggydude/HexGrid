@tool
extends EditorPlugin

## Hex Grid Editor Plugin
## Provides toolbar and mouse interaction for painting hex tiles

const HexGrid3DScript := preload("res://addons/hex_grid_editor/hex_grid_3d.gd")
const ToolbarScene := preload("res://addons/hex_grid_editor/hex_grid_editor_toolbar.gd")

var _edited_grid: HexGrid3D = null
var _toolbar: HexGridEditorToolbar = null
var _toolbar_container: Control = null
var _is_painting: bool = false
var _last_painted_coord: Vector2i = Vector2i(-99999, -99999)

# Preview mesh for painting
var _preview_instance: MeshInstance3D = null
var _preview_material: StandardMaterial3D = null


func _enter_tree() -> void:
	# Create toolbar container with background
	_toolbar_container = PanelContainer.new()
	_toolbar_container.visible = false
	_toolbar_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Create toolbar
	_toolbar = HexGridEditorToolbar.new()
	_toolbar.tile_selected.connect(_on_tile_selected)
	_toolbar.tool_changed.connect(_on_tool_changed)
	_toolbar_container.add_child(_toolbar)
	
	# Add to the spatial editor area (below the 3D viewport toolbar)
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_BOTTOM, _toolbar_container)
	
	# Create preview material - subtle transparency to indicate preview
	_preview_material = StandardMaterial3D.new()
	_preview_material.albedo_color = Color(1, 1, 1, 0.85)
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
		_toolbar.set_tile_palette(_edited_grid.tile_palette)
		_setup_preview()
	else:
		_edited_grid = null
		_cleanup_preview()


func _make_visible(visible: bool) -> void:
	if _toolbar_container and is_instance_valid(_toolbar_container):
		_toolbar_container.visible = visible
	
	if not visible:
		_cleanup_preview()
	elif _edited_grid:
		_setup_preview()


func _setup_preview() -> void:
	if _preview_instance:
		return
	
	_preview_instance = MeshInstance3D.new()
	_preview_instance.material_override = _preview_material
	
	if _edited_grid:
		_edited_grid.add_child(_preview_instance)
		_preview_instance.visible = false


func _cleanup_preview() -> void:
	if _preview_instance and is_instance_valid(_preview_instance):
		_preview_instance.queue_free()
		_preview_instance = null


func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	if not _edited_grid or not _toolbar or not is_instance_valid(_toolbar):
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	
	if not _toolbar_container or not _toolbar_container.visible:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	
	# Handle rotation key
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_R:
			if event.shift_pressed:
				_toolbar.rotate_tile(-60.0)
			else:
				_toolbar.rotate_tile(60.0)
			_update_preview_rotation()
			return EditorPlugin.AFTER_GUI_INPUT_STOP

		# Handle height adjustment keys (+ and -)
		if event.pressed:
			if event.keycode == KEY_EQUAL or event.keycode == KEY_KP_ADD:  # + key
				_toolbar.adjust_height(HexGridEditorToolbar.HEIGHT_STEP)
				_update_preview_scale()
				return EditorPlugin.AFTER_GUI_INPUT_STOP
			elif event.keycode == KEY_MINUS or event.keycode == KEY_KP_SUBTRACT:  # - key
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
			var tile := _toolbar.get_selected_tile()
			if tile:
				var rotation := _toolbar.get_rotation()
				var height_scale := _toolbar.get_height()

				# Store old state for undo
				var old_data := _edited_grid.get_tile_at(axial_coord)

				undo_redo.create_action("Paint Hex Tile")
				undo_redo.add_do_method(_edited_grid, "place_tile", axial_coord, tile, rotation, height_scale)

				if old_data.is_empty():
					undo_redo.add_undo_method(_edited_grid, "remove_tile", axial_coord)
				else:
					undo_redo.add_undo_method(_edited_grid, "place_tile", axial_coord,
						old_data.get("tile_resource"), old_data.get("rotation_degrees", 0.0),
						old_data.get("height_scale", 1.0))

				undo_redo.commit_action()
				return true

		HexGridEditorToolbar.ToolMode.ERASE:
			if _edited_grid.has_tile_at(axial_coord):
				var old_data := _edited_grid.get_tile_at(axial_coord)

				undo_redo.create_action("Erase Hex Tile")
				undo_redo.add_do_method(_edited_grid, "remove_tile", axial_coord)
				undo_redo.add_undo_method(_edited_grid, "place_tile", axial_coord,
					old_data.get("tile_resource"), old_data.get("rotation_degrees", 0.0),
					old_data.get("height_scale", 1.0))
				undo_redo.commit_action()
				return true
		
		HexGridEditorToolbar.ToolMode.PICK:
			if _edited_grid.has_tile_at(axial_coord):
				var cell_data := _edited_grid.get_tile_at(axial_coord)
				var tile: HexTileResource = cell_data.get("tile_resource")
				var rotation: float = cell_data.get("rotation_degrees", 0.0)
				var height_scale: float = cell_data.get("height_scale", 1.0)

				# Find and select the tile in palette
				for i in range(_edited_grid.tile_palette.size()):
					if _edited_grid.tile_palette[i] == tile:
						_toolbar.select_tile(i)
						_toolbar.set_rotation(rotation)
						_toolbar.set_height(height_scale)
						_toolbar.set_tool(HexGridEditorToolbar.ToolMode.PAINT)
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
	
	var tile := _toolbar.get_selected_tile()
	if not tile or _toolbar.get_tool() != HexGridEditorToolbar.ToolMode.PAINT:
		_preview_instance.visible = false
		return
	
	_preview_instance.visible = true
	_preview_instance.mesh = tile.mesh
	
	var world_pos := HexMath.axial_to_world(axial_coord, _edited_grid.hex_size, _edited_grid.pointy_top)

	# Apply scale to match what will be placed (with height scaling)
	var scale_factor := _edited_grid.hex_size * _edited_grid.mesh_scale
	var height_scale := _toolbar.get_height()
	_preview_instance.scale = Vector3(scale_factor, scale_factor * height_scale, scale_factor)

	# Set position with Y offset so the bottom of the mesh sits at y=0
	var y_offset := scale_factor * height_scale
	_preview_instance.position = Vector3(world_pos.x, y_offset, world_pos.z)

	_update_preview_rotation()


func _update_preview_rotation() -> void:
	if not _preview_instance:
		return

	# Just apply the user's rotation - mesh is already oriented correctly
	var rot := _toolbar.get_rotation()
	_preview_instance.rotation_degrees.y = rot
	print("[HexPlugin] _update_preview_rotation set to: ", rot, " actual: ", _preview_instance.rotation_degrees.y)


func _update_preview_scale() -> void:
	if not _preview_instance or not _edited_grid:
		return

	var scale_factor := _edited_grid.hex_size * _edited_grid.mesh_scale
	var height_scale := _toolbar.get_height()
	_preview_instance.scale = Vector3(scale_factor, scale_factor * height_scale, scale_factor)

	# Update Y position to keep bottom at ground level
	var y_offset := scale_factor * height_scale
	_preview_instance.position.y = y_offset


func _on_tile_selected(index: int) -> void:
	if _edited_grid and index >= 0 and index < _edited_grid.tile_palette.size():
		var tile := _edited_grid.tile_palette[index]
		if tile and _preview_instance:
			_preview_instance.mesh = tile.mesh


func _on_tool_changed(tool_mode: HexGridEditorToolbar.ToolMode) -> void:
	if _preview_instance:
		_preview_instance.visible = (tool_mode == HexGridEditorToolbar.ToolMode.PAINT)
