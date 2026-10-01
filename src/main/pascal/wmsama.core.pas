unit wmsama.core;

// wmsama.core
// ===========
// Core Compositing Window Manager implementation for Samarinda DE.
// Inherits from TXCBWindowManager and integrates TXCBCompositor for
// manual subwindow redirection, XDamage tracking, soft Gaussian shadows,
// frosted glass backdrop blur, and modern vector titlebars.

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
  Floria.Canvas.Agg;

type
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
  protected
    procedure DoOnClientMapped(const AClient: TXCBWMClient); override;
    procedure DoOnClientUnmapped(const AClient: TXCBWMClient); override;
    procedure DoOnClientActivated(const AClient: TXCBWMClient); override;
    procedure DoOnClientConfigure(const AClient: TXCBWMClient); override;
    procedure DoOnFramePaint(const AClient: TXCBWMClient; const ARect: TXCBRect); override;
  public
    constructor Create(AConn: Pxcb_connection_t = nil; const AScreenNum: Integer = 0);
    destructor Destroy(); override;

    function StartCompositor(): Boolean;
    procedure StopCompositor();

    procedure RequestComposite();
    procedure RenderComposite();

    procedure PaintAllFrames();
    procedure PaintClientFrame(const AClient: TXCBWMClient);

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
  metrics := TXCBFrameMetrics.Create(FTitlebarHeight, 1);
  FrameMetrics := metrics;

  FCompositorEnabled := True;
  FNeedsComposite := False;
  FBlurEnabled := False;
  FBlurRadius := 15;

  FShadowEnabled := True;
  FShadowRadius := 14;
  FShadowOffsetY := 4;
  FShadowOpacity := 0.35;

  FActiveShadowRadius := 18;
  FActiveShadowOffsetY := 6;
  FActiveShadowOpacity := 0.48;

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
  metrics := TXCBFrameMetrics.Create(FTitlebarHeight, 1);
  FrameMetrics := metrics;
  PaintAllFrames();
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
    compWin.CornerRadius := 8;
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
  w, h, th: Integer;
  isActive: Boolean;
  titleImg: TFloriaImage;
  canvas: TFloriaCanvasAgg;
  winTitle: AnsiString;
  dataLen: Cardinal;
  gc: xcb_gcontext_t;
  mask: Cardinal;
  values: array[0..0] of Cardinal;
  compWin: TXCBCompositedWindow;
begin
  if (AClient = nil) or not AClient.IsReparented or (AClient.FrameWindow = 0) then Exit;

  w := AClient.CurrentRect.Width;
  h := AClient.CurrentRect.Height;
  th := FTitlebarHeight;
  if (w <= 0) or (h <= 0) or (th <= 0) then Exit;

  isActive := (AClient = ActiveClient);

  titleImg := TFloriaImage.Create(w, th);
  try
    canvas := TFloriaCanvasAgg.Create(titleImg);
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

      // 2. Control dots (macOS / Samarinda modern aesthetic)
      if isActive then
      begin
        // Close: Coral Red (#FF5F56)
        canvas.DrawCircle(14, th / 2, 5.5, 255 / 255, 95 / 255, 86 / 255, 1.0);
        // Minimize: Warm Amber (#FFBD2E)
        canvas.DrawCircle(32, th / 2, 5.5, 255 / 255, 189 / 255, 46 / 255, 1.0);
        // Maximize: Mint Emerald (#27C93F)
        canvas.DrawCircle(50, th / 2, 5.5, 39 / 255, 201 / 255, 63 / 255, 1.0);
      end
      else
      begin
        // Muted dots when inactive (#45475A)
        canvas.DrawCircle(14, th / 2, 5.5, 69 / 255, 71 / 255, 90 / 255, 1.0);
        canvas.DrawCircle(32, th / 2, 5.5, 69 / 255, 71 / 255, 90 / 255, 1.0);
        canvas.DrawCircle(50, th / 2, 5.5, 69 / 255, 71 / 255, 90 / 255, 1.0);
      end;

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

    // 4. Send image to frame window
    if Connection <> nil then
    begin
      gc := xcb_generate_id(Connection);
      mask := 0;
      xcb_create_gc(Connection, gc, AClient.FrameWindow, mask, @values[0]);
      try
        dataLen := Cardinal(w * th * 4);
        xcb_put_image(Connection, XCB_IMAGE_FORMAT_Z_PIXMAP, AClient.FrameWindow, gc,
                      w, th, 0, 0, 0, 24, dataLen, PByte(titleImg.Data));
        xcb_flush(Connection);
      finally
        xcb_free_gc(Connection, gc);
      end;
    end;
  finally
    titleImg.Free();
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

function TWMSamaCompositingWM.ProcessEvent(const AEvent: Pxcb_generic_event_t): Boolean;
var
  evType: Byte;
  btnEv: Pxcb_button_press_event_t;
  cli: TXCBWMClient;
  localX, localY: Integer;
begin
  Result := False;
  if AEvent = nil then Exit;

  // Intercept XDamage notifications
  if (FCompositor <> nil) and FCompositor.IsDamageNotify(AEvent) then
  begin
    FCompositor.HandleDamageNotify(Pxcb_damage_notify_event_t(AEvent));
    RequestComposite();
    Exit(True);
  end;

  evType := AEvent^.response_type and $7F;
  if evType = XCB_BUTTON_PRESS then
  begin
    btnEv := Pxcb_button_press_event_t(AEvent);
    cli := FindClient(btnEv^.event);
    if (cli <> nil) and (btnEv^.event = cli.FrameWindow) then
    begin
      localX := btnEv^.event_x;
      localY := btnEv^.event_y;

      // Handle click on control dots
      if (localY >= 4) and (localY <= FTitlebarHeight - 4) and (btnEv^.detail = XCB_BUTTON_INDEX_1) then
      begin
        // Close button: X in [7..21]
        if (localX >= 7) and (localX <= 21) then
        begin
          cli.Close();
          Exit(True);
        end;

        // Minimize button: X in [25..39]
        if (localX >= 25) and (localX <= 39) then
        begin
          cli.Minimize();
          Exit(True);
        end;

        // Maximize button: X in [43..57]
        if (localX >= 43) and (localX <= 57) then
        begin
          if wsMaximizedHorz in cli.State then
            cli.Restore()
          else
            cli.Maximize();
          Exit(True);
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

  // Set running state via base class field or Stop()
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
