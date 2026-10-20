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

  TWMSamaButtonKind = (
    sbkClose,
    sbkMinimize,
    sbkMaximize,
    sbkShade,
    sbkPin,
    sbkMenu
  );

  TWMSamaButtonAlignment = (
    baLeft,
    baRight
  );

  TWMSamaButtonPlacement = (
    bpLeft,
    bpRight
  );

  TWMSamaButtonLayoutItem = record
    Kind: TWMSamaButtonKind;
    Placement: TWMSamaButtonPlacement;
  end;

  TWMSamaCalculatedButton = record
    Kind: TWMSamaButtonKind;
    Placement: TWMSamaButtonPlacement;
    X: Double;
    Y: Double;
    Size: Double;
  end;

  TWMSamaButtonArray = array of TWMSamaCalculatedButton;

  TWMSamaShadedWindow = record
    WindowId: xcb_window_t;
    OriginalHeight: Integer;
  end;

  Pxcb_map_notify_event_t = ^xcb_map_notify_event_t;
  Pxcb_unmap_notify_event_t = ^xcb_unmap_notify_event_t;

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

    // Window Button Theming, Layout and Hover States
    FWindowButtonStyle  : Integer;
    FThemeDarkMode      : Boolean;
    FButtonAlignment    : TWMSamaButtonAlignment;
    FButtonLayout       : AnsiString;
    FButtonLayoutItems  : array of TWMSamaButtonLayoutItem;
    FHoveredWindow      : xcb_window_t;
    FHoveredButton      : Integer;
    FPressedButton      : Integer;
    FPressedWindow      : xcb_window_t;
    FHoverCursorWindow  : xcb_window_t;
    FHoverCursor        : xcb_cursor_t;

    // Shaded Windows and Window Menu Overlay
    FShadedWindows      : array of TWMSamaShadedWindow;
    FWindowMenuClient   : TXCBWMClient;
    FWindowMenuRect     : TXCBRect;

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

    // Drag velocity tracking
    FLastDragX          : Integer;
    FLastDragY          : Integer;

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
    procedure SetButtonAlignment(const AValue: TWMSamaButtonAlignment);
    procedure SetButtonLayout(const AValue: AnsiString);

    procedure DoOnCompositorAfterRender(ASender: TObject; ACanvas: TFloriaCanvasAgg; const ASceneRect: TXCBRect);
  protected
    procedure DoOnClientMapped(const AClient: TXCBWMClient); override;
    procedure DoOnClientUnmapped(const AClient: TXCBWMClient); override;
    procedure DoOnClientActivated(const AClient: TXCBWMClient); override;
    procedure DoOnClientConfigure(const AClient: TXCBWMClient); override;
    procedure DoOnClientMinimized(const AClient: TXCBWMClient); override;
    procedure DoOnClientRestored(const AClient: TXCBWMClient); override;
    procedure DoOnMonitorsChanged(); override;
    procedure DoOnFramePaint(const AClient: TXCBWMClient; const ARect: TXCBRect); override;
  public
    function IsWindowMenu(const AWindow: xcb_window_t): Boolean;
    procedure ApplyClientCornerRadius(const AClient: TXCBWMClient; const ACompWin: TXCBCompositedWindow);
    procedure ApplyClientShadow(const AClient: TXCBWMClient; const ACompWin: TXCBCompositedWindow);
    procedure UpdateAllWindowShadows();

    constructor Create(AConn: Pxcb_connection_t = nil; const AScreenNum: Integer = 0);
    destructor Destroy(); override;

    function ClaimOwnership(): Boolean; override;
    procedure GrabGlobalKeys();
    procedure ScanWindows();

    function StartCompositor(): Boolean;
    procedure StopCompositor();

    procedure RequestComposite();
    procedure RenderComposite();

    procedure PaintAllFrames();
    procedure PaintClientFrame(const AClient: TXCBWMClient);

    // Window Button Layout and Hit Detection
    procedure CalculateButtons(const AWidth: Integer; out AButtons: TWMSamaButtonArray; out ATitleX, ATitleW: Integer); overload;
    procedure CalculateButtons(const AClient: TXCBWMClient; const AWidth: Integer; out AButtons: TWMSamaButtonArray; out ATitleX, ATitleW: Integer); overload;
    procedure GetWindowButtonMetrics(out ABtnSize, ABtnY, AX0, AX1, AX2: Double; out ATitleX: Integer);
    function GetButtonAt(const AX, AY: Integer; const AWidth: Integer = 820): Integer; overload;
    function GetButtonAt(const AX, AY: Integer; const AClient: TXCBWMClient; const AWidth: Integer = 0): Integer; overload;
    function IsTitlebarDraggable(const AX, AY, AWidth: Integer): Boolean; overload;
    function IsTitlebarDraggable(const AX, AY: Integer; const AClient: TXCBWMClient; const AWidth: Integer = 0): Boolean; overload;
    function GetResizeModeForPoint(const AClient: TXCBWMClient; const ARootX, ARootY: Integer): TXCBDragMode;

    // Additional Window Controls (Shade, Keep on Top, Window Menu)
    procedure ToggleKeepOnTop(const AClient: TXCBWMClient);
    procedure ToggleShade(const AClient: TXCBWMClient);
    function IsClientShaded(const AWin: xcb_window_t): Boolean;
    procedure TriggerWindowMenu(const AClient: TXCBWMClient);
    procedure DismissWindowMenu();

    // Interactive Dragging and Snapping
    procedure BeginDrag(const AClient: TXCBWMClient; const AMode: TXCBDragMode; const ARootX, ARootY: Integer); override;
    procedure UpdateDrag(const ARootX, ARootY: Integer); override;
    procedure EndDrag(); override;
    procedure UpdateHoverCursor(const ACursor: xcb_cursor_t; const AEventWindow: xcb_window_t);
    procedure DoOnClientPropertiesChanged(const AClient: TXCBWMClient); override;

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
    property ButtonAlignment    : TWMSamaButtonAlignment read FButtonAlignment    write SetButtonAlignment;
    property ButtonLayout       : AnsiString             read FButtonLayout       write SetButtonLayout;
    property WindowMenuClient   : TXCBWMClient           read FWindowMenuClient;
    property WindowMenuRect     : TXCBRect               read FWindowMenuRect;
    property ActiveSnap         : TWMSnapTarget  read FActiveSnap;
    property SnapPreviewRect    : TXCBRect       read FSnapPreviewRect;
    property AltTabActive       : Boolean        read FAltTabActive;
    property AltTabIndex        : Integer        read FAltTabIndex;
    property HoveredButton      : Integer        read FHoveredButton;
    property HoveredWindow      : xcb_window_t   read FHoveredWindow;
    property PressedButton      : Integer        read FPressedButton;
    property PressedWindow      : xcb_window_t   read FPressedWindow;
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
  FTitlebarHeight := 34;
  metrics := TXCBFrameMetrics.Create(FTitlebarHeight, 0);
  FrameMetrics := metrics;

  FCornerRadius := 12;
  FBottomCornerRadius := 12;

  FWindowButtonStyle := FT_WINDOW_BUTTON_CIRCLE;
  FThemeDarkMode := True;
  FButtonAlignment := baLeft;
  SetLength(FShadedWindows, 0);
  FWindowMenuClient := nil;
  FWindowMenuRect := TXCBRect.Create(0, 0, 0, 0);
  SetButtonLayout('close,minimize,maximize:');
  FHoveredWindow := 0;
  FHoveredButton := -1;
  FPressedButton := -1;
  FPressedWindow := 0;

  FCompositorEnabled := True;
  FNeedsComposite := False;
  FBlurEnabled := False;
  FBlurRadius := 15;

  FShadowEnabled := True;
  FShadowRadius := 10;
  FShadowOffsetY := 1;
  FShadowOpacity := 0.14;

  FActiveShadowRadius := 14;
  FActiveShadowOffsetY := 1;
  FActiveShadowOpacity := 0.22;

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
  SPACE_KEYCODE = 65;
  LEFT_KEYCODE = 113;
  RIGHT_KEYCODE = 114;
  UP_KEYCODE = 111;
  DOWN_KEYCODE = 116;
  MOD_ALT = 8;
  MOD_SUPER_SHIFT = 65; // Mod4 (64) + Shift (1)
  MOD_NUMLOCK = 16;
  MOD_CAPSLOCK = 2;
var
  alt_mods: array[0..3] of Word;
  super_mods: array[0..3] of Word;
  i: Integer;
begin
  if (Connection = nil) or (Screen = nil) then Exit;
  alt_mods[0] := MOD_ALT;
  alt_mods[1] := MOD_ALT or MOD_NUMLOCK;
  alt_mods[2] := MOD_ALT or MOD_CAPSLOCK;
  alt_mods[3] := MOD_ALT or MOD_NUMLOCK or MOD_CAPSLOCK;

  super_mods[0] := MOD_SUPER_SHIFT;
  super_mods[1] := MOD_SUPER_SHIFT or MOD_NUMLOCK;
  super_mods[2] := MOD_SUPER_SHIFT or MOD_CAPSLOCK;
  super_mods[3] := MOD_SUPER_SHIFT or MOD_NUMLOCK or MOD_CAPSLOCK;

  for i := 0 to 3 do
  begin
    xcb_grab_key(Connection, 1, Screen^.root, alt_mods[i], TAB_KEYCODE,
                 XCB_GRAB_MODE_ASYNC, XCB_GRAB_MODE_ASYNC);
    xcb_grab_key(Connection, 1, Screen^.root, alt_mods[i], SPACE_KEYCODE,
                 XCB_GRAB_MODE_ASYNC, XCB_GRAB_MODE_ASYNC);

    // Multi-monitor keyboard navigation: Super + Shift + Arrow keys
    xcb_grab_key(Connection, 1, Screen^.root, super_mods[i], LEFT_KEYCODE,
                 XCB_GRAB_MODE_ASYNC, XCB_GRAB_MODE_ASYNC);
    xcb_grab_key(Connection, 1, Screen^.root, super_mods[i], RIGHT_KEYCODE,
                 XCB_GRAB_MODE_ASYNC, XCB_GRAB_MODE_ASYNC);
    xcb_grab_key(Connection, 1, Screen^.root, super_mods[i], UP_KEYCODE,
                 XCB_GRAB_MODE_ASYNC, XCB_GRAB_MODE_ASYNC);
    xcb_grab_key(Connection, 1, Screen^.root, super_mods[i], DOWN_KEYCODE,
                 XCB_GRAB_MODE_ASYNC, XCB_GRAB_MODE_ASYNC);
  end;
  xcb_flush(Connection);
end;

procedure TWMSamaCompositingWM.ScanWindows();
var
  cookie: xcb_query_tree_cookie_t;
  reply: Pxcb_query_tree_reply_t;
  children: Pxcb_window_t;
  numChildren, i: Integer;
  attrCookie: xcb_get_window_attributes_cookie_t;
  attrReply: Pxcb_get_window_attributes_reply_t;
  geomCookie: xcb_get_geometry_cookie_t;
  geomReply: Pxcb_get_geometry_reply_t;
  compWin: TXCBCompositedWindow;
  geomRect: TXCBRect;
begin
  inherited ScanWindows();

  if (Connection = nil) or (Screen = nil) or (FCompositor = nil) then Exit;

  cookie := xcb_query_tree(Connection, Screen^.root);
  reply := xcb_query_tree_reply(Connection, cookie, nil);
  if reply = nil then Exit;

  try
    numChildren := xcb_query_tree_children_length(reply);
    children := xcb_query_tree_children(reply);
    for i := 0 to numChildren - 1 do
    begin
      if (children[i] = Screen^.root) or (FindClient(children[i]) <> nil) then Continue;

      attrCookie := xcb_get_window_attributes(Connection, children[i]);
      attrReply := xcb_get_window_attributes_reply(Connection, attrCookie, nil);
      if attrReply <> nil then
      begin
        try
          if (attrReply^.override_redirect <> 0) and
             (attrReply^.map_state <> XCB_MAP_STATE_UNMAPPED) then
          begin
            geomCookie := xcb_get_geometry(Connection, children[i]);
            geomReply := xcb_get_geometry_reply(Connection, geomCookie, nil);
            if geomReply <> nil then
            begin
              try
                geomRect := TXCBRect.Create(geomReply^.x, geomReply^.y, geomReply^.width, geomReply^.height);
                if (geomRect.Width > 1) and (geomRect.Height > 1) then
                begin
                  compWin := FCompositor.RegisterWindow(children[i], geomRect, 0);
                  if compWin <> nil then
                  begin
                    if IsWindowMenu(children[i]) then
                    begin
                      compWin.CornerRadius := 6;
                      compWin.BottomCornerRadius := 6;
                      compWin.ShadowConfig := TXCBWindowShadowConfig.Create(FShadowEnabled, 10, 1, 0.20);
                    end
                    else
                    begin
                      compWin.CornerRadius := 0;
                      compWin.BottomCornerRadius := 0;
                      compWin.ShadowConfig := TXCBWindowShadowConfig.Create(False, 0, 0, 0.0);
                    end;
                    FCompositor.Windows.Extract(compWin);
                    FCompositor.Windows.Add(compWin);
                    compWin.MarkDamaged();
                  end;
                end;
              finally
                xcb_free(geomReply);
              end;
            end;
          end;
        finally
          xcb_free(attrReply);
        end;
      end;
    end;
  finally
    xcb_free(reply);
  end;
  RequestComposite();
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
  UpdateAllWindowShadows();
end;

procedure TWMSamaCompositingWM.SetShadowRadius(const AValue: Integer);
begin
  FShadowRadius := Max(0, AValue);
  UpdateAllWindowShadows();
end;

procedure TWMSamaCompositingWM.SetShadowOffsetY(const AValue: Integer);
begin
  FShadowOffsetY := AValue;
  UpdateAllWindowShadows();
end;

procedure TWMSamaCompositingWM.SetShadowOpacity(const AValue: Single);
begin
  FShadowOpacity := AValue;
  UpdateAllWindowShadows();
end;

procedure TWMSamaCompositingWM.SetActiveShadowRadius(const AValue: Integer);
begin
  FActiveShadowRadius := Max(0, AValue);
  UpdateAllWindowShadows();
end;

procedure TWMSamaCompositingWM.SetActiveShadowOffsetY(const AValue: Integer);
begin
  FActiveShadowOffsetY := AValue;
  UpdateAllWindowShadows();
end;

procedure TWMSamaCompositingWM.SetActiveShadowOpacity(const AValue: Single);
begin
  FActiveShadowOpacity := AValue;
  UpdateAllWindowShadows();
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

function TWMSamaCompositingWM.IsWindowMenu(const AWindow: xcb_window_t): Boolean;
var
  cli: TXCBWMClient;
  propCookie: xcb_get_property_cookie_t;
  propReply: Pxcb_get_property_reply_t;
  atomsPtr: Pxcb_atom_t;
  atomsLen, i: Integer;
  atom: xcb_atom_t;
  roleCookie: xcb_get_property_cookie_t;
  roleReply: Pxcb_get_property_reply_t;
  roleStr: AnsiString;
  classCookie: xcb_get_property_cookie_t;
  classReply: Pxcb_get_property_reply_t;
  classStr: AnsiString;
begin
  Result := False;
  if (Connection = nil) or (AWindow = 0) then Exit;

  // 1. If it's a managed client, check client type
  cli := FindClient(AWindow);
  if cli <> nil then
    Exit(cli.IsMenu());

  // 2. Check _NET_WM_WINDOW_TYPE
  if EwmhInitialized then
  begin
    propCookie := xcb_get_property(Connection, 0, AWindow, Ewmh._NET_WM_WINDOW_TYPE, XCB_ATOM_ATOM, 0, 8);
    propReply := xcb_get_property_reply(Connection, propCookie, nil);
    if propReply <> nil then
    begin
      try
        atomsLen := xcb_get_property_value_length(propReply) div SizeOf(xcb_atom_t);
        if atomsLen > 0 then
        begin
          atomsPtr := Pxcb_atom_t(xcb_get_property_value(propReply));
          for i := 0 to atomsLen - 1 do
          begin
            atom := atomsPtr[i];
            // If it's explicitly a splash screen or dock or tooltip or desktop, it's NOT a menu
            if (atom = Ewmh._NET_WM_WINDOW_TYPE_SPLASH) or
               (atom = Ewmh._NET_WM_WINDOW_TYPE_DOCK) or
               (atom = Ewmh._NET_WM_WINDOW_TYPE_DESKTOP) or
               (atom = Ewmh._NET_WM_WINDOW_TYPE_TOOLTIP) or
               (atom = Ewmh._NET_WM_WINDOW_TYPE_NOTIFICATION) or
               (atom = Ewmh._NET_WM_WINDOW_TYPE_NORMAL) or
               (atom = Ewmh._NET_WM_WINDOW_TYPE_DIALOG) then
              Exit(False);

            if (atom = Ewmh._NET_WM_WINDOW_TYPE_POPUP_MENU) or
               (atom = Ewmh._NET_WM_WINDOW_TYPE_DROPDOWN_MENU) or
               (atom = Ewmh._NET_WM_WINDOW_TYPE_MENU) or
               (atom = Ewmh._NET_WM_WINDOW_TYPE_COMBO) then
              Exit(True);
          end;
        end;
      finally
        xcb_free(propReply);
      end;
    end;
  end;

  // 3. Check WM_WINDOW_ROLE
  roleCookie := xcb_get_property(Connection, 0, AWindow, InternAtom(Connection, 'WM_WINDOW_ROLE'), XCB_ATOM_STRING, 0, 32);
  roleReply := xcb_get_property_reply(Connection, roleCookie, nil);
  if roleReply <> nil then
  begin
    try
      if xcb_get_property_value_length(roleReply) > 0 then
      begin
        SetString(roleStr, PAnsiChar(xcb_get_property_value(roleReply)), xcb_get_property_value_length(roleReply));
        roleStr := LowerCase(Trim(roleStr));
        if (roleStr = 'popup') or (roleStr = 'menu') or (roleStr = 'dropdown') or
           (roleStr = 'popup-menu') or (roleStr = 'combobox') then
          Exit(True);
      end;
    finally
      xcb_free(roleReply);
    end;
  end;

  // 4. Check WM_CLASS
  classCookie := xcb_get_property(Connection, 0, AWindow, XCB_ATOM_WM_CLASS, XCB_ATOM_STRING, 0, 64);
  classReply := xcb_get_property_reply(Connection, classCookie, nil);
  if classReply <> nil then
  begin
    try
      if xcb_get_property_value_length(classReply) > 0 then
      begin
        SetString(classStr, PAnsiChar(xcb_get_property_value(classReply)), xcb_get_property_value_length(classReply));
        classStr := LowerCase(classStr);
        // If it mentions splash, definitely not a menu
        if Pos('splash', classStr) > 0 then
          Exit(False);
        if (Pos('menu', classStr) > 0) or (Pos('popup', classStr) > 0) or (Pos('dropdown', classStr) > 0) then
          Exit(True);
      end;
    finally
      xcb_free(classReply);
    end;
  end;
end;

procedure TWMSamaCompositingWM.ApplyClientCornerRadius(const AClient: TXCBWMClient; const ACompWin: TXCBCompositedWindow);
begin
  if (AClient = nil) or (ACompWin = nil) then Exit;

  if AClient.IsMenu() then
  begin
    ACompWin.CornerRadius := 6;
    ACompWin.BottomCornerRadius := 6;
  end
  else if AClient.IsDecorated() and
          not ((wsFullscreen in AClient.State) or (wsMaximizedHorz in AClient.State) or
               (wsTiledLeft in AClient.State) or (wsTiledRight in AClient.State)) then
  begin
    ACompWin.CornerRadius := FCornerRadius;
    ACompWin.BottomCornerRadius := FBottomCornerRadius;
  end
  else
  begin
    ACompWin.CornerRadius := 0;
    ACompWin.BottomCornerRadius := 0;
  end;
end;

procedure TWMSamaCompositingWM.ApplyClientShadow(const AClient: TXCBWMClient; const ACompWin: TXCBCompositedWindow);
begin
  if (AClient = nil) or (ACompWin = nil) then Exit;

  if AClient.IsMenu() then
  begin
    ACompWin.ShadowConfig := TXCBWindowShadowConfig.Create(FShadowEnabled, 10, 1, 0.20);
  end
  else if AClient.IsDecorated() and
          not ((wsFullscreen in AClient.State) or (wsMaximizedHorz in AClient.State) or
               (wsTiledLeft in AClient.State) or (wsTiledRight in AClient.State)) then
  begin
    if AClient = ActiveClient then
      ACompWin.ShadowConfig := TXCBWindowShadowConfig.Create(FShadowEnabled, FActiveShadowRadius, FActiveShadowOffsetY, FActiveShadowOpacity)
    else
      ACompWin.ShadowConfig := TXCBWindowShadowConfig.Create(FShadowEnabled, FShadowRadius, FShadowOffsetY, FShadowOpacity);
  end
  else
  begin
    // Undecorated windows (splash screens, docks/panels, borderless, tooltips,
    // notifications, or maximized/tiled windows) must NOT have shadows.
    ACompWin.ShadowConfig := TXCBWindowShadowConfig.Create(False, 0, 0, 0.0);
  end;
end;

procedure TWMSamaCompositingWM.UpdateAllWindowShadows();
var
  i: Integer;
  compWin: TXCBCompositedWindow;
  cli: TXCBWMClient;
begin
  if FCompositor = nil then Exit;

  for i := 0 to FCompositor.Windows.Count - 1 do
  begin
    compWin := TXCBCompositedWindow(FCompositor.Windows[i]);
    cli := FindClient(compWin.Window);
    if cli <> nil then
      ApplyClientShadow(cli, compWin)
    else if IsWindowMenu(compWin.Window) then
      compWin.ShadowConfig := TXCBWindowShadowConfig.Create(FShadowEnabled, 10, 1, 0.20)
    else
      compWin.ShadowConfig := TXCBWindowShadowConfig.Create(False, 0, 0, 0.0);
  end;
  RequestComposite();
end;

procedure TWMSamaCompositingWM.SetCornerRadius(const AValue: Integer);
var
  i: Integer;
  compWin: TXCBCompositedWindow;
  cli: TXCBWMClient;
begin
  FCornerRadius := Max(0, AValue);
  if FCompositor <> nil then
  begin
    for i := 0 to FCompositor.Windows.Count - 1 do
    begin
      compWin := TXCBCompositedWindow(FCompositor.Windows[i]);
      cli := FindClient(compWin.Window);
      if cli <> nil then
        ApplyClientCornerRadius(cli, compWin)
      else if not IsWindowMenu(compWin.Window) then
        compWin.CornerRadius := 0;
    end;
    RequestComposite();
  end;
end;

procedure TWMSamaCompositingWM.SetBottomCornerRadius(const AValue: Integer);
var
  i: Integer;
  compWin: TXCBCompositedWindow;
  cli: TXCBWMClient;
begin
  FBottomCornerRadius := Max(0, AValue);
  if FCompositor <> nil then
  begin
    for i := 0 to FCompositor.Windows.Count - 1 do
    begin
      compWin := TXCBCompositedWindow(FCompositor.Windows[i]);
      cli := FindClient(compWin.Window);
      if cli <> nil then
        ApplyClientCornerRadius(cli, compWin)
      else if not IsWindowMenu(compWin.Window) then
        compWin.BottomCornerRadius := 0;
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

procedure TWMSamaCompositingWM.SetButtonAlignment(const AValue: TWMSamaButtonAlignment);
begin
  if FButtonAlignment = AValue then Exit;
  FButtonAlignment := AValue;
  if FButtonAlignment = baLeft then
    SetButtonLayout('close,minimize,maximize:')
  else
    SetButtonLayout(':minimize,maximize,close');
end;

procedure TWMSamaCompositingWM.SetButtonLayout(const AValue: AnsiString);
var
  colonPos: Integer;
  leftStr, rightStr: AnsiString;

  procedure ParseSide(const ASideStr: AnsiString; const APlacement: TWMSamaButtonPlacement);
  var
    rawTokens: TStringArray;
    token, s: AnsiString;
    i, j: Integer;
    k: TWMSamaButtonKind;
    found: Boolean;
  begin
    s := Trim(ASideStr);
    if s = '' then Exit;

    if Pos(',', s) > 0 then
    begin
      rawTokens := s.Split([',']);
      for i := 0 to High(rawTokens) do
      begin
        token := LowerCase(Trim(rawTokens[i]));
        if token = '' then Continue;
        found := True;
        if (token = 'close') or (token = 'c') then k := sbkClose
        else if (token = 'minimize') or (token = 'min') or (token = 'm') then k := sbkMinimize
        else if (token = 'maximize') or (token = 'max') or (token = 'x') then k := sbkMaximize
        else if (token = 'shade') or (token = 's') or (token = 'rollup') then k := sbkShade
        else if (token = 'pin') or (token = 'p') or (token = 'stick') or (token = 'ontop') or (token = 'above') then k := sbkPin
        else if (token = 'menu') or (token = 'appmenu') or (token = 'h') or (token = 'burger') then k := sbkMenu
        else found := False;

        if found then
        begin
          SetLength(FButtonLayoutItems, Length(FButtonLayoutItems) + 1);
          FButtonLayoutItems[High(FButtonLayoutItems)].Kind := k;
          FButtonLayoutItems[High(FButtonLayoutItems)].Placement := APlacement;
        end;
      end;
    end
    else
    begin
      token := LowerCase(s);
      found := True;
      if (token = 'close') then k := sbkClose
      else if (token = 'minimize') or (token = 'min') then k := sbkMinimize
      else if (token = 'maximize') or (token = 'max') then k := sbkMaximize
      else if (token = 'shade') or (token = 'rollup') then k := sbkShade
      else if (token = 'pin') or (token = 'stick') or (token = 'ontop') or (token = 'above') then k := sbkPin
      else if (token = 'menu') or (token = 'appmenu') then k := sbkMenu
      else found := False;

      if found then
      begin
        SetLength(FButtonLayoutItems, Length(FButtonLayoutItems) + 1);
        FButtonLayoutItems[High(FButtonLayoutItems)].Kind := k;
        FButtonLayoutItems[High(FButtonLayoutItems)].Placement := APlacement;
      end
      else
      begin
        for j := 1 to Length(token) do
        begin
          found := True;
          case token[j] of
            'c': k := sbkClose;
            'm': k := sbkMinimize;
            'x': k := sbkMaximize;
            's': k := sbkShade;
            'p': k := sbkPin;
            'h': k := sbkMenu;
          else
            found := False;
          end;
          if found then
          begin
            SetLength(FButtonLayoutItems, Length(FButtonLayoutItems) + 1);
            FButtonLayoutItems[High(FButtonLayoutItems)].Kind := k;
            FButtonLayoutItems[High(FButtonLayoutItems)].Placement := APlacement;
          end;
        end;
      end;
    end;
  end;

var
  leftCount, rightCount, i: Integer;
begin
  colonPos := Pos(':', AValue);
  if colonPos > 0 then
  begin
    leftStr := Copy(AValue, 1, colonPos - 1);
    rightStr := Copy(AValue, colonPos + 1, Length(AValue) - colonPos);
  end
  else
  begin
    if FButtonAlignment = baLeft then
    begin
      leftStr := AValue;
      rightStr := '';
    end
    else
    begin
      leftStr := '';
      rightStr := AValue;
    end;
  end;

  SetLength(FButtonLayoutItems, 0);
  ParseSide(leftStr, bpLeft);
  ParseSide(rightStr, bpRight);

  if Length(FButtonLayoutItems) = 0 then
  begin
    SetLength(FButtonLayoutItems, 3);
    FButtonLayoutItems[0].Kind := sbkClose;
    FButtonLayoutItems[0].Placement := bpLeft;
    FButtonLayoutItems[1].Kind := sbkMinimize;
    FButtonLayoutItems[1].Placement := bpLeft;
    FButtonLayoutItems[2].Kind := sbkMaximize;
    FButtonLayoutItems[2].Placement := bpLeft;
    FButtonLayout := 'close,minimize,maximize:';
    FButtonAlignment := baLeft;
  end
  else
  begin
    FButtonLayout := AValue;
    leftCount := 0;
    rightCount := 0;
    for i := 0 to High(FButtonLayoutItems) do
    begin
      if FButtonLayoutItems[i].Placement = bpLeft then Inc(leftCount)
      else Inc(rightCount);
    end;
    if (leftCount = 0) and (rightCount > 0) then
      FButtonAlignment := baRight
    else if (leftCount > 0) and (rightCount = 0) then
      FButtonAlignment := baLeft;
  end;

  if (Clients <> nil) and (Clients.Count > 0) then
    PaintAllFrames();
  if FCompositor <> nil then
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
    ApplyClientShadow(AClient, compWin);

    compWin.HasBackdropBlur := FBlurEnabled;
    compWin.BlurRadius := FBlurRadius;

    ApplyClientCornerRadius(AClient, compWin);
  end;

  PaintClientFrame(AClient);
  RequestComposite();
end;

procedure TWMSamaCompositingWM.DoOnClientUnmapped(const AClient: TXCBWMClient);
var
  i, j: Integer;
begin
  inherited DoOnClientUnmapped(AClient);

  if AClient = nil then Exit;

  if FWindowMenuClient = AClient then
    DismissWindowMenu();

  if (AClient.FrameWindow <> 0) and (AClient.FrameWindow = FPressedWindow) then
  begin
    FPressedButton := -1;
    FPressedWindow := 0;
  end;
  if (AClient.FrameWindow <> 0) and (AClient.FrameWindow = FHoveredWindow) then
  begin
    FHoveredButton := -1;
    FHoveredWindow := 0;
  end;

  for i := 0 to High(FShadedWindows) do
    if FShadedWindows[i].WindowId = AClient.ClientWindow then
    begin
      for j := i to High(FShadedWindows) - 1 do
        FShadedWindows[j] := FShadedWindows[j + 1];
      SetLength(FShadedWindows, Length(FShadedWindows) - 1);
      Break;
    end;

  if FCompositor = nil then Exit;

  if AClient.FrameWindow <> 0 then
    FCompositor.UnregisterWindow(AClient.FrameWindow);
  FCompositor.UnregisterWindow(AClient.ClientWindow);

  RequestComposite();
end;

procedure TWMSamaCompositingWM.DoOnClientMinimized(const AClient: TXCBWMClient);
var
  compWin: TXCBCompositedWindow;
  targetWin: xcb_window_t;
begin
  inherited DoOnClientMinimized(AClient);

  if (AClient = nil) or (FCompositor = nil) then Exit;

  if AClient.IsReparented and (AClient.FrameWindow <> 0) then
    targetWin := AClient.FrameWindow
  else
    targetWin := AClient.ClientWindow;

  compWin := FCompositor.FindWindow(targetWin);
  if compWin <> nil then
    compWin.IsVisible := False;

  if (targetWin <> 0) and (targetWin = FHoveredWindow) then
  begin
    FHoveredWindow := 0;
    FHoveredButton := -1;
  end;
  if (targetWin <> 0) and (targetWin = FPressedWindow) then
  begin
    FPressedWindow := 0;
    FPressedButton := -1;
  end;

  if FWindowMenuClient = AClient then
    DismissWindowMenu();

  RequestComposite();
end;

procedure TWMSamaCompositingWM.DoOnClientRestored(const AClient: TXCBWMClient);
var
  compWin: TXCBCompositedWindow;
  targetWin: xcb_window_t;
begin
  inherited DoOnClientRestored(AClient);

  if (AClient = nil) or (FCompositor = nil) then Exit;

  if AClient.IsReparented and (AClient.FrameWindow <> 0) then
    targetWin := AClient.FrameWindow
  else
    targetWin := AClient.ClientWindow;

  compWin := FCompositor.FindWindow(targetWin);
  if compWin <> nil then
  begin
    compWin.IsVisible := True;
    compWin.UpdatePixmap();
    compWin.MarkDamaged();
  end
  else
    DoOnClientMapped(AClient);

  PaintClientFrame(AClient);
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
        // Move active window to top of stacking order in compositor
        FCompositor.Windows.Extract(compWin);
        FCompositor.Windows.Add(compWin);
      end;

      ApplyClientShadow(cli, compWin);
      ApplyClientCornerRadius(cli, compWin);
    end;
  end;

  // Ensure any transient children belonging to active client remain above it in compositor
  for i := 0 to Clients.Count - 1 do
  begin
    cli := TXCBWMClient(Clients[i]);
    if (cli <> AClient) and (cli.TransientFor = AClient.ClientWindow) and not (wsMinimized in cli.State) then
    begin
      if cli.IsReparented and (cli.FrameWindow <> 0) then
        targetWin := cli.FrameWindow
      else
        targetWin := cli.ClientWindow;
      compWin := FCompositor.FindWindow(targetWin);
      if compWin <> nil then
      begin
        FCompositor.Windows.Extract(compWin);
        FCompositor.Windows.Add(compWin);
      end;
    end;
  end;

  // Ensure all wsAbove windows remain at the very top of stacking order
  for i := 0 to Clients.Count - 1 do
  begin
    cli := TXCBWMClient(Clients[i]);
    if (cli <> AClient) and (wsAbove in cli.State) then
    begin
      if cli.IsReparented and (cli.FrameWindow <> 0) then
        targetWin := cli.FrameWindow
      else
        targetWin := cli.ClientWindow;
      compWin := FCompositor.FindWindow(targetWin);
      if compWin <> nil then
      begin
        FCompositor.Windows.Extract(compWin);
        FCompositor.Windows.Add(compWin);
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
    if IsClientShaded(AClient.ClientWindow) then
      compWin.UpdateGeometry(AClient.CurrentRect.X, AClient.CurrentRect.Y,
                             AClient.CurrentRect.Width, FTitlebarHeight)
    else
      compWin.UpdateGeometry(AClient.CurrentRect.X, AClient.CurrentRect.Y,
                             AClient.CurrentRect.Width, AClient.CurrentRect.Height);

    ApplyClientShadow(AClient, compWin);
    ApplyClientCornerRadius(AClient, compWin);
    compWin.MarkDamaged();
  end;

  PaintClientFrame(AClient);
  RequestComposite();
end;

procedure TWMSamaCompositingWM.DoOnFramePaint(const AClient: TXCBWMClient; const ARect: TXCBRect);
begin
  inherited DoOnFramePaint(AClient, ARect);
  PaintClientFrame(AClient);
end;

procedure TWMSamaCompositingWM.CalculateButtons(const AWidth: Integer; out AButtons: TWMSamaButtonArray; out ATitleX, ATitleW: Integer);
begin
  CalculateButtons(nil, AWidth, AButtons, ATitleX, ATitleW);
end;

procedure TWMSamaCompositingWM.CalculateButtons(const AClient: TXCBWMClient; const AWidth: Integer; out AButtons: TWMSamaButtonArray; out ATitleX, ATitleW: Integer);
var
  btnSize, gap, mLeft, mRight, btnY, curX: Double;
  leftCount, rightCount, i: Integer;
  totalRightWidth, rightStartX: Double;
  w: Integer;
  visibleItems: array of TWMSamaButtonLayoutItem;
  includeBtn: Boolean;
  visCount: Integer;
begin
  w := AWidth;
  if w <= 0 then
  begin
    if (Screen <> nil) and (Screen^.width_in_pixels > 0) then
      w := Screen^.width_in_pixels
    else
      w := 820;
  end;

  btnSize := Max(10.0, Round(FTitlebarHeight * 0.44));
  gap := Max(5.0, Round(btnSize * 0.50));
  mLeft := Max(8.0, Round(btnSize * 0.75));
  mRight := mLeft;
  btnY := (FTitlebarHeight - btnSize) * 0.5;

  // Filter visible layout items based on client capabilities/flags
  SetLength(visibleItems, Length(FButtonLayoutItems));
  visCount := 0;
  for i := 0 to High(FButtonLayoutItems) do
  begin
    includeBtn := True;
    if AClient <> nil then
    begin
      case FButtonLayoutItems[i].Kind of
        sbkClose:    includeBtn := AClient.HasCloseButton;
        sbkMinimize: includeBtn := AClient.HasMinimizeButton;
        sbkMaximize: includeBtn := AClient.HasMaximizeButton;
      end;
    end;
    if includeBtn then
    begin
      visibleItems[visCount] := FButtonLayoutItems[i];
      Inc(visCount);
    end;
  end;
  SetLength(visibleItems, visCount);

  SetLength(AButtons, Length(visibleItems));
  leftCount := 0;
  rightCount := 0;

  for i := 0 to High(visibleItems) do
  begin
    if visibleItems[i].Placement = bpLeft then
      Inc(leftCount)
    else
      Inc(rightCount);
  end;

  // 1. Position Left Buttons
  curX := mLeft;
  for i := 0 to High(visibleItems) do
  begin
    if visibleItems[i].Placement = bpLeft then
    begin
      AButtons[i].Kind := visibleItems[i].Kind;
      AButtons[i].Placement := bpLeft;
      AButtons[i].X := curX;
      AButtons[i].Y := btnY;
      AButtons[i].Size := btnSize;
      curX := curX + btnSize + gap;
    end;
  end;

  if leftCount > 0 then
    ATitleX := Round(curX - gap + mLeft + 2.0)
  else
    ATitleX := Round(mLeft + 3.0);

  // 2. Position Right Buttons
  if rightCount > 0 then
  begin
    totalRightWidth := (rightCount * btnSize) + ((rightCount - 1) * gap);
    rightStartX := w - mRight - totalRightWidth;
    curX := rightStartX;
    for i := 0 to High(visibleItems) do
    begin
      if visibleItems[i].Placement = bpRight then
      begin
        AButtons[i].Kind := visibleItems[i].Kind;
        AButtons[i].Placement := bpRight;
        AButtons[i].X := curX;
        AButtons[i].Y := btnY;
        AButtons[i].Size := btnSize;
        curX := curX + btnSize + gap;
      end;
    end;

    ATitleW := Max(0, Round(rightStartX - ATitleX - 8.0));
  end
  else
  begin
    ATitleW := Max(0, w - ATitleX - 8);
  end;
end;

procedure TWMSamaCompositingWM.GetWindowButtonMetrics(out ABtnSize, ABtnY, AX0, AX1, AX2: Double; out ATitleX: Integer);
var
  btns: TWMSamaButtonArray;
  tW: Integer;
begin
  CalculateButtons(820, btns, ATitleX, tW);
  ABtnSize := Max(10.0, Round(FTitlebarHeight * 0.44));
  ABtnY := (FTitlebarHeight - ABtnSize) * 0.5;
  AX0 := 11.0;
  AX1 := 34.0;
  AX2 := 57.0;
  if Length(btns) >= 3 then
  begin
    AX0 := btns[0].X;
    AX1 := btns[1].X;
    AX2 := btns[2].X;
  end;
end;

function TWMSamaCompositingWM.GetButtonAt(const AX, AY: Integer; const AWidth: Integer): Integer;
begin
  Result := GetButtonAt(AX, AY, nil, AWidth);
end;

function TWMSamaCompositingWM.GetButtonAt(const AX, AY: Integer; const AClient: TXCBWMClient; const AWidth: Integer): Integer;
var
  btns: TWMSamaButtonArray;
  tX, tW, i, w: Integer;
  pad: Double;
begin
  Result := -1;
  if (AY < 0) or (AY >= FTitlebarHeight) then Exit;

  w := AWidth;
  if (w <= 0) and (AClient <> nil) then
    w := AClient.CurrentRect.Width;
  if w <= 0 then w := 820;

  CalculateButtons(AClient, w, btns, tX, tW);
  pad := 3.0;

  for i := 0 to High(btns) do
  begin
    if (AY >= btns[i].Y - pad) and (AY <= btns[i].Y + btns[i].Size + pad) and
       (AX >= btns[i].X - pad) and (AX <= btns[i].X + btns[i].Size + pad) then
      Exit(i);
  end;
end;

function TWMSamaCompositingWM.IsTitlebarDraggable(const AX, AY, AWidth: Integer): Boolean;
begin
  Result := IsTitlebarDraggable(AX, AY, nil, AWidth);
end;

function TWMSamaCompositingWM.IsTitlebarDraggable(const AX, AY: Integer; const AClient: TXCBWMClient; const AWidth: Integer): Boolean;
var
  btns: TWMSamaButtonArray;
  tX, tW, i, w: Integer;
  leftEnd, rightStart: Double;
begin
  Result := False;
  if (AY < 0) or (AY >= FTitlebarHeight) then Exit;

  w := AWidth;
  if (w <= 0) and (AClient <> nil) then
    w := AClient.CurrentRect.Width;
  if w <= 0 then w := 820;

  CalculateButtons(AClient, w, btns, tX, tW);
  if GetButtonAt(AX, AY, AClient, w) >= 0 then Exit(False);

  leftEnd := 0.0;
  rightStart := w;

  for i := 0 to High(btns) do
  begin
    if btns[i].Placement = bpLeft then
    begin
      if btns[i].X + btns[i].Size > leftEnd then
        leftEnd := btns[i].X + btns[i].Size;
    end
    else
    begin
      if btns[i].X < rightStart then
        rightStart := btns[i].X;
    end;
  end;

  if leftEnd > 0 then leftEnd := leftEnd + 2.0;
  if rightStart < w then rightStart := rightStart - 2.0;

  Result := (AX >= leftEnd) and (AX <= rightStart);
end;

function TWMSamaCompositingWM.GetResizeModeForPoint(const AClient: TXCBWMClient; const ARootX, ARootY: Integer): TXCBDragMode;
var
  wx, wy, ww, wh: Integer;
  margin, cornerSize: Integer;
  inOuterX, inOuterY: Boolean;
  isLeft, isRight, isTop, isBottom: Boolean;
  isCornerLeft, isCornerRight, isCornerTop, isCornerBottom: Boolean;
begin
  Result := dmNone;
  if AClient = nil then Exit;

  // Windows that cannot resize never trigger resize modes
  if not AClient.CanResize then Exit;

  // Maximized and fullscreen windows cannot be resized
  if (wsMaximizedHorz in AClient.State) or (wsMaximizedVert in AClient.State) or
     (wsFullscreen in AClient.State) then
    Exit;

  wx := AClient.CurrentRect.X;
  wy := AClient.CurrentRect.Y;
  ww := AClient.CurrentRect.Width;
  wh := AClient.CurrentRect.Height;

  margin := 8;
  cornerSize := 16;

  // Tiled Right window: pinned to right screen edge; only allow resizing width on its left divider outer margin
  if wsTiledRight in AClient.State then
  begin
    // Left divider: outer margin [wx - margin .. wx)
    if (ARootX >= wx - margin) and (ARootX < wx) and (ARootY >= wy) and (ARootY < wy + wh) then
      Exit(dmResizeLeft);
    Exit;
  end;

  // Tiled Left window: pinned to left screen edge; only allow resizing width on its right divider outer margin
  if wsTiledLeft in AClient.State then
  begin
    // Right divider: outer margin [wx + ww .. wx + ww + margin)
    if (ARootX >= wx + ww) and (ARootX < wx + ww + margin) and (ARootY >= wy) and (ARootY < wy + wh) then
      Exit(dmResizeRight);
    Exit;
  end;

  // Floating Window:
  // Clicks INSIDE client content area NEVER trigger resize!
  // This guarantees that text selection inside xterm from column 0 or any edge is 100% protected.
  if (ARootX >= wx) and (ARootX < wx + ww) and (ARootY >= wy + FTitlebarHeight) and (ARootY < wy + wh) then
    Exit(dmNone);

  // Titlebar top edge and corners (on FrameWindow)
  if (ARootY >= wy) and (ARootY < wy + FTitlebarHeight) then
  begin
    // Top-Left corner (within cornerSize on titlebar)
    if (ARootX >= wx) and (ARootX < wx + cornerSize) and (ARootY < wy + cornerSize) then
      Exit(dmResizeTopLeft);
    // Top-Right corner (within cornerSize on titlebar)
    if (ARootX >= wx + ww - cornerSize) and (ARootX < wx + ww) and (ARootY < wy + cornerSize) then
      Exit(dmResizeTopRight);
    // Top edge (top 4px of titlebar)
    if (ARootX >= wx + cornerSize) and (ARootX < wx + ww - cornerSize) and (ARootY < wy + 4) then
      Exit(dmResizeTop);
    // Center / rest of titlebar is for dragging window position (dmNone)
    Exit(dmNone);
  end;

  // Check if point is within outer margin surrounding the window
  inOuterX := (ARootX >= wx - margin) and (ARootX < wx + ww + margin);
  inOuterY := (ARootY >= wy - margin) and (ARootY < wy + wh + margin);
  if not (inOuterX and inOuterY) then Exit(dmNone);

  isLeft   := (ARootX < wx);
  isRight  := (ARootX >= wx + ww);
  isTop    := (ARootY < wy);
  isBottom := (ARootY >= wy + wh);

  isCornerLeft   := (ARootX < wx + cornerSize);
  isCornerRight  := (ARootX >= wx + ww - cornerSize);
  isCornerTop    := (ARootY < wy + cornerSize);
  isCornerBottom := (ARootY >= wy + wh - cornerSize);

  // Outer Corners (8-directional)
  if (isLeft or isTop) and isCornerLeft and isCornerTop then
    Exit(dmResizeTopLeft);
  if (isRight or isTop) and isCornerRight and isCornerTop then
    Exit(dmResizeTopRight);
  if (isLeft or isBottom) and isCornerLeft and isCornerBottom then
    Exit(dmResizeBottomLeft);
  if (isRight or isBottom) and isCornerRight and isCornerBottom then
    Exit(dmResizeBottomRight);

  // Outer Edges
  if isTop then
    Exit(dmResizeTop);
  if isBottom then
    Exit(dmResizeBottom);
  if isLeft then
    Exit(dmResizeLeft);
  if isRight then
    Exit(dmResizeRight);
end;

procedure TWMSamaCompositingWM.ToggleKeepOnTop(const AClient: TXCBWMClient);
var
  targetWin: xcb_window_t;
  compWin: TXCBCompositedWindow;
  values: array[0..0] of Cardinal;
begin
  if AClient = nil then Exit;

  if wsAbove in AClient.State then
    AClient.State := AClient.State - [wsAbove]
  else
    AClient.State := AClient.State + [wsAbove];

  if AClient.IsReparented and (AClient.FrameWindow <> 0) then
    targetWin := AClient.FrameWindow
  else
    targetWin := AClient.ClientWindow;

  // Elevate in compositor stacking order
  if FCompositor <> nil then
  begin
    compWin := FCompositor.FindWindow(targetWin);
    if (compWin <> nil) and (wsAbove in AClient.State) then
    begin
      FCompositor.Windows.Extract(compWin);
      FCompositor.Windows.Add(compWin);
    end;
  end;

  // Elevate in X11
  if (Connection <> nil) and (wsAbove in AClient.State) then
  begin
    values[0] := XCB_STACK_MODE_ABOVE;
    xcb_configure_window(Connection, targetWin, XCB_CONFIG_WINDOW_STACK_MODE, @values[0]);
    xcb_flush(Connection);
  end;

  PaintClientFrame(AClient);
  RequestComposite();
end;

procedure TWMSamaCompositingWM.ToggleShade(const AClient: TXCBWMClient);
var
  i, idx, origH: Integer;
  targetWin: xcb_window_t;
  values: array[0..3] of Cardinal;
  r: TXCBRect;
  compWin: TXCBCompositedWindow;
begin
  if (AClient = nil) or not AClient.IsReparented or (AClient.FrameWindow = 0) then Exit;

  targetWin := AClient.ClientWindow;
  idx := -1;
  for i := 0 to High(FShadedWindows) do
    if FShadedWindows[i].WindowId = targetWin then
    begin
      idx := i;
      Break;
    end;

  if idx >= 0 then
  begin
    // Un-shade: restore original height
    origH := FShadedWindows[idx].OriginalHeight;
    for i := idx to High(FShadedWindows) - 1 do
      FShadedWindows[i] := FShadedWindows[i + 1];
    SetLength(FShadedWindows, Length(FShadedWindows) - 1);

    AClient.Resize(AClient.CurrentRect.Width, origH);
    if FCompositor <> nil then
    begin
      compWin := FCompositor.FindWindow(AClient.FrameWindow);
      if compWin <> nil then
        compWin.UpdateGeometry(AClient.CurrentRect.X, AClient.CurrentRect.Y,
                               AClient.CurrentRect.Width, origH);
    end;
  end
  else
  begin
    // Shade: record original height and collapse frame to titlebar height
    SetLength(FShadedWindows, Length(FShadedWindows) + 1);
    FShadedWindows[High(FShadedWindows)].WindowId := targetWin;
    FShadedWindows[High(FShadedWindows)].OriginalHeight := AClient.CurrentRect.Height;

    r := AClient.CurrentRect;
    r.Height := FTitlebarHeight;
    AClient.CurrentRect := r;
    if Connection <> nil then
    begin
      // Configure outer frame to titlebar height
      values[0] := AClient.CurrentRect.X;
      values[1] := AClient.CurrentRect.Y;
      values[2] := AClient.CurrentRect.Width;
      values[3] := FTitlebarHeight;
      xcb_configure_window(Connection, AClient.FrameWindow,
                           XCB_CONFIG_WINDOW_X or XCB_CONFIG_WINDOW_Y or
                           XCB_CONFIG_WINDOW_WIDTH or XCB_CONFIG_WINDOW_HEIGHT,
                           @values[0]);

      // Inner client window clipped below titlebar
      values[0] := 0;
      values[1] := FTitlebarHeight;
      values[2] := AClient.CurrentRect.Width;
      values[3] := 1;
      xcb_configure_window(Connection, targetWin,
                           XCB_CONFIG_WINDOW_X or XCB_CONFIG_WINDOW_Y or
                           XCB_CONFIG_WINDOW_WIDTH or XCB_CONFIG_WINDOW_HEIGHT,
                           @values[0]);
      xcb_flush(Connection);
    end;

    if FCompositor <> nil then
    begin
      compWin := FCompositor.FindWindow(AClient.FrameWindow);
      if compWin <> nil then
        compWin.UpdateGeometry(AClient.CurrentRect.X, AClient.CurrentRect.Y,
                               AClient.CurrentRect.Width, FTitlebarHeight);
    end;
  end;

  PaintClientFrame(AClient);
  RequestComposite();
end;

function TWMSamaCompositingWM.IsClientShaded(const AWin: xcb_window_t): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to High(FShadedWindows) do
    if FShadedWindows[i].WindowId = AWin then Exit(True);
end;

procedure TWMSamaCompositingWM.TriggerWindowMenu(const AClient: TXCBWMClient);
var
  btns: TWMSamaButtonArray;
  tX, tW, i, menuBtnX: Integer;
begin
  if (AClient = nil) or (FWindowMenuClient = AClient) then
  begin
    DismissWindowMenu();
    Exit;
  end;

  FWindowMenuClient := AClient;
  menuBtnX := 8;

  CalculateButtons(AClient, AClient.CurrentRect.Width, btns, tX, tW);
  for i := 0 to High(btns) do
    if btns[i].Kind = sbkMenu then
    begin
      menuBtnX := Round(btns[i].X);
      Break;
    end;

  FWindowMenuRect := TXCBRect.Create(
    Max(10, AClient.CurrentRect.X + menuBtnX - 4),
    AClient.CurrentRect.Y + FTitlebarHeight + 4,
    160,
    154
  );

  // Grab pointer so menu clicks anywhere on screen are intercepted by WM
  if (Connection <> nil) and (Screen <> nil) then
  begin
    xcb_grab_pointer(
      Connection,
      0,
      Screen^.root,
      XCB_EVENT_MASK_BUTTON_PRESS or XCB_EVENT_MASK_BUTTON_RELEASE or XCB_EVENT_MASK_POINTER_MOTION,
      XCB_GRAB_MODE_ASYNC,
      XCB_GRAB_MODE_ASYNC,
      XCB_NONE,
      XCB_NONE,
      XCB_CURRENT_TIME
    );
    xcb_flush(Connection);
  end;

  PaintClientFrame(AClient);
  RequestComposite();
end;

procedure TWMSamaCompositingWM.DismissWindowMenu();
var
  oldCli: TXCBWMClient;
begin
  if FWindowMenuClient <> nil then
  begin
    oldCli := FWindowMenuClient;
    FWindowMenuClient := nil;
    FWindowMenuRect := TXCBRect.Create(0, 0, 0, 0);

    if Connection <> nil then
    begin
      xcb_ungrab_pointer(Connection, XCB_CURRENT_TIME);
      xcb_flush(Connection);
    end;

    PaintClientFrame(oldCli);
    RequestComposite();
  end;
end;

procedure TWMSamaCompositingWM.PaintClientFrame(const AClient: TXCBWMClient);
var
  w, h, th, bw, i: Integer;
  isActive, isHoveredWin: Boolean;
  frameImg: TFloriaImage;
  canvas: TFloriaCanvasAgg;
  winTitle: AnsiString;
  dataLen: Cardinal;
  gc: xcb_gcontext_t;
  mask: Cardinal;
  values: array[0..0] of Cardinal;
  compWin: TXCBCompositedWindow;
  kindVal, btnState: Integer;
  btns: TWMSamaButtonArray;
  titleX, titleW: Integer;
begin
  if (AClient = nil) or not AClient.IsReparented or (AClient.FrameWindow = 0) or (wsMinimized in AClient.State) then Exit;

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
      CalculateButtons(AClient, w, btns, titleX, titleW);

      for i := 0 to High(btns) do
      begin
        isHoveredWin := (FHoveredWindow <> 0) and (FHoveredWindow = AClient.FrameWindow);
        if (FPressedWindow = AClient.FrameWindow) and (FPressedButton = i) and (FHoveredButton = i) then
          btnState := FT_BUTTON_STATE_PRESSED
        else if (FPressedButton = -1) and isHoveredWin and (FHoveredButton = i) then
          btnState := FT_BUTTON_STATE_HOVERED
        else if (btns[i].Kind = sbkPin) and (wsAbove in AClient.State) then
          btnState := FT_BUTTON_STATE_PRESSED
        else if (btns[i].Kind = sbkShade) and IsClientShaded(AClient.ClientWindow) then
          btnState := FT_BUTTON_STATE_PRESSED
        else
          btnState := FT_BUTTON_STATE_NORMAL;

        case btns[i].Kind of
          sbkClose:    kindVal := FT_WINDOW_BUTTON_CLOSE;
          sbkMinimize: kindVal := FT_WINDOW_BUTTON_MINIMIZE;
          sbkMaximize:
          begin
            if (wsMaximizedHorz in AClient.State) or (wsTiledLeft in AClient.State) or (wsTiledRight in AClient.State) then
              kindVal := FT_WINDOW_BUTTON_RESTORE
            else
              kindVal := FT_WINDOW_BUTTON_MAXIMIZE;
          end;
          sbkShade:    kindVal := FT_WINDOW_BUTTON_SHADE;
          sbkPin:      kindVal := FT_WINDOW_BUTTON_PIN;
          sbkMenu:     kindVal := FT_WINDOW_BUTTON_MENU;
        end;

        FtDrawWindowButton(canvas, btns[i].X, btns[i].Y, btns[i].Size, btns[i].Size,
                           kindVal, FWindowButtonStyle, btnState, FThemeDarkMode);
      end;

      // 3. Window title text (centered vertically with top and bottom margins)
      winTitle := AClient.Title;
      if winTitle = '' then
        winTitle := AClient.WindowClass;
      if winTitle = '' then
        winTitle := 'Window';

      if isActive then
        canvas.DrawTextLeft(titleX, 0, titleW, th, winTitle, nil, 236 / 255, 239 / 255, 244 / 255)
      else
        canvas.DrawTextLeft(titleX, 0, titleW, th, winTitle, nil, 127 / 255, 132 / 255, 156 / 255);
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
  FLastDragX := ARootX;
  FLastDragY := ARootY;
  inherited BeginDrag(AClient, AMode, ARootX, ARootY);
end;

procedure TWMSamaCompositingWM.UpdateDrag(const ARootX, ARootY: Integer);
var
  sw, sh, threshold, deltaDist: Integer;
  newX, newY: Integer;
  wa: TXCBRect;
  targetMon: TXCBMonitor;
  hasLeftNeighbor, hasRightNeighbor, hasTopNeighbor: Boolean;
begin
  deltaDist := Sqr(ARootX - FLastDragX) + Sqr(ARootY - FLastDragY);
  FLastDragX := ARootX;
  FLastDragY := ARootY;

  if (DragClient <> nil) and (DragMode = dmMove) and
     ((wsMaximizedHorz in DragClient.State) or (wsTiledLeft in DragClient.State) or (wsTiledRight in DragClient.State)) then
  begin
    DragClient.Restore();
    // Center title bar horizontally under cursor
    newX := ARootX - (DragClient.CurrentRect.Width div 2);
    // Position cursor in the middle of title bar vertically (clamp to top of target monitor workarea)
    targetMon := MonitorForPoint(ARootX, ARootY);
    if targetMon <> nil then
      newY := Max(targetMon.Workarea.Y, ARootY - (FTitlebarHeight div 2))
    else
      newY := Max(Workarea.Y, ARootY - (FTitlebarHeight div 2));

    DragClient.Move(newX, newY);
    UpdateDragOrigin(ARootX, ARootY, TXCBRect.Create(newX, newY, DragClient.CurrentRect.Width, DragClient.CurrentRect.Height));
  end;

  inherited UpdateDrag(ARootX, ARootY);

  if (DragClient = nil) or (DragMode <> dmMove) or (FCompositor = nil) then Exit;

  sw := FCompositor.ScreenWidth;
  sh := FCompositor.ScreenHeight;

  targetMon := MonitorForPoint(ARootX, ARootY);
  if targetMon <> nil then
    wa := targetMon.Workarea
  else
    wa := Workarea;

  if (wa.Width <= 0) or (wa.Height <= 0) then
    wa := TXCBRect.Create(0, 0, sw, sh);

  hasLeftNeighbor := (targetMon <> nil) and (AdjacentMonitor(targetMon, dirLeft) <> targetMon);
  hasRightNeighbor := (targetMon <> nil) and (AdjacentMonitor(targetMon, dirRight) <> targetMon);
  hasTopNeighbor := (targetMon <> nil) and (AdjacentMonitor(targetMon, dirUp) <> targetMon);

  threshold := 14;

  // Detect edge snapping triggers bounded by current monitor Workarea
  // If moving toward an interior boundary, high velocity (>20px/step, deltaDist > 400) passes through seamlessly;
  // slow motion / lingering (deltaDist <= 196, i.e. <= 14px) engages resistance and half-screen snap.
  if (ARootY <= wa.Y + threshold) and DragClient.CanMaximize then
  begin
    if (not hasTopNeighbor) or (deltaDist <= 196) then
    begin
      FActiveSnap := snapMaximize;
      FSnapPreviewRect := wa;
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
  end
  else if (ARootX <= wa.X + threshold) and DragClient.CanResize then
  begin
    if (not hasLeftNeighbor) or (deltaDist <= 196) then
    begin
      FActiveSnap := snapLeftHalf;
      FSnapPreviewRect := TXCBRect.Create(wa.X, wa.Y, wa.Width div 2, wa.Height);
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
  end
  else if (ARootX >= wa.Right() - threshold) and DragClient.CanResize then
  begin
    if (not hasRightNeighbor) or (deltaDist <= 196) then
    begin
      FActiveSnap := snapRightHalf;
      FSnapPreviewRect := TXCBRect.Create(wa.X + (wa.Width div 2), wa.Y, wa.Width - (wa.Width div 2), wa.Height);
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

procedure TWMSamaCompositingWM.DoOnMonitorsChanged();
var
  totalW, totalH, i: Integer;
  m: TXCBMonitor;
begin
  inherited DoOnMonitorsChanged();

  // Recompute root bounding box across all active monitors
  totalW := 0;
  totalH := 0;
  for i := 0 to MonitorCount - 1 do
  begin
    m := GetMonitor(i);
    if m <> nil then
    begin
      if m.Rect.Right() > totalW then totalW := m.Rect.Right();
      if m.Rect.Bottom() > totalH then totalH := m.Rect.Bottom();
    end;
  end;

  if (FCompositor <> nil) and (totalW > 0) and (totalH > 0) then
    FCompositor.Resize(totalW, totalH);

  RequestComposite();
end;

procedure TWMSamaCompositingWM.EndDrag();
var
  cli: TXCBWMClient;
  snap: TWMSnapTarget;
begin
  cli := DragClient;
  snap := FActiveSnap;

  FActiveSnap := snapNone;
  FSnapPreviewRect := TXCBRect.Create(0, 0, 0, 0);

  inherited EndDrag();

  if (cli <> nil) and (snap <> snapNone) and (FCompositor <> nil) then
  begin
    case snap of
      snapMaximize:
        cli.Maximize();
      snapLeftHalf:
        cli.TileLeft();
      snapRightHalf:
        cli.TileRight();
    end;
  end;

  if (Screen <> nil) and (CursorNormal <> 0) then
    UpdateHoverCursor(CursorNormal, Screen^.root);

  RequestComposite();
end;

procedure TWMSamaCompositingWM.UpdateHoverCursor(const ACursor: xcb_cursor_t; const AEventWindow: xcb_window_t);
var
  targetWin: xcb_window_t;
begin
  if (Connection = nil) or (ACursor = 0) then Exit;

  targetWin := AEventWindow;
  if (targetWin = 0) and (Screen <> nil) then
    targetWin := Screen^.root;

  if (targetWin = FHoverCursorWindow) and (ACursor = FHoverCursor) then Exit;

  FHoverCursorWindow := targetWin;
  FHoverCursor := ACursor;

  if (Screen <> nil) and (targetWin = Screen^.root) then
  begin
    if CurrentRootCursor <> ACursor then
    begin
      SetWindowCursor(Screen^.root, ACursor);
      CurrentRootCursor := ACursor;
    end;
  end
  else
  begin
    SetWindowCursor(targetWin, ACursor);
    if (Screen <> nil) and (CurrentRootCursor <> CursorNormal) then
    begin
      SetWindowCursor(Screen^.root, CursorNormal);
      CurrentRootCursor := CursorNormal;
    end;
  end;
end;

procedure TWMSamaCompositingWM.DoOnClientPropertiesChanged(const AClient: TXCBWMClient);
begin
  inherited DoOnClientPropertiesChanged(AClient);
  if AClient <> nil then
  begin
    PaintClientFrame(AClient);
    RequestComposite();
  end;
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
  targetMon: TXCBMonitor;
  hudArea: TXCBRect;
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
    targetMon := nil;
    if ActiveClient <> nil then
      targetMon := MonitorForClient(ActiveClient);
    if targetMon = nil then
      targetMon := PrimaryMonitor;
    if targetMon <> nil then
      hudArea := targetMon.Workarea
    else
      hudArea := Workarea;

    cardW := Min(hudArea.Width - 40, Max(360, Clients.Count * 130 + 40));
    cardH := 120;
    cardX := hudArea.X + (hudArea.Width - cardW) div 2;
    cardY := hudArea.Y + (hudArea.Height - cardH) div 2;

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

  // 3. Render Window Action Menu Overlay HUD
  if (FWindowMenuClient <> nil) and (FWindowMenuRect.Width > 0) then
  begin
    cardX := FWindowMenuRect.X;
    cardY := FWindowMenuRect.Y;
    cardW := FWindowMenuRect.Width;
    cardH := FWindowMenuRect.Height;

    ACanvas.DrawShadow(cardX, cardY, cardW, cardH, 12, 0, 4, 18, 0.0, 0.0, 0.0, 0.50);
    ACanvas.DrawRoundedRect(cardX, cardY, cardW, cardH, 10, 24 / 255, 25 / 255, 38 / 255, 0.96);
    ACanvas.DrawRoundedRectOutline(cardX, cardY, cardW, cardH, 10, 1.2, 69 / 255, 71 / 255, 90 / 255, 0.7);

    // Header
    ACanvas.DrawTextLeft(cardX + 12, cardY + 6, cardW - 24, 20, 'Window Actions', nil, 147 / 255, 153 / 255, 178 / 255);
    ACanvas.DrawLine(cardX + 8, cardY + 28, cardX + cardW - 8, cardY + 28, 1.0, 49 / 255, 50 / 255, 68 / 255, 0.8);

    // Items:
    // [0] Minimize
    ACanvas.DrawTextLeft(cardX + 14, cardY + 32, cardW - 28, 22, '—  Minimize', nil, 236 / 255, 239 / 255, 244 / 255);
    // [1] Maximize / Restore
    if (wsMaximizedHorz in FWindowMenuClient.State) or (wsTiledLeft in FWindowMenuClient.State) or (wsTiledRight in FWindowMenuClient.State) then
      ACanvas.DrawTextLeft(cardX + 14, cardY + 56, cardW - 28, 22, '⤡  Restore', nil, 236 / 255, 239 / 255, 244 / 255)
    else
      ACanvas.DrawTextLeft(cardX + 14, cardY + 56, cardW - 28, 22, '⤢  Maximize', nil, 236 / 255, 239 / 255, 244 / 255);
    // [2] Keep on Top (Pin)
    if wsAbove in FWindowMenuClient.State then
      ACanvas.DrawTextLeft(cardX + 14, cardY + 80, cardW - 28, 22, '✓  Always on Top', nil, 137 / 255, 180 / 255, 250 / 255)
    else
      ACanvas.DrawTextLeft(cardX + 14, cardY + 80, cardW - 28, 22, '•  Always on Top', nil, 205 / 255, 214 / 255, 244 / 255);
    // [3] Shade / Roll Up
    if IsClientShaded(FWindowMenuClient.ClientWindow) then
      ACanvas.DrawTextLeft(cardX + 14, cardY + 104, cardW - 28, 22, '✓  Roll Up (Shade)', nil, 137 / 255, 180 / 255, 250 / 255)
    else
      ACanvas.DrawTextLeft(cardX + 14, cardY + 104, cardW - 28, 22, '▴  Roll Up (Shade)', nil, 205 / 255, 214 / 255, 244 / 255);
    // Divider
    ACanvas.DrawLine(cardX + 8, cardY + 128, cardX + cardW - 8, cardY + 128, 1.0, 49 / 255, 50 / 255, 68 / 255, 0.8);
    // [4] Close
    ACanvas.DrawTextLeft(cardX + 14, cardY + 132, cardW - 28, 22, '×  Close Window', nil, 243 / 255, 139 / 255, 168 / 255);
  end;
end;

function TWMSamaCompositingWM.ProcessEvent(const AEvent: Pxcb_generic_event_t): Boolean;
var
  evType: Byte;
  btnEv: Pxcb_button_press_event_t;
  keyEv: Pxcb_key_press_event_t;
  motionEv: Pxcb_motion_notify_event_t;
  leaveEv: Pxcb_leave_notify_event_t;
  mapEv: Pxcb_map_notify_event_t;
  unmapEv: Pxcb_unmap_notify_event_t;
  destroyEv: Pxcb_destroy_notify_event_t;
  cfgNotifyEv: Pxcb_configure_notify_event_t;
  exposeEv: Pxcb_expose_event_t;
  geomCookie: xcb_get_geometry_cookie_t;
  geomReply: Pxcb_get_geometry_reply_t;
  geomRect: TXCBRect;
  compWin: TXCBCompositedWindow;
  cli, oldCli, menuCli, targetCli, candidateCli: TXCBWMClient;
  curMon, adjMon: TXCBMonitor;
  localX, localY, bw, th, newBtn: Integer;
  oldWin, pressedWin: xcb_window_t;
  btnIdx, releasedBtn, rx, ry, itemIdx, i: Integer;
  resizeMode: TXCBDragMode;
  btns: TWMSamaButtonArray;
  titleX, titleW: Integer;
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
      else if (keyEv^.detail = 65) then // Space (Alt+Space)
      begin
        menuCli := ActiveClient;
        if (menuCli = nil) and (Clients.Count > 0) then
          menuCli := TXCBWMClient(Clients[Clients.Count - 1]);
        if menuCli <> nil then
        begin
          TriggerWindowMenu(menuCli);
          Exit(True);
        end;
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
      end
      else if ((keyEv^.state and (64 or 1)) = (64 or 1)) and // Mod4 (Super) + Shift
              ((keyEv^.detail = 113) or (keyEv^.detail = 114) or (keyEv^.detail = 111) or (keyEv^.detail = 116)) then
      begin
        targetCli := ActiveClient;
        if targetCli <> nil then
        begin
          curMon := MonitorForClient(targetCli);
          if curMon <> nil then
          begin
            case keyEv^.detail of
              113: adjMon := AdjacentMonitor(curMon, dirLeft);
              114: adjMon := AdjacentMonitor(curMon, dirRight);
              111: adjMon := AdjacentMonitor(curMon, dirUp);
              116: adjMon := AdjacentMonitor(curMon, dirDown);
            else
              adjMon := curMon;
            end;
            if (adjMon <> nil) and (adjMon <> curMon) then
            begin
              MoveClientToMonitor(targetCli, adjMon);
              RequestComposite();
            end;
          end;
        end;
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
          newBtn := GetButtonAt(localX, localY, cli, cli.CurrentRect.Width);

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

        // Cursor hover detection on draggable resize margins
        targetCli := nil;
        resizeMode := dmNone;
        if (ActiveClient <> nil) and not (wsMinimized in ActiveClient.State) then
        begin
          resizeMode := GetResizeModeForPoint(ActiveClient, motionEv^.root_x, motionEv^.root_y);
          if resizeMode <> dmNone then
            targetCli := ActiveClient;
        end;

        if targetCli = nil then
        begin
          for i := Clients.Count - 1 downto 0 do
          begin
            candidateCli := TXCBWMClient(Clients[i]);
            if candidateCli.IsReparented and not (wsMinimized in candidateCli.State) then
            begin
              resizeMode := GetResizeModeForPoint(candidateCli, motionEv^.root_x, motionEv^.root_y);
              if resizeMode <> dmNone then
              begin
                targetCli := candidateCli;
                Break;
              end;
            end;
          end;
        end;

        if (targetCli <> nil) and (resizeMode <> dmNone) then
          UpdateHoverCursor(CursorForDragMode(resizeMode), motionEv^.event)
        else
          UpdateHoverCursor(CursorNormal, motionEv^.event);
      end;
    end;

    XCB_LEAVE_NOTIFY:
    begin
      leaveEv := Pxcb_leave_notify_event_t(AEvent);
      if leaveEv^.event = FHoverCursorWindow then
      begin
        FHoverCursorWindow := 0;
        FHoverCursor := 0;
      end;
      if (Screen <> nil) and (leaveEv^.event = Screen^.root) then
      begin
        CurrentRootCursor := 0;
      end;
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
      btnEv := Pxcb_button_release_event_t(AEvent);
      if (FPressedButton <> -1) and (btnEv^.detail = XCB_BUTTON_INDEX_1) then
      begin
        btnIdx := FPressedButton;
        pressedWin := FPressedWindow;
        FPressedButton := -1;
        FPressedWindow := 0;

        cli := FindClient(btnEv^.event);
        if (cli <> nil) and (cli.FrameWindow = pressedWin) then
        begin
          localX := btnEv^.event_x;
          localY := btnEv^.event_y;
          releasedBtn := GetButtonAt(localX, localY, cli, cli.CurrentRect.Width);

          FHoveredButton := releasedBtn;
          FHoveredWindow := cli.FrameWindow;
          PaintClientFrame(cli);
          RequestComposite();

          // ONLY trigger button action if released within the SAME button's click bound area!
          CalculateButtons(cli, cli.CurrentRect.Width, btns, titleX, titleW);
          if (releasedBtn = btnIdx) and (btnIdx >= 0) and (btnIdx <= High(btns)) then
          begin
            case btns[btnIdx].Kind of
              sbkClose: cli.Close();
              sbkMinimize: cli.Minimize();
              sbkMaximize:
              begin
                if (wsMaximizedHorz in cli.State) or (wsTiledLeft in cli.State) or (wsTiledRight in cli.State) then
                  cli.Restore()
                else if cli.CanMaximize then
                  cli.Maximize();
              end;
              sbkShade: ToggleShade(cli);
              sbkPin: ToggleKeepOnTop(cli);
              sbkMenu: TriggerWindowMenu(cli);
            end;
            Exit(True);
          end;
        end
        else
        begin
          if pressedWin <> 0 then
          begin
            oldCli := FindClient(pressedWin);
            if oldCli <> nil then
            begin
              FHoveredButton := -1;
              PaintClientFrame(oldCli);
            end;
          end;
          RequestComposite();
        end;
      end;
    end;

    XCB_BUTTON_PRESS:
    begin
      btnEv := Pxcb_button_press_event_t(AEvent);

      // Check if Window Menu HUD is active
      if (FWindowMenuClient <> nil) and (FWindowMenuRect.Width > 0) then
      begin
        rx := btnEv^.root_x;
        ry := btnEv^.root_y;
        if (rx >= FWindowMenuRect.X) and (rx < FWindowMenuRect.X + FWindowMenuRect.Width) and
           (ry >= FWindowMenuRect.Y) and (ry < FWindowMenuRect.Y + FWindowMenuRect.Height) then
        begin
          menuCli := FWindowMenuClient;
          DismissWindowMenu();
          if ry >= FWindowMenuRect.Y + 28 then
          begin
            itemIdx := (ry - (FWindowMenuRect.Y + 28)) div 24;
            case itemIdx of
              0: menuCli.Minimize();
              1:
              begin
                if (wsMaximizedHorz in menuCli.State) or (wsTiledLeft in menuCli.State) or (wsTiledRight in menuCli.State) then
                  menuCli.Restore()
                else
                  menuCli.Maximize();
              end;
              2: ToggleKeepOnTop(menuCli);
              3: ToggleShade(menuCli);
              4: menuCli.Close();
            end;
          end;
          Exit(True);
        end
        else
        begin
          DismissWindowMenu();
        end;
      end;

      // Check if clicked on outer resize margin on root window
      if (Screen <> nil) and (btnEv^.event = Screen^.root) and (btnEv^.detail = XCB_BUTTON_INDEX_1) then
      begin
        targetCli := nil;
        resizeMode := dmNone;
        if (ActiveClient <> nil) and not (wsMinimized in ActiveClient.State) then
        begin
          resizeMode := GetResizeModeForPoint(ActiveClient, btnEv^.root_x, btnEv^.root_y);
          if resizeMode <> dmNone then
            targetCli := ActiveClient;
        end;

        if targetCli = nil then
        begin
          for i := Clients.Count - 1 downto 0 do
          begin
            candidateCli := TXCBWMClient(Clients[i]);
            if candidateCli.IsReparented and not (wsMinimized in candidateCli.State) then
            begin
              resizeMode := GetResizeModeForPoint(candidateCli, btnEv^.root_x, btnEv^.root_y);
              if resizeMode <> dmNone then
              begin
                targetCli := candidateCli;
                Break;
              end;
            end;
          end;
        end;

        if (targetCli <> nil) and (resizeMode <> dmNone) then
        begin
          targetCli.Activate();
          BeginDrag(targetCli, resizeMode, btnEv^.root_x, btnEv^.root_y);
          Exit(True);
        end;
      end;

      cli := FindClient(btnEv^.event);
      if cli <> nil then
      begin
        // 0. Direct clicks on outer resize frame window (InputOnly window)
        if (cli.ResizeWindow <> 0) and (btnEv^.event = cli.ResizeWindow) and (btnEv^.detail = XCB_BUTTON_INDEX_1) then
        begin
          resizeMode := GetResizeModeForPoint(cli, btnEv^.root_x, btnEv^.root_y);
          if resizeMode <> dmNone then
          begin
            cli.Activate();
            BeginDrag(cli, resizeMode, btnEv^.root_x, btnEv^.root_y);
            Exit(True);
          end;
        end;

        // 1. Direct clicks on client application window (pass-through / click-to-focus)
        if btnEv^.event = cli.ClientWindow then
        begin
          // Check if this click falls in the outer resize zone of an overlapping window in front (e.g. ActiveClient)
          if (ActiveClient <> nil) and (ActiveClient <> cli) and
             not (wsMinimized in ActiveClient.State) and (btnEv^.detail = XCB_BUTTON_INDEX_1) then
          begin
            resizeMode := GetResizeModeForPoint(ActiveClient, btnEv^.root_x, btnEv^.root_y);
            if resizeMode <> dmNone then
            begin
              if Connection <> nil then
                xcb_allow_events(Connection, XCB_ALLOW_ASYNC_POINTER, btnEv^.time);
              BeginDrag(ActiveClient, resizeMode, btnEv^.root_x, btnEv^.root_y);
              Exit(True);
            end;
          end;

          // Alt + Left Click to move, Alt + Right Click to resize ANY window (including CSD windows)
          if (btnEv^.state and 8) <> 0 then
          begin
            cli.Activate();
            if Connection <> nil then
              xcb_allow_events(Connection, XCB_ALLOW_ASYNC_POINTER, btnEv^.time);
            if btnEv^.detail = XCB_BUTTON_INDEX_1 then
            begin
              BeginDrag(cli, dmMove, btnEv^.root_x, btnEv^.root_y);
              Exit(True);
            end
            else if btnEv^.detail = XCB_BUTTON_INDEX_3 then
            begin
              BeginDrag(cli, dmResize, btnEv^.root_x, btnEv^.root_y);
              Exit(True);
            end;
          end;

          // Pure client window click (inside xterm or app): activate client and replay pointer immediately!
          // (No resize inside ClientWindow, guaranteeing that text selection in xterm never accidentally triggers resize!)
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

          // A. Handle click on control dots (actions trigger on mouse button release)
          btnIdx := GetButtonAt(localX, localY, cli, cli.CurrentRect.Width);
          if (btnIdx >= 0) and (btnEv^.detail = XCB_BUTTON_INDEX_1) then
          begin
            FPressedButton := btnIdx;
            FPressedWindow := cli.FrameWindow;
            FHoveredButton := btnIdx;
            FHoveredWindow := cli.FrameWindow;
            PaintClientFrame(cli);
            RequestComposite();
            Exit(True);
          end;

          // B. Right-click on titlebar to resize window (legacy shortcut)
          if (localY >= 0) and (localY < th) and (btnEv^.detail = XCB_BUTTON_INDEX_3) and cli.CanResize then
          begin
            BeginDrag(cli, dmResize, btnEv^.root_x, btnEv^.root_y);
            Exit(True);
          end;

          // C. Handle perimeter resizing if cursor is in outer resize zone of an active window on top
          if (ActiveClient <> nil) and (ActiveClient <> cli) and
             not (wsMinimized in ActiveClient.State) and (btnEv^.detail = XCB_BUTTON_INDEX_1) then
          begin
            resizeMode := GetResizeModeForPoint(ActiveClient, btnEv^.root_x, btnEv^.root_y);
            if resizeMode <> dmNone then
            begin
              BeginDrag(ActiveClient, resizeMode, btnEv^.root_x, btnEv^.root_y);
              Exit(True);
            end;
          end;

          // D. Handle titlebar top edge and top corners resizing
          if (btnEv^.detail = XCB_BUTTON_INDEX_1) then
          begin
            resizeMode := GetResizeModeForPoint(cli, btnEv^.root_x, btnEv^.root_y);
            if resizeMode <> dmNone then
            begin
              BeginDrag(cli, resizeMode, btnEv^.root_x, btnEv^.root_y);
              Exit(True);
            end;
          end;

          // E. Handle Double-Click or drag on draggable titlebar area
          if (localY >= 0) and (localY < th) and IsTitlebarDraggable(localX, localY, cli, cli.CurrentRect.Width) and (btnEv^.detail = XCB_BUTTON_INDEX_1) then
          begin
            if (btnEv^.time - FLastClickTime < 350) and (FLastClickWindow = btnEv^.event) then
            begin
              if (wsMaximizedHorz in cli.State) or (wsTiledLeft in cli.State) or (wsTiledRight in cli.State) then
                cli.Restore()
              else if cli.CanMaximize then
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

          // E. Handle Border Resizing when border width > 0
          if (bw > 0) and ((localY >= th) or (localX < bw) or (localX >= cli.CurrentRect.Width - bw) or (localY >= cli.CurrentRect.Height - bw)) then
          begin
            BeginDrag(cli, dmResize, btnEv^.root_x, btnEv^.root_y);
            Exit(True);
          end;
        end;
      end;
    end;

    XCB_MAP_NOTIFY:
    begin
      mapEv := Pxcb_map_notify_event_t(AEvent);
      if (Connection <> nil) and (Screen <> nil) and
         (mapEv^.window <> Screen^.root) and (FindClient(mapEv^.window) = nil) then
      begin
        // If this is an override-redirect window (popup menu, dropdown, combobox, tooltip)
        if (mapEv^.override_redirect <> 0) and (FCompositor <> nil) then
        begin
          geomCookie := xcb_get_geometry(Connection, mapEv^.window);
          geomReply := xcb_get_geometry_reply(Connection, geomCookie, nil);
          if geomReply <> nil then
          begin
            try
              geomRect := TXCBRect.Create(geomReply^.x, geomReply^.y, geomReply^.width, geomReply^.height);
              if (geomRect.Width > 1) and (geomRect.Height > 1) then
              begin
                compWin := FCompositor.RegisterWindow(mapEv^.window, geomRect, 0);
                if compWin <> nil then
                begin
                  if IsWindowMenu(mapEv^.window) then
                  begin
                    compWin.CornerRadius := 6;
                    compWin.BottomCornerRadius := 6;
                    compWin.ShadowConfig := TXCBWindowShadowConfig.Create(FShadowEnabled, 10, 1, 0.20);
                  end
                  else
                  begin
                    compWin.CornerRadius := 0;
                    compWin.BottomCornerRadius := 0;
                    compWin.ShadowConfig := TXCBWindowShadowConfig.Create(False, 0, 0, 0.0);
                  end;
                  // Float popup menu to top of compositor stacking order
                  FCompositor.Windows.Extract(compWin);
                  FCompositor.Windows.Add(compWin);
                  compWin.MarkDamaged();
                  RequestComposite();
                end;
              end;
            finally
              xcb_free(geomReply);
            end;
          end;
        end;
      end;
    end;

    XCB_UNMAP_NOTIFY:
    begin
      unmapEv := Pxcb_unmap_notify_event_t(AEvent);
      if FCompositor <> nil then
      begin
        compWin := FCompositor.FindWindow(unmapEv^.window);
        if (compWin <> nil) and (compWin.FrameWindow = 0) and (FindClient(unmapEv^.window) = nil) then
        begin
          FCompositor.UnregisterWindow(unmapEv^.window);
          RequestComposite();
        end;
      end;
    end;

    XCB_DESTROY_NOTIFY:
    begin
      destroyEv := Pxcb_destroy_notify_event_t(AEvent);
      if FCompositor <> nil then
      begin
        compWin := FCompositor.FindWindow(destroyEv^.window);
        if (compWin <> nil) and (compWin.FrameWindow = 0) and (FindClient(destroyEv^.window) = nil) then
        begin
          FCompositor.UnregisterWindow(destroyEv^.window);
          RequestComposite();
        end;
      end;
    end;

    XCB_CONFIGURE_NOTIFY:
    begin
      cfgNotifyEv := Pxcb_configure_notify_event_t(AEvent);
      if FCompositor <> nil then
      begin
        compWin := FCompositor.FindWindow(cfgNotifyEv^.window);
        if (compWin <> nil) and (compWin.FrameWindow = 0) and (FindClient(cfgNotifyEv^.window) = nil) then
        begin
          compWin.UpdateGeometry(cfgNotifyEv^.x, cfgNotifyEv^.y, cfgNotifyEv^.width, cfgNotifyEv^.height);
          compWin.MarkDamaged();
          RequestComposite();
        end;
      end;
    end;

    XCB_EXPOSE:
    begin
      exposeEv := Pxcb_expose_event_t(AEvent);
      if FCompositor <> nil then
      begin
        compWin := FCompositor.FindWindow(exposeEv^.window);
        if compWin <> nil then
        begin
          compWin.MarkDamaged();
          RequestComposite();
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
