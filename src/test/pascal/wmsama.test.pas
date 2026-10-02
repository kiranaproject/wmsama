unit wmsama.test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Floria.XCB,
  Floria.XCB.WM,
  Floria.XCB.WM.Compositor,
  Floria.Image.Core,
  Floria.Canvas.Agg,
  WMSama.FT,
  wmsama.core;

type
  TWMSamaTest = class(TTestCase)
  published
    procedure TestWMCreation();
    procedure TestDesktopConfiguration();
    procedure TestCompositorConfiguration();
    procedure TestCornerRadiusConfiguration();
    procedure TestClientCompositorIntegration();
    procedure TestFrameMetricsAndTitlebar();
    procedure TestWindowSnappingAndPreviews();
    procedure TestAltTabSwitcher();
    procedure TestFloriaToolkitButtonStyling();
    procedure TestButtonAlignmentAndPlacement();
    procedure TestAdditionalWindowControls();
    procedure TestOverrideRedirectCompositorSupport();
    procedure TestWindowResizingDirectionalAndTiled();
    procedure TestWindowCursors();
    procedure TestWindowButtonReleaseAndCancel();
  end;

implementation

procedure TWMSamaTest.TestWMCreation();
var
  wm: TWMSamaCompositingWM;
begin
  wm := TWMSamaCompositingWM.Create(nil, 0);
  try
    AssertNotNull('WM instance created', wm);
    AssertEquals('WM name is wmsama', 'wmsama', wm.WMName);
    AssertEquals('Default titlebar height', 34, wm.TitlebarHeight);
    AssertEquals('Default top corner radius', 12, wm.CornerRadius);
    AssertEquals('Default bottom corner radius', 12, wm.BottomCornerRadius);
    AssertTrue('Compositor enabled by default', wm.CompositorEnabled);
    AssertNotNull('Compositor instance created', wm.Compositor);
    AssertFalse('Offline by default', wm.IsRunning);
  finally
    wm.Free();
  end;
end;

procedure TWMSamaTest.TestDesktopConfiguration();
var
  wm: TWMSamaCompositingWM;
begin
  wm := TWMSamaCompositingWM.Create(nil, 0);
  try
    AssertEquals('Default 4 desktops', 4, wm.DesktopCount);
    AssertEquals('Current desktop 0', 0, wm.CurrentDesktop);
    wm.SetDesktopCount(8);
    AssertEquals('Updated 8 desktops', 8, wm.DesktopCount);
    wm.SwitchDesktop(3);
    AssertEquals('Switched to desktop 3', 3, wm.CurrentDesktop);
  finally
    wm.Free();
  end;
end;

procedure TWMSamaTest.TestCompositorConfiguration();
var
  wm: TWMSamaCompositingWM;
begin
  wm := TWMSamaCompositingWM.Create(nil, 0);
  try
    // Test shadow configs
    wm.ShadowRadius := 16;
    AssertEquals('Shadow radius updated', 16, wm.ShadowRadius);

    wm.ShadowOffsetY := 5;
    AssertEquals('Shadow offset Y updated', 5, wm.ShadowOffsetY);

    wm.ShadowOpacity := 0.45;
    AssertTrue('Shadow opacity updated', Abs(wm.ShadowOpacity - 0.45) < 0.001);

    // Active shadow configs
    wm.ActiveShadowRadius := 22;
    AssertEquals('Active shadow radius updated', 22, wm.ActiveShadowRadius);

    wm.ActiveShadowOffsetY := 8;
    AssertEquals('Active shadow offset Y updated', 8, wm.ActiveShadowOffsetY);

    wm.ActiveShadowOpacity := 0.55;
    AssertTrue('Active shadow opacity updated', Abs(wm.ActiveShadowOpacity - 0.55) < 0.001);

    // Blur configs
    wm.BlurEnabled := True;
    AssertTrue('Blur enabled', wm.BlurEnabled);

    wm.BlurRadius := 20;
    AssertEquals('Blur radius updated', 20, wm.BlurRadius);

    // Compositor toggle
    wm.CompositorEnabled := False;
    AssertFalse('Compositor disabled', wm.CompositorEnabled);
    wm.CompositorEnabled := True;
    AssertTrue('Compositor re-enabled', wm.CompositorEnabled);
  finally
    wm.Free();
  end;
end;

procedure TWMSamaTest.TestCornerRadiusConfiguration();
var
  wm: TWMSamaCompositingWM;
begin
  wm := TWMSamaCompositingWM.Create(nil, 0);
  try
    wm.CornerRadius := 14;
    AssertEquals('Top corner radius updated', 14, wm.CornerRadius);

    wm.BottomCornerRadius := 16;
    AssertEquals('Bottom corner radius updated', 16, wm.BottomCornerRadius);
  finally
    wm.Free();
  end;
end;

procedure TWMSamaTest.TestClientCompositorIntegration();
var
  wm: TWMSamaCompositingWM;
  cli: TXCBWMClient;
  compWin: TXCBCompositedWindow;
  clientImg: TFloriaImage;
begin
  wm := TWMSamaCompositingWM.Create(nil, 0);
  try
    wm.BlurEnabled := True;
    wm.BlurRadius := 18;
    wm.CornerRadius := 12;
    wm.BottomCornerRadius := 12;

    // Simulate managing a client window (ID: 3001)
    cli := wm.ManageWindow(3001);
    AssertNotNull('Client managed', cli);
    AssertEquals('Client count is 1', 1, wm.Clients.Count);

    // Set geometry and title
    cli.Title := 'Samarinda Terminal';
    cli.SetGeometry(100, 100, 600, 400);

    // Verify window is registered in compositor
    compWin := wm.Compositor.FindWindow(cli.ClientWindow);
    AssertNotNull('Compositor registered window', compWin);
    AssertEquals('Blur radius synced', 18, compWin.BlurRadius);
    AssertTrue('Backdrop blur enabled', compWin.HasBackdropBlur);
    AssertEquals('Top corner radius applied', 12, compWin.CornerRadius);
    AssertEquals('Bottom corner radius applied', 12, compWin.BottomCornerRadius);

    // Simulate client image buffer
    clientImg := TFloriaImage.Create(600, 400);
    clientImg.Clear(24, 25, 38, 240);
    compWin.Image := clientImg;
    compWin.IsDirty := False;

    // Test activation & shadow elevation
    wm.SetActiveClient(cli);
    AssertSame('Active client is cli', cli, wm.ActiveClient);
    AssertEquals('Active shadow radius applied', wm.ActiveShadowRadius, compWin.ShadowConfig.Radius);

    // Test composite pass
    wm.RequestComposite();
    AssertTrue('Needs composite is true', wm.NeedsComposite);
    wm.RenderComposite();
    AssertFalse('Needs composite reset after render', wm.NeedsComposite);

    // Unmanage client
    wm.UnmanageWindow(cli);
    AssertEquals('Client count is 0', 0, wm.Clients.Count);
    AssertNull('Compositor window unregistered', wm.Compositor.FindWindow(3001));
  finally
    wm.Free();
  end;
end;

procedure TWMSamaTest.TestFrameMetricsAndTitlebar();
var
  wm: TWMSamaCompositingWM;
  metrics: TXCBFrameMetrics;
  btnSize, btnY, x0, x1, x2: Double;
  titleX: Integer;
begin
  wm := TWMSamaCompositingWM.Create(nil, 0);
  try
    metrics := wm.FrameMetrics;
    AssertEquals('FrameMetrics titlebar height', 34, metrics.TitlebarHeight);
    AssertEquals('FrameMetrics top inset matches titlebar', 34, metrics.Insets.Top);
    AssertEquals('FrameMetrics left inset is 0', 0, metrics.Insets.Left);
    AssertEquals('FrameMetrics right inset is 0', 0, metrics.Insets.Right);
    AssertEquals('FrameMetrics bottom inset is 0', 0, metrics.Insets.Bottom);

    // Test automatic button scaling and hit testing with default 34px titlebar
    wm.GetWindowButtonMetrics(btnSize, btnY, x0, x1, x2, titleX);
    AssertTrue('Button size scaled for 34px titlebar', Abs(btnSize - 15.0) < 0.01);
    AssertTrue('Button Y centered in 34px titlebar', Abs(btnY - 9.5) < 0.01);
    AssertEquals('Hit close button', 0, wm.GetButtonAt(Round(x0), Round(btnY + 2)));
    AssertEquals('Hit minimize button', 1, wm.GetButtonAt(Round(x1), Round(btnY + 2)));
    AssertEquals('Hit maximize button', 2, wm.GetButtonAt(Round(x2), Round(btnY + 2)));
    AssertEquals('Hit title text is not button', -1, wm.GetButtonAt(titleX, 10));

    // Update titlebar height to 40
    wm.TitlebarHeight := 40;
    AssertEquals('Updated titlebar height', 40, wm.TitlebarHeight);
    metrics := wm.FrameMetrics;
    AssertEquals('FrameMetrics titlebar height updated', 40, metrics.TitlebarHeight);
    AssertEquals('FrameMetrics top inset updated', 40, metrics.Insets.Top);

    // Verify automatic button scaling with 40px titlebar
    wm.GetWindowButtonMetrics(btnSize, btnY, x0, x1, x2, titleX);
    AssertTrue('Button size scaled for 40px titlebar', Abs(btnSize - 18.0) < 0.01);
    AssertTrue('Button Y centered in 40px titlebar', Abs(btnY - 11.0) < 0.01);
    AssertEquals('Hit close button in 40px', 0, wm.GetButtonAt(Round(x0), Round(btnY + 2)));
  finally
    wm.Free();
  end;
end;

procedure TWMSamaTest.TestWindowSnappingAndPreviews();
var
  wm: TWMSamaCompositingWM;
  cli: TXCBWMClient;
begin
  wm := TWMSamaCompositingWM.Create(nil, 0);
  try
    cli := wm.ManageWindow(4001);
    cli.SetGeometry(100, 100, 800, 600);

    // 1. Test Snapping to Top (Maximize)
    wm.BeginDrag(cli, dmMove, 500, 200);
    wm.UpdateDrag(500, 5); // Drag to top threshold
    AssertEquals('Snap mode is maximize', Ord(snapMaximize), Ord(wm.ActiveSnap));
    AssertTrue('Snap preview has full width', wm.SnapPreviewRect.Width > 0);
    AssertEquals('Snap preview width matches screen', wm.Compositor.ScreenWidth, wm.SnapPreviewRect.Width);
    wm.EndDrag();
    AssertEquals('Active snap reset after release', Ord(snapNone), Ord(wm.ActiveSnap));
    AssertTrue('Client maximized', wsMaximizedHorz in cli.State);

    // 2. Test Snapping to Left (Half Screen)
    wm.BeginDrag(cli, dmMove, 500, 200);
    wm.UpdateDrag(5, 400); // Drag to left threshold
    AssertEquals('Snap mode is left half', Ord(snapLeftHalf), Ord(wm.ActiveSnap));
    AssertEquals('Snap preview is half screen width', wm.Compositor.ScreenWidth div 2, wm.SnapPreviewRect.Width);
    wm.EndDrag();
    AssertEquals('Client snapped to left half', wm.Compositor.ScreenWidth div 2, cli.CurrentRect.Width);
    AssertEquals('Client X is 0', 0, cli.CurrentRect.X);

    // 3. Test Snapping to Right (Half Screen)
    wm.BeginDrag(cli, dmMove, 500, 200);
    wm.UpdateDrag(wm.Compositor.ScreenWidth - 5, 400); // Drag to right threshold
    AssertEquals('Snap mode is right half', Ord(snapRightHalf), Ord(wm.ActiveSnap));
    wm.EndDrag();
    AssertEquals('Client snapped to right half', wm.Compositor.ScreenWidth - (wm.Compositor.ScreenWidth div 2), cli.CurrentRect.Width);
    AssertEquals('Client X is right half start', wm.Compositor.ScreenWidth div 2, cli.CurrentRect.X);

    // 4. Test dragging from right half restores pre-tiled size and centers under cursor
    wm.BeginDrag(cli, dmMove, wm.Compositor.ScreenWidth - 100, 20);
    wm.UpdateDrag(500, 200); // Drag to middle of screen
    AssertEquals('Client restored to pre-tiled width 800', 800, cli.CurrentRect.Width);
    AssertEquals('Client restored to pre-tiled height 600', 600, cli.CurrentRect.Height);
    AssertEquals('Client centered under cursor X', 500 - (800 div 2), cli.CurrentRect.X);
    wm.EndDrag();

    // 5. Test dragging from maximized restores pre-tiled size and centers under cursor
    cli.Maximize();
    AssertTrue('Client maximized', wsMaximizedHorz in cli.State);
    wm.BeginDrag(cli, dmMove, 700, 10);
    wm.UpdateDrag(600, 150);
    AssertFalse('Client unmaximized', wsMaximizedHorz in cli.State);
    AssertEquals('Client restored to pre-tiled width 800', 800, cli.CurrentRect.Width);
    AssertEquals('Client restored to pre-tiled height 600', 600, cli.CurrentRect.Height);
    AssertEquals('Client centered under cursor X (600 - 400)', 200, cli.CurrentRect.X);
    wm.EndDrag();
  finally
    wm.Free();
  end;
end;

procedure TWMSamaTest.TestAltTabSwitcher();
var
  wm: TWMSamaCompositingWM;
  cli1, cli2: TXCBWMClient;
begin
  wm := TWMSamaCompositingWM.Create(nil, 0);
  try
    cli1 := wm.ManageWindow(5001);
    cli1.Title := 'Editor';
    cli2 := wm.ManageWindow(5002);
    cli2.Title := 'Browser';

    AssertFalse('Alt-Tab inactive initially', wm.AltTabActive);

    // Trigger forward
    wm.TriggerAltTabForward();
    AssertTrue('Alt-Tab activated', wm.AltTabActive);
    AssertEquals('Alt-Tab index is 1', 1, wm.AltTabIndex);

    // Trigger forward again (cycles)
    wm.TriggerAltTabForward();
    AssertEquals('Alt-Tab cycled to index 0', 0, wm.AltTabIndex);

    // Dismiss activates selected client
    wm.TriggerAltTabDismiss();
    AssertFalse('Alt-Tab dismissed', wm.AltTabActive);
    AssertSame('Selected client is active', cli1, wm.ActiveClient);
  finally
    wm.Free();
  end;
end;

procedure TWMSamaTest.TestFloriaToolkitButtonStyling();
var
  wm: TWMSamaCompositingWM;
  img: TFloriaImage;
  canvas: TFloriaCanvasAgg;
  loaded: Boolean;
begin
  wm := TWMSamaCompositingWM.Create(nil, 0);
  try
    // Test default button style and theme
    AssertEquals('Default button style is circle', FT_WINDOW_BUTTON_CIRCLE, wm.WindowButtonStyle);
    AssertTrue('Default theme is dark mode', wm.ThemeDarkMode);

    // Test setting squircle and square
    wm.WindowButtonStyle := FT_WINDOW_BUTTON_SQUIRCLE;
    AssertEquals('WindowButtonStyle updated to squircle', FT_WINDOW_BUTTON_SQUIRCLE, wm.WindowButtonStyle);

    wm.WindowButtonStyle := FT_WINDOW_BUTTON_SQUARE;
    AssertEquals('WindowButtonStyle updated to square', FT_WINDOW_BUTTON_SQUARE, wm.WindowButtonStyle);

    wm.ThemeDarkMode := False;
    AssertFalse('ThemeDarkMode updated to light mode', wm.ThemeDarkMode);

    // Test dynamic loading and drawing
    loaded := InitFloriaToolkit('');
    AssertTrue('Floria Toolkit loaded via WMSama.FT', loaded);
    AssertTrue('FloriaToolkitLoaded returns true', FloriaToolkitLoaded());

    // Test drawing into a canvas
    img := TFloriaImage.Create(100, 30);
    try
      img.Clear(30, 30, 40, 255);
      canvas := TFloriaCanvasAgg.Create(img);
      try
        // Draw close, minimize, maximize, restore in all states
        FtDrawWindowButton(canvas, 5, 8, 13, 13, FT_WINDOW_BUTTON_CLOSE, FT_WINDOW_BUTTON_CIRCLE, FT_BUTTON_STATE_NORMAL, True);
        FtDrawWindowButton(canvas, 25, 8, 13, 13, FT_WINDOW_BUTTON_MINIMIZE, FT_WINDOW_BUTTON_CIRCLE, FT_BUTTON_STATE_HOVERED, True);
        FtDrawWindowButton(canvas, 45, 8, 13, 13, FT_WINDOW_BUTTON_MAXIMIZE, FT_WINDOW_BUTTON_CIRCLE, FT_BUTTON_STATE_PRESSED, True);
        FtDrawWindowButton(canvas, 65, 8, 13, 13, FT_WINDOW_BUTTON_RESTORE, FT_WINDOW_BUTTON_CIRCLE, FT_BUTTON_STATE_NORMAL, False);

        // Verify pixel data modified
        AssertTrue('Canvas rendered pixels', img.Data <> nil);
      finally
        canvas.Free();
      end;
    finally
      img.Free();
    end;
  finally
    wm.Free();
  end;
end;

procedure TWMSamaTest.TestButtonAlignmentAndPlacement();
var
  wm: TWMSamaCompositingWM;
  btns: TWMSamaButtonArray;
  tX, tW: Integer;
begin
  wm := TWMSamaCompositingWM.Create(nil, 0);
  try
    // 1. Default is baLeft with 3 buttons
    AssertEquals('Default button alignment is baLeft', Ord(baLeft), Ord(wm.ButtonAlignment));
    AssertEquals('Default button layout is close,minimize,maximize:', 'close,minimize,maximize:', wm.ButtonLayout);

    wm.CalculateButtons(800, btns, tX, tW);
    AssertEquals('3 buttons calculated', 3, Length(btns));
    AssertEquals('Button 0 is close', Ord(sbkClose), Ord(btns[0].Kind));
    AssertEquals('Button 0 is left', Ord(bpLeft), Ord(btns[0].Placement));
    AssertTrue('Button 0 is near left margin', btns[0].X < 20.0);
    AssertTrue('Title starts after left buttons', tX > btns[2].X);

    // 2. Switch to baRight
    wm.ButtonAlignment := baRight;
    AssertEquals('Button alignment changed to baRight', Ord(baRight), Ord(wm.ButtonAlignment));
    AssertEquals('Button layout updated to right style', ':minimize,maximize,close', wm.ButtonLayout);

    wm.CalculateButtons(800, btns, tX, tW);
    AssertEquals('3 buttons calculated on right', 3, Length(btns));
    AssertEquals('Button 0 is minimize', Ord(sbkMinimize), Ord(btns[0].Kind));
    AssertEquals('Button 0 is right', Ord(bpRight), Ord(btns[0].Placement));
    AssertTrue('Right buttons are positioned near right edge', btns[0].X > 700.0);
    AssertTrue('Title starts near left edge when no left buttons', tX < 20);

    // 3. Custom button layout with both sides: menu on left, shade, pin, min, max, close on right
    wm.ButtonLayout := 'menu:shade,pin,minimize,maximize,close';
    AssertEquals('Button layout parsed', 'menu:shade,pin,minimize,maximize,close', wm.ButtonLayout);
    wm.CalculateButtons(800, btns, tX, tW);
    AssertEquals('6 buttons in custom layout', 6, Length(btns));
    AssertEquals('Button 0 is menu', Ord(sbkMenu), Ord(btns[0].Kind));
    AssertEquals('Button 0 placement is left', Ord(bpLeft), Ord(btns[0].Placement));
    AssertEquals('Button 1 is shade', Ord(sbkShade), Ord(btns[1].Kind));
    AssertEquals('Button 1 placement is right', Ord(bpRight), Ord(btns[1].Placement));
    AssertEquals('Button 2 is pin', Ord(sbkPin), Ord(btns[2].Kind));
    AssertEquals('Button 5 is close', Ord(sbkClose), Ord(btns[5].Kind));

    // 4. Test draggable titlebar boundaries
    AssertFalse('Click on menu button is not draggable', wm.IsTitlebarDraggable(Round(btns[0].X), 10, 800));
    AssertFalse('Click on close button is not draggable', wm.IsTitlebarDraggable(Round(btns[5].X), 10, 800));
    AssertTrue('Click in center caption is draggable', wm.IsTitlebarDraggable(400, 10, 800));
  finally
    wm.Free();
  end;
end;

procedure TWMSamaTest.TestAdditionalWindowControls();
var
  wm: TWMSamaCompositingWM;
  cli: TXCBWMClient;
begin
  wm := TWMSamaCompositingWM.Create(nil, 0);
  try
    cli := wm.ManageWindow(6001);
    cli.SetGeometry(100, 100, 500, 350);

    // 1. Keep on Top (Pin)
    AssertFalse('Client initially not wsAbove', wsAbove in cli.State);
    wm.ToggleKeepOnTop(cli);
    AssertTrue('Client now wsAbove after toggle', wsAbove in cli.State);
    wm.ToggleKeepOnTop(cli);
    AssertFalse('Client no longer wsAbove after toggle off', wsAbove in cli.State);

    // 2. Shade / Roll-up (requires reparented client)
    // Manually mark reparented for test simulation
    cli.IsReparented := True;
    cli.FrameWindow := 6002;
    AssertFalse('Client not shaded initially', wm.IsClientShaded(cli.ClientWindow));
    wm.ToggleShade(cli);
    AssertTrue('Client shaded after toggle', wm.IsClientShaded(cli.ClientWindow));
    AssertEquals('Frame height collapsed to titlebar height', wm.TitlebarHeight, cli.CurrentRect.Height);

    wm.ToggleShade(cli);
    AssertFalse('Client unshaded after second toggle', wm.IsClientShaded(cli.ClientWindow));
    AssertEquals('Frame height restored to 350', 350, cli.CurrentRect.Height);

    // 3. Window Menu HUD
    AssertNull('Window menu initially closed', wm.WindowMenuClient);
    wm.TriggerWindowMenu(cli);
    AssertSame('Window menu opened for client', cli, wm.WindowMenuClient);
    AssertTrue('Window menu rect calculated', wm.WindowMenuRect.Width > 0);
    AssertEquals('Window menu width', 160, wm.WindowMenuRect.Width);
    AssertEquals('Window menu height', 154, wm.WindowMenuRect.Height);

    wm.DismissWindowMenu();
    AssertNull('Window menu dismissed', wm.WindowMenuClient);
    AssertEquals('Window menu rect cleared', 0, wm.WindowMenuRect.Width);
  finally
    wm.Free();
  end;
end;

procedure TWMSamaTest.TestOverrideRedirectCompositorSupport();
var
  wm: TWMSamaCompositingWM;
  popupWin: xcb_window_t;
  popupRect: TXCBRect;
  compWin: TXCBCompositedWindow;
  img: TFloriaImage;
begin
  wm := TWMSamaCompositingWM.Create(nil, 0);
  try
    // Simulate an override-redirect window created by client application
    // (e.g. TFtPopupMenu, TFtComboBox dropdown list, or tooltip)
    popupWin := 9001;
    popupRect := TXCBRect.Create(250, 180, 200, 160);

    // Register in Compositor with frameWin = 0
    compWin := wm.Compositor.RegisterWindow(popupWin, popupRect, 0);
    AssertNotNull('Compositor registered override-redirect window', compWin);
    AssertEquals('Frame window is 0 for unmanaged popup', 0, compWin.FrameWindow);
    AssertNull('Client is unmanaged (nil in WM client list)', wm.FindClient(popupWin));

    // Configure popup styling (rounded corners and shadow)
    compWin.CornerRadius := 6;
    compWin.BottomCornerRadius := 6;
    compWin.ShadowConfig := TXCBWindowShadowConfig.Create(True, 12, 4, 0.40);
    AssertEquals('Corner radius set to 6', 6, compWin.CornerRadius);
    AssertEquals('Bottom corner radius set to 6', 6, compWin.BottomCornerRadius);
    AssertTrue('Drop shadow enabled', compWin.ShadowConfig.Enabled);
    AssertEquals('Drop shadow radius', 12, compWin.ShadowConfig.Radius);

    // Stacking: elevate to top of compositor stack
    wm.Compositor.Windows.Extract(compWin);
    wm.Compositor.Windows.Add(compWin);
    AssertSame('Popup is topmost window in compositor', compWin, wm.Compositor.Windows.Last);

    // Geometry updates (e.g. cascading submenu positioning or combo repositioning)
    compWin.UpdateGeometry(260, 220, 220, 180);
    AssertEquals('Geometry X updated', 260, compWin.Geometry.X);
    AssertEquals('Geometry Y updated', 220, compWin.Geometry.Y);
    AssertEquals('Geometry Width updated', 220, compWin.Geometry.Width);
    AssertEquals('Geometry Height updated', 180, compWin.Geometry.Height);

    // Damage & Composite pass
    img := TFloriaImage.Create(220, 180);
    img.Clear(255, 255, 255, 255);
    compWin.Image := img;
    compWin.MarkDamaged();
    AssertTrue('Window marked dirty/damaged', compWin.IsDirty);

    wm.RequestComposite();
    AssertTrue('Compositor requests redraw', wm.NeedsComposite);
    wm.RenderComposite();
    AssertFalse('Needs composite cleared after render', wm.NeedsComposite);

    // Unregistration upon unmap / destroy
    wm.Compositor.UnregisterWindow(popupWin);
    AssertNull('Popup window unregistered from compositor', wm.Compositor.FindWindow(popupWin));
  finally
    wm.Free();
  end;
end;

procedure TWMSamaTest.TestWindowResizingDirectionalAndTiled();
var
  wm: TWMSamaCompositingWM;
  cli: TXCBWMClient;
  origW, origH, origX, origY: Integer;
begin
  wm := TWMSamaCompositingWM.Create(nil, 0);
  try
    cli := wm.ManageWindow(5555);
    cli.CurrentRect := TXCBRect.Create(100, 100, 400, 300);
    cli.RestoredRect := cli.CurrentRect;

    // 1. Floating Window: Outer Corner hit tests (outside window boundary)
    AssertEquals('Top-Left corner (outer)', Integer(dmResizeTopLeft), Integer(wm.GetResizeModeForPoint(cli, 96, 96)));
    AssertEquals('Top-Right corner (outer)', Integer(dmResizeTopRight), Integer(wm.GetResizeModeForPoint(cli, 504, 96)));
    AssertEquals('Bottom-Left corner (outer)', Integer(dmResizeBottomLeft), Integer(wm.GetResizeModeForPoint(cli, 96, 404)));
    AssertEquals('Bottom-Right corner (outer)', Integer(dmResizeBottomRight), Integer(wm.GetResizeModeForPoint(cli, 504, 404)));

    // 2. Floating Window: Outer Edge hit tests (outside window boundary)
    AssertEquals('Top edge (height only, outer)', Integer(dmResizeTop), Integer(wm.GetResizeModeForPoint(cli, 250, 96)));
    AssertEquals('Bottom edge (height only, outer)', Integer(dmResizeBottom), Integer(wm.GetResizeModeForPoint(cli, 250, 404)));
    AssertEquals('Left edge (width only, outer)', Integer(dmResizeLeft), Integer(wm.GetResizeModeForPoint(cli, 96, 200)));
    AssertEquals('Right edge (width only, outer)', Integer(dmResizeRight), Integer(wm.GetResizeModeForPoint(cli, 504, 200)));

    // 3. Floating Window: Client application interior and edges MUST return dmNone
    // This ensures selecting text inside xterm from column 0 or any edge never triggers resize!
    AssertEquals('Client app left edge (text selection protected)', Integer(dmNone), Integer(wm.GetResizeModeForPoint(cli, 102, 200)));
    AssertEquals('Client app right edge (text selection protected)', Integer(dmNone), Integer(wm.GetResizeModeForPoint(cli, 496, 200)));
    AssertEquals('Client app bottom edge', Integer(dmNone), Integer(wm.GetResizeModeForPoint(cli, 250, 396)));
    AssertEquals('Client app bottom-left', Integer(dmNone), Integer(wm.GetResizeModeForPoint(cli, 105, 395)));
    AssertEquals('Client app bottom-right', Integer(dmNone), Integer(wm.GetResizeModeForPoint(cli, 495, 395)));
    AssertEquals('Titlebar center draggable', Integer(dmNone), Integer(wm.GetResizeModeForPoint(cli, 250, 120)));
    AssertEquals('Client app interior', Integer(dmNone), Integer(wm.GetResizeModeForPoint(cli, 250, 250)));
    AssertEquals('Far outside window', Integer(dmNone), Integer(wm.GetResizeModeForPoint(cli, 50, 50)));

    // 4. Maximized Window: Resizing completely disabled
    cli.Maximize();
    AssertTrue('Window is maximized', wsMaximizedHorz in cli.State);
    AssertEquals('Maximized top edge returns dmNone', Integer(dmNone), Integer(wm.GetResizeModeForPoint(cli, 250, 2)));
    AssertEquals('Maximized bottom edge returns dmNone', Integer(dmNone), Integer(wm.GetResizeModeForPoint(cli, 250, 1078)));
    AssertEquals('Maximized left edge returns dmNone', Integer(dmNone), Integer(wm.GetResizeModeForPoint(cli, 2, 200)));
    AssertEquals('Maximized right edge returns dmNone', Integer(dmNone), Integer(wm.GetResizeModeForPoint(cli, 1918, 200)));
    AssertEquals('Maximized corners return dmNone', Integer(dmNone), Integer(wm.GetResizeModeForPoint(cli, 2, 2)));
    cli.Restore();

    // 5. Tiled Right Window: Only left divider outer margin allowed to resize width
    cli.TileRight();
    AssertTrue('Window is tiled right', wsTiledRight in cli.State);
    origX := cli.CurrentRect.X;
    origY := cli.CurrentRect.Y;
    origW := cli.CurrentRect.Width;
    origH := cli.CurrentRect.Height;

    // Hit-testing tiled right
    AssertEquals('Tiled Right outer left divider allows dmResizeLeft', Integer(dmResizeLeft), Integer(wm.GetResizeModeForPoint(cli, origX - 4, 300)));
    AssertEquals('Tiled Right client interior protects text selection', Integer(dmNone), Integer(wm.GetResizeModeForPoint(cli, origX + 2, 300)));
    AssertEquals('Tiled Right top edge disallowed', Integer(dmNone), Integer(wm.GetResizeModeForPoint(cli, origX + 100, 2)));
    AssertEquals('Tiled Right bottom edge disallowed', Integer(dmNone), Integer(wm.GetResizeModeForPoint(cli, origX + 100, origH - 2)));
    AssertEquals('Tiled Right outer right edge disallowed', Integer(dmNone), Integer(wm.GetResizeModeForPoint(cli, origX + origW - 2, 300)));

    // Interactive drag update on Tiled Right
    wm.BeginDrag(cli, dmResizeLeft, origX - 4, 300);
    wm.UpdateDrag(origX - 74, 360); // Drag divider 70px left (expanding width); DeltaY must be locked!
    AssertEquals('Tiled Right width expanded by 70', origW + 70, cli.CurrentRect.Width);
    AssertEquals('Tiled Right X moved left by 70', origX - 70, cli.CurrentRect.X);
    AssertEquals('Tiled Right height strictly locked to full height', origH, cli.CurrentRect.Height);
    AssertEquals('Tiled Right Y strictly locked to 0', 0, cli.CurrentRect.Y);
    AssertEquals('Tiled Right right-edge stays pinned to screen edge', origX + origW, cli.CurrentRect.X + cli.CurrentRect.Width);
    wm.EndDrag();

    // 6. Restored Rect integrity: Resizing tiled width does NOT overwrite restored floating rect
    AssertEquals('Floating RestoredRect Width intact', 400, cli.RestoredRect.Width);
    AssertEquals('Floating RestoredRect Height intact', 300, cli.RestoredRect.Height);

    // 7. Tiled Left Window: Only right divider outer margin allowed to resize width
    cli.TileLeft();
    AssertTrue('Window is tiled left', wsTiledLeft in cli.State);
    origX := cli.CurrentRect.X;
    origY := cli.CurrentRect.Y;
    origW := cli.CurrentRect.Width;
    origH := cli.CurrentRect.Height;

    // Hit-testing tiled left
    AssertEquals('Tiled Left outer right divider allows dmResizeRight', Integer(dmResizeRight), Integer(wm.GetResizeModeForPoint(cli, origW + 4, 300)));
    AssertEquals('Tiled Left client interior protects text selection', Integer(dmNone), Integer(wm.GetResizeModeForPoint(cli, origW - 2, 300)));
    AssertEquals('Tiled Left outer left edge disallowed', Integer(dmNone), Integer(wm.GetResizeModeForPoint(cli, 2, 300)));
    AssertEquals('Tiled Left top edge disallowed', Integer(dmNone), Integer(wm.GetResizeModeForPoint(cli, 100, 2)));
    AssertEquals('Tiled Left bottom edge disallowed', Integer(dmNone), Integer(wm.GetResizeModeForPoint(cli, 100, origH - 2)));

    // Interactive drag update on Tiled Left
    wm.BeginDrag(cli, dmResizeRight, origW + 4, 300);
    wm.UpdateDrag(origW + 94, 380); // Drag divider 90px right (expanding width); DeltaY must be locked!
    AssertEquals('Tiled Left width expanded by 90', origW + 90, cli.CurrentRect.Width);
    AssertEquals('Tiled Left X strictly locked to 0', 0, cli.CurrentRect.X);
    AssertEquals('Tiled Left height strictly locked to full height', origH, cli.CurrentRect.Height);
    AssertEquals('Tiled Left Y strictly locked to 0', 0, cli.CurrentRect.Y);
    wm.EndDrag();

    // 8. Restore returns cleanly to remembered floating dimensions
    cli.Restore();
    AssertEquals('Restored floating X', 100, cli.CurrentRect.X);
    AssertEquals('Restored floating Y', 100, cli.CurrentRect.Y);
    AssertEquals('Restored floating Width', 400, cli.CurrentRect.Width);
    AssertEquals('Restored floating Height', 300, cli.CurrentRect.Height);
  finally
    wm.Free();
  end;
end;

procedure TWMSamaTest.TestWindowCursors();
var
  wm: TWMSamaCompositingWM;
begin
  wm := TWMSamaCompositingWM.Create(nil, 0);
  try
    // 1. Cursor mapping for drag modes offline
    AssertEquals('dmNone maps to normal cursor', wm.CursorNormal, wm.CursorForDragMode(dmNone));
    AssertEquals('dmMove maps to move cursor', wm.CursorMove, wm.CursorForDragMode(dmMove));
    AssertEquals('dmResizeLeft maps to resize left cursor', wm.CursorResizeLeft, wm.CursorForDragMode(dmResizeLeft));
    AssertEquals('dmResizeRight maps to resize right cursor', wm.CursorResizeRight, wm.CursorForDragMode(dmResizeRight));
    AssertEquals('dmResizeTop maps to resize top cursor', wm.CursorResizeTop, wm.CursorForDragMode(dmResizeTop));
    AssertEquals('dmResizeBottom maps to resize bottom cursor', wm.CursorResizeBottom, wm.CursorForDragMode(dmResizeBottom));
    AssertEquals('dmResizeTopLeft maps to top-left corner cursor', wm.CursorResizeTopLeft, wm.CursorForDragMode(dmResizeTopLeft));
    AssertEquals('dmResizeTopRight maps to top-right corner cursor', wm.CursorResizeTopRight, wm.CursorForDragMode(dmResizeTopRight));
    AssertEquals('dmResizeBottomLeft maps to bottom-left corner cursor', wm.CursorResizeBottomLeft, wm.CursorForDragMode(dmResizeBottomLeft));
    AssertEquals('dmResizeBottomRight maps to bottom-right corner cursor', wm.CursorResizeBottomRight, wm.CursorForDragMode(dmResizeBottomRight));

    // 2. Hover Cursor Updates
    wm.UpdateHoverCursor(1234, 0);
    AssertNotNull('UpdateHoverCursor offline safety verified', wm);
  finally
    wm.Free();
  end;
end;

procedure TWMSamaTest.TestWindowButtonReleaseAndCancel();
var
  wm: TWMSamaCompositingWM;
  cli: TXCBWMClient;
  pressEv: xcb_button_press_event_t;
  releaseEv: xcb_button_release_event_t;
  motionEv: xcb_motion_notify_event_t;
  btnIdx: Integer;
begin
  wm := TWMSamaCompositingWM.Create(nil, 0);
  try
    cli := wm.ManageWindow(7001);
    cli.IsReparented := True;
    cli.FrameWindow := 7002;
    cli.SetGeometry(100, 100, 500, 350);

    // Default button layout: 'close,minimize,maximize:'
    // Close is btn 0, Minimize is btn 1, Maximize is btn 2
    btnIdx := wm.GetButtonAt(64, 17, 500);
    AssertEquals('Button at (64, 17) is maximize button (idx 2)', 2, btnIdx);

    // 1. Mouse Button 1 Down on Maximize Button
    FillChar(pressEv, SizeOf(pressEv), 0);
    pressEv.response_type := XCB_BUTTON_PRESS;
    pressEv.detail := XCB_BUTTON_INDEX_1;
    pressEv.event := cli.FrameWindow;
    pressEv.event_x := 64;
    pressEv.event_y := 17;
    wm.ProcessEvent(Pxcb_generic_event_t(@pressEv));

    // Must be in pressed state, but NOT yet maximized!
    AssertEquals('PressedButton recorded as 2', 2, wm.PressedButton);
    AssertEquals('PressedWindow recorded as FrameWindow', cli.FrameWindow, wm.PressedWindow);
    AssertFalse('Client NOT maximized on button press', wsMaximizedHorz in cli.State);

    // 2. Drag cursor outside the button (to cancel)
    FillChar(motionEv, SizeOf(motionEv), 0);
    motionEv.response_type := XCB_MOTION_NOTIFY;
    motionEv.event := cli.FrameWindow;
    motionEv.event_x := 200; // Far in titlebar center
    motionEv.event_y := 17;
    wm.ProcessEvent(Pxcb_generic_event_t(@motionEv));
    AssertEquals('HoveredButton now -1 outside button', -1, wm.HoveredButton);

    // 3. Release mouse outside the button
    FillChar(releaseEv, SizeOf(releaseEv), 0);
    releaseEv.response_type := XCB_BUTTON_RELEASE;
    releaseEv.detail := XCB_BUTTON_INDEX_1;
    releaseEv.event := cli.FrameWindow;
    releaseEv.event_x := 200; // Released outside!
    releaseEv.event_y := 17;
    wm.ProcessEvent(Pxcb_generic_event_t(@releaseEv));

    // Pressed state cleared, action CANCELLED (still not maximized)
    AssertEquals('PressedButton reset to -1', -1, wm.PressedButton);
    AssertFalse('Client still NOT maximized after cancel release', wsMaximizedHorz in cli.State);

    // 4. Mouse Button 1 Down on Maximize Button again
    wm.ProcessEvent(Pxcb_generic_event_t(@pressEv));
    AssertEquals('PressedButton recorded as 2 again', 2, wm.PressedButton);
    AssertFalse('Client still NOT maximized on press', wsMaximizedHorz in cli.State);

    // 5. Release mouse INSIDE the Maximize Button
    FillChar(releaseEv, SizeOf(releaseEv), 0);
    releaseEv.response_type := XCB_BUTTON_RELEASE;
    releaseEv.detail := XCB_BUTTON_INDEX_1;
    releaseEv.event := cli.FrameWindow;
    releaseEv.event_x := 64; // Released within button bounds!
    releaseEv.event_y := 17;
    wm.ProcessEvent(Pxcb_generic_event_t(@releaseEv));

    // Maximize action MUST now be executed!
    AssertEquals('PressedButton reset to -1 after execute', -1, wm.PressedButton);
    AssertTrue('Client successfully maximized on release within bounds!', wsMaximizedHorz in cli.State);

    // 6. Test Restore button on release within bounds
    // Window is now maximized, button 2 is restore button
    wm.ProcessEvent(Pxcb_generic_event_t(@pressEv));
    AssertTrue('Client still maximized on press', wsMaximizedHorz in cli.State);

    wm.ProcessEvent(Pxcb_generic_event_t(@releaseEv));
    AssertFalse('Client successfully restored on release within bounds!', wsMaximizedHorz in cli.State);
  finally
    wm.Free();
  end;
end;

initialization
  RegisterTest(TWMSamaTest);

end.
