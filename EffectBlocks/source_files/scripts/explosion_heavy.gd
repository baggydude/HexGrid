#explosion_heavy
@tool
extends Node3D

@export var auto_animate: bool = false
@export var cooldown: float = 2.0
var animation_time: float = 0.0

@onready var fire: GPUParticles3D = $Fire
@onready var sparks: GPUParticles3D = $Sparks
@onready var smoke: GPUParticles3D = $Smoke
@onready var debri: GPUParticles3D = $Debri

func _process(delta: float) -> void:
	if auto_animate:
		animation_time += delta
		
		if animation_time >= cooldown:
			explosion()
			animation_time = 0.0
	
	elif Input.is_action_just_pressed("ui_accept"):
		explosion()

func explosion() -> void:
	fire.restart()
	sparks.restart()
	smoke.restart()
	debri.restart()
	
