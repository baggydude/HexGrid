# Hex Grid Editor for Godot 4

A comprehensive 3D hex grid editor plugin for Godot 4 that allows you to create, paint, and manage hexagonal grids with snapping, rotation, and customizable tile types.

## Features

- **Flexible Grid Configuration**
  - Pointy-top or flat-top hex orientations
  - Configurable grid width and height
  - Adjustable hex size
  
- **Visual Guide Grid**
  - Toggle-able guide overlay showing hex boundaries
  - Customizable grid color and transparency
  
- **Tile Painting System**
  - Paint mode (LMB) - place tiles
  - Erase mode (Shift+LMB) - remove tiles
  - Pick mode (Alt+LMB) - sample existing tiles
  - Drag painting support
  - Live preview of tile placement
  
- **Rotation Support**
  - Press **R** to rotate tile 60° clockwise
  - Press **Shift+R** to rotate counter-clockwise
  - Rotation persists per tile
  
- **Tile Resources**
  - Custom mesh per tile type
  - Material overrides
  - Gameplay properties (IsBlocked, MovementCost)
  - Height offset for terrain variation
  - Preview colors for editor palette

## Installation

1. Copy the `addons/hex_grid_editor` folder to your project's `addons` directory
2. Enable the plugin: Project > Project Settings > Plugins > Enable "Hex Grid Editor"

## Quick Start

### 1. Create Tile Resources

Create `HexTileResource` files for each terrain type:

```gdscript
var grass = HexTileResource.new()
grass.tile_name = "Grass"
grass.mesh = preload("res://meshes/hex_grass.tres")
grass.is_blocked = false
grass.movement_cost = 1.0
grass.preview_color = Color.GREEN
```

Or run the included `create_example_tiles.gd` script from the editor to generate sample tiles.

### 2. Add a HexGrid3D Node

1. Add a `HexGrid3D` node to your scene
2. Configure grid settings in the inspector:
   - **Grid Width/Height**: Size of the grid
   - **Hex Size**: Radius of each hex
   - **Pointy Top**: Toggle orientation
3. Add your `HexTileResource` files to the **Tile Palette** array

### 3. Paint Your Grid

1. Select the HexGrid3D node
2. The toolbar appears above the 3D viewport
3. Select a tile from the palette
4. Click and drag to paint tiles
5. Use modifiers for different tools:
   - **LMB**: Paint
   - **Shift+LMB**: Erase  
   - **Alt+LMB**: Pick tile
   - **R**: Rotate 60° CW
   - **Shift+R**: Rotate 60° CCW

## API Reference

### HexGrid3D

The main grid node.

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `grid_width` | int | Number of columns |
| `grid_height` | int | Number of rows |
| `hex_size` | float | Hex radius |
| `pointy_top` | bool | Orientation (true = pointy top) |
| `show_guide_grid` | bool | Toggle guide visibility |
| `guide_grid_color` | Color | Guide line color |
| `grid_data` | HexGridData | Serialized grid state |
| `tile_palette` | Array[HexTileResource] | Available tiles |

#### Methods

```gdscript
# Place a tile
func place_tile(axial_coord: Vector2i, tile: HexTileResource, rotation_degrees: float = 0.0) -> void

# Remove a tile
func remove_tile(axial_coord: Vector2i) -> void

# Get tile data at position
func get_tile_at(axial_coord: Vector2i) -> Dictionary

# Check if tile exists
func has_tile_at(axial_coord: Vector2i) -> bool

# Clear all tiles
func clear_all_tiles() -> void

# Coordinate conversions
func world_to_axial(world_pos: Vector3) -> Vector2i
func axial_to_world(axial_coord: Vector2i) -> Vector3
func snap_to_hex(world_pos: Vector3) -> Vector3

# Bounds checking
func is_in_bounds(axial_coord: Vector2i) -> bool
```

#### Signals

```gdscript
signal cell_changed(axial_coord: Vector2i)
signal grid_cleared
```

### HexTileResource

Resource defining a tile type.

| Property | Type | Description |
|----------|------|-------------|
| `tile_name` | String | Display name |
| `mesh` | Mesh | 3D mesh to render |
| `material_override` | Material | Optional material |
| `is_blocked` | bool | Movement blocked? |
| `movement_cost` | float | Pathfinding cost |
| `height_offset` | float | Y position offset |
| `preview_color` | Color | Editor palette color |
| `custom_properties` | Dictionary | Custom data |

### HexMath

Static utility class for hex coordinate math.

```gdscript
# Convert between coordinate systems
HexMath.axial_to_world(axial: Vector2i, hex_size: float, pointy_top: bool) -> Vector3
HexMath.world_to_axial(world_pos: Vector3, hex_size: float, pointy_top: bool) -> Vector2i

# Offset coordinates (for rectangular bounds)
HexMath.axial_to_offset(axial: Vector2i, pointy_top: bool) -> Vector2i
HexMath.offset_to_axial(offset: Vector2i, pointy_top: bool) -> Vector2i

# Get all coords in a grid
HexMath.get_grid_coords(width: int, height: int, pointy_top: bool) -> Array[Vector2i]

# Get neighboring hexes
HexMath.get_neighbors(axial: Vector2i) -> Array[Vector2i]

# Calculate hex distance
HexMath.distance(a: Vector2i, b: Vector2i) -> int
```

### HexMeshGenerator

Utility for generating hex meshes procedurally.

```gdscript
# Create a hex prism (with height)
HexMeshGenerator.create_hex_prism(hex_size: float, height: float, pointy_top: bool) -> ArrayMesh

# Create a flat hex (no height)
HexMeshGenerator.create_hex_flat(hex_size: float, pointy_top: bool) -> ArrayMesh
```

## Runtime Usage

The grid works at runtime too! Access tiles for gameplay:

```gdscript
extends Node3D

@onready var hex_grid: HexGrid3D = $HexGrid3D

func get_movement_cost(world_position: Vector3) -> float:
    var axial = hex_grid.world_to_axial(world_position)
    var tile_data = hex_grid.get_tile_at(axial)
    
    if tile_data.is_empty():
        return INF  # No tile = impassable
    
    var tile: HexTileResource = tile_data.get("tile_resource")
    return tile.movement_cost if tile else INF

func is_walkable(world_position: Vector3) -> bool:
    var axial = hex_grid.world_to_axial(world_position)
    var tile_data = hex_grid.get_tile_at(axial)
    
    if tile_data.is_empty():
        return false
    
    var tile: HexTileResource = tile_data.get("tile_resource")
    return not tile.is_blocked if tile else false
```

## Coordinate Systems

The plugin uses **axial coordinates** (q, r) internally, which are ideal for hex math. The `HexMath` class provides conversion to/from:

- **World coordinates**: 3D Vector3 positions
- **Offset coordinates**: Grid-aligned (col, row) for rectangular bounds

### Pointy-Top vs Flat-Top

```
Pointy-Top (default):     Flat-Top:
    /\                    ____
   /  \                  /    \
  /    \                /      \
  \    /                \      /
   \  /                  \____/
    \/
```

## File Structure

```
addons/hex_grid_editor/
├── plugin.cfg                    # Plugin metadata
├── hex_grid_editor_plugin.gd     # Main editor plugin
├── hex_grid_editor_toolbar.gd    # Toolbar UI
├── hex_grid_3d.gd                # Main grid node
├── hex_grid_data.gd              # Serializable grid data
├── hex_tile_resource.gd          # Tile type resource
├── hex_math.gd                   # Coordinate math utilities
└── hex_mesh_generator.gd         # Procedural mesh generation
```

## Tips

1. **Performance**: For large grids, consider using instancing or MultiMesh for rendering
2. **Custom Meshes**: Use the `HexMeshGenerator` for quick prototypes, then replace with proper models
3. **Saving**: The `HexGridData` resource auto-saves with your scene
4. **Pathfinding**: Use `HexMath.get_neighbors()` and `HexMath.distance()` for A* implementation

## License

MIT License - Feel free to use in your projects!
