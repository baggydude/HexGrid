# Procedural Quad Godray Plugin

A Godot plugin that creates volumetric god ray effects by generating a grid of aligned quads that follow the sun's direction.

## Features

- **Automatic Sun Detection**: Searches for a DirectionalLight3D node named "Sun" in the scene
- **Grid-based Quad Generation**: Creates multiple layers of quads in a grid pattern
- **High Performance**: Uses MultiMeshInstance3D for efficient rendering of hundreds of quads
- **Sun Alignment**: Automatically aligns all quads to face the sun direction
- **Customizable Parameters**: Adjust grid size, quad spacing, layer count, and more
- **Separate Width/Height Control**: Independent control over quad width and height
- **Auto-stretch**: Quads can be automatically stretched in the sun's direction
- **Real-time Updates**: Quads update automatically when the sun moves
- **Shell Texturing Fix**: Advanced parameters to eliminate visible grid gaps at any camera angle

## Installation

1. Copy the `procedural_quad_godray` folder to your project's `addons/` directory
2. Enable the plugin in Project Settings > Plugins
3. The "ProceduralQuadGodray" node will be available in the Create Node dialog

## Usage

1. Add a `DirectionalLight3D` node to your scene
2. Add a `ProceduralQuadGodray` node to your scene
3. Configure the parameters in the inspector:
   - **Grid Size**: Number of quads in X and Z directions
   - **Quad Spacing**: Distance between quads
   - **Layer Count**: Number of quad layers
   - **Layer Spacing**: Distance between layers
   - **Quad Width**: Width of individual quads
   - **Quad Height**: Height of individual quads
   - **Auto Stretch**: Enable automatic stretching in sun direction
   - **Stretch Factor**: How much to stretch the quads
   - **Godray Material**: Assign the included godray material or your own

## Parameters

### Grid Settings
- `grid_size`: Vector2i - Number of quads in the grid (default: 10x10)
- `quad_spacing`: float - Spacing between quads (default: 1.0)
- `layer_count`: int - Number of layers (default: 5)
- `layer_spacing`: float - Distance between layers (default: 0.5)

### Quad Settings
- `quad_width`: float - Width of individual quads (default: 1.0)
- `quad_height`: float - Height of individual quads (default: 1.0)
- `auto_stretch`: bool - Automatically stretch quads in sun direction (default: true)
- `stretch_factor`: float - Stretch multiplier (default: 2.0)

### Shell Texturing Fix
- `adaptive_density`: bool - Enable adaptive grid density to reduce gaps (default: true)
- `density_multiplier`: float - Multiplier for grid density (default: 2.0)
- `jitter_amount`: float - Amount of random jitter to break up patterns (default: 0.3)
- `layer_overlap`: float - Overlap between layers to reduce gaps (default: 0.2)
- `adaptive_layer_spacing`: bool - Use non-linear layer spacing (default: true)
- `min_layer_spacing`: float - Minimum spacing between layers (default: 0.1)
- `max_layer_spacing`: float - Maximum spacing between layers (default: 1.0)

### Material
- `godray_material`: Material - Material to apply to all quads

### Debug
- `show_debug_info`: bool - Print debug information to console
- `regenerate_quads`: bool - Force regeneration of all quads

## Included Shader

The plugin includes a godray shader (`godray_shader.gdshader`) with the following parameters:

### Core Parameters
- `intensity`: Overall brightness of the effect
- `fade_power`: How quickly the effect fades vertically
- `ray_color`: Color of the god rays
- `noise_scale`: Scale of the noise pattern
- `noise_speed`: Animation speed of the noise
- `edge_fade`: Fade amount at the edges

### Shell Texturing Improvements
- `depth_blend_factor`: Strength of depth-based blending (default: 0.8)
- `layer_blend_smoothness`: Smoothness of layer blending (default: 0.15)
- `use_soft_edges`: Enable soft edge transitions (default: true)
- `soft_edge_radius`: Radius for soft edge calculation (default: 0.35)

## Shell Texturing Fix

The plugin includes advanced features to eliminate visible grid gaps that commonly occur in shell texturing techniques:

### Adaptive Density
- Automatically increases grid density to reduce visible gaps
- Uses a density multiplier to create more quads in the same space
- Maintains performance by using efficient MultiMesh rendering

### Jitter and Variation
- Adds random jitter to break up regular grid patterns
- Layer-based variation prevents visible seams between layers
- Configurable jitter amount for fine-tuning

### Adaptive Layer Spacing
- Uses non-linear spacing between layers to reduce visible gaps
- Exponential distribution provides better visual coverage
- Configurable min/max spacing for different effects

### Improved Shader
- Removed billboard rotation that caused alignment issues
- Added depth-based blending to reduce layer visibility
- Soft edge transitions for smoother appearance
- Layer variation through noise textures

## Tips

- **For best shell texturing**: Enable `adaptive_density` and `adaptive_layer_spacing`
- **Reduce gaps**: Increase `density_multiplier` and `jitter_amount`
- **Smoother appearance**: Use the included `godray_material.tres` with optimized parameters
- **Performance**: Keep `grid_size` and `layer_count` reasonable for your target platform
- **Custom effects**: Adjust `layer_overlap` and spacing parameters for different visual styles
- **Camera angles**: The shell texturing fix ensures consistent appearance from any viewing angle

## Requirements

- Godot 4.0 or later
- A DirectionalLight3D node named "Sun" in the scene (or any DirectionalLight3D as fallback)
