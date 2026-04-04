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

    // ── Cell Highlights ──────────────────────────────────────────────────────
    [ExportGroup("Cell Highlights")]

    private Godot.Collections.Array<Vector2I> _moveableCells = new();
    [Export]
    public Godot.Collections.Array<Vector2I> MoveableCells
    {
        get => _moveableCells;
        set { _moveableCells = value ?? new(); UpdateCellOverlays(); }
    }

    private Color _moveableGlowColor = new Color(0f, 0.8f, 1f, 0.7f);
    [Export]
    public Color MoveableGlowColor
    {
        get => _moveableGlowColor;
        set { _moveableGlowColor = value; UpdateMoveableOverlayColors(); }
    }

    private float _moveableGlowIntensity = 2.0f;
    [Export(PropertyHint.Range, "0.0,10.0,0.1")]
    public float MoveableGlowIntensity
    {
        get => _moveableGlowIntensity;
        set { _moveableGlowIntensity = value; UpdateMoveableOverlayColors(); }
    }

    private Godot.Collections.Array<Vector2I> _threatenedCells = new();
    [Export]
    public Godot.Collections.Array<Vector2I> ThreatenedCells
    {
        get => _threatenedCells;
        set { _threatenedCells = value ?? new(); UpdateCellOverlays(); }
    }

    private Color _threatenedGlowColor = new Color(1f, 0.15f, 0f, 0.7f);
    [Export]
    public Color ThreatenedGlowColor
    {
        get => _threatenedGlowColor;
        set { _threatenedGlowColor = value; UpdateThreatenedOverlayColors(); }
    }

    private float _threatenedGlowIntensity = 2.0f;
    [Export(PropertyHint.Range, "0.0,10.0,0.1")]
    public float ThreatenedGlowIntensity
    {
        get => _threatenedGlowIntensity;
        set { _threatenedGlowIntensity = value; UpdateThreatenedOverlayColors(); }
    }

    private float _highlightHeight = 0.05f;
    [Export(PropertyHint.Range, "0.0,2.0,0.001,suffix:m")]
    public float HighlightHeight
    {
        get => _highlightHeight;
        set { _highlightHeight = value; UpdateCellOverlays(); }
    }

    private float _pulseSpeed = 1.5f;
    [Export(PropertyHint.Range, "0.0,10.0,0.1")]
    public float PulseSpeed
    {
        get => _pulseSpeed;
        set { _pulseSpeed = value; UpdateAllOverlayShaderParams(); }
    }

    private float _pulseAmount = 0.3f;
    [Export(PropertyHint.Range, "0.0,1.0,0.05")]
    public float PulseAmount
    {
        get => _pulseAmount;
        set { _pulseAmount = value; UpdateAllOverlayShaderParams(); }
    }

    // ── Internal nodes & state ───────────────────────────────────────────────
    private MeshInstance3D _guideMeshInstance;
    private MeshInstance3D _borderMeshInstance;
    private Node3D _cellContainer;
    private Node3D _highlightContainer;

    // Tracks instantiated tile scenes per axial coord
    private readonly System.Collections.Generic.Dictionary<Vector2I, Node3D> _cellInstances = new();

    // Tracks highlight overlay meshes per axial coord
    private readonly System.Collections.Generic.Dictionary<Vector2I, MeshInstance3D> _moveableOverlays = new();
    private readonly System.Collections.Generic.Dictionary<Vector2I, MeshInstance3D> _threatenedOverlays = new();

    // ── Lifecycle ─────────────────────────────────────────────────────────────
    public override void _Ready()
    {
        SetupContainers();
        UpdateGuideGrid();
        ScanTileFolder();
        if (_gridData != null) SyncFromData();
        UpdateCellOverlays();
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

        _highlightContainer = GetNodeOrNull<Node3D>("HighlightContainer");
        if (_highlightContainer == null)
        {
            _highlightContainer = new Node3D { Name = "HighlightContainer" };
            AddChild(_highlightContainer);
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
        if (_borderMeshInstance == null) return;
        if (_borderMaterial is BaseMaterial3D baseMat)
        {
            // Force double-sided on the material itself so the user's live edits
            // (albedo, shadows, alpha, etc.) are always reflected immediately.
            // Duplicating would snapshot the material and break live editing.
            baseMat.CullMode = BaseMaterial3D.CullModeEnum.Disabled;
            _borderMeshInstance.MaterialOverride = baseMat;
        }
        else if (_borderMaterial != null)
        {
            // ShaderMaterial: user controls culling in their shader.
            _borderMeshInstance.MaterialOverride = _borderMaterial;
        }
        else
        {
            _borderMeshInstance.MaterialOverride = new StandardMaterial3D
            {
                ShadingMode = BaseMaterial3D.ShadingModeEnum.Unshaded,
                CullMode    = BaseMaterial3D.CullModeEnum.Disabled,
            };
        }
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

        var st = new SurfaceTool();
        st.Begin(Mesh.PrimitiveType.Triangles);
        AddRectangularFrame(st, _borderHeight);
        _borderMeshInstance.Mesh = st.Commit();
        UpdateBorderMaterial();
        _borderMeshInstance.Visible = true;
    }

    // ── Rectangular border geometry ───────────────────────────────────────────

    /// <summary>
    /// Generates a rectangular frame mesh around the hex grid.
    /// The inner edge aligns exactly with the outermost hex cell extents;
    /// the outer edge is 1 hex-cell-spacing further out on each axis.
    /// The frame is solid from Y=0 up to <paramref name="height"/>.
    /// </summary>
    private void AddRectangularFrame(SurfaceTool st, float height)
    {
        // --- Inner rectangle: outer edge of the grid hex cells ---
        float halfX = _pointyTop ? _hexSize * Mathf.Sqrt(3f) / 2f : _hexSize;
        float halfZ = _pointyTop ? _hexSize                        : _hexSize * Mathf.Sqrt(3f) / 2f;

        float minCX = float.PositiveInfinity, maxCX = float.NegativeInfinity;
        float minCZ = float.PositiveInfinity, maxCZ = float.NegativeInfinity;
        foreach (var axial in HexMath.GetGridCoords(_gridWidth, _gridHeight, _pointyTop))
        {
            var p = HexMath.AxialToWorld(axial, _hexSize, _pointyTop);
            if (p.X < minCX) minCX = p.X;
            if (p.X > maxCX) maxCX = p.X;
            if (p.Z < minCZ) minCZ = p.Z;
            if (p.Z > maxCZ) maxCZ = p.Z;
        }

        float iMinX = minCX - halfX;
        float iMaxX = maxCX + halfX;
        float iMinZ = minCZ - halfZ;
        float iMaxZ = maxCZ + halfZ;

        // --- Outer rectangle: 1 hex-cell-spacing further out ---
        float thickX = _pointyTop ? _hexSize * Mathf.Sqrt(3f) : _hexSize * 1.5f;
        float thickZ = _pointyTop ? _hexSize * 1.5f            : _hexSize * Mathf.Sqrt(3f);

        float oMinX = iMinX - thickX;
        float oMaxX = iMaxX + thickX;
        float oMinZ = iMinZ - thickZ;
        float oMaxZ = iMaxZ + thickZ;

        float h = height;

        // --- Top ring (8 quads, normal = +Y) ---
        // NW corner
        AddTopQuad(st, oMinX, oMinZ, iMinX, iMinZ, h);
        // N strip
        AddTopQuad(st, iMinX, oMinZ, iMaxX, iMinZ, h);
        // NE corner
        AddTopQuad(st, iMaxX, oMinZ, oMaxX, iMinZ, h);
        // W strip
        AddTopQuad(st, oMinX, iMinZ, iMinX, iMaxZ, h);
        // E strip
        AddTopQuad(st, iMaxX, iMinZ, oMaxX, iMaxZ, h);
        // SW corner
        AddTopQuad(st, oMinX, iMaxZ, iMinX, oMaxZ, h);
        // S strip
        AddTopQuad(st, iMinX, iMaxZ, iMaxX, oMaxZ, h);
        // SE corner
        AddTopQuad(st, iMaxX, iMaxZ, oMaxX, oMaxZ, h);

        // --- Outer walls (normals face outward) ---
        AddWallEdge(st, new Vector2(oMaxX, oMinZ), new Vector2(oMinX, oMinZ), h); // N  (-Z)
        AddWallEdge(st, new Vector2(oMinX, oMaxZ), new Vector2(oMaxX, oMaxZ), h); // S  (+Z)
        AddWallEdge(st, new Vector2(oMinX, oMinZ), new Vector2(oMinX, oMaxZ), h); // W  (-X)
        AddWallEdge(st, new Vector2(oMaxX, oMaxZ), new Vector2(oMaxX, oMinZ), h); // E  (+X)

        // --- Inner walls (normals face inward toward grid) ---
        AddWallEdge(st, new Vector2(iMinX, iMinZ), new Vector2(iMaxX, iMinZ), h); // N  (+Z)
        AddWallEdge(st, new Vector2(iMaxX, iMaxZ), new Vector2(iMinX, iMaxZ), h); // S  (-Z)
        AddWallEdge(st, new Vector2(iMinX, iMaxZ), new Vector2(iMinX, iMinZ), h); // W  (+X)
        AddWallEdge(st, new Vector2(iMaxX, iMinZ), new Vector2(iMaxX, iMaxZ), h); // E  (-X)

        // --- Gap fills: partial-hex shapes that square off the hex silhouette ---
        AddPartialHexFills(st, h, iMinX, iMaxX, iMinZ, iMaxZ, halfX, halfZ);
    }

    /// <summary>
    /// Fills the gaps left by the staggered hex silhouette with proper partial-hex geometry:
    /// parallelogram prisms on the sides (for offset rows/cols) and triangle prisms on the
    /// top and bottom edges (to fill valleys between hex tips).
    /// </summary>
    private void AddPartialHexFills(SurfaceTool st, float h,
                                     float iMinX, float iMaxX,
                                     float iMinZ, float iMaxZ,
                                     float halfX, float halfZ)
    {
        if (_pointyTop)
            AddPointyTopPartialHexFills(st, h, iMinX, iMaxX, iMinZ, iMaxZ, halfX, halfZ);
        else
            AddFlatTopPartialHexFills(st, h, iMinX, iMaxX, iMinZ, iMaxZ, halfX, halfZ);
    }

    // ── Pointy-top (odd-r offset) fills ──────────────────────────────────────

    private void AddPointyTopPartialHexFills(SurfaceTool st, float h,
                                              float iMinX, float iMaxX,
                                              float iMinZ, float iMaxZ,
                                              float halfX, float halfZ)
    {
        float qtrZ    = halfZ * 0.5f;
        float colStep = halfX * 2f;
        float rowStep = _hexSize * 1.5f;

        // ── Side fills: parallelogram prisms for each row ─────────────────────
        for (int row = 0; row < _gridHeight; row++)
        {
            float zC = rowStep * row;
            if ((row & 1) == 1)
            {
                // Odd row → left parallelogram (ghost-hex right-half at x=iMinX)
                var A = new Vector2(iMinX,         zC - halfZ);
                var B = new Vector2(iMinX + halfX, zC - qtrZ);
                var C = new Vector2(iMinX + halfX, zC + qtrZ);
                var D = new Vector2(iMinX,         zC + halfZ);
                // Top face A→B→C→D is CCW from +Y
                AddTopFaceQuad(st, V(A,h), V(B,h), V(C,h), V(D,h));
                // Walls following the CCW top-face order; skip D→A (inner W wall)
                AddWallEdge(st, A, B, h);
                AddWallEdge(st, B, C, h);
                AddWallEdge(st, C, D, h);
            }
            else
            {
                // Even row → right parallelogram (ghost-hex left-half at x=iMaxX)
                var A = new Vector2(iMaxX,         zC - halfZ);
                var B = new Vector2(iMaxX - halfX, zC - qtrZ);
                var C = new Vector2(iMaxX - halfX, zC + qtrZ);
                var D = new Vector2(iMaxX,         zC + halfZ);
                // Top face D→C→B→A is CCW from +Y (mirrored winding)
                AddTopFaceQuad(st, V(D,h), V(C,h), V(B,h), V(A,h));
                // Walls in reversed order; skip A→D (inner E wall)
                AddWallEdge(st, D, C, h);
                AddWallEdge(st, C, B, h);
                AddWallEdge(st, B, A, h);
            }
        }

        // ── Top edge fills: triangles between hex tips (row 0, always even) ──
        // Left corner triangle
        {
            var P0 = new Vector2(iMinX,         iMinZ);
            var P1 = new Vector2(iMinX + halfX, iMinZ);
            var P2 = new Vector2(iMinX,         iMinZ + qtrZ);
            AddTopTri(st, V(P0,h), V(P1,h), V(P2,h));
            // Skip P0→P1 (inner N wall), skip P2→P0 (inner W wall)
            AddWallEdge(st, P1, P2, h);
        }
        // Valley triangles between adjacent top tips
        for (int c = 0; c < _gridWidth - 1; c++)
        {
            float cx   = c * colStep;
            var   P0   = new Vector2(cx,            iMinZ);
            var   P1   = new Vector2(cx + halfX,    iMinZ + qtrZ);
            var   P2   = new Vector2(cx + colStep,  iMinZ);
            // Emit P0,P2,P1 for CCW from +Y (P1/P2 order reversed vs default)
            AddTopTri(st, V(P0,h), V(P2,h), V(P1,h));
            // Skip P0→P2 (inner N wall)
            AddWallEdge(st, P2, P1, h);
            AddWallEdge(st, P1, P0, h);
        }
        // Right corner triangle
        {
            float lastX = (_gridWidth - 1) * colStep;
            var P0 = new Vector2(lastX,        iMinZ);
            var P1 = new Vector2(iMaxX,        iMinZ);
            var P2 = new Vector2(iMaxX - halfX, iMinZ + qtrZ);
            AddTopTri(st, V(P0,h), V(P1,h), V(P2,h));
            // Skip P0→P1 (inner N wall)
            AddWallEdge(st, P1, P2, h);
            AddWallEdge(st, P2, P0, h);
        }

        // ── Bottom edge fills ─────────────────────────────────────────────────
        int  lastRow    = _gridHeight - 1;
        bool lastRowOdd = (lastRow & 1) == 1;

        if (!lastRowOdd)
        {
            // Even last row: hex tips at x = c * colStep
            // Left corner
            {
                var P0 = new Vector2(iMinX,         iMaxZ);
                var P1 = new Vector2(iMinX + halfX, iMaxZ);
                var P2 = new Vector2(iMinX,         iMaxZ - qtrZ);
                // Emit P0,P2,P1 for CCW from +Y
                AddTopTri(st, V(P0,h), V(P2,h), V(P1,h));
                // Skip P0→P2 (inner W wall), skip P1→P0 (inner S wall)
                AddWallEdge(st, P2, P1, h);
            }
            // Valley triangles
            for (int c = 0; c < _gridWidth - 1; c++)
            {
                float cx = c * colStep;
                var P0   = new Vector2(cx,           iMaxZ);
                var P1   = new Vector2(cx + halfX,   iMaxZ - qtrZ);
                var P2   = new Vector2(cx + colStep, iMaxZ);
                AddTopTri(st, V(P0,h), V(P1,h), V(P2,h));
                // Skip P2→P0 (inner S wall)
                AddWallEdge(st, P0, P1, h);
                AddWallEdge(st, P1, P2, h);
            }
            // Right corner
            {
                float lastX = (_gridWidth - 1) * colStep;
                var P0 = new Vector2(lastX,         iMaxZ);
                var P1 = new Vector2(iMaxX,         iMaxZ);
                var P2 = new Vector2(iMaxX - halfX, iMaxZ - qtrZ);
                // Emit P0,P2,P1 for CCW from +Y
                AddTopTri(st, V(P0,h), V(P2,h), V(P1,h));
                // Skip P1→P0 (inner S wall)
                AddWallEdge(st, P0, P2, h);
                AddWallEdge(st, P2, P1, h);
            }
        }
        else
        {
            // Odd last row: hex tips at x = c * colStep + halfX
            // Left corner (fills from iMinX to the first tip at x=halfX)
            {
                var P0 = new Vector2(iMinX,          iMaxZ);
                var P1 = new Vector2(iMinX + 2*halfX, iMaxZ);   // = halfX, first tip
                var P2 = new Vector2(iMinX + halfX,   iMaxZ - qtrZ); // col-0 bottom-left corner
                // Emit P0,P2,P1 for CCW from +Y
                AddTopTri(st, V(P0,h), V(P2,h), V(P1,h));
                // Skip P1→P0 (inner S wall)
                AddWallEdge(st, P0, P2, h);
                AddWallEdge(st, P2, P1, h);
            }
            // Valley triangles
            for (int c = 0; c < _gridWidth - 1; c++)
            {
                float cx = c * colStep + halfX;       // odd-row tip x for col c
                var P0   = new Vector2(cx,            iMaxZ);
                var P1   = new Vector2(cx + halfX,    iMaxZ - qtrZ); // shared corner
                var P2   = new Vector2(cx + colStep,  iMaxZ);         // next tip
                AddTopTri(st, V(P0,h), V(P1,h), V(P2,h));
                // Skip P2→P0 (inner S wall)
                AddWallEdge(st, P0, P1, h);
                AddWallEdge(st, P1, P2, h);
            }
            // Right corner (last tip IS at iMaxX-halfX; small triangle to inner-E+S corner)
            {
                float lastTipX = (_gridWidth - 1) * colStep + halfX; // = iMaxX - halfX
                var P0 = new Vector2(lastTipX, iMaxZ);
                var P1 = new Vector2(iMaxX,    iMaxZ - qtrZ); // bottom-right hex corner
                var P2 = new Vector2(iMaxX,    iMaxZ);         // inner E+S corner
                AddTopTri(st, V(P0,h), V(P1,h), V(P2,h));
                // Skip P1→P2 (inner E wall), skip P2→P0 (inner S wall)
                AddWallEdge(st, P0, P1, h);
            }
        }
    }

    // ── Flat-top (odd-q offset) fills ────────────────────────────────────────

    private void AddFlatTopPartialHexFills(SurfaceTool st, float h,
                                            float iMinX, float iMaxX,
                                            float iMinZ, float iMaxZ,
                                            float halfX, float halfZ)
    {
        float qtrX    = halfX * 0.5f;
        float colStep = _hexSize * 1.5f;
        float rowStep = halfZ * 2f;  // = hexSize * √3

        // ── Top/bottom fills: parallelogram prisms for odd columns ─────────────
        for (int col = 0; col < _gridWidth; col++)
        {
            if ((col & 1) == 0) continue; // only odd columns have a gap
            float xC = col * colStep;

            // Top parallelogram (between z=iMinZ and the top of odd-col row-0 hex)
            {
                var A = new Vector2(xC - halfX, iMinZ);
                var B = new Vector2(xC - qtrX,  iMinZ + halfZ);
                var C = new Vector2(xC + qtrX,  iMinZ + halfZ);
                var D = new Vector2(xC + halfX, iMinZ);
                // Top face D→C→B→A is CCW from +Y; skip A→D (inner N wall)
                AddTopFaceQuad(st, V(D,h), V(C,h), V(B,h), V(A,h));
                AddWallEdge(st, D, C, h);
                // Skip C→B (interior face, z=iMinZ+halfZ)
                AddWallEdge(st, B, A, h);
            }
            // Bottom parallelogram (between the bottom of odd-col last-row hex and z=iMaxZ)
            {
                var A = new Vector2(xC - halfX, iMaxZ);
                var B = new Vector2(xC - qtrX,  iMaxZ - halfZ);
                var C = new Vector2(xC + qtrX,  iMaxZ - halfZ);
                var D = new Vector2(xC + halfX, iMaxZ);
                // Top face A→B→C→D is CCW from +Y; skip D→A (inner S wall)
                AddTopFaceQuad(st, V(A,h), V(B,h), V(C,h), V(D,h));
                AddWallEdge(st, A, B, h);
                // Skip B→C (interior face, z=iMaxZ-halfZ)
                AddWallEdge(st, C, D, h);
            }
        }

        // ── Left edge fills: triangle scallop along col-0 ─────────────────────
        // Top-left corner
        {
            var P0 = new Vector2(iMinX,          iMinZ);
            var P1 = new Vector2(iMinX + qtrX,   iMinZ);
            var P2 = new Vector2(iMinX,          iMinZ + halfZ);
            AddTopTri(st, V(P0,h), V(P1,h), V(P2,h));
            // Skip P0→P1 (inner N wall), skip P2→P0 (inner W wall)
            AddWallEdge(st, P1, P2, h);
        }
        // Valley triangles
        for (int r = 0; r < _gridHeight - 1; r++)
        {
            float rz = r * rowStep;
            var P0   = new Vector2(iMinX,         rz);
            var P1   = new Vector2(iMinX + qtrX,  rz + halfZ);
            var P2   = new Vector2(iMinX,         rz + rowStep);
            AddTopTri(st, V(P0,h), V(P1,h), V(P2,h));
            // Skip P2→P0 (inner W wall)
            AddWallEdge(st, P0, P1, h);
            AddWallEdge(st, P1, P2, h);
        }
        // Bottom-left corner
        {
            float lastRZ = (_gridHeight - 1) * rowStep;
            var P0 = new Vector2(iMinX,          lastRZ);
            var P1 = new Vector2(iMinX,          iMaxZ);
            var P2 = new Vector2(iMinX + qtrX,   iMaxZ - halfZ);
            // Emit P0,P2,P1 for CCW from +Y
            AddTopTri(st, V(P0,h), V(P2,h), V(P1,h));
            // Skip P1→P0 (inner W wall)
            AddWallEdge(st, P0, P2, h);
            AddWallEdge(st, P2, P1, h);
        }

        // ── Right edge fills ──────────────────────────────────────────────────
        int  lastCol    = _gridWidth - 1;
        bool lastColOdd = (lastCol & 1) == 1;

        if (!lastColOdd)
        {
            // Even last col: right tips at (iMaxX, r*rowStep)
            // Top-right corner
            {
                var P0 = new Vector2(iMaxX,          iMinZ);
                var P1 = new Vector2(iMaxX - qtrX,   iMinZ);
                var P2 = new Vector2(iMaxX,          iMinZ + halfZ);
                // Emit P0,P2,P1 for CCW from +Y
                AddTopTri(st, V(P0,h), V(P2,h), V(P1,h));
                // Skip P0→P2 (inner E wall), skip P1→P0 (inner N wall)
                AddWallEdge(st, P2, P1, h);
            }
            // Valley triangles
            for (int r = 0; r < _gridHeight - 1; r++)
            {
                float rz = r * rowStep;
                var P0   = new Vector2(iMaxX,         rz);
                var P1   = new Vector2(iMaxX - qtrX,  rz + halfZ);
                var P2   = new Vector2(iMaxX,         rz + rowStep);
                // Emit P0,P2,P1 for CCW from +Y (mirrored vs left-edge valleys)
                AddTopTri(st, V(P0,h), V(P2,h), V(P1,h));
                // Skip P0→P2 (inner E wall)
                AddWallEdge(st, P2, P1, h);
                AddWallEdge(st, P1, P0, h);
            }
            // Bottom-right corner
            {
                float lastRZ = (_gridHeight - 1) * rowStep;
                var P0 = new Vector2(iMaxX,          lastRZ);
                var P1 = new Vector2(iMaxX,          iMaxZ);
                var P2 = new Vector2(iMaxX - qtrX,   iMaxZ - halfZ);
                AddTopTri(st, V(P0,h), V(P1,h), V(P2,h));
                // Skip P0→P1 (inner E wall)
                AddWallEdge(st, P1, P2, h);
                AddWallEdge(st, P2, P0, h);
            }
        }
        else
        {
            // Odd last col: right tips at (iMaxX, r*rowStep + halfZ)
            // Top-right corner
            {
                float firstTipZ = halfZ; // = iMinZ + halfZ
                var P0 = new Vector2(iMaxX,          iMinZ);
                var P1 = new Vector2(iMaxX,          firstTipZ);
                var P2 = new Vector2(iMaxX - qtrX,   iMinZ);
                AddTopTri(st, V(P0,h), V(P1,h), V(P2,h));
                // Skip P0→P1 (inner E wall), skip P2→P0 (inner N wall)
                AddWallEdge(st, P1, P2, h);
            }
            // Valley triangles
            for (int r = 0; r < _gridHeight - 1; r++)
            {
                float rz = r * rowStep + halfZ; // odd-col tip z
                var P0   = new Vector2(iMaxX,         rz);
                var P1   = new Vector2(iMaxX - qtrX,  rz + halfZ);
                var P2   = new Vector2(iMaxX,         rz + rowStep);
                // Emit P0,P2,P1 for CCW from +Y
                AddTopTri(st, V(P0,h), V(P2,h), V(P1,h));
                // Skip P0→P2 (inner E wall)
                AddWallEdge(st, P2, P1, h);
                AddWallEdge(st, P1, P0, h);
            }
            // Bottom-right corner
            {
                float lastTipZ = (_gridHeight - 1) * rowStep + halfZ; // = iMaxZ - halfZ
                var P0 = new Vector2(iMaxX,          lastTipZ);
                var P1 = new Vector2(iMaxX,          iMaxZ);
                var P2 = new Vector2(iMaxX - qtrX,   iMaxZ);
                AddTopTri(st, V(P0,h), V(P1,h), V(P2,h));
                // Skip P0→P1 (inner E wall), skip P1→P2 (inner S wall)
                AddWallEdge(st, P2, P0, h);
            }
        }
    }

    /// <summary>Horizontal quad at Y=h over the rectangle (x1,z1)→(x2,z2), normal pointing up.</summary>
    private static void AddTopQuad(SurfaceTool st, float x1, float z1, float x2, float z2, float h)
    {
        var n = Vector3.Up;
        st.SetNormal(n); st.AddVertex(new Vector3(x1, h, z1));
        st.SetNormal(n); st.AddVertex(new Vector3(x2, h, z1));
        st.SetNormal(n); st.AddVertex(new Vector3(x2, h, z2));
        st.SetNormal(n); st.AddVertex(new Vector3(x1, h, z1));
        st.SetNormal(n); st.AddVertex(new Vector3(x2, h, z2));
        st.SetNormal(n); st.AddVertex(new Vector3(x1, h, z2));
    }

    /// <summary>Emits a top-face quad (a,b,c,d) with normal = +Y.</summary>
    private static void AddTopFaceQuad(SurfaceTool st, Vector3 a, Vector3 b, Vector3 c, Vector3 d)
    {
        var n = Vector3.Up;
        st.SetNormal(n); st.AddVertex(a);
        st.SetNormal(n); st.AddVertex(b);
        st.SetNormal(n); st.AddVertex(c);
        st.SetNormal(n); st.AddVertex(a);
        st.SetNormal(n); st.AddVertex(c);
        st.SetNormal(n); st.AddVertex(d);
    }

    /// <summary>Emits a top-face triangle (a, b, c) with normal = +Y.</summary>
    private static void AddTopTri(SurfaceTool st, Vector3 a, Vector3 b, Vector3 c)
    {
        var n = Vector3.Up;
        st.SetNormal(n); st.AddVertex(a);
        st.SetNormal(n); st.AddVertex(b);
        st.SetNormal(n); st.AddVertex(c);
    }

    /// <summary>
    /// Emits a vertical wall quad for the edge a→b extruded from y=h down to y=0.
    /// The normal faces LEFT of the directed edge a→b in XZ.
    /// </summary>
    private static void AddWallEdge(SurfaceTool st, Vector2 a, Vector2 b, float h)
    {
        var d = (b - a).Normalized();
        var n = new Vector3(-d.Y, 0f, d.X); // left perpendicular of a→b in XZ
        var topA = new Vector3(a.X, h,  a.Y);
        var topB = new Vector3(b.X, h,  b.Y);
        var botA = new Vector3(a.X, 0f, a.Y);
        var botB = new Vector3(b.X, 0f, b.Y);
        st.SetNormal(n); st.AddVertex(topA);
        st.SetNormal(n); st.AddVertex(topB);
        st.SetNormal(n); st.AddVertex(botB);
        st.SetNormal(n); st.AddVertex(topA);
        st.SetNormal(n); st.AddVertex(botB);
        st.SetNormal(n); st.AddVertex(botA);
    }

    /// <summary>Lifts a 2-D XZ point to a 3-D position at the given Y height.</summary>
    private static Vector3 V(Vector2 p, float y) => new Vector3(p.X, y, p.Y);

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

    // ── Cell Highlight API ────────────────────────────────────────────────────

    /// <summary>Add a cell to the moveable highlights. Does nothing if already present.</summary>
    public void AddMoveableCell(Vector2I axial)
    {
        if (_moveableCells.Contains(axial)) return;
        _moveableCells.Add(axial);
        CreateOverlay(axial, _moveableGlowColor, _moveableGlowIntensity, _moveableOverlays);
    }

    /// <summary>Remove a cell from the moveable highlights.</summary>
    public void RemoveMoveableCell(Vector2I axial)
    {
        _moveableCells.Remove(axial);
        RemoveOverlay(axial, _moveableOverlays);
    }

    /// <summary>Replace all moveable highlight cells at once.</summary>
    public void SetMoveableCells(Godot.Collections.Array<Vector2I> cells)
    {
        _moveableCells = cells ?? new();
        UpdateCellOverlays();
    }

    /// <summary>Clear all moveable highlight cells.</summary>
    public void ClearMoveableCells()
    {
        _moveableCells.Clear();
        foreach (var overlay in _moveableOverlays.Values) overlay.QueueFree();
        _moveableOverlays.Clear();
    }

    /// <summary>Add a cell to the threatened highlights. Does nothing if already present.</summary>
    public void AddThreatenedCell(Vector2I axial)
    {
        if (_threatenedCells.Contains(axial)) return;
        _threatenedCells.Add(axial);
        CreateOverlay(axial, _threatenedGlowColor, _threatenedGlowIntensity, _threatenedOverlays);
    }

    /// <summary>Remove a cell from the threatened highlights.</summary>
    public void RemoveThreatenedCell(Vector2I axial)
    {
        _threatenedCells.Remove(axial);
        RemoveOverlay(axial, _threatenedOverlays);
    }

    /// <summary>Replace all threatened highlight cells at once.</summary>
    public void SetThreatenedCells(Godot.Collections.Array<Vector2I> cells)
    {
        _threatenedCells = cells ?? new();
        UpdateCellOverlays();
    }

    /// <summary>Clear all threatened highlight cells.</summary>
    public void ClearThreatenedCells()
    {
        _threatenedCells.Clear();
        foreach (var overlay in _threatenedOverlays.Values) overlay.QueueFree();
        _threatenedOverlays.Clear();
    }

    // ── Overlay internals ─────────────────────────────────────────────────────
    private void UpdateCellOverlays()
    {
        if (!IsInsideTree()) return;
        SetupContainers();

        foreach (var overlay in _moveableOverlays.Values) overlay.QueueFree();
        _moveableOverlays.Clear();
        foreach (var overlay in _threatenedOverlays.Values) overlay.QueueFree();
        _threatenedOverlays.Clear();

        foreach (var axial in _moveableCells)
            CreateOverlay(axial, _moveableGlowColor, _moveableGlowIntensity, _moveableOverlays);

        foreach (var axial in _threatenedCells)
            CreateOverlay(axial, _threatenedGlowColor, _threatenedGlowIntensity, _threatenedOverlays);
    }

    private void CreateOverlay(Vector2I axial, Color color, float intensity,
        System.Collections.Generic.Dictionary<Vector2I, MeshInstance3D> registry)
    {
        if (_highlightContainer == null) return;

        var shader = ResourceLoader.Load<Shader>(
            "res://addons/hex_grid_editor/shaders/cell_highlight.gdshader");
        if (shader == null) return;

        var mat = new ShaderMaterial();
        mat.Shader = shader;
        mat.SetShaderParameter("glow_color",      color);
        mat.SetShaderParameter("glow_intensity",  intensity);
        mat.SetShaderParameter("pulse_speed",     _pulseSpeed);
        mat.SetShaderParameter("pulse_amount",    _pulseAmount);

        var center = HexMath.AxialToWorld(axial, _hexSize, _pointyTop);
        center.Y = _highlightHeight;

        var st = new SurfaceTool();
        st.Begin(Mesh.PrimitiveType.Triangles);

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
        var n = Vector3.Up;
        for (int i = 0; i < 6; i++)
        {
            st.SetNormal(n); st.AddVertex(center);
            st.SetNormal(n); st.AddVertex(corners[i]);
            st.SetNormal(n); st.AddVertex(corners[(i + 1) % 6]);
        }

        var meshInstance = new MeshInstance3D();
        meshInstance.Mesh = st.Commit();
        meshInstance.MaterialOverride = mat;
        _highlightContainer.AddChild(meshInstance);

        registry[axial] = meshInstance;
    }

    private static void RemoveOverlay(Vector2I axial,
        System.Collections.Generic.Dictionary<Vector2I, MeshInstance3D> registry)
    {
        if (registry.TryGetValue(axial, out var overlay))
        {
            overlay.QueueFree();
            registry.Remove(axial);
        }
    }

    private void UpdateMoveableOverlayColors()
    {
        foreach (var overlay in _moveableOverlays.Values)
        {
            if (overlay.MaterialOverride is ShaderMaterial mat)
            {
                mat.SetShaderParameter("glow_color",     _moveableGlowColor);
                mat.SetShaderParameter("glow_intensity", _moveableGlowIntensity);
            }
        }
    }

    private void UpdateThreatenedOverlayColors()
    {
        foreach (var overlay in _threatenedOverlays.Values)
        {
            if (overlay.MaterialOverride is ShaderMaterial mat)
            {
                mat.SetShaderParameter("glow_color",     _threatenedGlowColor);
                mat.SetShaderParameter("glow_intensity", _threatenedGlowIntensity);
            }
        }
    }

    private void UpdateAllOverlayShaderParams()
    {
        foreach (var overlay in _moveableOverlays.Values)
        {
            if (overlay.MaterialOverride is ShaderMaterial mat)
            {
                mat.SetShaderParameter("pulse_speed",  _pulseSpeed);
                mat.SetShaderParameter("pulse_amount", _pulseAmount);
            }
        }
        foreach (var overlay in _threatenedOverlays.Values)
        {
            if (overlay.MaterialOverride is ShaderMaterial mat)
            {
                mat.SetShaderParameter("pulse_speed",  _pulseSpeed);
                mat.SetShaderParameter("pulse_amount", _pulseAmount);
            }
        }
    }

    public override string[] _GetConfigurationWarnings()
    {
        if (TilePalette.Count == 0)
            return new[] { "No tile scenes found. Add .tscn files to: " + _tileScenesFolder };
        return System.Array.Empty<string>();
    }
}
