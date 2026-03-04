@tool
class_name HexGridEditorToolbar
extends VBoxContainer

## Bottom panel editor for hex grid painting with tile grid preview

signal tile_selected(scene_path: String)
signal tool_changed(tool_mode: ToolMode)
signal rotation_changed(degrees: float)
signal height_changed(height: float)

enum ToolMode { PAINT, ERASE }

var _tile_scenes: Dictionary = {}  # scene_path -> PackedScene
var _selected_tile_path: String = ""
var _current_tool: ToolMode = ToolMode.PAINT
var _current_rotation: float = 0.0
var _current_height: float = 1.0

const HEIGHT_MIN: float = 1.0
const HEIGHT_MAX: float = 10.0
const HEIGHT_STEP: float = 0.25
const PREVIEW_SIZE: int = 80

# UI elements
var _tool_buttons: Dictionary = {}
var _rotation_label: Label
var _height_label: Label
var _tile_grid: GridContainer
var _tile_buttons: Dictionary = {}  # scene_path -> Button
var _preview_viewports: Array[SubViewport] = []


func _ready() -> void:
	print("[HexToolbar] _ready called")
	custom_minimum_size = Vector2(0, 200)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_ui()
	print("[HexToolbar] _build_ui done, child count: ", get_child_count())


func _build_ui() -> void:
	# Top controls bar — added directly to self (VBoxContainer)
	var controls_bar := HBoxContainer.new()
	controls_bar.add_theme_constant_override("separation", 16)
	add_child(controls_bar)

	# Paint/Erase buttons
	var tool_box := HBoxContainer.new()
	tool_box.add_theme_constant_override("separation", 4)
	controls_bar.add_child(tool_box)

	var paint_btn := Button.new()
	paint_btn.text = "Paint"
	paint_btn.toggle_mode = true
	paint_btn.button_pressed = true
	paint_btn.tooltip_text = "Paint tiles (Left Click)"
	paint_btn.custom_minimum_size = Vector2(70, 28)
	paint_btn.pressed.connect(_on_tool_pressed.bind(ToolMode.PAINT))
	tool_box.add_child(paint_btn)
	_tool_buttons[ToolMode.PAINT] = paint_btn

	var erase_btn := Button.new()
	erase_btn.text = "Erase"
	erase_btn.toggle_mode = true
	erase_btn.tooltip_text = "Erase tiles (Shift + Left Click)"
	erase_btn.custom_minimum_size = Vector2(70, 28)
	erase_btn.pressed.connect(_on_tool_pressed.bind(ToolMode.ERASE))
	tool_box.add_child(erase_btn)
	_tool_buttons[ToolMode.ERASE] = erase_btn

	controls_bar.add_child(VSeparator.new())

	# Rotation controls
	var rot_box := HBoxContainer.new()
	rot_box.add_theme_constant_override("separation", 4)
	controls_bar.add_child(rot_box)

	var rot_label := Label.new()
	rot_label.text = "Rot:"
	rot_box.add_child(rot_label)

	_rotation_label = Label.new()
	_rotation_label.text = "0°"
	_rotation_label.custom_minimum_size.x = 36
	rot_box.add_child(_rotation_label)

	var rot_ccw := Button.new()
	rot_ccw.text = "<"
	rot_ccw.tooltip_text = "Rotate 60° CCW (Shift+R)"
	rot_ccw.custom_minimum_size = Vector2(28, 28)
	rot_ccw.pressed.connect(rotate_tile.bind(-60.0))
	rot_box.add_child(rot_ccw)

	var rot_cw := Button.new()
	rot_cw.text = ">"
	rot_cw.tooltip_text = "Rotate 60° CW (R)"
	rot_cw.custom_minimum_size = Vector2(28, 28)
	rot_cw.pressed.connect(rotate_tile.bind(60.0))
	rot_box.add_child(rot_cw)

	controls_bar.add_child(VSeparator.new())

	# Height controls
	var height_box := HBoxContainer.new()
	height_box.add_theme_constant_override("separation", 4)
	controls_bar.add_child(height_box)

	var height_label := Label.new()
	height_label.text = "Height:"
	height_box.add_child(height_label)

	_height_label = Label.new()
	_height_label.text = "1.00x"
	_height_label.custom_minimum_size.x = 44
	height_box.add_child(_height_label)

	var height_dec := Button.new()
	height_dec.text = "-"
	height_dec.tooltip_text = "Decrease height (-)"
	height_dec.custom_minimum_size = Vector2(28, 28)
	height_dec.pressed.connect(adjust_height.bind(-HEIGHT_STEP))
	height_box.add_child(height_dec)

	var height_inc := Button.new()
	height_inc.text = "+"
	height_inc.tooltip_text = "Increase height (+)"
	height_inc.custom_minimum_size = Vector2(28, 28)
	height_inc.pressed.connect(adjust_height.bind(HEIGHT_STEP))
	height_box.add_child(height_inc)

	# Tile grid area (scrollable)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 160)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	_tile_grid = GridContainer.new()
	_tile_grid.columns = 8
	_tile_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tile_grid.add_theme_constant_override("h_separation", 4)
	_tile_grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(_tile_grid)


## Set the available tile scenes and build the preview grid
func set_tile_palette(palette: Dictionary) -> void:
	print("[HexToolbar] set_tile_palette called with ", palette.size(), " tiles")
	_tile_scenes = palette
	_rebuild_tile_grid()

	# Auto-select first tile if none selected
	if _selected_tile_path.is_empty() and not _tile_scenes.is_empty():
		var paths := _tile_scenes.keys()
		paths.sort()
		select_tile(paths[0])


func select_tile(scene_path: String) -> void:
	if not _tile_scenes.has(scene_path):
		return

	_selected_tile_path = scene_path

	# Update visual selection
	for path in _tile_buttons:
		var btn: Button = _tile_buttons[path]
		btn.button_pressed = (path == scene_path)

	tile_selected.emit(scene_path)


func get_selected_tile_path() -> String:
	return _selected_tile_path


func get_selected_tile_scene() -> PackedScene:
	return _tile_scenes.get(_selected_tile_path)


func _rebuild_tile_grid() -> void:
	print("[HexToolbar] _rebuild_tile_grid called, _tile_grid valid: ", is_instance_valid(_tile_grid))
	print("[HexToolbar] self visible: ", visible, " self size: ", size, " parent: ", get_parent())
	if not is_instance_valid(_tile_grid):
		print("[HexToolbar] ERROR: _tile_grid is not valid!")
		return

	# Check _tile_grid is in the tree
	print("[HexToolbar] _tile_grid in tree: ", _tile_grid.is_inside_tree(), " _tile_grid parent: ", _tile_grid.get_parent())

	# Fix scroll container size — _build_ui doesn't re-run on hot-reload,
	# so we must ensure the scroll parent has proper sizing here
	var scroll_parent := _tile_grid.get_parent()
	if scroll_parent is ScrollContainer:
		scroll_parent.custom_minimum_size = Vector2(0, 160)
		scroll_parent.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Clear existing grid
	for child in _tile_grid.get_children():
		_tile_grid.remove_child(child)
		child.queue_free()
	_tile_buttons.clear()

	# Clean up old preview viewports
	for vp in _preview_viewports:
		if is_instance_valid(vp):
			vp.queue_free()
	_preview_viewports.clear()

	# Sort paths alphabetically
	var paths := _tile_scenes.keys()
	paths.sort()
	print("[HexToolbar] building ", paths.size(), " tile buttons")

	for path in paths:
		var file_name: String = path.get_file().get_basename()

		# Container for each tile preview
		var tile_btn := Button.new()
		tile_btn.toggle_mode = true
		tile_btn.custom_minimum_size = Vector2(PREVIEW_SIZE + 8, PREVIEW_SIZE + 24)
		tile_btn.tooltip_text = file_name
		tile_btn.pressed.connect(select_tile.bind(path))
		_tile_grid.add_child(tile_btn)
		_tile_buttons[path] = tile_btn

		# VBox inside button for preview + label — must anchor to fill the button
		var vbox := VBoxContainer.new()
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile_btn.add_child(vbox)
		vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		# Placeholder white box instead of viewport preview
		var color_rect := ColorRect.new()
		color_rect.custom_minimum_size = Vector2(PREVIEW_SIZE, PREVIEW_SIZE)
		color_rect.color = Color(0.85, 0.85, 0.85)
		color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(color_rect)

		# Label with tile name
		var name_label := Label.new()
		name_label.text = file_name
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 10)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(name_label)

	print("[HexToolbar] grid child count after build: ", _tile_grid.get_child_count())
	print("[HexToolbar] grid size: ", _tile_grid.size, " grid min size: ", _tile_grid.get_combined_minimum_size())
	var scroll := _tile_grid.get_parent()
	if scroll:
		print("[HexToolbar] scroll size: ", scroll.size, " scroll min size: ", scroll.get_combined_minimum_size())


# --- Tool methods ---

func set_tool(tool_mode: ToolMode) -> void:
	_current_tool = tool_mode
	for mode in _tool_buttons:
		_tool_buttons[mode].button_pressed = (mode == tool_mode)
	tool_changed.emit(tool_mode)


func get_tool() -> ToolMode:
	return _current_tool


func rotate_tile(amount: float = 60.0) -> void:
	_current_rotation = fmod(_current_rotation + amount, 360.0)
	if _current_rotation < 0:
		_current_rotation += 360.0
	_rotation_label.text = "%d°" % int(_current_rotation)
	rotation_changed.emit(_current_rotation)


func set_tile_rotation(degrees: float) -> void:
	_current_rotation = fmod(degrees, 360.0)
	if _current_rotation < 0:
		_current_rotation += 360.0
	_rotation_label.text = "%d°" % int(_current_rotation)


func get_tile_rotation() -> float:
	return _current_rotation


func adjust_height(amount: float) -> void:
	var new_height := clamp(_current_height + amount, HEIGHT_MIN, HEIGHT_MAX)
	if new_height != _current_height:
		_current_height = new_height
		_height_label.text = "%.2fx" % _current_height
		height_changed.emit(_current_height)


func set_height(height: float) -> void:
	_current_height = clamp(height, HEIGHT_MIN, HEIGHT_MAX)
	_height_label.text = "%.2fx" % _current_height


func get_height() -> float:
	return _current_height


func _on_tool_pressed(tool_mode: ToolMode) -> void:
	set_tool(tool_mode)
