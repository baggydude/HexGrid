@tool
class_name HexGridEditorToolbar
extends Control

## Editor toolbar for hex grid painting

signal tile_selected(index: int)
signal tool_changed(tool_mode: ToolMode)
signal rotation_changed(degrees: float)
signal height_changed(height: float)

enum ToolMode { PAINT, ERASE, PICK }

var _tile_palette: Array[HexTileResource] = []
var _selected_tile_index: int = -1
var _current_tool: ToolMode = ToolMode.PAINT
var _current_rotation: float = 0.0
var _current_height: float = 1.0

const HEIGHT_MIN: float = 1.0
const HEIGHT_MAX: float = 2.0
const HEIGHT_STEP: float = 0.25

# UI elements
var _toolbar_container: HBoxContainer
var _palette_scroll: ScrollContainer
var _palette_container: HBoxContainer
var _tool_buttons: Dictionary = {}
var _rotation_label: Label
var _height_label: Label
var _palette_buttons: Array[Button] = []
var _empty_label: Label = null


func _ready() -> void:
	custom_minimum_size.y = 80
	_build_ui()


func _build_ui() -> void:
	# Main container
	_toolbar_container = HBoxContainer.new()
	_toolbar_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toolbar_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_toolbar_container.add_theme_constant_override("separation", 16)
	add_child(_toolbar_container)
	
	# Tool section with header
	var tool_section := VBoxContainer.new()
	_toolbar_container.add_child(tool_section)
	
	var tool_header := Label.new()
	tool_header.text = "Tools"
	tool_header.add_theme_font_size_override("font_size", 14)
	tool_section.add_child(tool_header)
	
	var tool_buttons_container := HBoxContainer.new()
	tool_buttons_container.add_theme_constant_override("separation", 4)
	tool_section.add_child(tool_buttons_container)
	
	# Paint button
	var paint_btn := Button.new()
	paint_btn.text = "🖌 Paint"
	paint_btn.toggle_mode = true
	paint_btn.button_pressed = true
	paint_btn.tooltip_text = "Paint tiles (Left Click)"
	paint_btn.custom_minimum_size = Vector2(80, 32)
	paint_btn.pressed.connect(_on_tool_button_pressed.bind(ToolMode.PAINT))
	tool_buttons_container.add_child(paint_btn)
	_tool_buttons[ToolMode.PAINT] = paint_btn
	
	# Erase button
	var erase_btn := Button.new()
	erase_btn.text = "🗑 Erase"
	erase_btn.toggle_mode = true
	erase_btn.tooltip_text = "Erase tiles (Shift + Left Click)"
	erase_btn.custom_minimum_size = Vector2(80, 32)
	erase_btn.pressed.connect(_on_tool_button_pressed.bind(ToolMode.ERASE))
	tool_buttons_container.add_child(erase_btn)
	_tool_buttons[ToolMode.ERASE] = erase_btn
	
	# Pick button
	var pick_btn := Button.new()
	pick_btn.text = "💉 Pick"
	pick_btn.toggle_mode = true
	pick_btn.tooltip_text = "Pick tile from grid (Alt + Left Click)"
	pick_btn.custom_minimum_size = Vector2(80, 32)
	pick_btn.pressed.connect(_on_tool_button_pressed.bind(ToolMode.PICK))
	tool_buttons_container.add_child(pick_btn)
	_tool_buttons[ToolMode.PICK] = pick_btn
	
	# Separator
	var sep1 := VSeparator.new()
	_toolbar_container.add_child(sep1)
	
	# Rotation section
	var rotation_section := VBoxContainer.new()
	_toolbar_container.add_child(rotation_section)
	
	var rot_header := Label.new()
	rot_header.text = "Rotation"
	rot_header.add_theme_font_size_override("font_size", 14)
	rotation_section.add_child(rot_header)
	
	var rot_row := HBoxContainer.new()
	rot_row.add_theme_constant_override("separation", 8)
	rotation_section.add_child(rot_row)
	
	_rotation_label = Label.new()
	_rotation_label.text = "0°"
	_rotation_label.custom_minimum_size.x = 50
	_rotation_label.add_theme_font_size_override("font_size", 18)
	rot_row.add_child(_rotation_label)
	
	var rot_ccw_btn := Button.new()
	rot_ccw_btn.text = "↺"
	rot_ccw_btn.tooltip_text = "Rotate 60° counter-clockwise (Shift+R)"
	rot_ccw_btn.custom_minimum_size = Vector2(32, 32)
	rot_ccw_btn.pressed.connect(rotate_tile.bind(-60.0))
	rot_row.add_child(rot_ccw_btn)
	
	var rot_cw_btn := Button.new()
	rot_cw_btn.text = "↻"
	rot_cw_btn.tooltip_text = "Rotate 60° clockwise (R)"
	rot_cw_btn.custom_minimum_size = Vector2(32, 32)
	rot_cw_btn.pressed.connect(rotate_tile.bind(60.0))
	rot_row.add_child(rot_cw_btn)

	# Separator
	var sep2 := VSeparator.new()
	_toolbar_container.add_child(sep2)

	# Height section
	var height_section := VBoxContainer.new()
	_toolbar_container.add_child(height_section)

	var height_header := Label.new()
	height_header.text = "Height"
	height_header.add_theme_font_size_override("font_size", 14)
	height_section.add_child(height_header)

	var height_row := HBoxContainer.new()
	height_row.add_theme_constant_override("separation", 8)
	height_section.add_child(height_row)

	_height_label = Label.new()
	_height_label.text = "1.00x"
	_height_label.custom_minimum_size.x = 50
	_height_label.add_theme_font_size_override("font_size", 18)
	height_row.add_child(_height_label)

	var height_dec_btn := Button.new()
	height_dec_btn.text = "-"
	height_dec_btn.tooltip_text = "Decrease height (-)"
	height_dec_btn.custom_minimum_size = Vector2(32, 32)
	height_dec_btn.pressed.connect(adjust_height.bind(-HEIGHT_STEP))
	height_row.add_child(height_dec_btn)

	var height_inc_btn := Button.new()
	height_inc_btn.text = "+"
	height_inc_btn.tooltip_text = "Increase height (+)"
	height_inc_btn.custom_minimum_size = Vector2(32, 32)
	height_inc_btn.pressed.connect(adjust_height.bind(HEIGHT_STEP))
	height_row.add_child(height_inc_btn)

	# Separator
	var sep3 := VSeparator.new()
	_toolbar_container.add_child(sep3)
	
	# Palette section
	var palette_section := VBoxContainer.new()
	palette_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toolbar_container.add_child(palette_section)
	
	var palette_header := Label.new()
	palette_header.text = "Tile Palette (add HexTileResources to the grid's Tile Palette array)"
	palette_header.add_theme_font_size_override("font_size", 14)
	palette_section.add_child(palette_header)
	
	_palette_scroll = ScrollContainer.new()
	_palette_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_palette_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_palette_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	palette_section.add_child(_palette_scroll)
	
	_palette_container = HBoxContainer.new()
	_palette_container.add_theme_constant_override("separation", 8)
	_palette_scroll.add_child(_palette_container)


func set_tile_palette(palette: Array[HexTileResource]) -> void:
	_tile_palette = palette
	_rebuild_palette_ui()
	
	# Auto-select first tile if none selected
	if _selected_tile_index < 0 and not _tile_palette.is_empty():
		select_tile(0)


func _rebuild_palette_ui() -> void:
	# Clear existing buttons
	for btn in _palette_buttons:
		btn.queue_free()
	_palette_buttons.clear()
	
	# Clear empty label if it exists
	if _empty_label and is_instance_valid(_empty_label):
		_empty_label.queue_free()
		_empty_label = null
	
	if _tile_palette.is_empty():
		_empty_label = Label.new()
		_empty_label.text = "No tiles - add HexTileResources to Tile Palette"
		_empty_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		_palette_container.add_child(_empty_label)
		return
	
	# Create buttons for each tile
	for i in range(_tile_palette.size()):
		var tile := _tile_palette[i]
		var btn := Button.new()
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(80, 48)
		btn.tooltip_text = tile.tile_name if tile else "Empty"
		
		# Create a visual representation
		if tile:
			btn.text = tile.tile_name
			var style_normal := StyleBoxFlat.new()
			style_normal.bg_color = tile.preview_color if tile.preview_color != Color.WHITE else Color(0.3, 0.3, 0.3)
			style_normal.set_border_width_all(2)
			style_normal.border_color = Color(0.5, 0.5, 0.5)
			style_normal.set_corner_radius_all(4)
			btn.add_theme_stylebox_override("normal", style_normal)
			
			var style_pressed := style_normal.duplicate()
			style_pressed.border_color = Color(1.0, 0.8, 0.2)
			style_pressed.border_width_bottom = 4
			style_pressed.border_width_top = 4
			style_pressed.border_width_left = 4
			style_pressed.border_width_right = 4
			btn.add_theme_stylebox_override("pressed", style_pressed)
			
			# Contrast text color based on background
			var luminance := tile.preview_color.r * 0.299 + tile.preview_color.g * 0.587 + tile.preview_color.b * 0.114
			if luminance > 0.5:
				btn.add_theme_color_override("font_color", Color.BLACK)
				btn.add_theme_color_override("font_pressed_color", Color.BLACK)
		else:
			btn.text = "?"
		
		btn.pressed.connect(_on_palette_button_pressed.bind(i))
		_palette_container.add_child(btn)
		_palette_buttons.append(btn)


func select_tile(index: int) -> void:
	if index < 0 or index >= _tile_palette.size():
		return
	
	_selected_tile_index = index
	
	# Update button states
	for i in range(_palette_buttons.size()):
		_palette_buttons[i].button_pressed = (i == index)
	
	tile_selected.emit(index)


func get_selected_tile() -> HexTileResource:
	if _selected_tile_index >= 0 and _selected_tile_index < _tile_palette.size():
		return _tile_palette[_selected_tile_index]
	return null


func get_selected_tile_index() -> int:
	return _selected_tile_index


func set_tool(tool_mode: ToolMode) -> void:
	_current_tool = tool_mode
	
	# Update button states
	for mode in _tool_buttons:
		_tool_buttons[mode].button_pressed = (mode == tool_mode)
	
	tool_changed.emit(tool_mode)


func get_tool() -> ToolMode:
	return _current_tool


func rotate_tile(amount: float = 60.0) -> void:
	# Toggle between 0 and 60 degrees only
	if _current_rotation == 0.0:
		_current_rotation = 60.0
	else:
		_current_rotation = 0.0
	_rotation_label.text = "%d°" % int(_current_rotation)
	rotation_changed.emit(_current_rotation)

func set_rotation(degrees: float) -> void:
	_current_rotation = fmod(degrees, 360.0)
	if _current_rotation < 0:
		_current_rotation += 360.0
	_rotation_label.text = "%d°" % int(_current_rotation)


func get_rotation() -> float:
	return _current_rotation


func _on_tool_button_pressed(tool_mode: ToolMode) -> void:
	set_tool(tool_mode)


func _on_palette_button_pressed(index: int) -> void:
	select_tile(index)
	# Switch to paint mode when selecting a tile
	set_tool(ToolMode.PAINT)


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
