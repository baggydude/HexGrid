@tool
extends EditorPlugin

func _enter_tree():
	add_custom_type(
		"ProceduralQuadGodray",
		"Node3D",
		preload("res://addons/procedural_quad_godray/procedural_quad_godray.gd"),
		preload("res://addons/procedural_quad_godray/icon.svg")
	)

func _exit_tree():
	remove_custom_type("ProceduralQuadGodray")