using Godot;
using Godot.Collections;
using System.Collections.Generic;

/// <summary>
/// 3D hex grid node with editor support for painting tile scenes.
/// </summary>
[Tool]
[GlobalClass]
public partial class HexGrid3D : Node3D
{
    private const string DefaultTilePath = "res://addons/hex_grid_editor/tiles/";

    // ── Signals ─────────────────────────────────────────────────────────────
    [Signal] public delegate void CellChangedEventHandler(Vector2I axialCoord);
    [Signal] public delegate void GridClearedEventHandler();

    // ── Grid Settings ────────────────────────────────────────────────────────
    [ExportGroup("Grid Settings")]

    private int _gridWidth = 10;
    [Export]
    public int GridWidth
    {
        get => _gridWidth;
        set
        {
            _gridWidth = Mathf.Max(1, value);
            if (_gridData != null) _gridData.GridWidth = _gridWidth;
            UpdateGuideGrid();
        }
    }

    private int _gridHeight = 10;
    [Export]
    public int GridHeight
    {
        get => _gridHeight;
        set
        {
            _gridHeight = Mathf.Max(1, value);
            if (_gridData != null) _gridData.GridHeight = _gridHeight;
            UpdateGuideGrid();
        }
    }

    private float _hexSize = 1f;
    [Export(PropertyHint.Range, "0.1,100.0,0.001,suffix:m")]
    public float HexSize
    {
        get => _hexSize;
        set
        {
            _hexSize = Mathf.Max(0.1f, value);
            if (_gridData != null) _gridData.HexSize = _hexSize;
            UpdateGuideGrid();
        }
    }

    private bool _pointyTop = true;
    [Export]
    public bool PointyTop
    {
        get => _pointyTop;
        set
        {
            if (value != _pointyTop)
            {
                _pointyTop = value;
                if (_gridData != null) _gridData.PointyTop = _pointyTop;
                ClearAllTiles();
                UpdateGuideGrid();
            }
            else
            {
                _pointyTop = value;
            }
        }
    }

    // ── Visual Settings ──────────────────────────────────────────────────────
    [ExportGroup("Visual Settings")]

    private bool _showGuideGrid = true;
    [Export]
    public bool ShowGuideGrid
    {
        get => _showGuideGrid;
        set { _showGuideGrid = value; UpdateGuideVisibility(); }
    }

    private Color _guideGridColor = new Color(0.5f, 0.5f, 0.5f, 0.5f);
    [Export]
    public Color GuideGridColor
    {
        get => _guideGridColor;
        set { _guideGridColor = value; UpdateGuideMaterial(); }
    }

    private float _guideGridHeight = 0.01f;
    [Export]
    public float GuideGridHeight
    {
        get => _guideGridHeight;
        set { _guideGridHeight = value; UpdateGuideGrid(); }
    }

    // ── Border Settings ──────────────────────────────────────────────────────
    [ExportGroup("Border Settings")]

    private bool _showBorder = false;
    [Export]
    public bool ShowBorder
    {
        get => _showBorder;
        set
        {
            _showBorder = value;
            UpdateBorderVisibility();
            if (_showBorder) UpdateBorderMesh();
        }
    }

    private float _borderHeight = 0.5f;
    [Export(PropertyHint.Range, "0.1,50.0,0.01,suffix:m")]
    public float BorderHeight
    {
        get => _borderHeight;
        set { _borderHeight = Mathf.Max(0.1f, value); UpdateBorderMesh(); }
    }

    private Material _borderMaterial;
    [Export]
    public Material BorderMaterial
    {
        get => _borderMaterial;
        set { _borderMaterial = value; UpdateBorderMaterial(); }
    }

    // ── Data & Tile Folder ───────────────────────────────────────────────────
    [ExportGroup("Data")]

    private HexGridData _gridData;
    [Export]
    public HexGridData GridData
    {
        get => _gridData;
        set
        {
            _gridData = value;
            if (_gridData != null) SyncFromData();
        }
    }

    private string _tileScenesFolder = DefaultTilePath;
    [Export]
    public string TileScenesFolder
    {
        get => _tileScenesFolder;
        set { _tileScenesFolder = value; ScanTileFolder(); }
    }

    // ── Public tile palette (scene_path → PackedScene) ───────────────────────
    public Dictionary TilePalette { get; } = new();

    // ── Internal nodes & state ───────────────────────────────────────────────
    private MeshInstance3D _guideMeshInstance;
    private MeshInstance3D _borderMeshInstance;
    private Node3D _cellContainer;

    // Tracks instantiated tile scenes per axial coord
    private readonly System.Collections.Generic.Dictionary<Vector2I, Node3D> _cellInstances = new();

    // ── Lifecycle ─────────────────────────────────────────────────────────────
    public override void _Ready()
    {
        SetupContainers();
        UpdateGuideGrid();
        ScanTileFolder();
        if (_gridData != null) SyncFromData();
    }

    private void SetupContainers()
    {
        _cellContainer = GetNodeOrNull<Node3D>("CellContainer");
        if (_cellContainer == null)
        {
            _cellContainer = new Node3D { Name = "CellContainer" };
            AddChild(_cellContainer);
        }

        _guideMeshInstance = GetNodeOrNull<MeshInstance3D>("GuideGrid");
        if (_guideMeshInstance == null)
        {
            _guideMeshInstance = new MeshInstance3D { Name = "GuideGrid" };
            AddChild(_guideMeshInstance);
        }

        _borderMeshInstance = GetNodeOrNull<MeshInstance3D>("BorderMesh");
        if (_borderMeshInstance == null)
        {
            _borderMeshInstance = new MeshInstance3D { Name = "BorderMesh" };
            AddChild(_borderMeshInstance);
        }
    }

    // ── Tile folder scanning ──────────────────────────────────────────────────
    private void ScanTileFolder()
    {
        TilePalette.Clear();
        using var dir = DirAccess.Open(_tileScenesFolder);
        if (dir == null) return;

        dir.ListDirBegin();
        string fileName = dir.GetNext();
        while (fileName != "")
        {
            if (!dir.CurrentIsDir() && fileName.EndsWith(".tscn"))
            {
                string path = _tileScenesFolder.PathJoin(fileName);
                var scene = ResourceLoader.Load<PackedScene>(path);
                if (scene != null) TilePalette[path] = scene;
            }
            fileName = dir.GetNext();
        }
    }

    // ── Guide grid ────────────────────────────────────────────────────────────
    private void UpdateGuideVisibility()
    {
        if (_guideMeshInstance != null)
            _guideMeshInstance.Visible = _showGuideGrid;
    }

    private void UpdateGuideMaterial()
    {
        if (_guideMeshInstance?.Mesh == null) return;
        var mat = new StandardMaterial3D
        {
            AlbedoColor = _guideGridColor,
            Transparency = BaseMaterial3D.TransparencyEnum.Alpha,
            ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded,
            CullMode = BaseMaterial3D.CullModeEnum.Disabled,
        };
        _guideMeshInstance.MaterialOverride = mat;
    }

    private void UpdateGuideGrid()
    {
        if (!IsInsideTree()) return;
        SetupContainers();

        var st = new SurfaceTool();
        st.Begin(Mesh.PrimitiveType.Lines);

        foreach (var axial in HexMath.GetGridCoords(_gridWidth, _gridHeight, _pointyTop))
        {
            var center = HexMath.AxialToWorld(axial, _hexSize, _pointyTop);
            center.Y = _guideGridHeight;
            AddHexOutline(st, center);
        }

        _guideMeshInstance.Mesh = st.Commit();
        UpdateGuideMaterial();
        UpdateGuideVisibility();
        if (_showBorder) UpdateBorderMesh();
    }

    private void AddHexOutline(SurfaceTool st, Vector3 center)
    {
        float angleOffset = _pointyTop ? -Mathf.Pi / 2f : 0f;
        var corners = new Vector3[6];
        for (int i = 0; i < 6; i++)
        {
            float angle = angleOffset + i * Mathf.Pi / 3f;
            corners[i] = new Vector3(
                center.X + _hexSize * Mathf.Cos(angle),
                center.Y,
                center.Z + _hexSize * Mathf.Sin(angle));
        }
        for (int i = 0; i < 6; i++)
        {
            st.AddVertex(corners[i]);
            st.AddVertex(corners[(i + 1) % 6]);
        }
    }

    // ── Border mesh ───────────────────────────────────────────────────────────
    private void UpdateBorderVisibility()
    {
        if (_borderMeshInstance != null)
            _borderMeshInstance.Visible = _showBorder;
    }

    private void UpdateBorderMaterial()
    {
        if (_borderMeshInstance != null)
            _borderMeshInstance.MaterialOverride = _borderMaterial;
    }

    private void UpdateBorderMesh()
    {
        if (!IsInsideTree()) return;
        SetupContainers();

        if (!_showBorder)
        {
            _borderMeshInstance.Mesh = null;
            _borderMeshInstance.Visible = false;
            return;
        }

        var borderPositions = GenerateBorderPositions();
        if (borderPositions.Count == 0)
        {
            _borderMeshInstance.Mesh = null;
            return;
        }

        var st = new SurfaceTool();
        st.Begin(Mesh.PrimitiveType.Triangles);
        foreach (var axial in borderPositions)
        {
            var center = HexMath.AxialToWorld(axial, _hexSize, _pointyTop);
            AddHexPrism(st, center, _borderHeight);
        }
        st.GenerateNormals();
        _borderMeshInstance.Mesh = st.Commit();
        UpdateBorderMaterial();
        _borderMeshInstance.Visible = true;
    }

    private List<Vector2I> GenerateBorderPositions()
    {
        var gridSet = new HashSet<Vector2I>();
        for (int row = 0; row < _gridHeight; row++)
            for (int col = 0; col < _gridWidth; col++)
                gridSet.Add(HexMath.OffsetToAxial(new Vector2I(col, row), _pointyTop));

        float minX = float.PositiveInfinity, maxX = float.NegativeInfinity;
        float minZ = float.PositiveInfinity, maxZ = float.NegativeInfinity;
        foreach (var axial in gridSet)
        {
            var pos = HexMath.AxialToWorld(axial, _hexSize, _pointyTop);
            if (pos.X < minX) minX = pos.X;
            if (pos.X > maxX) maxX = pos.X;
            if (pos.Z < minZ) minZ = pos.Z;
            if (pos.Z > maxZ) maxZ = pos.Z;
        }

        float hexWidth  = _pointyTop ? _hexSize * Mathf.Sqrt(3f) : _hexSize * 2f;
        float hexHeight = _pointyTop ? _hexSize * 2f : _hexSize * Mathf.Sqrt(3f);
        minX -= hexWidth  * 1.5f; maxX += hexWidth  * 1.5f;
        minZ -= hexHeight * 1.5f; maxZ += hexHeight * 1.5f;

        var border = new List<Vector2I>();
        for (int row = -2; row < _gridHeight + 3; row++)
        {
            for (int col = -2; col < _gridWidth + 3; col++)
            {
                var axial = HexMath.OffsetToAxial(new Vector2I(col, row), _pointyTop);
                if (gridSet.Contains(axial)) continue;
                var pos = HexMath.AxialToWorld(axial, _hexSize, _pointyTop);
                if (pos.X >= minX && pos.X <= maxX && pos.Z >= minZ && pos.Z <= maxZ)
                    border.Add(axial);
            }
        }
        return border;
    }

    // ── Hex prism geometry (used by border) ──────────────────────────────────
    /// <summary>
    /// Adds a solid hex prism to the SurfaceTool.
    /// Bottom face is at Y=0, top face is at Y=height.
    /// center.Y is ignored — XZ position only.
    /// </summary>
    public void AddHexPrism(SurfaceTool st, Vector3 center, float height)
    {
        float angleOffset = _pointyTop ? -Mathf.Pi / 2f : 0f;
        var topCorners    = new Vector3[6];
        var bottomCorners = new Vector3[6];

        for (int i = 0; i < 6; i++)
        {
            float angle = angleOffset + i * Mathf.Pi / 3f;
            float dx = _hexSize * Mathf.Cos(angle);
            float dz = _hexSize * Mathf.Sin(angle);
            topCorners[i]    = new Vector3(center.X + dx, height, center.Z + dz);
            bottomCorners[i] = new Vector3(center.X + dx, 0f,     center.Z + dz);
        }

        var topCenter    = new Vector3(center.X, height, center.Z);
        var bottomCenter = new Vector3(center.X, 0f,     center.Z);

        // Top face (facing up)
        for (int i = 0; i < 6; i++)
        {
            st.AddVertex(topCenter);
            st.AddVertex(topCorners[i]);
            st.AddVertex(topCorners[(i + 1) % 6]);
        }

        // Bottom face (reversed winding, facing down)
        for (int i = 0; i < 6; i++)
        {
            st.AddVertex(bottomCenter);
            st.AddVertex(bottomCorners[(i + 1) % 6]);
            st.AddVertex(bottomCorners[i]);
        }

        // Side walls (6 quads = 12 triangles)
        for (int i = 0; i < 6; i++)
        {
            int next = (i + 1) % 6;
            st.AddVertex(topCorners[i]);
            st.AddVertex(bottomCorners[i]);
            st.AddVertex(bottomCorners[next]);

            st.AddVertex(topCorners[i]);
            st.AddVertex(bottomCorners[next]);
            st.AddVertex(topCorners[next]);
        }
    }

    // ── Public API ────────────────────────────────────────────────────────────
    /// <summary>Place a tile scene at the given axial coordinate.</summary>
    public void PlaceTile(Vector2I axialCoord, string scenePath,
                          float rotationDegrees = 0f, float heightScale = 1f)
    {
        if (!TilePalette.TryGetValue(scenePath, out var sceneVariant))
        {
            var loaded = ResourceLoader.Load<PackedScene>(scenePath);
            if (loaded == null) return;
            TilePalette[scenePath] = loaded;
            sceneVariant = loaded;
        }
        var scene = sceneVariant.As<PackedScene>();
        if (scene == null) return;

        var offset = HexMath.AxialToOffset(axialCoord, _pointyTop);
        if (!HexMath.IsInBounds(offset, _gridWidth, _gridHeight)) return;

        if (_gridData == null)
        {
            _gridData = new HexGridData
            {
                GridWidth  = _gridWidth,
                GridHeight = _gridHeight,
                HexSize    = _hexSize,
                PointyTop  = _pointyTop,
            };
        }

        var worldPos = HexMath.AxialToWorld(axialCoord, _hexSize, _pointyTop);
        _gridData.SetCell(axialCoord, scenePath, rotationDegrees, worldPos, _pointyTop, heightScale);
        CreateOrUpdateCellInstance(axialCoord, scene, scenePath, rotationDegrees, worldPos, _pointyTop, heightScale);

        EmitSignal(SignalName.CellChanged, axialCoord);
    }

    /// <summary>Remove the tile at the given axial coordinate.</summary>
    public void RemoveTile(Vector2I axialCoord)
    {
        _gridData?.RemoveCell(axialCoord);

        if (_cellInstances.TryGetValue(axialCoord, out var instance))
        {
            instance.QueueFree();
            _cellInstances.Remove(axialCoord);
        }

        EmitSignal(SignalName.CellChanged, axialCoord);
    }

    /// <summary>Returns the cell data dictionary for the given coordinate, or empty.</summary>
    public Dictionary GetTileAt(Vector2I axialCoord) =>
        _gridData != null ? _gridData.GetCell(axialCoord) : new Dictionary();

    /// <summary>Returns true if a tile exists at the given coordinate.</summary>
    public bool HasTileAt(Vector2I axialCoord) =>
        _gridData != null && _gridData.HasCell(axialCoord);

    /// <summary>Remove all placed tiles and clear grid data.</summary>
    public void ClearAllTiles()
    {
        _gridData?.Clear();

        foreach (var cell in _cellInstances.Values) cell.QueueFree();
        _cellInstances.Clear();

        EmitSignal(SignalName.GridCleared);
    }

    /// <summary>Convert a world-space position to axial grid coordinates.</summary>
    public Vector2I WorldToAxial(Vector3 worldPos)
    {
        var localPos = ToLocal(worldPos);
        return HexMath.WorldToAxial(localPos, _hexSize, _pointyTop);
    }

    /// <summary>Convert axial coordinates to a world-space position.</summary>
    public Vector3 AxialToWorld(Vector2I axialCoord)
    {
        var localPos = HexMath.AxialToWorld(axialCoord, _hexSize, _pointyTop);
        return ToGlobal(localPos);
    }

    /// <summary>Snap a world-space position to the nearest hex center.</summary>
    public Vector3 SnapToHex(Vector3 worldPos) => AxialToWorld(WorldToAxial(worldPos));

    /// <summary>Returns true if the axial coordinate is within the grid bounds.</summary>
    public bool IsInBounds(Vector2I axialCoord)
    {
        var offset = HexMath.AxialToOffset(axialCoord, _pointyTop);
        return HexMath.IsInBounds(offset, _gridWidth, _gridHeight);
    }

    // ── Instance management ───────────────────────────────────────────────────
    private void CreateOrUpdateCellInstance(Vector2I axialCoord, PackedScene scene,
        string scenePath, float rotationDegrees, Vector3 worldPos,
        bool placedPointyTop, float heightScale)
    {
        SetupContainers();

        if (_cellInstances.TryGetValue(axialCoord, out var old))
        {
            old.QueueFree();
            _cellInstances.Remove(axialCoord);
        }

        var instance = scene.Instantiate<Node3D>();
        _cellContainer.AddChild(instance);
        if (Engine.IsEditorHint() && GetTree() != null)
            SetOwners(instance, GetTree().EditedSceneRoot);
        _cellInstances[axialCoord] = instance;

        instance.RotationDegrees = new Vector3(0f, rotationDegrees, 0f);
        instance.Position = new Vector3(worldPos.X, heightScale, worldPos.Z);

        instance.SetMeta("axial_coord",       axialCoord);
        instance.SetMeta("scene_path",         scenePath);
        instance.SetMeta("rotation_degrees",   rotationDegrees);
        instance.SetMeta("world_position",     worldPos);
        instance.SetMeta("placed_pointy_top",  placedPointyTop);
        instance.SetMeta("height_scale",       heightScale);
    }

    private void SyncFromData()
    {
        if (_gridData == null) return;

        foreach (var cell in _cellInstances.Values) cell.QueueFree();
        _cellInstances.Clear();

        // Node properties are the source of truth
        _gridData.GridWidth  = _gridWidth;
        _gridData.GridHeight = _gridHeight;
        _gridData.HexSize    = _hexSize;
        _gridData.PointyTop  = _pointyTop;

        foreach (var key in _gridData.Cells.Keys)
        {
            var axialCoord = key.As<Vector2I>();
            var cellData   = _gridData.Cells[key].As<Dictionary>();

            string scenePath       = cellData.TryGetValue("scene_path",        out var sp)  ? sp.AsString()    : "";
            float  rotation        = cellData.TryGetValue("rotation_degrees",  out var rd)  ? rd.AsSingle()    : 0f;
            Vector3 worldPos       = cellData.TryGetValue("world_position",    out var wp)  ? wp.AsVector3()   : Vector3.Zero;
            bool   placedPointy    = cellData.TryGetValue("placed_pointy_top", out var ppt) ? ppt.AsBool()     : _pointyTop;
            float  heightScale     = cellData.TryGetValue("height_scale",      out var hs)  ? hs.AsSingle()    : 1f;

            if (string.IsNullOrEmpty(scenePath)) continue;
            if (worldPos == Vector3.Zero)
                worldPos = HexMath.AxialToWorld(axialCoord, _hexSize, placedPointy);

            // Use pre-loaded palette; fall back to disk only for out-of-folder scenes
            PackedScene scene;
            if (TilePalette.TryGetValue(scenePath, out var cached) && cached.AsGodotObject() is PackedScene ps)
                scene = ps;
            else
            {
                scene = ResourceLoader.Load<PackedScene>(scenePath);
                if (scene != null) TilePalette[scenePath] = scene;
            }
            if (scene != null)
                CreateOrUpdateCellInstance(axialCoord, scene, scenePath, rotation, worldPos, placedPointy, heightScale);
        }
    }

    private static void SetOwners(Node node, Node newOwner)
    {
        node.Owner = newOwner;
        foreach (Node child in node.GetChildren())
            SetOwners(child, newOwner);
    }

    public override string[] _GetConfigurationWarnings()
    {
        if (TilePalette.Count == 0)
            return new[] { "No tile scenes found. Add .tscn files to: " + _tileScenesFolder };
        return System.Array.Empty<string>();
    }
}
