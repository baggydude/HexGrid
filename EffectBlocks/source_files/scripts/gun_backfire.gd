extends MeshInstance3D

enum BackfireDirection {
	NEGATIVE_X,
	POSITIVE_X,
	NEGATIVE_Y,
	POSITIVE_Y,
	NEGATIVE_Z,
	POSITIVE_Z
}

@export var muzzle_flash: Node3D
@export var auto_animate: bool = false
@export var backfire_direction: BackfireDirection = BackfireDirection.NEGATIVE_Z
@export var distance = 0.02
@export var duration = 0.05
@export var cooldown = 0.1

var is_backfiring = false
var backfire_timer = 0.0
var animation_time: float = 0.0

var original_position = Vector3.ZERO
var backfire_position = Vector3.ZERO

func _ready():
	original_position = position

func _process(delta):
	# Initialize position if not set
	if original_position == Vector3.ZERO:
		original_position = position
	
	if auto_animate:
		animation_time += delta
		if animation_time >= cooldown and not is_backfiring:
			start_animation()
			animation_time = 0.0
	
	# Manual trigger (only when auto_animate is disabled)
	# Use Engine.is_editor_hint() to handle input differently in editor
	if not auto_animate and not is_backfiring:
		var should_trigger = false
		if Engine.is_editor_hint():
			# In editor, trigger on space key
			should_trigger = Input.is_key_pressed(KEY_SPACE)
		else:
			# In game, use the action
			should_trigger = Input.is_action_just_pressed("ui_accept")
		
		if should_trigger:
			start_animation()
	
	if is_backfiring:
		backfire_timer += delta
		
		if backfire_timer <= duration / 2:
			var t = backfire_timer / (duration / 2)
			position = original_position.lerp(backfire_position, t)
		elif backfire_timer <= duration:
			var t = (backfire_timer - duration / 2) / (duration / 2)
			position = backfire_position.lerp(original_position, t)
		else:
			position = original_position
			is_backfiring = false
			backfire_timer = 0.0

func start_animation():
	if muzzle_flash and muzzle_flash.has_method("muzzle_flash"):
		muzzle_flash.muzzle_flash()
	
	is_backfiring = true
	backfire_timer = 0.0
	
	var direction_vector = get_direction_vector()
	backfire_position = original_position + direction_vector * distance

func get_direction_vector() -> Vector3:
	match backfire_direction:
		BackfireDirection.NEGATIVE_X:
			return -Vector3.RIGHT
		BackfireDirection.POSITIVE_X:
			return Vector3.RIGHT
		BackfireDirection.NEGATIVE_Y:
			return -Vector3.UP
		BackfireDirection.POSITIVE_Y:
			return Vector3.UP
		BackfireDirection.NEGATIVE_Z:
			return -Vector3.FORWARD
		BackfireDirection.POSITIVE_Z:
			return Vector3.FORWARD
		_:
			return -Vector3.FORWARD
