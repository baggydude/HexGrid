using Godot;
using Godot.Collections;

/// <summary>
/// Optional per-tile metadata resource. Currently informational — tiles use scene-based
/// instantiation rather than this resource. Kept for future extensibility.
/// </summary>
[Tool]
[GlobalClass]
public partial class HexTileResource : Resource
{
    [Export] public string TileName           { get; set; } = "";
    [Export] public Mesh Mesh                 { get; set; }
    [Export] public Material MaterialOverride { get; set; }
    [Export] public bool IsBlocked            { get; set; } = false;
    [Export] public float MovementCost        { get; set; } = 1f;
    [Export] public float HeightOffset        { get; set; } = 0f;
    [Export] public Color PreviewColor        { get; set; } = Colors.White;
    [Export] public Dictionary CustomProperties { get; set; } = new();
}
