using Godot;
using Godot.Collections;

/// <summary>
/// Bottom-panel toolbar for the hex grid editor.
/// Provides paint/erase tool selection, rotation and height controls,
/// a preview-size slider, a filter box, and a scrollable tile palette
/// where each tile is rendered via a SubViewport preview.
/// </summary>
[Tool]
public partial class HexGridEditorToolbar : VBoxContainer
{
    // ── Signals ───────────────────────────────────────────────────────────────
    [Signal] public delegate void TileSelectedEventHandler(string scenePath);
    [Signal] public delegate void ToolChangedEventHandler(ToolMode toolMode);
    [Signal] public delegate void RotationChangedEventHandler(float degrees);
    [Signal] public delegate void HeightChangedEventHandler(float height);

    // ── Enums / constants ─────────────────────────────────────────────────────
    public enum ToolMode { Paint, Erase }

    public const float HeightMin  = 1f;
    public const float HeightMax  = 2f;
    public const float HeightStep = 0.25f;

    private const int PreviewSizeMin     = 48;
    private const int PreviewSizeMax     = 160;
    private const int PreviewSizeDefault = 80;
    private const int ViewportsPerFrame  = 2;   // SubViewports created per _Process tick

    // ── State ─────────────────────────────────────────────────────────────────
    private Dictionary _tileScenes = new();   // scene_path → PackedScene
    private string _selectedTilePath = "";
    private ToolMode _currentTool = ToolMode.Paint;
    private float _currentRotation = 0f;
    private float _currentHeight = 1f;
    private int _previewSize = PreviewSizeDefault;
    private string _filterText = "";

    // Deferred preview queue: (scenePath, targetTextureRect)
    private readonly System.Collections.Generic.Queue<(string scenePath, TextureRect texRect)>
        _pendingPreviews = new();

    // ── UI references ─────────────────────────────────────────────────────────
    private System.Collections.Generic.Dictionary<ToolMode, Button> _toolButtons = new();
    private Label _rotationLabel;
    private Label _heightLabel;
    private LineEdit _filterEdit;
    private HSlider _sizeSlider;
    private GridContainer _tileGrid;
    private System.Collections.Generic.Dictionary<string, Button> _tileButtons = new();
    private System.Collections.Generic.List<SubViewport> _previewViewports = new();

    // ── Lifecycle ─────────────────────────────────────────────────────────────
    public override void _Ready()
    {
        CustomMinimumSize = new Vector2(0, 200);
        SizeFlagsHorizontal = SizeFlags.ExpandFill;
        SizeFlagsVertical   = SizeFlags.ExpandFill;
        BuildUi();
        Resized += OnResized;
        SetProcess(false);
    }

    public override void _Process(double delta)
    {
        for (int i = 0; i < ViewportsPerFrame && _pendingPreviews.Count > 0; i++)
        {
            var (scenePath, texRect) = _pendingPreviews.Dequeue();
            if (IsInstanceValid(texRect))
                AttachViewportToPreview(scenePath, texRect);
        }

        if (_pendingPreviews.Count == 0)
            SetProcess(false);
    }

    // ── UI construction ───────────────────────────────────────────────────────
    private void BuildUi()
    {
        var controlsBar = new HBoxContainer();
        controlsBar.AddThemeConstantOverride("separation", 16);
        AddChild(controlsBar);

        // Paint / Erase buttons
        var toolBox = new HBoxContainer();
        toolBox.AddThemeConstantOverride("separation", 4);
        controlsBar.AddChild(toolBox);

        var toolGroup = new ButtonGroup();

        var paintBtn = MakeToolButton("Paint", "Paint tiles (Left Click)", ToolMode.Paint, toolGroup, true);
        toolBox.AddChild(paintBtn);
        _toolButtons[ToolMode.Paint] = paintBtn;

        var eraseBtn = MakeToolButton("Erase", "Erase tiles (Left Click)", ToolMode.Erase, toolGroup, false);
        toolBox.AddChild(eraseBtn);
        _toolButtons[ToolMode.Erase] = eraseBtn;

        controlsBar.AddChild(new VSeparator());

        // Rotation controls
        var rotBox = new HBoxContainer();
        rotBox.AddThemeConstantOverride("separation", 4);
        controlsBar.AddChild(rotBox);
        rotBox.AddChild(new Label { Text = "Rot:" });

        _rotationLabel = new Label { Text = "0°" };
        _rotationLabel.CustomMinimumSize = new Vector2(36, 0);
        rotBox.AddChild(_rotationLabel);

        var rotCcw = new Button { Text = "<", TooltipText = "Rotate 60° CCW (Shift+R)" };
        rotCcw.CustomMinimumSize = new Vector2(28, 28);
        rotCcw.Pressed += () => RotateTile(-60f);
        rotBox.AddChild(rotCcw);

        var rotCw = new Button { Text = ">", TooltipText = "Rotate 60° CW (R)" };
        rotCw.CustomMinimumSize = new Vector2(28, 28);
        rotCw.Pressed += () => RotateTile(60f);
        rotBox.AddChild(rotCw);

        controlsBar.AddChild(new VSeparator());

        // Height controls
        var heightBox = new HBoxContainer();
        heightBox.AddThemeConstantOverride("separation", 4);
        controlsBar.AddChild(heightBox);
        heightBox.AddChild(new Label { Text = "Height:" });

        _heightLabel = new Label { Text = "1.00x" };
        _heightLabel.CustomMinimumSize = new Vector2(44, 0);
        heightBox.AddChild(_heightLabel);

        var heightDec = new Button { Text = "-", TooltipText = "Decrease height (-)" };
        heightDec.CustomMinimumSize = new Vector2(28, 28);
        heightDec.Pressed += () => AdjustHeight(-HeightStep);
        heightBox.AddChild(heightDec);

        var heightInc = new Button { Text = "+", TooltipText = "Increase height (+)" };
        heightInc.CustomMinimumSize = new Vector2(28, 28);
        heightInc.Pressed += () => AdjustHeight(HeightStep);
        heightBox.AddChild(heightInc);

        // Spacer
        var spacer = new Control { SizeFlagsHorizontal = SizeFlags.ExpandFill };
        controlsBar.AddChild(spacer);

        // Preview size slider
        var sizeBox = new HBoxContainer();
        sizeBox.AddThemeConstantOverride("separation", 4);
        controlsBar.AddChild(sizeBox);
        sizeBox.AddChild(new Label { Text = "Size:" });

        _sizeSlider = new HSlider
        {
            MinValue = PreviewSizeMin,
            MaxValue = PreviewSizeMax,
            Value    = PreviewSizeDefault,
            Step     = 8,
        };
        _sizeSlider.CustomMinimumSize = new Vector2(100, 0);
        _sizeSlider.SizeFlagsVertical = SizeFlags.ShrinkCenter;
        _sizeSlider.ValueChanged += OnSizeChanged;
        sizeBox.AddChild(_sizeSlider);

        controlsBar.AddChild(new VSeparator());

        // Filter box
        _filterEdit = new LineEdit
        {
            PlaceholderText   = "Filter...",
            ClearButtonEnabled = true,
        };
        _filterEdit.CustomMinimumSize = new Vector2(150, 0);
        _filterEdit.TextChanged += OnFilterChanged;
        controlsBar.AddChild(_filterEdit);

        // Scrollable tile grid
        var scroll = new ScrollContainer
        {
            SizeFlagsHorizontal = SizeFlags.ExpandFill,
            SizeFlagsVertical   = SizeFlags.ExpandFill,
            HorizontalScrollMode = ScrollContainer.ScrollMode.Disabled,
        };
        scroll.CustomMinimumSize = new Vector2(0, 160);
        AddChild(scroll);

        _tileGrid = new GridContainer { Columns = 8 };
        _tileGrid.SizeFlagsHorizontal = SizeFlags.ExpandFill;
        _tileGrid.AddThemeConstantOverride("h_separation", 4);
        _tileGrid.AddThemeConstantOverride("v_separation", 4);
        scroll.AddChild(_tileGrid);
    }

    private Button MakeToolButton(string text, string tooltip, ToolMode mode, ButtonGroup group, bool initiallyPressed)
    {
        var btn = new Button
        {
            Text        = text,
            TooltipText = tooltip,
            ToggleMode  = true,
            ButtonGroup = group,
        };
        btn.CustomMinimumSize = new Vector2(70, 28);
        // Connect signal first, then set initial state via SetPressedNoSignal so
        // the signal does not fire during initialisation.
        btn.Pressed += () => OnToolPressed(mode);
        if (initiallyPressed) btn.SetPressedNoSignal(true);
        return btn;
    }

    // ── Palette ───────────────────────────────────────────────────────────────
    public void SetTilePalette(Dictionary palette)
    {
        _tileScenes = palette;
        RebuildTileGrid();

        if (string.IsNullOrEmpty(_selectedTilePath) && _tileScenes.Count > 0)
        {
            var paths = new System.Collections.Generic.List<string>();
            foreach (var key in _tileScenes.Keys)
                paths.Add(key.AsString());
            paths.Sort();
            SelectTile(paths[0]);
        }
    }

    public void SelectTile(string scenePath)
    {
        if (!_tileScenes.ContainsKey(scenePath)) return;
        _selectedTilePath = scenePath;

        // Use SetPressedNoSignal to avoid triggering Pressed → SelectTile recursion.
        foreach (var (path, btn) in _tileButtons)
            btn.SetPressedNoSignal(path == scenePath);

        // Selecting a tile implicitly switches to Paint mode.
        if (_currentTool != ToolMode.Paint)
            SetTool(ToolMode.Paint);

        EmitSignal(SignalName.TileSelected, scenePath);
    }

    public string GetSelectedTilePath() => _selectedTilePath;

    public PackedScene GetSelectedTileScene() =>
        _tileScenes.TryGetValue(_selectedTilePath, out var v) ? v.As<PackedScene>() : null;

    private void RebuildTileGrid()
    {
        if (!IsInstanceValid(_tileGrid)) return;

        // Cancel any pending deferred work
        _pendingPreviews.Clear();
        SetProcess(false);

        foreach (Node child in _tileGrid.GetChildren())
        {
            _tileGrid.RemoveChild(child);
            child.QueueFree();
        }
        _tileButtons.Clear();

        foreach (var vp in _previewViewports)
            if (IsInstanceValid(vp)) vp.QueueFree();
        _previewViewports.Clear();

        int btnWidth   = _previewSize + 8;
        int separation = _tileGrid.GetThemeConstant("h_separation");
        float available = Size.X > 0 ? Size.X : 800f;
        _tileGrid.Columns = Mathf.Max(1, (int)(available / (btnWidth + separation)));

        var paths = new System.Collections.Generic.List<string>();
        foreach (var key in _tileScenes.Keys) paths.Add(key.AsString());
        paths.Sort();

        foreach (var path in paths)
        {
            string fileName = path.GetFile().GetBaseName();
            if (!string.IsNullOrEmpty(_filterText) &&
                !fileName.ToLower().Contains(_filterText.ToLower())) continue;

            var tileBtn = new Button
            {
                ToggleMode  = true,
                TooltipText = fileName,
            };
            tileBtn.CustomMinimumSize = new Vector2(btnWidth, _previewSize + 24);
            tileBtn.Pressed += () => SelectTile(path);
            _tileGrid.AddChild(tileBtn);
            _tileButtons[path] = tileBtn;

            var vbox = new VBoxContainer { MouseFilter = MouseFilterEnum.Ignore };
            tileBtn.AddChild(vbox);
            vbox.SetAnchorsAndOffsetsPreset(LayoutPreset.FullRect);

            // Placeholder TextureRect — viewport attached later in _Process
            var texRect = new TextureRect
            {
                StretchMode = TextureRect.StretchModeEnum.KeepAspectCentered,
                ExpandMode  = TextureRect.ExpandModeEnum.IgnoreSize,
                MouseFilter = MouseFilterEnum.Ignore,
            };
            texRect.CustomMinimumSize = new Vector2(_previewSize, _previewSize);
            vbox.AddChild(texRect);

            var nameLabel = new Label
            {
                Text = fileName,
                HorizontalAlignment = HorizontalAlignment.Center,
                MouseFilter = MouseFilterEnum.Ignore,
            };
            nameLabel.AddThemeFontSizeOverride("font_size", 10);
            vbox.AddChild(nameLabel);

            _pendingPreviews.Enqueue((path, texRect));
        }

        if (_tileButtons.ContainsKey(_selectedTilePath))
            _tileButtons[_selectedTilePath].SetPressedNoSignal(true);

        if (_pendingPreviews.Count > 0)
            SetProcess(true);
    }

    /// <summary>
    /// Creates a SubViewport for <paramref name="scenePath"/> and assigns its texture
    /// to <paramref name="texRect"/>. Called from _Process to spread the cost over frames.
    /// </summary>
    private void AttachViewportToPreview(string scenePath, TextureRect texRect)
    {
        if (!_tileScenes.TryGetValue(scenePath, out var sceneVariant)) return;
        var packedScene = sceneVariant.As<PackedScene>();
        if (packedScene == null) return;

        var viewport = new SubViewport
        {
            Size = new Vector2I(_previewSize * 2, _previewSize * 2),
            RenderTargetUpdateMode = SubViewport.UpdateMode.Disabled,
            TransparentBg = true,
            OwnWorld3D = true,
            Msaa3D = Viewport.Msaa.Msaa4X,
        };

        // Camera at consistent isometric angle
        var camera = new Camera3D { Fov = 30f };
        var camPos    = new Vector3(3.2f, 3.8f, 3.2f);
        var camTarget = new Vector3(0f, -0.2f, 0f);
        camera.Transform = Transform3D.Identity.LookingAt(camTarget - camPos, Vector3.Up);
        camera.Transform = new Transform3D(camera.Transform.Basis, camPos);
        viewport.AddChild(camera);

        // Environment
        var env = new Godot.Environment
        {
            BackgroundMode        = Godot.Environment.BGMode.Color,
            BackgroundColor       = new Color(0.2f, 0.2f, 0.25f),
            AmbientLightSource    = Godot.Environment.AmbientSource.Color,
            AmbientLightColor     = Colors.White,
            AmbientLightEnergy    = 0.4f,
            TonemapMode           = Godot.Environment.ToneMapper.Filmic,
        };
        var worldEnv = new WorldEnvironment { Environment = env };
        viewport.AddChild(worldEnv);

        // Key light
        var keyLight = new DirectionalLight3D { LightEnergy = 0.8f, ShadowEnabled = false };
        keyLight.RotationDegrees = new Vector3(-50f, -30f, 0f);
        viewport.AddChild(keyLight);

        // Fill light
        var fillLight = new DirectionalLight3D { LightEnergy = 0.3f, ShadowEnabled = false };
        fillLight.RotationDegrees = new Vector3(20f, 150f, 0f);
        viewport.AddChild(fillLight);

        // Tile instance
        var instance = packedScene.Instantiate();
        if (instance is Node3D node3D)
            node3D.Transform = Transform3D.Identity;
        viewport.AddChild(instance);

        AddChild(viewport);
        _previewViewports.Add(viewport);
        viewport.RenderTargetUpdateMode = SubViewport.UpdateMode.Once;

        texRect.Texture = viewport.GetTexture();
    }

    // ── Event handlers ────────────────────────────────────────────────────────
    private void OnResized()
    {
        if (_tileScenes.Count > 0 && IsInstanceValid(_tileGrid))
        {
            int btnWidth   = _previewSize + 8;
            int separation = _tileGrid.GetThemeConstant("h_separation");
            int newColumns = Mathf.Max(1, (int)(Size.X / (btnWidth + separation)));
            if (newColumns != _tileGrid.Columns)
                _tileGrid.Columns = newColumns;
        }
    }

    private void OnFilterChanged(string newText)
    {
        _filterText = newText;
        RebuildTileGrid();
    }

    private void OnSizeChanged(double newSize)
    {
        _previewSize = (int)newSize;
        if (!IsInstanceValid(_tileGrid)) return;

        int btnWidth = _previewSize + 8;
        foreach (var (_, btn) in _tileButtons)
        {
            btn.CustomMinimumSize = new Vector2(btnWidth, _previewSize + 24);
            if (btn.GetChildCount() > 0 && btn.GetChild(0) is VBoxContainer vbox &&
                vbox.GetChildCount() > 0 && vbox.GetChild(0) is TextureRect texRect)
            {
                texRect.CustomMinimumSize = new Vector2(_previewSize, _previewSize);
            }
        }

        int separation = _tileGrid.GetThemeConstant("h_separation");
        float available = Size.X > 0 ? Size.X : 800f;
        _tileGrid.Columns = Mathf.Max(1, (int)(available / (btnWidth + separation)));
    }

    private void OnToolPressed(ToolMode mode) => SetTool(mode);

    // ── Public tool/state API ─────────────────────────────────────────────────
    public void SetTool(ToolMode mode)
    {
        _currentTool = mode;
        // SetPressedNoSignal on the target button; ButtonGroup automatically
        // deselects the other tool button without emitting any signals.
        _toolButtons[mode].SetPressedNoSignal(true);
        EmitSignal(SignalName.ToolChanged, (int)mode);
    }

    public ToolMode GetTool() => _currentTool;

    public void RotateTile(float amount = 60f)
    {
        _currentRotation = Mathf.PosMod(_currentRotation + amount, 360f);
        _rotationLabel.Text = $"{(int)_currentRotation}°";
        EmitSignal(SignalName.RotationChanged, _currentRotation);
    }

    public void SetTileRotation(float degrees)
    {
        _currentRotation = Mathf.PosMod(degrees, 360f);
        _rotationLabel.Text = $"{(int)_currentRotation}°";
    }

    public float GetTileRotation() => _currentRotation;

    public void AdjustHeight(float amount)
    {
        float newHeight = Mathf.Clamp(_currentHeight + amount, HeightMin, HeightMax);
        if (Mathf.IsEqualApprox(newHeight, _currentHeight)) return;
        _currentHeight = newHeight;
        _heightLabel.Text = $"{_currentHeight:F2}x";
        EmitSignal(SignalName.HeightChanged, _currentHeight);
    }

    public void SetHeight(float height)
    {
        _currentHeight = Mathf.Clamp(height, HeightMin, HeightMax);
        _heightLabel.Text = $"{_currentHeight:F2}x";
    }

    public float GetHeight() => _currentHeight;
}
