#lightning
@tool
extends GPUParticles3D

@export var auto_animate: bool = false
@export var cooldown: float = 2.0
var animation_time: float = 0.0

func _process(delta: float) -> void:

	if auto_animate:
		animation_time += delta
		if animation_time >= cooldown:
			animation_time = 0.0
			lightining()

	elif Input.is_action_just_pressed("ui_accept"):
		lightining()

func lightining():
	restart()
