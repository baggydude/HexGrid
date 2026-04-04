using Godot;

/// <summary>
/// Editor plugin for the hex grid — handles the bottom panel toolbar,
/// mouse/keyboard input in the 3D viewport, ghost tile preview, and undo/redo.
/// </summary>
[Tool]
public partial class HexGridEditorPlugin : EditorPlugin
{
    private HexGrid3D _editedGrid;
    private HexGridEditorToolbar _toolbar;
    private Button _bottomPanelButton;
    private bool _isPainting;
    private Vector2I _lastPaintedCoord = new Vector2I(-99999, -99999);

    // Ghost preview — the tile scene instance following the mouse
    private Node3D _previewInstance;

    // ── Plugin lifecycle ───────────────────────────────────────────────────────
    public override void _EnterTree()
    {
        _toolbar = new HexGridEditorToolbar();
        _toolbar.TileSelected  += OnTileSelected;
        _toolbar.ToolChanged   += OnToolChanged;
        _bottomPanelButton = AddControlToBottomPanel(_toolbar, "Hex Editor");
        _bottomPanelButton.Visible = false;
    }

    public override void _ExitTree()
    {
        CleanupPreview();
        if (_toolbar != null && IsInstanceValid(_toolbar))
        {
            RemoveControlFromBottomPanel(_toolbar);
            _toolbar.QueueFree();
            _toolbar = null;
        }
        _bottomPanelButton = null;
    }

    // ── Node selection ─────────────────────────────────────────────────────────
    public override bool _Handles(GodotObject @object) => @object is HexGrid3D;

    public override void _Edit(GodotObject @object)
    {
        if (@object is HexGrid3D grid)
        {
            _editedGrid = grid;
            if (!_editedGrid.IsConnected(Node.SignalName.TreeExiting,
                    Callable.From(OnGridDeleted)))
                _editedGrid.TreeExiting += OnGridDeleted;

            if (_toolbar != null && IsInstanceValid(_toolbar))
                _toolbar.SetTilePalette(_editedGrid.TilePalette);

            Callable.From(RebuildGhostPreview).CallDeferred();
        }
        else
        {
            _editedGrid = null;
            CleanupPreview();
        }
    }

    private void OnGridDeleted()
    {
        _editedGrid = null;
        CleanupPreview();
        if (_bottomPanelButton != null) _bottomPanelButton.Visible = false;
        HideBottomPanel();
    }

    public override void _MakeVisible(bool visible)
    {
        if (visible && _editedGrid != null)
        {
            if (_bottomPanelButton != null) _bottomPanelButton.Visible = true;
            MakeBottomPanelItemVisible(_toolbar);
        }
    }

    // ── Ghost preview ─────────────────────────────────────────────────────────
    private void SetupPreview()
    {
        CleanupPreview();
        var scene = _toolbar?.GetSelectedTileScene();
        if (scene == null || _editedGrid == null) return;

        _previewInstance = scene.Instantiate<Node3D>();
        _editedGrid.AddChild(_previewInstance);
        _previewInstance.Visible = false;
    }

    private void CleanupPreview()
    {
        if (_previewInstance != null && IsInstanceValid(_previewInstance))
        {
            _previewInstance.QueueFree();
            _previewInstance = null;
        }
    }

    private void RebuildGhostPreview()
    {
        bool wasVisible = _previewInstance != null && IsInstanceValid(_previewInstance) && _previewInstance.Visible;
        Vector3 oldPos = _previewInstance != null && IsInstanceValid(_previewInstance)
            ? _previewInstance.Position : Vector3.Zero;
        float oldRot = _previewInstance != null && IsInstanceValid(_previewInstance)
            ? _previewInstance.RotationDegrees.Y : 0f;

        SetupPreview();

        if (_previewInstance != null && wasVisible)
        {
            _previewInstance.Position = oldPos;
            _previewInstance.RotationDegrees = new Vector3(0f, oldRot, 0f);
            _previewInstance.Visible = true;
        }
    }

    // ── Viewport input ────────────────────────────────────────────────────────
    public override int _Forward3DGuiInput(Camera3D viewportCamera, InputEvent @event)
    {
        if (_editedGrid == null || _toolbar == null || !IsInstanceValid(_toolbar))
            return 0;
        if (_bottomPanelButton == null || !_bottomPanelButton.Visible)
            return 0;

        if (@event is InputEventKey keyEvent && keyEvent.Pressed)
        {
            if (keyEvent.Keycode == Key.R)
            {
                _toolbar.RotateTile(keyEvent.ShiftPressed ? -60f : 60f);
                UpdatePreviewRotation();
                return 1;
            }
            if (keyEvent.Keycode is Key.Equal or Key.KpAdd)
            {
                _toolbar.AdjustHeight(HexGridEditorToolbar.HeightStep);
                UpdatePreviewScale();
                return 1;
            }
            if (keyEvent.Keycode is Key.Minus or Key.KpSubtract)
            {
                _toolbar.AdjustHeight(-HexGridEditorToolbar.HeightStep);
                UpdatePreviewScale();
                return 1;
            }
        }

        if (@event is InputEventMouseButton mouseBtn && mouseBtn.ButtonIndex == MouseButton.Left)
        {
            if (mouseBtn.Pressed)
            {
                _isPainting = true;
                _lastPaintedCoord = new Vector2I(-99999, -99999);

                if (mouseBtn.AltPressed)
                {
                    if (HandlePick(viewportCamera, mouseBtn.Position))
                        return 1;
                }

                if (HandlePaint(viewportCamera, mouseBtn.Position))
                    return 1;
            }
            else
            {
                _isPainting = false;
                _lastPaintedCoord = new Vector2I(-99999, -99999);
            }
        }

        if (@event is InputEventMouseMotion motionEvent)
        {
            UpdatePreview(viewportCamera, motionEvent.Position);
            if (_isPainting && HandlePaint(viewportCamera, motionEvent.Position))
                return 1;
        }

        return 0;
    }

    // ── Raycast ────────────────────────────────────────────────────────────────
    private Godot.Collections.Dictionary RaycastToGrid(Camera3D camera, Vector2 screenPos)
    {
        var rayOrigin = camera.ProjectRayOrigin(screenPos);
        var rayDir    = camera.ProjectRayNormal(screenPos);

        var plane = new Plane(Vector3.Up, 0f);
        plane = _editedGrid.GlobalTransform * plane;

        var intersection = plane.IntersectsRay(rayOrigin, rayDir);
        if (intersection == null) return new Godot.Collections.Dictionary();

        var localPos   = _editedGrid.ToLocal(intersection.Value);
        var axialCoord = HexMath.WorldToAxial(localPos, _editedGrid.HexSize, _editedGrid.PointyTop);

        if (!_editedGrid.IsInBounds(axialCoord)) return new Godot.Collections.Dictionary();

        return new Godot.Collections.Dictionary { ["axial_coord"] = axialCoord };
    }

    // ── Paint / Erase / Pick ──────────────────────────────────────────────────
    private bool HandlePaint(Camera3D camera, Vector2 screenPos)
    {
        var hit = RaycastToGrid(camera, screenPos);
        if (hit.Count == 0) return false;

        var axialCoord = hit["axial_coord"].As<Vector2I>();
        if (axialCoord == _lastPaintedCoord) return true;
        _lastPaintedCoord = axialCoord;

        var undoRedo = GetUndoRedo();

        switch (_toolbar.GetTool())
        {
            case HexGridEditorToolbar.ToolMode.Paint:
            {
                string scenePath = _toolbar.GetSelectedTilePath();
                if (string.IsNullOrEmpty(scenePath)) return false;

                float rotation    = _toolbar.GetTileRotation();
                float heightScale = _toolbar.GetHeight();
                var   oldData     = _editedGrid.GetTileAt(axialCoord);

                undoRedo.CreateAction("Paint Hex Tile");
                undoRedo.AddDoMethod(_editedGrid,
                    HexGrid3D.MethodName.PlaceTile,
                    axialCoord, scenePath, rotation, heightScale);

                if (oldData.Count == 0)
                {
                    undoRedo.AddUndoMethod(_editedGrid,
                        HexGrid3D.MethodName.RemoveTile, axialCoord);
                }
                else
                {
                    undoRedo.AddUndoMethod(_editedGrid,
                        HexGrid3D.MethodName.PlaceTile,
                        axialCoord,
                        oldData.TryGetValue("scene_path",       out var osp) ? osp.AsString()  : "",
                        oldData.TryGetValue("rotation_degrees", out var ord) ? ord.AsSingle()  : 0f,
                        oldData.TryGetValue("height_scale",     out var ohs) ? ohs.AsSingle()  : 1f);
                }
                undoRedo.CommitAction();
                return true;
            }

            case HexGridEditorToolbar.ToolMode.Erase:
            {
                if (!_editedGrid.HasTileAt(axialCoord)) return false;
                var oldData = _editedGrid.GetTileAt(axialCoord);

                undoRedo.CreateAction("Erase Hex Tile");
                undoRedo.AddDoMethod(_editedGrid,
                    HexGrid3D.MethodName.RemoveTile, axialCoord);
                undoRedo.AddUndoMethod(_editedGrid,
                    HexGrid3D.MethodName.PlaceTile,
                    axialCoord,
                    oldData.TryGetValue("scene_path",       out var osp) ? osp.AsString()  : "",
                    oldData.TryGetValue("rotation_degrees", out var ord) ? ord.AsSingle()  : 0f,
                    oldData.TryGetValue("height_scale",     out var ohs) ? ohs.AsSingle()  : 1f);
                undoRedo.CommitAction();
                return true;
            }
        }
        return false;
    }

    private bool HandlePick(Camera3D camera, Vector2 screenPos)
    {
        var hit = RaycastToGrid(camera, screenPos);
        if (hit.Count == 0) return false;

        var axialCoord = hit["axial_coord"].As<Vector2I>();
        if (!_editedGrid.HasTileAt(axialCoord)) return false;

        var cellData = _editedGrid.GetTileAt(axialCoord);
        string scenePath = cellData.TryGetValue("scene_path", out var sp) ? sp.AsString() : "";
        if (string.IsNullOrEmpty(scenePath)) return false;

        float rotation    = cellData.TryGetValue("rotation_degrees", out var rd) ? rd.AsSingle() : 0f;
        float heightScale = cellData.TryGetValue("height_scale",     out var hs) ? hs.AsSingle() : 1f;

        _toolbar.SelectTile(scenePath);
        _toolbar.SetTileRotation(rotation);
        _toolbar.SetHeight(heightScale);
        _toolbar.SetTool(HexGridEditorToolbar.ToolMode.Paint);
        RebuildGhostPreview();
        return true;
    }

    // ── Preview updates ────────────────────────────────────────────────────────
    private void UpdatePreview(Camera3D camera, Vector2 screenPos)
    {
        if (_previewInstance == null || _editedGrid == null) return;

        var hit = RaycastToGrid(camera, screenPos);
        if (hit.Count == 0 ||
            string.IsNullOrEmpty(_toolbar.GetSelectedTilePath()) ||
            _toolbar.GetTool() != HexGridEditorToolbar.ToolMode.Paint)
        {
            _previewInstance.Visible = false;
            return;
        }

        _previewInstance.Visible = true;
        var axialCoord = hit["axial_coord"].As<Vector2I>();
        var worldPos   = HexMath.AxialToWorld(axialCoord, _editedGrid.HexSize, _editedGrid.PointyTop);
        float height   = _toolbar.GetHeight();

        _previewInstance.Position = new Vector3(worldPos.X, height, worldPos.Z);
        UpdatePreviewRotation();
    }

    private void UpdatePreviewRotation()
    {
        if (_previewInstance == null) return;
        _previewInstance.RotationDegrees = new Vector3(0f, _toolbar.GetTileRotation(), 0f);
    }

    private void UpdatePreviewScale()
    {
        if (_previewInstance == null || _editedGrid == null) return;
        float height = _toolbar.GetHeight();

        // Reposition tile scene to new height
        _previewInstance.Position = new Vector3(
            _previewInstance.Position.X, height, _previewInstance.Position.Z);

    }

    // ── Toolbar signal callbacks ───────────────────────────────────────────────
    private void OnTileSelected(string _scenePath)
    {
        // Selecting a tile from the palette switches back to Paint mode.
        _toolbar.SetTool(HexGridEditorToolbar.ToolMode.Paint);
        RebuildGhostPreview();
    }

    private void OnToolChanged(HexGridEditorToolbar.ToolMode toolMode)
    {
        if (_previewInstance != null)
            _previewInstance.Visible = toolMode == HexGridEditorToolbar.ToolMode.Paint;
    }
}
