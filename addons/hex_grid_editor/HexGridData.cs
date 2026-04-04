using Godot;
using Godot.Collections;

/// <summary>
/// Serializable resource storing all placed cell data for a HexGrid3D.
/// Each entry in Cells maps a Vector2I axial coordinate to a Dictionary with:
///   "scene_path"       : string  — res:// path to the tile .tscn
///   "rotation_degrees" : float   — Y-axis rotation
///   "world_position"   : Vector3 — stored XZ position (for persistence)
///   "placed_pointy_top": bool    — grid orientation at placement time
///   "height_scale"     : float   — height multiplier (1.0 = default)
/// </summary>
[Tool]
[GlobalClass]
public partial class HexGridData : Resource
{
    [Export] public Dictionary Cells { get; set; } = new();

    [Export] public int GridWidth  { get; set; } = 10;
    [Export] public int GridHeight { get; set; } = 10;
    [Export] public float HexSize  { get; set; } = 1f;
    [Export] public bool PointyTop { get; set; } = true;

    public void SetCell(Vector2I axialCoord, string scenePath, float rotationDeg,
                        Vector3 worldPos, bool wasPointyTop, float heightScale = 1f)
    {
        var data = new Dictionary
        {
            ["scene_path"]        = scenePath,
            ["rotation_degrees"]  = rotationDeg,
            ["world_position"]    = worldPos,
            ["placed_pointy_top"] = wasPointyTop,
            ["height_scale"]      = heightScale,
        };
        Cells[axialCoord] = data;
    }

    public void RemoveCell(Vector2I axialCoord) => Cells.Remove(axialCoord);

    public Dictionary GetCell(Vector2I axialCoord) =>
        Cells.TryGetValue(axialCoord, out var val) ? val.AsGodotDictionary() : new Dictionary();

    public bool HasCell(Vector2I axialCoord) => Cells.ContainsKey(axialCoord);

    public void Clear() => Cells.Clear();
}
