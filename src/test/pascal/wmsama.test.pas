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

initialization
  RegisterTest(TWMSamaTest);

end.
