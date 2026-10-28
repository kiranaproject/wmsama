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

    // Keyboard grab ownership for the Alt+Tab switcher.
    // A single flag governs acquire/release so the grab and the HUD state can
    // never diverge: FKeyboardGrabHeld is the only thing any release path checks.
    FKeyboardGrabHeld   : Boolean;
    FGrabAttempts       : Integer;
    FReleaseAttempts    : Integer;

    // Cached titlebar GC. One GC is enough for every frame: they all share the
    // same root and depth. Creating and freeing one per paint cost two round-trip
    // requests per frame on every focus change.
    FTitlebarGC         : xcb_gcontext_t;

    // Last client whose frame was painted as active. Lets a focus change repaint
    // only the two frames whose appearance actually changed.
    FLastActiveClient   : TXCBWMClient;

    // Diagnostics
    FDebugEnabled       : Boolean;
    // Counts PaintClientFrame calls. Used by tests to prove that a focus change
    // repaints only the affected frames rather than every window.
    FFramePaintCount    : Integer;

    // Drag velocity tracking
    FLastDragX          : Integer;
    FLastDragY          : Integer;

    function AcquireKeyboardGrab(): Boolean;

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
    procedure DoOnTick(const AElapsedMs: Integer); override;
  public
    function IsWindowMenu(const AWindow: xcb_window_t): Boolean;
    procedure ApplyClientCornerRadius(const AClient: TXCBWMClient; const ACompWin: TXCBCompositedWindow);
    procedure ApplyClientShadow(const AClient: TXCBWMClient; const ACompWin: TXCBCompositedWindow);
    procedure UpdateAllWindowShadows();

    constructor Create(AConn: Pxcb_connection_t = nil; const AScreenNum: Integer = 0);
    destructor Destroy(); override;

    function ClaimOwnership(): Boolean; override;
    procedure GrabGlobalKeys();
    procedure RebindGlobalKeys(); override;
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
    procedure UpdateHoverCursor(const ACursor: xcb_cursor_t; const AClient: TXCBWMClient);
    procedure DoOnClientPropertiesChanged(const AClient: TXCBWMClient); override;

    // Alt+Tab HUD controls
    function IsAltTabEligible(const AClient: TXCBWMClient): Boolean;
    procedure GetAltTabEligibleClients(const AList: TFPList);
    procedure TriggerAltTabForward();
    procedure TriggerAltTabDismiss();
    procedure CancelAltTab();
    procedure ReleaseKeyboardGrab();

    // Diagnostics
    // Single funnel for debug output. Flushes explicitly: FPC buffers StdErr, and
    // buffered diagnostics once led to a wrong conclusion about the event pump.
    procedure DebugLog(const AMsg: AnsiString);
    function DescribeXError(const AError: Pxcb_generic_error_t): AnsiString;
    procedure LogXError(const AError: Pxcb_generic_error_t; const AContext: AnsiString);

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
    property KeyboardGrabHeld   : Boolean        read FKeyboardGrabHeld;
    property KeyboardGrabAttempts    : Integer   read FGrabAttempts;
    property KeyboardReleaseAttempts : Integer   read FReleaseAttempts;
    property DebugEnabled       : Boolean        read FDebugEnabled        write FDebugEnabled;
    property HoveredButton      : Integer        read FHoveredButton;
    property HoveredWindow      : xcb_window_t   read FHoveredWindow;
    // The window currently carrying the hover cursor. Must only ever be the root
    // or a frame window, never a client window (see UpdateHoverCursor).
    property HoverCursorWindow  : xcb_window_t   read FHoverCursorWindow;
    property FramePaintCount    : Integer        read FFramePaintCount;
    // Cached titlebar GC. Zero until the first paint on a live connection.
    property TitlebarGC         : xcb_gcontext_t read FTitlebarGC;
    property PressedButton      : Integer        read FPressedButton;
    property PressedWindow      : xcb_window_t   read FPressedWindow;
  end;

implementation

function XErrorName(const ACode: Byte): AnsiString;
begin
  case ACode of
    1:  Result := 'BadRequest';
    2:  Result := 'BadValue';
    3:  Result := 'BadWindow';
    4:  Result := 'BadPixmap';
    5:  Result := 'BadAtom';
    6:  Result := 'BadCursor';
    7:  Result := 'BadFont';
    8:  Result := 'BadMatch';
    9:  Result := 'BadDrawable';
    10: Result := 'BadAccess';
    11: Result := 'BadAlloc';
    12: Result := 'BadColormap';
    13: Result := 'BadGContext';
    14: Result := 'BadIDChoice';
    15: Result := 'BadName';
    16: Result := 'BadLength';
    17: Result := 'BadImplementation';
  else
    Result := 'Unknown';
  end;
end;

function XRequestName(const AMajor: Byte): AnsiString;
begin
  // Core protocol opcodes (X11 Protocol, Appendix A). Extension requests start at
  // 128, so anything above that is reported relative to its extension opcode.
  case AMajor of
    1:   Result := 'CreateWindow';
    2:   Result := 'ChangeWindowAttributes';
    3:   Result := 'GetWindowAttributes';
    4:   Result := 'DestroyWindow';
    5:   Result := 'DestroySubwindows';
    6:   Result := 'ChangeSaveSet';
    7:   Result := 'ReparentWindow';
    8:   Result := 'MapWindow';
    9:   Result := 'UnmapWindow';
    10:  Result := 'MapSubwindows';
    11:  Result := 'UnmapSubwindows';
    12:  Result := 'ConfigureWindow';
    13:  Result := 'CirculateWindow';
    14:  Result := 'GetGeometry';
    15:  Result := 'QueryTree';
    16:  Result := 'InternAtom';
    17:  Result := 'GetAtomName';
    18:  Result := 'ChangeProperty';
    19:  Result := 'DeleteProperty';
    20:  Result := 'GetProperty';
    21:  Result := 'ListProperties';
    22:  Result := 'SetSelectionOwner';
    23:  Result := 'GetSelectionOwner';
    24:  Result := 'ConvertSelection';
    25:  Result := 'SendEvent';
    26:  Result := 'GrabPointer';
    27:  Result := 'UngrabPointer';
    28:  Result := 'GrabButton';
    29:  Result := 'UngrabButton';
    30:  Result := 'ChangeActivePointerGrab';
    31:  Result := 'GrabKeyboard';
    32:  Result := 'UngrabKeyboard';
    33:  Result := 'GrabKey';
    34:  Result := 'UngrabKey';
    35:  Result := 'AllowEvents';
    36:  Result := 'GrabServer';
    37:  Result := 'UngrabServer';
    38:  Result := 'QueryPointer';
    39:  Result := 'GetMotionEvents';
    40:  Result := 'TranslateCoordinates';
    41:  Result := 'WarpPointer';
    42:  Result := 'SetInputFocus';
    43:  Result := 'GetInputFocus';
    44:  Result := 'QueryKeymap';
    45:  Result := 'OpenFont';
    46:  Result := 'CloseFont';
    47:  Result := 'QueryFont';
    48:  Result := 'QueryTextExtents';
    49:  Result := 'ListFonts';
    50:  Result := 'ListFontsWithInfo';
    51:  Result := 'SetFontPath';
    52:  Result := 'GetFontPath';
    53:  Result := 'CreatePixmap';
    54:  Result := 'FreePixmap';
    55:  Result := 'CreateGC';
    56:  Result := 'ChangeGC';
    57:  Result := 'CopyGC';
    58:  Result := 'SetDashes';
    59:  Result := 'SetClipRectangles';
    60:  Result := 'FreeGC';
    61:  Result := 'ClearArea';
    62:  Result := 'CopyArea';
    63:  Result := 'CopyPlane';
    64:  Result := 'PolyPoint';
    65:  Result := 'PolyLine';
    66:  Result := 'PolySegment';
    67:  Result := 'PolyRectangle';
    68:  Result := 'PolyArc';
    69:  Result := 'FillPoly';
    70:  Result := 'PolyFillRectangle';
    71:  Result := 'PolyFillArc';
    72:  Result := 'PutImage';
    73:  Result := 'GetImage';
    74:  Result := 'PolyText8';
    75:  Result := 'PolyText16';
    76:  Result := 'ImageText8';
    77:  Result := 'ImageText16';
    78:  Result := 'CreateColormap';
    79:  Result := 'FreeColormap';
    80:  Result := 'CopyColormapAndFree';
    81:  Result := 'InstallColormap';
    82:  Result := 'UninstallColormap';
    83:  Result := 'ListInstalledColormaps';
    84:  Result := 'AllocColor';
    85:  Result := 'AllocNamedColor';
    86:  Result := 'AllocColorCells';
    87:  Result := 'AllocColorPlanes';
    88:  Result := 'FreeColors';
    89:  Result := 'StoreColors';
    90:  Result := 'StoreNamedColor';
    91:  Result := 'QueryColors';
    92:  Result := 'LookupColor';
    93:  Result := 'CreateCursor';
    94:  Result := 'CreateGlyphCursor';
    95:  Result := 'FreeCursor';
    96:  Result := 'RecolorCursor';
    97:  Result := 'QueryBestSize';
    98:  Result := 'QueryExtension';
    99:  Result := 'ListExtensions';
    100: Result := 'ChangeKeyboardMapping';
    101: Result := 'GetKeyboardMapping';
    102: Result := 'ChangeKeyboardControl';
    103: Result := 'GetKeyboardControl';
    104: Result := 'Bell';
    105: Result := 'ChangePointerControl';
    106: Result := 'GetPointerControl';
    107: Result := 'SetScreenSaver';
    108: Result := 'GetScreenSaver';
    109: Result := 'ChangeHosts';
    110: Result := 'ListHosts';
    111: Result := 'SetAccessControl';
    112: Result := 'SetCloseDownMode';
    113: Result := 'KillClient';
    114: Result := 'RotateProperties';
    115: Result := 'ForceScreenSaver';
    116: Result := 'SetPointerMapping';
    117: Result := 'GetPointerMapping';
    118: Result := 'SetModifierMapping';
    119: Result := 'GetModifierMapping';
    120: Result := 'NoOperation';
  else
    if AMajor >= 128 then
      Result := 'Extension+' + IntToStr(AMajor - 128)
    else
      Result := 'Opcode' + IntToStr(AMajor);
  end;
end;

procedure TWMSamaCompositingWM.DebugLog(const AMsg: AnsiString);
begin
  if not FDebugEnabled then Exit;
  WriteLn(StdErr, '[wmsama] ', AMsg);
  Flush(StdErr);
end;

// Decode a generic X error into a single human-readable line.
function TWMSamaCompositingWM.DescribeXError(const AError: Pxcb_generic_error_t): AnsiString;
begin
  Result := '';
  if AError = nil then Exit;

  Result := Format('X error %s (%d) on request %s (%d) minor=%d resource=0x%.8x seq=%d',
    [XErrorName(AError^.error_code), AError^.error_code,
     XRequestName(AError^.major_code), AError^.major_code,
     AError^.minor_code, AError^.resource_id, AError^.full_sequence]);
end;

// Errors arrive as events with response_type = 0. Without this they are silently
// dropped by the event case statement, which turns every failed request into an
// untraceable cosmetic glitch.
procedure TWMSamaCompositingWM.LogXError(const AError: Pxcb_generic_error_t; const AContext: AnsiString);
begin
  if AError = nil then Exit;
  DebugLog(AContext + ': ' + DescribeXError(AError));
end;

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

  FKeyboardGrabHeld := False;
  FGrabAttempts := 0;
  FReleaseAttempts := 0;
  FTitlebarGC := 0;
  FLastActiveClient := nil;
  FFramePaintCount := 0;
  FDebugEnabled := GetEnvironmentVariable('WMSAMA_DEBUG') <> '';

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
  // Never leave the keyboard grabbed across a teardown.
  ReleaseKeyboardGrab();

  if (Connection <> nil) and (FTitlebarGC <> 0) then
  begin
    xcb_free_gc(Connection, FTitlebarGC);
    FTitlebarGC := 0;
  end;

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
var
  altMods: array[0..3] of Word;
  superMods: array[0..3] of Word;
  i: Integer;
begin
  if (Connection = nil) or (Screen = nil) then Exit;

  // Keycodes and modifier masks come from the server (ResolveKeyBindings), not
  // from hardcoded evdev assumptions, so a non-US layout still binds correctly.
  if not KeyBindingsValid then
    ResolveKeyBindings();

  if (KeycodeTab = 0) or (ModAlt = 0) then
  begin
    DebugLog('key bindings unavailable; Alt+Tab not grabbed');
    Exit;
  end;

  altMods[0] := ModAlt;
  altMods[1] := ModAlt or ModNumLock;
  altMods[2] := ModAlt or ModCapsLock;
  altMods[3] := ModAlt or ModNumLock or ModCapsLock;

  superMods[0] := ModSuper;
  superMods[1] := ModSuper or ModNumLock;
  superMods[2] := ModSuper or ModCapsLock;
  superMods[3] := ModSuper or ModNumLock or ModCapsLock;

  for i := 0 to 3 do
  begin
    xcb_grab_key(Connection, 1, Screen^.root, altMods[i], KeycodeTab,
                 XCB_GRAB_MODE_ASYNC, XCB_GRAB_MODE_ASYNC);
    if KeycodeSpace <> 0 then
      xcb_grab_key(Connection, 1, Screen^.root, altMods[i], KeycodeSpace,
                   XCB_GRAB_MODE_ASYNC, XCB_GRAB_MODE_ASYNC);

    // Multi-monitor keyboard navigation: Super + Shift + Arrow keys
    if ModSuper <> 0 then
    begin
      if KeycodeLeft <> 0 then
        xcb_grab_key(Connection, 1, Screen^.root, superMods[i] or XCB_MOD_MASK_SHIFT,
                     KeycodeLeft, XCB_GRAB_MODE_ASYNC, XCB_GRAB_MODE_ASYNC);
      if KeycodeRight <> 0 then
        xcb_grab_key(Connection, 1, Screen^.root, superMods[i] or XCB_MOD_MASK_SHIFT,
                     KeycodeRight, XCB_GRAB_MODE_ASYNC, XCB_GRAB_MODE_ASYNC);
      if KeycodeUp <> 0 then
        xcb_grab_key(Connection, 1, Screen^.root, superMods[i] or XCB_MOD_MASK_SHIFT,
                     KeycodeUp, XCB_GRAB_MODE_ASYNC, XCB_GRAB_MODE_ASYNC);
      if KeycodeDown <> 0 then
        xcb_grab_key(Connection, 1, Screen^.root, superMods[i] or XCB_MOD_MASK_SHIFT,
                     KeycodeDown, XCB_GRAB_MODE_ASYNC, XCB_GRAB_MODE_ASYNC);
    end;
  end;

  xcb_flush(Connection);
end;

// Called by the base class after a MappingNotify: drop the old grabs and re-issue
// them against the new mapping. Without this a layout switch silently kills every
// binding, because a passive grab on a keycode that is no longer mapped never fires.
procedure TWMSamaCompositingWM.RebindGlobalKeys();
begin
  if (Connection = nil) or (Screen = nil) then Exit;

  // Ungrab everything this client holds on the root before re-resolving, so stale
  // grabs do not accumulate across layout switches. XCB_GRAB_ANY with
  // XCB_MOD_MASK_ANY matches every key/modifier combination.
  xcb_ungrab_key(Connection, XCB_GRAB_ANY, Screen^.root, XCB_MOD_MASK_ANY);

  ResolveKeyBindings();
  GrabGlobalKeys();

  DebugLog('key bindings re-resolved after mapping change');
end;

// Acquire the active keyboard grab used by the Alt+Tab switcher.
// Returns True only when the WM really holds the grab, so callers never mark the
// switcher active on a refused grab (BadAccess / AlreadyGrabbed).
function TWMSamaCompositingWM.AcquireKeyboardGrab(): Boolean;
var
  cookie: xcb_grab_keyboard_cookie_t;
  reply: Pxcb_grab_keyboard_reply_t;
begin
  Result := False;
  if FKeyboardGrabHeld then Exit(True);

  Inc(FGrabAttempts);

  if (Connection = nil) or (Screen = nil) then
  begin
    // Offline / headless (unit tests, or before xcb_connect): there is no server
    // to contend with, so the switcher runs on logical ownership alone.
    FKeyboardGrabHeld := True;
    Exit(True);
  end;

  cookie := xcb_grab_keyboard(Connection, 1, Screen^.root, XCB_CURRENT_TIME,
                              XCB_GRAB_MODE_ASYNC, XCB_GRAB_MODE_ASYNC);
  reply := xcb_grab_keyboard_reply(Connection, cookie, nil);
  if reply = nil then
  begin
    DebugLog('xcb_grab_keyboard: no reply');
    Exit;
  end;

  try
    if reply^.status <> XCB_GRAB_STATUS_SUCCESS then
    begin
      DebugLog('xcb_grab_keyboard refused, status=' + IntToStr(reply^.status));
      Exit;
    end;
  finally
    xcb_free(reply);
  end;

  FKeyboardGrabHeld := True;
  Result := True;
end;

// Release the keyboard grab. Idempotent and safe to call at any time: this is the
// single place that clears FKeyboardGrabHeld, so every exit path from the switcher
// (Escape, Return, Alt release, client unmap, shutdown) funnels through it.
procedure TWMSamaCompositingWM.ReleaseKeyboardGrab();
begin
  if not FKeyboardGrabHeld then Exit;

  Inc(FReleaseAttempts);

  if (Connection <> nil) then
  begin
    xcb_ungrab_keyboard(Connection, XCB_CURRENT_TIME);
    xcb_flush(Connection);
  end;

  FKeyboardGrabHeld := False;
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
    if AClient.WindowType = wtDesktop then
    begin
      // Desktop windows must be pinned to the absolute bottom of compositor stack
      FCompositor.Windows.Extract(compWin);
      FCompositor.Windows.Insert(0, compWin);
    end;

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

  // FLastActiveClient must never outlive the client it points at.
  if FLastActiveClient = AClient then
    FLastActiveClient := nil;

  // A window disappearing mid-switch would leave the HUD pointing at a dead
  // client; drop the switcher (and its grab) instead.
  if FAltTabActive then
    CancelAltTab();

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
        if cli.WindowType = wtDesktop then
        begin
          // Desktop background stays at absolute bottom
          FCompositor.Windows.Extract(compWin);
          FCompositor.Windows.Insert(0, compWin);
        end
        else
        begin
          // Move active window to top of stacking order in compositor
          FCompositor.Windows.Extract(compWin);
          FCompositor.Windows.Add(compWin);
        end;
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

  // Ensure all wtDesktop windows remain at the very bottom of stacking order
  for i := 0 to Clients.Count - 1 do
  begin
    cli := TXCBWMClient(Clients[i]);
    if cli.WindowType = wtDesktop then
    begin
      if cli.IsReparented and (cli.FrameWindow <> 0) then
        targetWin := cli.FrameWindow
      else
        targetWin := cli.ClientWindow;
      compWin := FCompositor.FindWindow(targetWin);
      if compWin <> nil then
      begin
        FCompositor.Windows.Extract(compWin);
        FCompositor.Windows.Insert(0, compWin);
      end;
    end;
  end;

  // Repaint only the frames whose active appearance actually changed: the frame
  // that just lost focus and the one that gained it. Painting every frame on each
  // focus change meant a full titlebar rasterisation per window per click.
  if (FLastActiveClient <> nil) and (FLastActiveClient <> AClient) and
     (FLastActiveClient.FrameWindow <> 0) then
    PaintClientFrame(FLastActiveClient);
  if AClient <> nil then
    PaintClientFrame(AClient);
  FLastActiveClient := AClient;
  if Connection <> nil then
    xcb_flush(Connection);

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

  Inc(FFramePaintCount);

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
      // Reuse one GC for every frame. It is created against the root window
      // because all frames share the same root and depth, so a single GC is valid
      // for all of them; the old code created and destroyed one per paint.
      if FTitlebarGC = 0 then
      begin
        FTitlebarGC := xcb_generate_id(Connection);
        mask := 0;
        xcb_create_gc(Connection, FTitlebarGC, RootWindow, mask, @values[0]);
      end;

      dataLen := Cardinal(w * th * 4);
      xcb_put_image(Connection, XCB_IMAGE_FORMAT_Z_PIXMAP, AClient.FrameWindow, FTitlebarGC,
                    w, th, 0, 0, 0, 24, dataLen, PByte(frameImg.Data));
      // Flushing per frame would be a round-trip per window during a focus change;
      // callers flush once after their batch (see PaintAllFrames / DoOnClientActivated).
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
  // PaintClientFrame no longer flushes; one flush covers the whole batch.
  if Connection <> nil then
    xcb_flush(Connection);
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

  if CursorNormal <> 0 then
    UpdateHoverCursor(CursorNormal, nil);

  RequestComposite();
end;

// Apply a hover cursor.
//
// Cursor state belongs to windows the WM owns: the root and frame windows. It is
// never written onto a client window. X resolves the cursor from the innermost
// window under the pointer, so setting one on a client window permanently
// overwrites the application's own cursor — the I-beam in a terminal, the hand
// over a link — and the application has no way to take it back.
//
// AClient is the client whose frame should carry the cursor, or nil for the root.
// Passing nil (or a client without a frame) restores the root cursor.
procedure TWMSamaCompositingWM.UpdateHoverCursor(const ACursor: xcb_cursor_t; const AClient: TXCBWMClient);
var
  targetWin, prevWin: xcb_window_t;
begin
  if Connection = nil then Exit;

  if (AClient <> nil) and (AClient.FrameWindow <> 0) then
    targetWin := AClient.FrameWindow
  else if Screen <> nil then
    targetWin := Screen^.root
  else
    Exit;

  if (targetWin = FHoverCursorWindow) and (ACursor = FHoverCursor) then Exit;

  prevWin := FHoverCursorWindow;
  FHoverCursorWindow := targetWin;
  FHoverCursor := ACursor;

  // Reset the window we were decorating, so a stale resize cursor does not linger
  // on a frame after the pointer has moved on.
  if (prevWin <> 0) and (prevWin <> targetWin) then
  begin
    if (Screen <> nil) and (prevWin = Screen^.root) then
    begin
      SetWindowCursor(Screen^.root, CursorNormal);
      CurrentRootCursor := CursorNormal;
    end
    else if CursorNormal <> 0 then
      SetWindowCursor(prevWin, CursorNormal);
  end;

  if (Screen <> nil) and (targetWin = Screen^.root) then
  begin
    if CurrentRootCursor <> ACursor then
    begin
      SetWindowCursor(Screen^.root, ACursor);
      CurrentRootCursor := ACursor;
    end;
  end
  else
    SetWindowCursor(targetWin, ACursor);
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

function TWMSamaCompositingWM.IsAltTabEligible(const AClient: TXCBWMClient): Boolean;
begin
  if AClient = nil then Exit(False);
  // Exclude desktop background, docks/panels, splashes, menus, tooltips, notifications
  if AClient.WindowType in [wtDesktop, wtDock, wtSplash, wtMenu, wtDropdownMenu, wtPopupMenu, wtTooltip, wtNotification, wtCombo, wtDnd] then
    Exit(False);
  Result := True;
end;

procedure TWMSamaCompositingWM.GetAltTabEligibleClients(const AList: TFPList);
var
  i: Integer;
  cli: TXCBWMClient;
begin
  if AList = nil then Exit;
  AList.Clear();

  // MRU order first: index 0 is the current window, index 1 the previous one.
  // That is what makes a single Alt+Tab mean "go back to what I was using".
  for i := 0 to MruClients.Count - 1 do
  begin
    cli := TXCBWMClient(MruClients[i]);
    if IsAltTabEligible(cli) then
      AList.Add(cli);
  end;

  // Clients that have never been activated have no MRU entry yet; append them in
  // creation order so they are still reachable.
  for i := 0 to Clients.Count - 1 do
  begin
    cli := TXCBWMClient(Clients[i]);
    if IsAltTabEligible(cli) and (AList.IndexOf(cli) < 0) then
      AList.Add(cli);
  end;
end;

procedure TWMSamaCompositingWM.TriggerAltTabForward();
var
  eligibleList: TFPList;
  opened: Boolean;
begin
  // Resolve the candidate list *before* touching the keyboard grab. On an empty
  // desktop there is nothing to switch to, so no grab is attempted at all — that
  // ordering is what prevents the grab leak (see docs/roadmap.md WM-01).
  eligibleList := TFPList.Create();
  try
    GetAltTabEligibleClients(eligibleList);
    if eligibleList.Count <= 0 then
    begin
      if FAltTabActive then
      begin
        FAltTabActive := False;
        RequestComposite();
      end;
      ReleaseKeyboardGrab();
      Exit;
    end;

    opened := False;
    if not FAltTabActive then
    begin
      // Only mark the switcher active once the grab is really ours.
      if not AcquireKeyboardGrab() then
      begin
        DebugLog('Alt+Tab skipped: keyboard grab unavailable');
        Exit;
      end;
      FAltTabActive := True;
      // The list is in MRU order, so index 0 is the window that already has
      // focus. The first press must move to the *previous* window, which is
      // index 1. Selecting index 0 would re-activate the current window and make
      // Alt+Tab appear to do nothing.
      if eligibleList.Count > 1 then
        FAltTabIndex := 1
      else
        FAltTabIndex := 0;
      opened := True;
    end;

    if not opened then
      FAltTabIndex := (FAltTabIndex + 1) mod eligibleList.Count;

    RequestComposite();
  finally
    eligibleList.Free();
  end;
end;

procedure TWMSamaCompositingWM.TriggerAltTabDismiss();
var
  eligibleList: TFPList;
  targetCli: TXCBWMClient;
begin
  if not FAltTabActive then
  begin
    // Defensive: never leave a grab behind even if the HUD flag was cleared early.
    ReleaseKeyboardGrab();
    Exit;
  end;

  FAltTabActive := False;
  ReleaseKeyboardGrab();

  eligibleList := TFPList.Create();
  try
    GetAltTabEligibleClients(eligibleList);
    if (eligibleList.Count > 0) and (FAltTabIndex >= 0) and (FAltTabIndex < eligibleList.Count) then
    begin
      targetCli := TXCBWMClient(eligibleList[FAltTabIndex]);
      targetCli.Activate();
    end;
  finally
    eligibleList.Free();
  end;

  RequestComposite();
end;

// Escape / cancel: drop the switcher without activating anything.
procedure TWMSamaCompositingWM.CancelAltTab();
begin
  if not FAltTabActive and not FKeyboardGrabHeld then Exit;

  FAltTabActive := False;
  ReleaseKeyboardGrab();
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
  eligibleList: TFPList;
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
  eligibleList := TFPList.Create();
  try
    GetAltTabEligibleClients(eligibleList);
    if FAltTabActive and (eligibleList.Count > 0) then
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

    cardW := Min(hudArea.Width - 40, Max(360, eligibleList.Count * 130 + 40));
    cardH := 120;
    cardX := hudArea.X + (hudArea.Width - cardW) div 2;
    cardY := hudArea.Y + (hudArea.Height - cardH) div 2;

    // Card shadow and dark frosted glass background
    ACanvas.DrawShadow(cardX, cardY, cardW, cardH, 16, 0, 8, 24, 0.0, 0.0, 0.0, 0.55);
    ACanvas.DrawRoundedRect(cardX, cardY, cardW, cardH, 16, 24 / 255, 25 / 255, 38 / 255, 0.92);
    ACanvas.DrawRoundedRectOutline(cardX, cardY, cardW, cardH, 16, 1.5, 69 / 255, 71 / 255, 90 / 255, 0.6);

    itemW := 114;
    itemH := 88;

    for i := 0 to eligibleList.Count - 1 do
    begin
      cli := TXCBWMClient(eligibleList[i]);
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
  finally
    eligibleList.Free();
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

  // 0. X errors (response_type = 0) must be handled before anything else.
  // Damage notifications are extension events, but IsDamageNotify matches on
  // (type and $7F) = FDamageEventBase + 0, so an error event could otherwise be
  // reinterpreted as a damage notify and silently swallowed.
  if (AEvent^.response_type and $7F) = 0 then
  begin
    LogXError(Pxcb_generic_error_t(AEvent), 'event loop');
    Exit(True);
  end;

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
      // All keycodes below come from ResolveKeyBindings, not from hardcoded
      // evdev values, so a non-US layout binds the same physical keys.
      if (KeycodeTab <> 0) and (keyEv^.detail = KeycodeTab) then
      begin
        // Grab ownership is decided inside TriggerAltTabForward, after the
        // eligible list is known to be non-empty.
        TriggerAltTabForward();
        Exit(True);
      end
      else if (KeycodeSpace <> 0) and (keyEv^.detail = KeycodeSpace) then // Alt+Space
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
      else if FAltTabActive and (keyEv^.detail = KeycodeEscape) then
      begin
        CancelAltTab();
        Exit(True);
      end
      else if FAltTabActive and (keyEv^.detail = KeycodeReturn) then
      begin
        TriggerAltTabDismiss();
        Exit(True);
      end
      else if ((keyEv^.state and (ModSuper or XCB_MOD_MASK_SHIFT)) =
               (ModSuper or XCB_MOD_MASK_SHIFT)) and
              ((keyEv^.detail = KeycodeLeft) or (keyEv^.detail = KeycodeRight) or
               (keyEv^.detail = KeycodeUp) or (keyEv^.detail = KeycodeDown)) then
      begin
        targetCli := ActiveClient;
        if targetCli <> nil then
        begin
          curMon := MonitorForClient(targetCli);
          if curMon <> nil then
          begin
            if keyEv^.detail = KeycodeLeft then
              adjMon := AdjacentMonitor(curMon, dirLeft)
            else if keyEv^.detail = KeycodeRight then
              adjMon := AdjacentMonitor(curMon, dirRight)
            else if keyEv^.detail = KeycodeUp then
              adjMon := AdjacentMonitor(curMon, dirUp)
            else
              adjMon := AdjacentMonitor(curMon, dirDown);
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
      // Alt released: dismiss the switcher. Checked by keycode only: the state
      // field of a KeyRelease still has the modifier set for the key being
      // released, so testing it here would never fire.
      if FAltTabActive and
         ((keyEv^.detail = KeycodeAltL) or (keyEv^.detail = KeycodeAltR)) then
      begin
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
          UpdateHoverCursor(CursorForDragMode(resizeMode), targetCli)
        else
          // Not on a resize margin: normal cursor on the frame under the pointer,
          // or the root. Never on the client window itself, which owns its cursor.
          UpdateHoverCursor(CursorNormal, FindClient(motionEv^.event));
      end;
    end;

    XCB_LEAVE_NOTIFY:
    begin
      leaveEv := Pxcb_leave_notify_event_t(AEvent);
      // Leaving a frame we had decorated: put its cursor back rather than just
      // forgetting about it, otherwise the resize cursor stays painted on the
      // frame for as long as the pointer is elsewhere.
      if (FHoverCursorWindow <> 0) and (leaveEv^.event = FHoverCursorWindow) then
      begin
        if (Screen <> nil) and (FHoverCursorWindow = Screen^.root) then
        begin
          if CursorNormal <> 0 then
            SetWindowCursor(Screen^.root, CursorNormal);
          CurrentRootCursor := CursorNormal;
        end
        else if CursorNormal <> 0 then
          SetWindowCursor(FHoverCursorWindow, CursorNormal);
        FHoverCursorWindow := 0;
        FHoverCursor := 0;
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
          if (btnEv^.state and ModAlt) <> 0 then
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

          // F. Border resizing when border width > 0
          if (bw > 0) and ((localY >= th) or (localX < bw) or (localX >= cli.CurrentRect.Width - bw) or (localY >= cli.CurrentRect.Height - bw)) then
          begin
            BeginDrag(cli, dmResize, btnEv^.root_x, btnEv^.root_y);
            Exit(True);
          end;

          // The frame click is ours whether or not A-F matched. Falling through to
          // the inherited handler would run its unconditional BeginDrag(dmMove),
          // turning a click on dead space in the titlebar into an unintended
          // window move. Consume it instead.
          Exit(True);
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
begin
  if Connection = nil then Exit;

  // Initial paint of all frames and initial composite scene
  PaintAllFrames();
  RequestComposite();
  RenderComposite();

  // The pump itself (select + self-pipe + tick) lives in the base class so that
  // shutdown is uniform; this class only decides what to present per tick.
  inherited Run();
end;

procedure TWMSamaCompositingWM.DoOnTick(const AElapsedMs: Integer);
begin
  inherited DoOnTick(AElapsedMs);
  // Presentation happens here, once per pump cycle, rather than inline in the
  // event handlers. RenderComposite owns the enabled/needed guards.
  RenderComposite();
end;

end.
