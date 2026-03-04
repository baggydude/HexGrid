@tool
extends EditorPlugin

## Hex Grid Editor Plugin
## Provides bottom panel and mouse interaction for painting hex tiles

var _edited_grid: HexGrid3D = null
var _toolbar: HexGridEditorToolbar = null
var _bottom_panel_button: Button = null
var _is_painting: bool = false
var _last_painted_coord: Vector2i = Vector2i(-99999, -99999)

# Ghost preview in the 3D viewport (instantiated scene)
var _preview_instance: Node3D = null


func _enter_tree() -> void:
	_toolbar = HexGridEditorToolbar.new()
	_toolbar.tile_selected.connect(_on_tile_selected)
	_toolbar.tool_changed.connect(_on_tool_changed)
	_bottom_panel_button = add_control_to_bottom_panel(_toolbar, "Hex Editor")
	_bottom_panel_button.visible = false


func _exit_tree() -> void:
	_cleanup_preview()
	if _toolbar and is_instance_valid(_toolbar):
		remove_control_from_bottom_panel(_toolbar)
		_toolbar.queue_free()
		_toolbar = null
	_bottom_panel_button = null


func _handles(object: Object) -> bool:
	return object is HexGrid3D


func _edit(object: Object) -> void:
	if object is HexGrid3D:
		_edited_grid = object
		if not _edited_grid.tree_exiting.is_connected(_on_grid_deleted):
			_edited_grid.tree_exiting.connect(_on_grid_deleted)
		_toolbar.set_tile_palette(_edited_grid.tile_palette)
		_rebuild_ghost_preview.call_deferred()
	else:
		_edited_grid = null
		_cleanup_preview()


func _on_grid_deleted() -> void:
	_edited_grid = null
	_cleanup_preview()
	_make_visible(false)
	hide_bottom_panel()


func _make_visible(visible_flag: bool) -> void:
	if _bottom_panel_button:
		_bottom_panel_button.visible = visible_flag

	if visible_flag and _edited_grid:
		make_bottom_panel_item_visible(_toolbar)
	elif not visible_flag:
		_cleanup_preview()


func _setup_preview() -> void:
	_cleanup_preview()

	var scene := _toolbar.get_selected_tile_scene()
	if not scene:
		return

	_preview_instance = scene.instantiate()

	if _edited_grid:
		_edited_grid.add_child(_preview_instance)
		_preview_instance.visible = false


func _cleanup_preview() -> void:
	if _preview_instance and is_instance_valid(_preview_instance):
		_preview_instance.queue_free()
		_preview_instance = null



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

	if not _bottom_panel_button or not _bottom_panel_button.visible:
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

				# Alt+Click = Pick
				if mouse_event.alt_pressed:
					var result := _handle_pick(viewport_camera, mouse_event.position)
					if result:
						return EditorPlugin.AFTER_GUI_INPUT_STOP
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
		_update_preview(viewport_camera, motion_event.position)

		if _is_painting:
			var result := _handle_paint(viewport_camera, motion_event.position)
			if result:
				return EditorPlugin.AFTER_GUI_INPUT_STOP

	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _raycast_to_grid(camera: Camera3D, screen_pos: Vector2) -> Dictionary:
	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)

	var plane := Plane(Vector3.UP, 0)
	var grid_transform := _edited_grid.global_transform
	plane = grid_transform * plane

	var intersection := plane.intersects_ray(ray_origin, ray_dir)
	if intersection == null:
		return {}

	var local_pos := _edited_grid.to_local(intersection)
	var axial_coord := HexMath.world_to_axial(local_pos, _edited_grid.hex_size, _edited_grid.pointy_top)

	if not _edited_grid.is_in_bounds(axial_coord):
		return {}

	return {"axial_coord": axial_coord}


func _handle_paint(camera: Camera3D, screen_pos: Vector2) -> bool:
	var hit := _raycast_to_grid(camera, screen_pos)
	if hit.is_empty():
		return false

	var axial_coord: Vector2i = hit.axial_coord

	if axial_coord == _last_painted_coord:
		return true

	_last_painted_coord = axial_coord
	var undo_redo := get_undo_redo()

	match _toolbar.get_tool():
		HexGridEditorToolbar.ToolMode.PAINT:
			var scene_path := _toolbar.get_selected_tile_path()
			if scene_path.is_empty():
				return false

			var rotation := _toolbar.get_tile_rotation()
			var height_scale := _toolbar.get_height()
			var old_data := _edited_grid.get_tile_at(axial_coord)

			undo_redo.create_action("Paint Hex Tile")
			undo_redo.add_do_method(_edited_grid, "place_tile", axial_coord, scene_path, rotation, height_scale)

			if old_data.is_empty():
				undo_redo.add_undo_method(_edited_grid, "remove_tile", axial_coord)
			else:
				undo_redo.add_undo_method(_edited_grid, "place_tile", axial_coord,
					old_data.get("scene_path", ""),
					old_data.get("rotation_degrees", 0.0),
					old_data.get("height_scale", 1.0))

			undo_redo.commit_action()
			return true

		HexGridEditorToolbar.ToolMode.ERASE:
			if _edited_grid.has_tile_at(axial_coord):
				var old_data := _edited_grid.get_tile_at(axial_coord)

				undo_redo.create_action("Erase Hex Tile")
				undo_redo.add_do_method(_edited_grid, "remove_tile", axial_coord)
				undo_redo.add_undo_method(_edited_grid, "place_tile", axial_coord,
					old_data.get("scene_path", ""),
					old_data.get("rotation_degrees", 0.0),
					old_data.get("height_scale", 1.0))
				undo_redo.commit_action()
				return true

	return false


func _handle_pick(camera: Camera3D, screen_pos: Vector2) -> bool:
	var hit := _raycast_to_grid(camera, screen_pos)
	if hit.is_empty():
		return false

	var axial_coord: Vector2i = hit.axial_coord

	if _edited_grid.has_tile_at(axial_coord):
		var cell_data := _edited_grid.get_tile_at(axial_coord)
		var scene_path: String = cell_data.get("scene_path", "")
		var rotation: float = cell_data.get("rotation_degrees", 0.0)
		var height_scale: float = cell_data.get("height_scale", 1.0)

		if not scene_path.is_empty():
			_toolbar.select_tile(scene_path)
			_toolbar.set_tile_rotation(rotation)
			_toolbar.set_height(height_scale)
			_toolbar.set_tool(HexGridEditorToolbar.ToolMode.PAINT)
			_rebuild_ghost_preview()
			return true

	return false


func _update_preview(camera: Camera3D, screen_pos: Vector2) -> void:
	if not _preview_instance or not _edited_grid:
		return

	var hit := _raycast_to_grid(camera, screen_pos)
	if hit.is_empty() or _toolbar.get_selected_tile_path().is_empty() or _toolbar.get_tool() != HexGridEditorToolbar.ToolMode.PAINT:
		_preview_instance.visible = false
		return

	_preview_instance.visible = true
	var axial_coord: Vector2i = hit.axial_coord
	var world_pos := HexMath.axial_to_world(axial_coord, _edited_grid.hex_size, _edited_grid.pointy_top)
	var height_scale := _toolbar.get_height()

	_preview_instance.position = Vector3(world_pos.x, height_scale, world_pos.z)
	_update_preview_rotation()

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
	var base_node := _preview_instance.find_child("Base", true, false) as MeshInstance3D
	if base_node:
		base_node.scale.y = height_scale


func _on_tile_selected(_scene_path: String) -> void:
	_rebuild_ghost_preview()


func _on_tool_changed(tool_mode: HexGridEditorToolbar.ToolMode) -> void:
	if _preview_instance:
		_preview_instance.visible = (tool_mode == HexGridEditorToolbar.ToolMode.PAINT)
