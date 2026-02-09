extends Node3D

@export var auto_animate: bool = false
@export var cooldown: float = 2.0
var animation_time: float = 0.0

@onready var spikes: GPUParticles3D = $Spikes
@onready var sparks: GPUParticles3D = $Sparks
@onready var crack: Decal = $Crack

func _process(delta):
	if auto_animate:
		animation_time += delta
		
		if animation_time >= cooldown:
			ground_attack()
			animation_time = 0.0
	
	elif Input.is_action_just_pressed("ui_accept"):
		ground_attack()

func ground_attack():
	spikes.restart()
	sparks.restart()
	crack.emission_energy = 0.0

	await get_tree().create_timer(0.2).timeout
	crack.emission_energy = 16.0

	await get_tree().create_timer(1.0).timeout

	var duration := 2.0
	var steps := 20
	for i in range(steps + 1):
		var t := i / float(steps)
		crack.emission_energy = lerp(16.0, 0.0, t)
		await get_tree().create_timer(duration / steps).timeout
