@tool
class_name HexGridEditorToolbar
extends Control

## Editor toolbar for hex grid painting with brush navigation and scene preview

signal brush_selected(index: int)
signal variation_changed(variation_index: int)
signal tool_changed(tool_mode: ToolMode)
signal rotation_changed(degrees: float)
signal height_changed(height: float)

enum ToolMode { PAINT, ERASE, PICK }

var _brush_palette: Array[HexBrushResource] = []
var _selected_brush_index: int = -1
var _current_variation_index: int = 0
var _current_tool: ToolMode = ToolMode.PAINT
var _current_rotation: float = 0.0
var _current_height: float = 1.0

const HEIGHT_MIN: float = 1.0
const HEIGHT_MAX: float = 2.0
const HEIGHT_STEP: float = 0.25

# UI elements
var _toolbar_container: HBoxContainer
var _tool_buttons: Dictionary = {}
var _rotation_label: Label
var _height_label: Label
var _brush_name_label: Label
var _variation_label: Label

# SubViewport preview
var _preview_viewport: SubViewport
var _preview_camera: Camera3D
var _preview_light: DirectionalLight3D
var _preview_scene_instance: Node3D = null


func _ready() -> void:
	custom_minimum_size.y = 160
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
	paint_btn.text = "Paint"
	paint_btn.toggle_mode = true
	paint_btn.button_pressed = true
	paint_btn.tooltip_text = "Paint tiles (Left Click)"
	paint_btn.custom_minimum_size = Vector2(80, 32)
	paint_btn.pressed.connect(_on_tool_button_pressed.bind(ToolMode.PAINT))
	tool_buttons_container.add_child(paint_btn)
	_tool_buttons[ToolMode.PAINT] = paint_btn

	# Erase button
	var erase_btn := Button.new()
	erase_btn.text = "Erase"
	erase_btn.toggle_mode = true
	erase_btn.tooltip_text = "Erase tiles (Shift + Left Click)"
	erase_btn.custom_minimum_size = Vector2(80, 32)
	erase_btn.pressed.connect(_on_tool_button_pressed.bind(ToolMode.ERASE))
	tool_buttons_container.add_child(erase_btn)
	_tool_buttons[ToolMode.ERASE] = erase_btn

	# Pick button
	var pick_btn := Button.new()
	pick_btn.text = "Pick"
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
	_rotation_label.text = "0"
	_rotation_label.custom_minimum_size.x = 50
	_rotation_label.add_theme_font_size_override("font_size", 18)
	rot_row.add_child(_rotation_label)

	var rot_ccw_btn := Button.new()
	rot_ccw_btn.text = "<-"
	rot_ccw_btn.tooltip_text = "Rotate 60 counter-clockwise (Shift+R)"
	rot_ccw_btn.custom_minimum_size = Vector2(32, 32)
	rot_ccw_btn.pressed.connect(rotate_tile.bind(-60.0))
	rot_row.add_child(rot_ccw_btn)

	var rot_cw_btn := Button.new()
	rot_cw_btn.text = "->"
	rot_cw_btn.tooltip_text = "Rotate 60 clockwise (R)"
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

	# Brush palette section
	var palette_section := VBoxContainer.new()
	palette_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_toolbar_container.add_child(palette_section)

	# Brush name label
	_brush_name_label = Label.new()
	_brush_name_label.text = "No brush selected"
	_brush_name_label.add_theme_font_size_override("font_size", 14)
	palette_section.add_child(_brush_name_label)

	# Variation label
	_variation_label = Label.new()
	_variation_label.text = ""
	_variation_label.add_theme_font_size_override("font_size", 12)
	palette_section.add_child(_variation_label)

	# Navigation buttons row
	var nav_row := HBoxContainer.new()
	nav_row.add_theme_constant_override("separation", 4)
	palette_section.add_child(nav_row)

	var prev_brush_btn := Button.new()
	prev_brush_btn.text = "< Prev"
	prev_brush_btn.tooltip_text = "Previous brush"
	prev_brush_btn.custom_minimum_size = Vector2(64, 28)
	prev_brush_btn.pressed.connect(navigate_brush.bind(-1))
	nav_row.add_child(prev_brush_btn)

	var next_brush_btn := Button.new()
	next_brush_btn.text = "Next >"
	next_brush_btn.tooltip_text = "Next brush"
	next_brush_btn.custom_minimum_size = Vector2(64, 28)
	next_brush_btn.pressed.connect(navigate_brush.bind(1))
	nav_row.add_child(next_brush_btn)

	var cycle_btn := Button.new()
	cycle_btn.text = "Cycle (V)"
	cycle_btn.tooltip_text = "Cycle through scene variations (V)"
	cycle_btn.custom_minimum_size = Vector2(80, 28)
	cycle_btn.pressed.connect(cycle_variation)
	nav_row.add_child(cycle_btn)

	# Separator
	var sep4 := VSeparator.new()
	_toolbar_container.add_child(sep4)

	# Preview section
	var preview_section := VBoxContainer.new()
	_toolbar_container.add_child(preview_section)

	var preview_header := Label.new()
	preview_header.text = "Preview"
	preview_header.add_theme_font_size_override("font_size", 14)
	preview_section.add_child(preview_header)

	_build_preview_viewport(preview_section)


func _build_preview_viewport(parent: Control) -> void:
	# SubViewport added to toolbar tree for processing (not inside SubViewportContainer)
	_preview_viewport = SubViewport.new()
	_preview_viewport.size = Vector2i(120, 120)
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_preview_viewport.transparent_bg = false
	_preview_viewport.own_world_3d = true
	add_child(_preview_viewport)

	# TextureRect displays the viewport's rendered output
	var preview_rect := TextureRect.new()
	preview_rect.custom_minimum_size = Vector2(120, 120)
	preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_rect.texture = _preview_viewport.get_texture()
	parent.add_child(preview_rect)

	# Camera looking at the scene from an angled position
	_preview_camera = Camera3D.new()
	_preview_camera.position = Vector3(1.5, 2.0, 1.5)
	_preview_camera.look_at(Vector3.ZERO)
	_preview_viewport.add_child(_preview_camera)
	_preview_camera.make_current()

	# Directional light for illumination
	_preview_light = DirectionalLight3D.new()
	_preview_light.rotation_degrees = Vector3(-45, -45, 0)
	_preview_viewport.add_child(_preview_light)

	# Environment with ambient light (required for own_world_3d viewports)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.2, 0.2)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.5
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_preview_viewport.add_child(world_env)


# --- Brush palette methods ---

func set_brush_palette(palette: Array[HexBrushResource]) -> void:
	_brush_palette = palette
	_current_variation_index = 0

	# Auto-select first brush if none selected
	if _selected_brush_index < 0 and not _brush_palette.is_empty():
		select_brush(0)
	elif _brush_palette.is_empty():
		_selected_brush_index = -1
		_update_brush_label()
		_update_preview_scene()
	else:
		# Re-clamp index
		_selected_brush_index = clampi(_selected_brush_index, 0, _brush_palette.size() - 1)
		_update_brush_label()
		_update_preview_scene()


func select_brush(index: int) -> void:
	if index < 0 or index >= _brush_palette.size():
		return

	_selected_brush_index = index
	_current_variation_index = 0
	_update_brush_label()
	_update_preview_scene()
	brush_selected.emit(index)


func navigate_brush(delta: int) -> void:
	if _brush_palette.is_empty():
		return
	var new_index := wrapi(_selected_brush_index + delta, 0, _brush_palette.size())
	select_brush(new_index)


func cycle_variation() -> void:
	var brush := get_selected_brush()
	if not brush or brush.variations.size() <= 1:
		return
	_current_variation_index = wrapi(_current_variation_index + 1, 0, brush.variations.size())
	_update_brush_label()
	_update_preview_scene()
	variation_changed.emit(_current_variation_index)


func get_selected_brush() -> HexBrushResource:
	if _selected_brush_index >= 0 and _selected_brush_index < _brush_palette.size():
		return _brush_palette[_selected_brush_index]
	return null


func get_selected_brush_index() -> int:
	return _selected_brush_index


func get_variation_index() -> int:
	return _current_variation_index


func set_variation_index(idx: int) -> void:
	var brush := get_selected_brush()
	if brush and not brush.variations.is_empty():
		_current_variation_index = clampi(idx, 0, brush.variations.size() - 1)
	else:
		_current_variation_index = 0
	_update_brush_label()
	_update_preview_scene()


func _update_brush_label() -> void:
	var brush := get_selected_brush()
	if brush:
		_brush_name_label.text = "%s (%d/%d)" % [brush.name, _selected_brush_index + 1, _brush_palette.size()]
		if brush.variations.size() > 0:
			_variation_label.text = "Variation %d/%d" % [_current_variation_index + 1, brush.variations.size()]
		else:
			_variation_label.text = "No variations"
	else:
		_brush_name_label.text = "No brush selected"
		_variation_label.text = ""


func _update_preview_scene() -> void:
	# Remove old preview instance
	if _preview_scene_instance and is_instance_valid(_preview_scene_instance):
		_preview_scene_instance.queue_free()
		_preview_scene_instance = null

	var brush := get_selected_brush()
	if not brush or brush.variations.is_empty():
		return

	var idx := clampi(_current_variation_index, 0, brush.variations.size() - 1)
	var scene: PackedScene = brush.variations[idx]
	if not scene:
		return

	_preview_scene_instance = scene.instantiate()
	_preview_scene_instance.rotation_degrees.y = _current_rotation
	_preview_viewport.add_child(_preview_scene_instance)


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
	_rotation_label.text = "%d" % int(_current_rotation)
	rotation_changed.emit(_current_rotation)
	# Update preview rotation
	if _preview_scene_instance and is_instance_valid(_preview_scene_instance):
		_preview_scene_instance.rotation_degrees.y = _current_rotation


func set_tile_rotation(degrees: float) -> void:
	_current_rotation = fmod(degrees, 360.0)
	if _current_rotation < 0:
		_current_rotation += 360.0
	_rotation_label.text = "%d" % int(_current_rotation)
	# Update preview rotation
	if _preview_scene_instance and is_instance_valid(_preview_scene_instance):
		_preview_scene_instance.rotation_degrees.y = _current_rotation


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


func _on_tool_button_pressed(tool_mode: ToolMode) -> void:
	set_tool(tool_mode)


