@tool
extends EditorScript

## Run this script from the editor to generate example tile resources
## Editor > Run Script (after selecting this file)

func _run() -> void:
	print("Creating example hex tile resources...")
	
	# Create resources directory
	var dir := DirAccess.open("res://")
	if dir:
		dir.make_dir_recursive("res://hex_tiles")
	
	# Generate hex meshes
	var hex_mesh_flat := HexMeshGenerator.create_hex_prism(0.95, 0.05, true)
	var hex_mesh_tall := HexMeshGenerator.create_hex_prism(0.95, 0.3, true)
	var hex_mesh_water := HexMeshGenerator.create_hex_prism(0.95, 0.02, true)
	
	# Save meshes
	ResourceSaver.save(hex_mesh_flat, "res://hex_tiles/hex_mesh_flat.tres")
	ResourceSaver.save(hex_mesh_tall, "res://hex_tiles/hex_mesh_tall.tres")
	ResourceSaver.save(hex_mesh_water, "res://hex_tiles/hex_mesh_water.tres")
	
	# Create materials
	var grass_mat := StandardMaterial3D.new()
	grass_mat.albedo_color = Color(0.3, 0.6, 0.2)
	ResourceSaver.save(grass_mat, "res://hex_tiles/grass_material.tres")
	
	var stone_mat := StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.5, 0.5, 0.5)
	ResourceSaver.save(stone_mat, "res://hex_tiles/stone_material.tres")
	
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.2, 0.4, 0.8, 0.8)
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ResourceSaver.save(water_mat, "res://hex_tiles/water_material.tres")
	
	var sand_mat := StandardMaterial3D.new()
	sand_mat.albedo_color = Color(0.9, 0.8, 0.5)
	ResourceSaver.save(sand_mat, "res://hex_tiles/sand_material.tres")
	
	var forest_mat := StandardMaterial3D.new()
	forest_mat.albedo_color = Color(0.15, 0.35, 0.1)
	ResourceSaver.save(forest_mat, "res://hex_tiles/forest_material.tres")
	
	var mountain_mat := StandardMaterial3D.new()
	mountain_mat.albedo_color = Color(0.4, 0.35, 0.3)
	ResourceSaver.save(mountain_mat, "res://hex_tiles/mountain_material.tres")
	
	# Create tile resources
	var grass_tile := HexTileResource.new()
	grass_tile.tile_name = "Grass"
	grass_tile.mesh = hex_mesh_flat
	grass_tile.material_override = grass_mat
	grass_tile.is_blocked = false
	grass_tile.movement_cost = 1.0
	grass_tile.preview_color = Color(0.3, 0.6, 0.2)
	ResourceSaver.save(grass_tile, "res://hex_tiles/tile_grass.tres")
	
	var stone_tile := HexTileResource.new()
	stone_tile.tile_name = "Stone"
	stone_tile.mesh = hex_mesh_flat
	stone_tile.material_override = stone_mat
	stone_tile.is_blocked = false
	stone_tile.movement_cost = 1.5
	stone_tile.preview_color = Color(0.5, 0.5, 0.5)
	ResourceSaver.save(stone_tile, "res://hex_tiles/tile_stone.tres")
	
	var water_tile := HexTileResource.new()
	water_tile.tile_name = "Water"
	water_tile.mesh = hex_mesh_water
	water_tile.material_override = water_mat
	water_tile.is_blocked = true
	water_tile.movement_cost = 99.0
	water_tile.height_offset = -0.05
	water_tile.preview_color = Color(0.2, 0.4, 0.8)
	ResourceSaver.save(water_tile, "res://hex_tiles/tile_water.tres")
	
	var sand_tile := HexTileResource.new()
	sand_tile.tile_name = "Sand"
	sand_tile.mesh = hex_mesh_flat
	sand_tile.material_override = sand_mat
	sand_tile.is_blocked = false
	sand_tile.movement_cost = 2.0
	sand_tile.preview_color = Color(0.9, 0.8, 0.5)
	ResourceSaver.save(sand_tile, "res://hex_tiles/tile_sand.tres")
	
	var forest_tile := HexTileResource.new()
	forest_tile.tile_name = "Forest"
	forest_tile.mesh = hex_mesh_tall
	forest_tile.material_override = forest_mat
	forest_tile.is_blocked = false
	forest_tile.movement_cost = 2.5
	forest_tile.preview_color = Color(0.15, 0.35, 0.1)
	ResourceSaver.save(forest_tile, "res://hex_tiles/tile_forest.tres")
	
	var mountain_tile := HexTileResource.new()
	mountain_tile.tile_name = "Mountain"
	mountain_tile.mesh = hex_mesh_tall
	mountain_tile.material_override = mountain_mat
	mountain_tile.is_blocked = true
	mountain_tile.movement_cost = 99.0
	mountain_tile.height_offset = 0.1
	mountain_tile.preview_color = Color(0.4, 0.35, 0.3)
	ResourceSaver.save(mountain_tile, "res://hex_tiles/tile_mountain.tres")
	
	print("Done! Created 6 tile resources in res://hex_tiles/")
	print("Add them to your HexGrid3D's Tile Palette array to use them.")
