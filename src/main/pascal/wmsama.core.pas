unit wmsama.core;

// wmsama.core
// ===========
// Core Compositing Window Manager implementation for Samarinda DE.
// Inherits from TXCBWindowManager and integrates TXCBCompositor for
// manual subwindow redirection, XDamage tracking, soft Gaussian shadows,
// frosted glass backdrop blur, rounded bottom corners, window edge snapping,
// titlebar double-click maximize, and Alt+Tab window switcher HUD.

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, Contnrs, Math,
  Floria.XCB,
  Floria.XCB.WM,
  Floria.XCB.WM.Compositor,
  Floria.XCB.Damage,
  Floria.Image.Core,
  Floria.Canvas.Agg,
  WMSama.FT;

type
  TWMSnapTarget = (
    snapNone,
    snapMaximize,
    snapLeftHalf,
    snapRightHalf
  );

  TWMSamaCompositingWM = class(TXCBWindowManager)
  private
    FCompositor         : TXCBCompositor;
    FCompositorEnabled  : Boolean;
    FNeedsComposite     : Boolean;
    FBlurEnabled        : Boolean;
    FBlurRadius         : Integer;
    FShadowEnabled      : Boolean;
    FShadowRadius       : Integer;
    FShadowOffsetY      : Integer;
    FShadowOpacity      : Single;
    FActiveShadowRadius : Integer;
    FActiveShadowOffsetY: Integer;
    FActiveShadowOpacity: Single;
    FTitlebarHeight     : Integer;
    FCornerRadius       : Integer;
    FBottomCornerRadius : Integer;

    // Window Button Theming and Hover States
    FWindowButtonStyle  : Integer;
    FThemeDarkMode      : Boolean;
    FHoveredWindow      : xcb_window_t;
    FHoveredButton      : Integer;
    FPressedButton      : Integer;

    // Double-click detection
    FLastClickTime      : Cardinal;
    FLastClickWindow    : xcb_window_t;

    // Window Edge Snapping
    FActiveSnap         : TWMSnapTarget;
    FSnapPreviewRect    : TXCBRect;
    FPreSnapRect        : TXCBRect;

    // Alt+Tab Switcher
    FAltTabActive       : Boolean;
    FAltTabIndex        : Integer;

    procedure SetCompositorEnabled(const AValue: Boolean);
    procedure SetBlurEnabled(const AValue: Boolean);
    procedure SetBlurRadius(const AValue: Integer);
    procedure SetShadowEnabled(const AValue: Boolean);
    procedure SetShadowRadius(const AValue: Integer);
    procedure SetShadowOffsetY(const AValue: Integer);
    procedure SetShadowOpacity(const AValue: Single);
    procedure SetActiveShadowRadius(const AValue: Integer);
    procedure SetActiveShadowOffsetY(const AValue: Integer);
    procedure SetActiveShadowOpacity(const AValue: Single);
    procedure SetTitlebarHeight(const AValue: Integer);
    procedure SetCornerRadius(const AValue: Integer);
    procedure SetBottomCornerRadius(const AValue: Integer);
    procedure SetWindowButtonStyle(const AValue: Integer);
    procedure SetThemeDarkMode(const AValue: Boolean);

    procedure DoOnCompositorAfterRender(ASender: TObject; ACanvas: TFloriaCanvasAgg; const ASceneRect: TXCBRect);
  protected
    procedure DoOnClientMapped(const AClient: TXCBWMClient); override;
    procedure DoOnClientUnmapped(const AClient: TXCBWMClient); override;
    procedure DoOnClientActivated(const AClient: TXCBWMClient); override;
    procedure DoOnClientConfigure(const AClient: TXCBWMClient); override;
    procedure DoOnFramePaint(const AClient: TXCBWMClient; const ARect: TXCBRect); override;
  public
    constructor Create(AConn: Pxcb_connection_t = nil; const AScreenNum: Integer = 0);
    destructor Destroy(); override;

    function ClaimOwnership(): Boolean; override;
    procedure GrabGlobalKeys();

    function StartCompositor(): Boolean;
    procedure StopCompositor();

    procedure RequestComposite();
    procedure RenderComposite();

    procedure PaintAllFrames();
    procedure PaintClientFrame(const AClient: TXCBWMClient);

    // Interactive Dragging and Snapping
    procedure BeginDrag(const AClient: TXCBWMClient; const AMode: TXCBDragMode; const ARootX, ARootY: Integer); override;
    procedure UpdateDrag(const ARootX, ARootY: Integer); override;
    procedure EndDrag(); override;

    // Alt+Tab HUD controls
    procedure TriggerAltTabForward();
    procedure TriggerAltTabDismiss();

    function ProcessEvent(const AEvent: Pxcb_generic_event_t): Boolean; override;
    procedure Run(); override;

    property Compositor         : TXCBCompositor read FCompositor;
    property CompositorEnabled  : Boolean        read FCompositorEnabled   write SetCompositorEnabled;
    property NeedsComposite     : Boolean        read FNeedsComposite;
    property BlurEnabled        : Boolean        read FBlurEnabled         write SetBlurEnabled;
    property BlurRadius         : Integer        read FBlurRadius          write SetBlurRadius;
    property ShadowEnabled      : Boolean        read FShadowEnabled       write SetShadowEnabled;
    property ShadowRadius       : Integer        read FShadowRadius        write SetShadowRadius;
    property ShadowOffsetY      : Integer        read FShadowOffsetY       write SetShadowOffsetY;
    property ShadowOpacity      : Single         read FShadowOpacity       write SetShadowOpacity;
    property ActiveShadowRadius : Integer        read FActiveShadowRadius  write SetActiveShadowRadius;
    property ActiveShadowOffsetY: Integer        read FActiveShadowOffsetY write SetActiveShadowOffsetY;
    property ActiveShadowOpacity: Single         read FActiveShadowOpacity write SetActiveShadowOpacity;
    property TitlebarHeight     : Integer        read FTitlebarHeight      write SetTitlebarHeight;
    property CornerRadius       : Integer        read FCornerRadius        write SetCornerRadius;
    property BottomCornerRadius : Integer        read FBottomCornerRadius  write SetBottomCornerRadius;
    property WindowButtonStyle  : Integer        read FWindowButtonStyle   write SetWindowButtonStyle;
    property ThemeDarkMode      : Boolean        read FThemeDarkMode       write SetThemeDarkMode;
    property ActiveSnap         : TWMSnapTarget  read FActiveSnap;
    property SnapPreviewRect    : TXCBRect       read FSnapPreviewRect;
    property AltTabActive       : Boolean        read FAltTabActive;
    property AltTabIndex        : Integer        read FAltTabIndex;
  end;

implementation

constructor TWMSamaCompositingWM.Create(AConn: Pxcb_connection_t; const AScreenNum: Integer);
var
  w, h: Integer;
  rootWin: xcb_window_t;
  metrics: TXCBFrameMetrics;
begin
  inherited Create(AConn, AScreenNum);

  WMName := 'wmsama';
  FTitlebarHeight := 28;
  metrics := TXCBFrameMetrics.Create(FTitlebarHeight, 0);
  FrameMetrics := metrics;

  FCornerRadius := 12;
  FBottomCornerRadius := 12;

  FWindowButtonStyle := FT_WINDOW_BUTTON_CIRCLE;
  FThemeDarkMode := True;
  FHoveredWindow := 0;
  FHoveredButton := -1;
  FPressedButton := -1;

  FCompositorEnabled := True;
  FNeedsComposite := False;
  FBlurEnabled := False;
  FBlurRadius := 15;

  FShadowEnabled := True;
  FShadowRadius := 14;
  FShadowOffsetY := 4;
  FShadowOpacity := 0.35;

  FActiveShadowRadius := 20;
  FActiveShadowOffsetY := 6;
  FActiveShadowOpacity := 0.48;

  FLastClickTime := 0;
  FLastClickWindow := 0;

  FActiveSnap := snapNone;
  FSnapPreviewRect := TXCBRect.Create(0, 0, 0, 0);
  FPreSnapRect := TXCBRect.Create(0, 0, 0, 0);

  FAltTabActive := False;
  FAltTabIndex := 0;

  w := 1920;
  h := 1080;
  rootWin := 0;

  if (Connection <> nil) and (Screen <> nil) then
  begin
    w := Screen^.width_in_pixels;
    h := Screen^.height_in_pixels;
    rootWin := Screen^.root;
  end;

  FCompositor := TXCBCompositor.Create(AConn, rootWin, w, h);
  // Default modern dark slate background (#1E1E2E)
  FCompositor.SetBackgroundColor(30, 30, 46, 255);
  FCompositor.OnAfterRender := @DoOnCompositorAfterRender;
end;

destructor TWMSamaCompositingWM.Destroy();
begin
  StopCompositor();

  if FCompositor <> nil then
  begin
    FCompositor.Free();
    FCompositor := nil;
  end;

  inherited Destroy();
end;

function TWMSamaCompositingWM.ClaimOwnership(): Boolean;
begin
  Result := inherited ClaimOwnership();
  if Result then
    GrabGlobalKeys();
end;

procedure TWMSamaCompositingWM.GrabGlobalKeys();
const
  TAB_KEYCODE = 23;
  MOD_ALT = 8;
  MOD_NUMLOCK = 16;
  MOD_CAPSLOCK = 2;
var
  mods: array[0..3] of Word;
  i: Integer;
begin
  if (Connection = nil) or (Screen = nil) then Exit;
  mods[0] := MOD_ALT;
  mods[1] := MOD_ALT or MOD_NUMLOCK;
  mods[2] := MOD_ALT or MOD_CAPSLOCK;
  mods[3] := MOD_ALT or MOD_NUMLOCK or MOD_CAPSLOCK;

  for i := 0 to 3 do
  begin
    xcb_grab_key(Connection, 1, Screen^.root, mods[i], TAB_KEYCODE,
                 XCB_GRAB_MODE_ASYNC, XCB_GRAB_MODE_ASYNC);
  end;
  xcb_flush(Connection);
end;

function TWMSamaCompositingWM.StartCompositor(): Boolean;
begin
  Result := False;
  if not FCompositorEnabled then
    FCompositorEnabled := True;

  if (Connection = nil) or (FCompositor = nil) then
  begin
    Result := True;
    Exit;
  end;

  Result := FCompositor.EnableCompositing();
  if Result then
    RequestComposite();
end;

procedure TWMSamaCompositingWM.StopCompositor();
begin
  if (FCompositor <> nil) and FCompositor.IsActive then
    FCompositor.DisableCompositing();
  FCompositorEnabled := False;
  FNeedsComposite := False;
end;

procedure TWMSamaCompositingWM.RequestComposite();
begin
  FNeedsComposite := True;
end;

procedure TWMSamaCompositingWM.RenderComposite();
begin
  if not FCompositorEnabled or not FNeedsComposite or (FCompositor = nil) then Exit;

  FCompositor.CompositeScene();
  FCompositor.PresentToScreen();
  FNeedsComposite := False;
end;

procedure TWMSamaCompositingWM.SetCompositorEnabled(const AValue: Boolean);
begin
  if FCompositorEnabled = AValue then Exit;
  FCompositorEnabled := AValue;
  if FCompositorEnabled then
    StartCompositor()
  else
    StopCompositor();
end;

procedure TWMSamaCompositingWM.SetBlurEnabled(const AValue: Boolean);
var
  i: Integer;
  compWin: TXCBCompositedWindow;
begin
  if FBlurEnabled = AValue then Exit;
  FBlurEnabled := AValue;

  if FCompositor <> nil then
  begin
    for i := 0 to FCompositor.Windows.Count - 1 do
    begin
      compWin := TXCBCompositedWindow(FCompositor.Windows[i]);
      compWin.HasBackdropBlur := FBlurEnabled;
      compWin.BlurRadius := FBlurRadius;
    end;
    RequestComposite();
  end;
end;

procedure TWMSamaCompositingWM.SetBlurRadius(const AValue: Integer);
var
  i: Integer;
  compWin: TXCBCompositedWindow;
begin
  FBlurRadius := Max(1, AValue);
  if FCompositor <> nil then
  begin
    for i := 0 to FCompositor.Windows.Count - 1 do
    begin
      compWin := TXCBCompositedWindow(FCompositor.Windows[i]);
      compWin.BlurRadius := FBlurRadius;
    end;
    if FBlurEnabled then
      RequestComposite();
  end;
end;

procedure TWMSamaCompositingWM.SetShadowEnabled(const AValue: Boolean);
begin
  FShadowEnabled := AValue;
  RequestComposite();
end;

procedure TWMSamaCompositingWM.SetShadowRadius(const AValue: Integer);
begin
  FShadowRadius := Max(0, AValue);
  RequestComposite();
end;

procedure TWMSamaCompositingWM.SetShadowOffsetY(const AValue: Integer);
begin
  FShadowOffsetY := AValue;
  RequestComposite();
end;

procedure TWMSamaCompositingWM.SetShadowOpacity(const AValue: Single);
begin
  FShadowOpacity := AValue;
  RequestComposite();
end;

procedure TWMSamaCompositingWM.SetActiveShadowRadius(const AValue: Integer);
begin
  FActiveShadowRadius := Max(0, AValue);
  RequestComposite();
end;

procedure TWMSamaCompositingWM.SetActiveShadowOffsetY(const AValue: Integer);
begin
  FActiveShadowOffsetY := AValue;
  RequestComposite();
end;

procedure TWMSamaCompositingWM.SetActiveShadowOpacity(const AValue: Single);
begin
  FActiveShadowOpacity := AValue;
  RequestComposite();
end;

procedure TWMSamaCompositingWM.SetTitlebarHeight(const AValue: Integer);
var
  metrics: TXCBFrameMetrics;
begin
  if FTitlebarHeight = AValue then Exit;
  FTitlebarHeight := Max(16, AValue);
  metrics := TXCBFrameMetrics.Create(FTitlebarHeight, FrameMetrics.BorderWidth);
  FrameMetrics := metrics;
  PaintAllFrames();
end;

procedure TWMSamaCompositingWM.SetCornerRadius(const AValue: Integer);
var
  i: Integer;
  compWin: TXCBCompositedWindow;
begin
  FCornerRadius := Max(0, AValue);
  if FCompositor <> nil then
  begin
    for i := 0 to FCompositor.Windows.Count - 1 do
    begin
      compWin := TXCBCompositedWindow(FCompositor.Windows[i]);
      compWin.CornerRadius := FCornerRadius;
    end;
    RequestComposite();
  end;
end;

procedure TWMSamaCompositingWM.SetBottomCornerRadius(const AValue: Integer);
var
  i: Integer;
  compWin: TXCBCompositedWindow;
begin
  FBottomCornerRadius := Max(0, AValue);
  if FCompositor <> nil then
  begin
    for i := 0 to FCompositor.Windows.Count - 1 do
    begin
      compWin := TXCBCompositedWindow(FCompositor.Windows[i]);
      compWin.BottomCornerRadius := FBottomCornerRadius;
    end;
    RequestComposite();
  end;
end;

procedure TWMSamaCompositingWM.SetWindowButtonStyle(const AValue: Integer);
begin
  if FWindowButtonStyle = AValue then Exit;
  FWindowButtonStyle := AValue;
  PaintAllFrames();
  RequestComposite();
end;

procedure TWMSamaCompositingWM.SetThemeDarkMode(const AValue: Boolean);
begin
  if FThemeDarkMode = AValue then Exit;
  FThemeDarkMode := AValue;
  PaintAllFrames();
  RequestComposite();
end;

procedure TWMSamaCompositingWM.DoOnClientMapped(const AClient: TXCBWMClient);
var
  targetWin, frameWin: xcb_window_t;
  compWin: TXCBCompositedWindow;
begin
  inherited DoOnClientMapped(AClient);

  if (AClient = nil) or (FCompositor = nil) then Exit;

  if AClient.IsReparented and (AClient.FrameWindow <> 0) then
  begin
    targetWin := AClient.FrameWindow;
    frameWin := AClient.ClientWindow;
  end
  else
  begin
    targetWin := AClient.ClientWindow;
    frameWin := 0;
  end;

  compWin := FCompositor.RegisterWindow(targetWin, AClient.CurrentRect, frameWin);
  if compWin <> nil then
  begin
    if AClient = ActiveClient then
      compWin.ShadowConfig := TXCBWindowShadowConfig.Create(FShadowEnabled, FActiveShadowRadius, FActiveShadowOffsetY, FActiveShadowOpacity)
    else
      compWin.ShadowConfig := TXCBWindowShadowConfig.Create(FShadowEnabled, FShadowRadius, FShadowOffsetY, FShadowOpacity);

    compWin.HasBackdropBlur := FBlurEnabled;
    compWin.BlurRadius := FBlurRadius;

    // Apply 4-corner rounded radii (both top and bottom)
    if (wsFullscreen in AClient.State) or (wsMaximizedHorz in AClient.State) then
    begin
      compWin.CornerRadius := 0;
      compWin.BottomCornerRadius := 0;
    end
    else
    begin
      compWin.CornerRadius := FCornerRadius;
      compWin.BottomCornerRadius := FBottomCornerRadius;
    end;
  end;

  PaintClientFrame(AClient);
  RequestComposite();
end;

procedure TWMSamaCompositingWM.DoOnClientUnmapped(const AClient: TXCBWMClient);
begin
  inherited DoOnClientUnmapped(AClient);

  if (AClient = nil) or (FCompositor = nil) then Exit;

  if AClient.FrameWindow <> 0 then
    FCompositor.UnregisterWindow(AClient.FrameWindow);
  FCompositor.UnregisterWindow(AClient.ClientWindow);

  RequestComposite();
end;

procedure TWMSamaCompositingWM.DoOnClientActivated(const AClient: TXCBWMClient);
var
  i: Integer;
  cli: TXCBWMClient;
  compWin: TXCBCompositedWindow;
  targetWin: xcb_window_t;
begin
  inherited DoOnClientActivated(AClient);

  if FCompositor = nil then Exit;

  // Update shadow elevations on active vs inactive clients
  for i := 0 to Clients.Count - 1 do
  begin
    cli := TXCBWMClient(Clients[i]);
    if cli.IsReparented and (cli.FrameWindow <> 0) then
      targetWin := cli.FrameWindow
    else
      targetWin := cli.ClientWindow;

    compWin := FCompositor.FindWindow(targetWin);
    if compWin <> nil then
    begin
      if cli = AClient then
      begin
        compWin.ShadowConfig := TXCBWindowShadowConfig.Create(FShadowEnabled, FActiveShadowRadius, FActiveShadowOffsetY, FActiveShadowOpacity);
        // Move active window to top of stacking order in compositor
        FCompositor.Windows.Extract(compWin);
        FCompositor.Windows.Add(compWin);
      end
      else
        compWin.ShadowConfig := TXCBWindowShadowConfig.Create(FShadowEnabled, FShadowRadius, FShadowOffsetY, FShadowOpacity);

      if (wsFullscreen in cli.State) or (wsMaximizedHorz in cli.State) then
      begin
        compWin.CornerRadius := 0;
        compWin.BottomCornerRadius := 0;
      end
      else
      begin
        compWin.CornerRadius := FCornerRadius;
        compWin.BottomCornerRadius := FBottomCornerRadius;
      end;
    end;
  end;

  PaintAllFrames();
  RequestComposite();
end;

procedure TWMSamaCompositingWM.DoOnClientConfigure(const AClient: TXCBWMClient);
var
  targetWin: xcb_window_t;
  compWin: TXCBCompositedWindow;
begin
  inherited DoOnClientConfigure(AClient);

  if (AClient = nil) or (FCompositor = nil) then Exit;

  if AClient.IsReparented and (AClient.FrameWindow <> 0) then
    targetWin := AClient.FrameWindow
  else
    targetWin := AClient.ClientWindow;

  compWin := FCompositor.FindWindow(targetWin);
  if compWin <> nil then
  begin
    compWin.UpdateGeometry(AClient.CurrentRect.X, AClient.CurrentRect.Y,
                           AClient.CurrentRect.Width, AClient.CurrentRect.Height);

    if (wsFullscreen in AClient.State) or (wsMaximizedHorz in AClient.State) then
    begin
      compWin.CornerRadius := 0;
      compWin.BottomCornerRadius := 0;
    end
    else
    begin
      compWin.CornerRadius := FCornerRadius;
      compWin.BottomCornerRadius := FBottomCornerRadius;
    end;
  end;

  PaintClientFrame(AClient);
  RequestComposite();
end;

procedure TWMSamaCompositingWM.DoOnFramePaint(const AClient: TXCBWMClient; const ARect: TXCBRect);
begin
  inherited DoOnFramePaint(AClient, ARect);
  PaintClientFrame(AClient);
end;

procedure TWMSamaCompositingWM.PaintClientFrame(const AClient: TXCBWMClient);
var
  w, h, th, bw: Integer;
  isActive, isHoveredWin: Boolean;
  frameImg: TFloriaImage;
  canvas: TFloriaCanvasAgg;
  winTitle: AnsiString;
  dataLen: Cardinal;
  gc: xcb_gcontext_t;
  mask: Cardinal;
  values: array[0..0] of Cardinal;
  compWin: TXCBCompositedWindow;
  s0, s1, s2, maxKind: Integer;
  btnSize, btnY: Double;
begin
  if (AClient = nil) or not AClient.IsReparented or (AClient.FrameWindow = 0) then Exit;

  w := AClient.CurrentRect.Width;
  h := AClient.CurrentRect.Height;
  th := FTitlebarHeight;
  bw := FrameMetrics.BorderWidth;
  if (w <= 0) or (h <= 0) or (th <= 0) then Exit;

  isActive := (AClient = ActiveClient);

  frameImg := TFloriaImage.Create(w, th);
  try
    canvas := TFloriaCanvasAgg.Create(frameImg);
    try
      // 1. Titlebar background
      if isActive then
      begin
        // Deep Charcoal Sapphire (#21232B)
        canvas.DrawRect(0, 0, w, th, 33 / 255, 35 / 255, 43 / 255, 1.0);
        // Top highlight line (#3E4452)
        canvas.DrawLine(0, 0, w, 0, 1.0, 62 / 255, 68 / 255, 82 / 255, 1.0);
        // Bottom divider line (#181920)
        canvas.DrawLine(0, th - 1, w, th - 1, 1.0, 24 / 255, 25 / 255, 32 / 255, 1.0);
      end
      else
      begin
        // Muted Charcoal (#181920)
        canvas.DrawRect(0, 0, w, th, 24 / 255, 25 / 255, 32 / 255, 1.0);
        // Bottom divider line (#121318)
        canvas.DrawLine(0, th - 1, w, th - 1, 1.0, 18 / 255, 19 / 255, 24 / 255, 1.0);
      end;

      // 2. Vector Window Buttons via Floria Toolkit (libft.so)
      isHoveredWin := (FHoveredWindow <> 0) and (FHoveredWindow = AClient.FrameWindow);
      if isHoveredWin and (FPressedButton = 0) then s0 := FT_BUTTON_STATE_PRESSED
      else if isHoveredWin and (FHoveredButton = 0) then s0 := FT_BUTTON_STATE_HOVERED
      else s0 := FT_BUTTON_STATE_NORMAL;

      if isHoveredWin and (FPressedButton = 1) then s1 := FT_BUTTON_STATE_PRESSED
      else if isHoveredWin and (FHoveredButton = 1) then s1 := FT_BUTTON_STATE_HOVERED
      else s1 := FT_BUTTON_STATE_NORMAL;

      if isHoveredWin and (FPressedButton = 2) then s2 := FT_BUTTON_STATE_PRESSED
      else if isHoveredWin and (FHoveredButton = 2) then s2 := FT_BUTTON_STATE_HOVERED
      else s2 := FT_BUTTON_STATE_NORMAL;

      if wsMaximizedHorz in AClient.State then
        maxKind := FT_WINDOW_BUTTON_RESTORE
      else
        maxKind := FT_WINDOW_BUTTON_MAXIMIZE;

      btnSize := 13.0;
      btnY := (th - btnSize) * 0.5;

      FtDrawWindowButton(canvas, 8.0, btnY, btnSize, btnSize,
                         FT_WINDOW_BUTTON_CLOSE, FWindowButtonStyle, s0,
                         FThemeDarkMode);
      FtDrawWindowButton(canvas, 27.0, btnY, btnSize, btnSize,
                         FT_WINDOW_BUTTON_MINIMIZE, FWindowButtonStyle, s1,
                         FThemeDarkMode);
      FtDrawWindowButton(canvas, 46.0, btnY, btnSize, btnSize,
                         maxKind, FWindowButtonStyle, s2,
                         FThemeDarkMode);

      // 3. Window title text
      winTitle := AClient.Title;
      if winTitle = '' then
        winTitle := AClient.WindowClass;
      if winTitle = '' then
        winTitle := 'Window';

      if isActive then
        canvas.DrawTextLeft(68, 0, Max(0, w - 76), th, winTitle, nil, 236 / 255, 239 / 255, 244 / 255)
      else
        canvas.DrawTextLeft(68, 0, Max(0, w - 76), th, winTitle, nil, 127 / 255, 132 / 255, 156 / 255);
    finally
      canvas.Free();
    end;

    // 4. Send image to frame window titlebar
    if Connection <> nil then
    begin
      gc := xcb_generate_id(Connection);
      mask := 0;
      xcb_create_gc(Connection, gc, AClient.FrameWindow, mask, @values[0]);
      try
        dataLen := Cardinal(w * th * 4);
        xcb_put_image(Connection, XCB_IMAGE_FORMAT_Z_PIXMAP, AClient.FrameWindow, gc,
                      w, th, 0, 0, 0, 24, dataLen, PByte(frameImg.Data));
        xcb_flush(Connection);
      finally
        xcb_free_gc(Connection, gc);
      end;
    end;
  finally
    frameImg.Free();
  end;

  if FCompositor <> nil then
  begin
    compWin := FCompositor.FindWindow(AClient.FrameWindow);
    if compWin <> nil then
      compWin.MarkDamaged();
  end;
end;

procedure TWMSamaCompositingWM.PaintAllFrames();
var
  i: Integer;
begin
  for i := 0 to Clients.Count - 1 do
    PaintClientFrame(TXCBWMClient(Clients[i]));
end;

procedure TWMSamaCompositingWM.BeginDrag(const AClient: TXCBWMClient; const AMode: TXCBDragMode; const ARootX, ARootY: Integer);
begin
  if (AClient <> nil) and (AMode = dmMove) then
  begin
    // Un-maximize if moving from maximized state
    if wsMaximizedHorz in AClient.State then
    begin
      AClient.Restore();
      // Center restored window horizontally under cursor
      AClient.Move(Max(0, ARootX - (AClient.CurrentRect.Width div 2)), Max(0, ARootY - 12));
    end;
  end;

  inherited BeginDrag(AClient, AMode, ARootX, ARootY);
end;

procedure TWMSamaCompositingWM.UpdateDrag(const ARootX, ARootY: Integer);
var
  sw, sh, threshold: Integer;
begin
  inherited UpdateDrag(ARootX, ARootY);

  if (DragClient = nil) or (DragMode <> dmMove) or (FCompositor = nil) then Exit;

  sw := FCompositor.ScreenWidth;
  sh := FCompositor.ScreenHeight;
  threshold := 14;

  // Detect edge snapping triggers
  if ARootY <= threshold then
  begin
    FActiveSnap := snapMaximize;
    FSnapPreviewRect := TXCBRect.Create(0, 0, sw, sh);
    RequestComposite();
  end
  else if ARootX <= threshold then
  begin
    FActiveSnap := snapLeftHalf;
    FSnapPreviewRect := TXCBRect.Create(0, 0, sw div 2, sh);
    RequestComposite();
  end
  else if ARootX >= sw - threshold then
  begin
    FActiveSnap := snapRightHalf;
    FSnapPreviewRect := TXCBRect.Create(sw div 2, 0, sw - (sw div 2), sh);
    RequestComposite();
  end
  else
  begin
    if FActiveSnap <> snapNone then
    begin
      FActiveSnap := snapNone;
      FSnapPreviewRect := TXCBRect.Create(0, 0, 0, 0);
      RequestComposite();
    end;
  end;
end;

procedure TWMSamaCompositingWM.EndDrag();
var
  cli: TXCBWMClient;
  snap: TWMSnapTarget;
  sw, sh: Integer;
begin
  cli := DragClient;
  snap := FActiveSnap;

  FActiveSnap := snapNone;
  FSnapPreviewRect := TXCBRect.Create(0, 0, 0, 0);

  inherited EndDrag();

  if (cli <> nil) and (snap <> snapNone) and (FCompositor <> nil) then
  begin
    sw := FCompositor.ScreenWidth;
    sh := FCompositor.ScreenHeight;

    case snap of
      snapMaximize:
        cli.Maximize();
      snapLeftHalf:
        cli.SetGeometry(0, 0, sw div 2, sh);
      snapRightHalf:
        cli.SetGeometry(sw div 2, 0, sw - (sw div 2), sh);
    end;
  end;

  RequestComposite();
end;

procedure TWMSamaCompositingWM.TriggerAltTabForward();
begin
  if Clients.Count <= 0 then Exit;
  if not FAltTabActive then
  begin
    FAltTabActive := True;
    FAltTabIndex := 0;
  end;

  FAltTabIndex := (FAltTabIndex + 1) mod Clients.Count;
  RequestComposite();
end;

procedure TWMSamaCompositingWM.TriggerAltTabDismiss();
var
  targetCli: TXCBWMClient;
begin
  if not FAltTabActive then Exit;
  FAltTabActive := False;

  if (Clients.Count > 0) and (FAltTabIndex >= 0) and (FAltTabIndex < Clients.Count) then
  begin
    targetCli := TXCBWMClient(Clients[FAltTabIndex]);
    targetCli.Activate();
  end;

  RequestComposite();
end;

procedure TWMSamaCompositingWM.DoOnCompositorAfterRender(ASender: TObject; ACanvas: TFloriaCanvasAgg; const ASceneRect: TXCBRect);
var
  sw, sh, cardW, cardH, cardX, cardY: Integer;
  itemX, itemY, itemW, itemH, i: Integer;
  cli: TXCBWMClient;
  titleStr: AnsiString;
begin
  if (FCompositor = nil) or (ACanvas = nil) then Exit;
  sw := FCompositor.ScreenWidth;
  sh := FCompositor.ScreenHeight;

  // 1. Render Window Edge Snapping Preview Overlay
  if FSnapPreviewRect.Width > 0 then
  begin
    // Soft glowing translucent snapping preview with rounded corners
    ACanvas.DrawRoundedRect(FSnapPreviewRect.X + 8, FSnapPreviewRect.Y + 8,
                            FSnapPreviewRect.Width - 16, FSnapPreviewRect.Height - 16,
                            14, 137 / 255, 180 / 255, 250 / 255, 0.22);
    ACanvas.DrawRoundedRectOutline(FSnapPreviewRect.X + 8, FSnapPreviewRect.Y + 8,
                                   FSnapPreviewRect.Width - 16, FSnapPreviewRect.Height - 16,
                                   14, 2.0, 137 / 255, 180 / 255, 250 / 255, 0.75);
  end;

  // 2. Render Alt+Tab Window Switcher Overlay HUD
  if FAltTabActive and (Clients.Count > 0) then
  begin
    cardW := Min(sw - 40, Max(360, Clients.Count * 130 + 40));
    cardH := 120;
    cardX := (sw - cardW) div 2;
    cardY := (sh - cardH) div 2;

    // Card shadow and dark frosted glass background
    ACanvas.DrawShadow(cardX, cardY, cardW, cardH, 16, 0, 8, 24, 0.0, 0.0, 0.0, 0.55);
    ACanvas.DrawRoundedRect(cardX, cardY, cardW, cardH, 16, 24 / 255, 25 / 255, 38 / 255, 0.92);
    ACanvas.DrawRoundedRectOutline(cardX, cardY, cardW, cardH, 16, 1.5, 69 / 255, 71 / 255, 90 / 255, 0.6);

    itemW := 114;
    itemH := 88;

    for i := 0 to Clients.Count - 1 do
    begin
      cli := TXCBWMClient(Clients[i]);
      itemX := cardX + 20 + (i * 130);
      itemY := cardY + 16;
      if itemX + itemW > cardX + cardW - 10 then Break;

      titleStr := cli.Title;
      if titleStr = '' then titleStr := cli.WindowClass;
      if Length(titleStr) > 14 then
        titleStr := Copy(titleStr, 1, 12) + '..';

      if i = FAltTabIndex then
      begin
        // Active selection highlight
        ACanvas.DrawRoundedRect(itemX, itemY, itemW, itemH, 10, 49 / 255, 50 / 255, 68 / 255, 0.95);
        ACanvas.DrawRoundedRectOutline(itemX, itemY, itemW, itemH, 10, 2.0, 137 / 255, 180 / 255, 250 / 255, 0.95);
        // Window badge circle
        ACanvas.DrawCircle(itemX + (itemW div 2), itemY + 28, 12, 137 / 255, 180 / 255, 250 / 255, 1.0);
        ACanvas.DrawTextLeft(itemX + 8, itemY + 54, itemW - 16, 24, titleStr, nil, 236 / 255, 239 / 255, 244 / 255);
      end
      else
      begin
        // Unselected window card
        ACanvas.DrawRoundedRect(itemX, itemY, itemW, itemH, 10, 30 / 255, 30 / 255, 46 / 255, 0.6);
        ACanvas.DrawCircle(itemX + (itemW div 2), itemY + 28, 10, 88 / 255, 91 / 255, 112 / 255, 1.0);
        ACanvas.DrawTextLeft(itemX + 8, itemY + 54, itemW - 16, 24, titleStr, nil, 147 / 255, 153 / 255, 178 / 255);
      end;
    end;
  end;
end;

function TWMSamaCompositingWM.ProcessEvent(const AEvent: Pxcb_generic_event_t): Boolean;
var
  evType: Byte;
  btnEv: Pxcb_button_press_event_t;
  keyEv: Pxcb_key_press_event_t;
  motionEv: Pxcb_motion_notify_event_t;
  leaveEv: Pxcb_leave_notify_event_t;
  cli, oldCli: TXCBWMClient;
  localX, localY, bw, th, newBtn: Integer;
  oldWin: xcb_window_t;
begin
  Result := False;
  if AEvent = nil then Exit;

  // 1. Intercept XDamage notifications
  if (FCompositor <> nil) and FCompositor.IsDamageNotify(AEvent) then
  begin
    FCompositor.HandleDamageNotify(Pxcb_damage_notify_event_t(AEvent));
    RequestComposite();
    Exit(True);
  end;

  evType := AEvent^.response_type and $7F;
  case evType of
    XCB_KEY_PRESS:
    begin
      keyEv := Pxcb_key_press_event_t(AEvent);
      if keyEv^.detail = 23 then // Tab
      begin
        if not FAltTabActive then
        begin
          if (Connection <> nil) and (Screen <> nil) then
            xcb_grab_keyboard(Connection, 1, Screen^.root, XCB_CURRENT_TIME,
                              XCB_GRAB_MODE_ASYNC, XCB_GRAB_MODE_ASYNC);
        end;
        TriggerAltTabForward();
        Exit(True);
      end
      else if FAltTabActive and (keyEv^.detail = 9) then // Escape: cancel switcher
      begin
        if Connection <> nil then
          xcb_ungrab_keyboard(Connection, XCB_CURRENT_TIME);
        FAltTabActive := False;
        RequestComposite();
        Exit(True);
      end
      else if FAltTabActive and (keyEv^.detail = 36) then // Return: activate selected
      begin
        if Connection <> nil then
          xcb_ungrab_keyboard(Connection, XCB_CURRENT_TIME);
        TriggerAltTabDismiss();
        Exit(True);
      end;
    end;

    XCB_KEY_RELEASE:
    begin
      keyEv := Pxcb_key_press_event_t(AEvent);
      // Alt_L (64) or Alt_R (108) released
      if FAltTabActive and ((keyEv^.detail = 64) or (keyEv^.detail = 108)) then
      begin
        if Connection <> nil then
          xcb_ungrab_keyboard(Connection, XCB_CURRENT_TIME);
        TriggerAltTabDismiss();
        Exit(True);
      end;
    end;

    XCB_MOTION_NOTIFY:
    begin
      motionEv := Pxcb_motion_notify_event_t(AEvent);
      if DragMode = dmNone then
      begin
        cli := FindClient(motionEv^.event);
        if (cli <> nil) and (motionEv^.event = cli.FrameWindow) then
        begin
          localX := motionEv^.event_x;
          localY := motionEv^.event_y;
          th := FTitlebarHeight;
          newBtn := -1;
          if (localY >= 3) and (localY <= th - 3) then
          begin
            if (localX >= 6) and (localX <= 22) then newBtn := 0
            else if (localX >= 25) and (localX <= 41) then newBtn := 1
            else if (localX >= 44) and (localX <= 60) then newBtn := 2;
          end;

          if (newBtn <> FHoveredButton) or (cli.FrameWindow <> FHoveredWindow) then
          begin
            FHoveredButton := newBtn;
            FHoveredWindow := cli.FrameWindow;
            PaintClientFrame(cli);
            RequestComposite();
          end;
        end
        else if FHoveredWindow <> 0 then
        begin
          oldWin := FHoveredWindow;
          FHoveredWindow := 0;
          FHoveredButton := -1;
          oldCli := FindClient(oldWin);
          if oldCli <> nil then
            PaintClientFrame(oldCli);
          RequestComposite();
        end;
      end;
    end;

    XCB_LEAVE_NOTIFY:
    begin
      leaveEv := Pxcb_leave_notify_event_t(AEvent);
      if (FHoveredWindow <> 0) and (leaveEv^.event = FHoveredWindow) then
      begin
        oldWin := FHoveredWindow;
        FHoveredWindow := 0;
        FHoveredButton := -1;
        oldCli := FindClient(oldWin);
        if oldCli <> nil then
          PaintClientFrame(oldCli);
        RequestComposite();
      end;
    end;

    XCB_BUTTON_RELEASE:
    begin
      if FPressedButton <> -1 then
      begin
        FPressedButton := -1;
        if FHoveredWindow <> 0 then
        begin
          oldCli := FindClient(FHoveredWindow);
          if oldCli <> nil then
            PaintClientFrame(oldCli);
          RequestComposite();
        end;
      end;
    end;

    XCB_BUTTON_PRESS:
    begin
      btnEv := Pxcb_button_press_event_t(AEvent);
      cli := FindClient(btnEv^.event);
      if cli <> nil then
      begin
        // 1. Direct clicks on client application window (pass-through / click-to-focus)
        if btnEv^.event = cli.ClientWindow then
        begin
          cli.Activate();
          if Connection <> nil then
          begin
            xcb_allow_events(Connection, XCB_ALLOW_REPLAY_POINTER, btnEv^.time);
            xcb_flush(Connection);
          end;
          Exit(True);
        end;

        // 2. Clicks on frame window decorations
        if btnEv^.event = cli.FrameWindow then
        begin
          localX := btnEv^.event_x;
          localY := btnEv^.event_y;
          th := FTitlebarHeight;
          bw := FrameMetrics.BorderWidth;

          cli.Activate();
          if Connection <> nil then
            xcb_allow_events(Connection, XCB_ALLOW_ASYNC_POINTER, btnEv^.time);

          // A. Handle click on control dots
          if (localY >= 3) and (localY <= th - 3) and (btnEv^.detail = XCB_BUTTON_INDEX_1) then
          begin
            // Close button: X in [6..22]
            if (localX >= 6) and (localX <= 22) then
            begin
              FPressedButton := 0;
              PaintClientFrame(cli);
              cli.Close();
              Exit(True);
            end;

            // Minimize button: X in [25..41]
            if (localX >= 25) and (localX <= 41) then
            begin
              FPressedButton := 1;
              PaintClientFrame(cli);
              cli.Minimize();
              Exit(True);
            end;

            // Maximize button: X in [44..60]
            if (localX >= 44) and (localX <= 60) then
            begin
              FPressedButton := 2;
              PaintClientFrame(cli);
              if wsMaximizedHorz in cli.State then
                cli.Restore()
              else
                cli.Maximize();
              Exit(True);
            end;
          end;

          // B. Right-click on titlebar to resize window
          if (localY >= 0) and (localY < th) and (btnEv^.detail = XCB_BUTTON_INDEX_3) then
          begin
            BeginDrag(cli, dmResize, btnEv^.root_x, btnEv^.root_y);
            Exit(True);
          end;

          // C. Handle Double-Click on titlebar to Maximize / Restore
          if (localY >= 0) and (localY < th) and (localX >= 60) and (btnEv^.detail = XCB_BUTTON_INDEX_1) then
          begin
            if (btnEv^.time - FLastClickTime < 350) and (FLastClickWindow = btnEv^.event) then
            begin
              if wsMaximizedHorz in cli.State then
                cli.Restore()
              else
                cli.Maximize();
              FLastClickTime := 0;
              Exit(True);
            end
            else
            begin
              FLastClickTime := btnEv^.time;
              FLastClickWindow := btnEv^.event;
            end;

            // Otherwise begin window moving
            BeginDrag(cli, dmMove, btnEv^.root_x, btnEv^.root_y);
            Exit(True);
          end;

          // D. Handle Border Resizing when border width > 0
          if (bw > 0) and ((localY >= th) or (localX < bw) or (localX >= cli.CurrentRect.Width - bw) or (localY >= cli.CurrentRect.Height - bw)) then
          begin
            BeginDrag(cli, dmResize, btnEv^.root_x, btnEv^.root_y);
            Exit(True);
          end;
        end;
      end;
    end;
  end;

  // Default Window Manager event handling
  Result := inherited ProcessEvent(AEvent);
end;

procedure TWMSamaCompositingWM.Run();
var
  event: Pxcb_generic_event_t;
begin
  if Connection = nil then Exit;

  // Initial paint of all frames and initial composite scene
  PaintAllFrames();
  if FCompositorEnabled and (FCompositor <> nil) then
  begin
    FCompositor.CompositeScene();
    FCompositor.PresentToScreen();
  end;

  // Main event pump with batched presentation
  while True do
  begin
    event := xcb_wait_for_event(Connection);
    if event = nil then Break;

    try
      ProcessEvent(event);
    finally
      xcb_free(event);
    end;

    // Process all pending events in queue before compositing
    while True do
    begin
      event := xcb_poll_for_event(Connection);
      if event = nil then Break;
      try
        ProcessEvent(event);
      finally
        xcb_free(event);
      end;
    end;

    // Render composited frame if damage occurred or state changed
    if FCompositorEnabled and FNeedsComposite and (FCompositor <> nil) then
    begin
      FCompositor.CompositeScene();
      FCompositor.PresentToScreen();
      FNeedsComposite := False;
    end;
  end;
end;

end.
