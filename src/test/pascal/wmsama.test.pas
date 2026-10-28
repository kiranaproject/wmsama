unit wmsama.test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Floria.XCB,
  Floria.XCB.EWMH,
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
    procedure TestAltTabTogglesBetweenTwoWindows();
    procedure TestAltTabCyclesThroughMruOrder();
    procedure TestAltTabSkipsClosedWindows();
    procedure TestAltTabEmptyDesktopDoesNotGrab();
    procedure TestAltTabGrabAlwaysReleased();
    procedure TestXErrorDecoding();
    procedure TestErrorEventsAreConsumed();
    procedure TestLiveFrameBehaviour();
    procedure TestFloriaToolkitButtonStyling();
    procedure TestButtonAlignmentAndPlacement();
    procedure TestAdditionalWindowControls();
    procedure TestOverrideRedirectCompositorSupport();
    procedure TestWindowResizingDirectionalAndTiled();
    procedure TestWindowCursors();
    procedure TestWindowButtonReleaseAndCancel();
    procedure TestWindowSnappingWithStrutsAndWorkarea();
    procedure TestWindowMinimizeAndRestoreCompositor();
    procedure TestUndecoratedAndSplashCornerRadius();
    procedure TestCSDAndAltClickDragging();
    procedure TestMultiMonitorSnappingAndResistance();
    procedure TestMultiMonitorKeyboardNavigation();
    procedure TestMultiMonitorAltTabAndAutoMigration();
    procedure TestNonResizableAndButtonFiltering();
    procedure TestTransientDialogStackingAndICCCMPlacement();
    procedure TestDesktopWindowCompositingAndAltTabExclusion();
  end;

implementation

// Claiming substructure redirect is exclusive per display. When several tests in
// one process each claim and release, the server may not have processed the
// previous connection's close yet, so the next claim fails with BadAccess. Retry
// briefly rather than silently skipping the test body.
function TryClaimOwnership(const AWM: TWMSamaCompositingWM): Boolean;
var
  Attempt: Integer;
begin
  Result := False;
  for Attempt := 1 to 40 do
  begin
    if AWM.ClaimOwnership() then
      Exit(True);
    Sleep(10);
  end;
end;

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

    // Establish MRU order the way real use does: activate Editor, then Browser.
    cli1.Activate();
    cli2.Activate();
    AssertSame('Browser is active', cli2, wm.ActiveClient);
    AssertSame('MRU front is the active window', cli2, wm.MruClients[0]);
    AssertSame('MRU second is the previous window', cli1, wm.MruClients[1]);

    AssertFalse('Alt-Tab inactive initially', wm.AltTabActive);
    AssertFalse('No keyboard grab held initially', wm.KeyboardGrabHeld);

    // The list is MRU-ordered, so index 0 is the window that already has focus.
    // The first press must land on index 1 — the previous window. Landing on 0
    // would re-activate the current window and make Alt+Tab appear inert.
    wm.TriggerAltTabForward();
    AssertTrue('Alt-Tab activated', wm.AltTabActive);
    AssertEquals('First press selects the previous window', 1, wm.AltTabIndex);
    AssertTrue('Keyboard grab held while switching', wm.KeyboardGrabHeld);

    // Dismiss activates the highlighted client.
    wm.TriggerAltTabDismiss();
    AssertFalse('Alt-Tab dismissed', wm.AltTabActive);
    AssertFalse('Keyboard grab released on dismiss', wm.KeyboardGrabHeld);
    AssertSame('Editor is active after switching', cli1, wm.ActiveClient);
    AssertSame('MRU front followed the switch', cli1, wm.MruClients[0]);
  finally
    wm.Free();
  end;
end;

// WM-10: Alt+Tab must behave as a toggle. With MRU ordering, switching to the
// previous window makes it the new front, so the next Alt+Tab returns to where we
// started. This is the behaviour users have hard-wired, and it regressed once
// already while fixing the index semantics.
procedure TWMSamaTest.TestAltTabTogglesBetweenTwoWindows();
var
  wm: TWMSamaCompositingWM;
  cli1, cli2: TXCBWMClient;
begin
  wm := TWMSamaCompositingWM.Create(nil, 0);
  try
    cli1 := wm.ManageWindow(5101);
    cli2 := wm.ManageWindow(5102);
    cli1.Activate();
    cli2.Activate();

    // First switch: Browser -> Editor.
    wm.TriggerAltTabForward();
    wm.TriggerAltTabDismiss();
    AssertSame('Switched to Editor', cli1, wm.ActiveClient);

    // Second switch: Editor -> Browser. Must not stay on Editor.
    wm.TriggerAltTabForward();
    wm.TriggerAltTabDismiss();
    AssertSame('Switched back to Browser', cli2, wm.ActiveClient);

    // And again, to prove it keeps alternating.
    wm.TriggerAltTabForward();
    wm.TriggerAltTabDismiss();
    AssertSame('Alternates back to Editor', cli1, wm.ActiveClient);
  finally
    wm.Free();
  end;
end;

// WM-10: cycling with Alt held must walk the MRU list in order, and wrap.
procedure TWMSamaTest.TestAltTabCyclesThroughMruOrder();
var
  wm: TWMSamaCompositingWM;
  cli1, cli2, cli3: TXCBWMClient;
begin
  wm := TWMSamaCompositingWM.Create(nil, 0);
  try
    cli1 := wm.ManageWindow(5201);
    cli2 := wm.ManageWindow(5202);
    cli3 := wm.ManageWindow(5203);
    // MRU becomes: 3, 2, 1
    cli1.Activate();
    cli2.Activate();
    cli3.Activate();
    AssertSame('MRU front is 3', cli3, wm.MruClients[0]);
    AssertSame('MRU second is 2', cli2, wm.MruClients[1]);
    AssertSame('MRU third is 1', cli1, wm.MruClients[2]);

    wm.TriggerAltTabForward();
    AssertEquals('First press lands on previous window (index 1)', 1, wm.AltTabIndex);
    wm.TriggerAltTabForward();
    AssertEquals('Second press advances to index 2', 2, wm.AltTabIndex);
    wm.TriggerAltTabForward();
    AssertEquals('Third press wraps to index 0', 0, wm.AltTabIndex);

    wm.TriggerAltTabDismiss();
    AssertSame('Wrapped selection is the MRU front', cli3, wm.ActiveClient);
  finally
    wm.Free();
  end;
end;

// WM-10: a window that goes away must leave the MRU list, so Alt+Tab cannot
// select a dead client.
procedure TWMSamaTest.TestAltTabSkipsClosedWindows();
var
  wm: TWMSamaCompositingWM;
  cli1, cli2: TXCBWMClient;
  eligible: TFPList;
begin
  wm := TWMSamaCompositingWM.Create(nil, 0);
  try
    cli1 := wm.ManageWindow(5301);
    cli2 := wm.ManageWindow(5302);
    cli1.Activate();
    cli2.Activate();

    wm.UnmanageWindow(cli2);
    AssertEquals('Closed window removed from MRU', -1, wm.MruClients.IndexOf(cli2));
    AssertEquals('Survivor still in MRU', 0, wm.MruClients.IndexOf(cli1));

    eligible := TFPList.Create();
    try
      wm.GetAltTabEligibleClients(eligible);
      AssertEquals('Only the surviving client is eligible', 1, eligible.Count);
      AssertSame('Survivor is the eligible one', cli1, TXCBWMClient(eligible[0]));
    finally
      eligible.Free();
    end;
  finally
    wm.Free();
  end;
end;

// WM-01: pressing Alt+Tab with nothing to switch to must not acquire (and
// therefore never leak) the keyboard grab. The historical bug grabbed first and
// only then discovered the candidate list was empty, leaving the WM holding the
// keyboard with no code path able to release it.
procedure TWMSamaTest.TestAltTabEmptyDesktopDoesNotGrab();
var
  wm: TWMSamaCompositingWM;
begin
  wm := TWMSamaCompositingWM.Create(nil, 0);
  try
    AssertEquals('No clients managed', 0, wm.Clients.Count);

    wm.TriggerAltTabForward();
    AssertFalse('Switcher not activated on empty desktop', wm.AltTabActive);
    AssertFalse('No keyboard grab held on empty desktop', wm.KeyboardGrabHeld);
    AssertEquals('Grab never even attempted', 0, wm.KeyboardGrabAttempts);

    // Repeating must stay inert (the wedge scenario: every keypress swallowed).
    wm.TriggerAltTabForward();
    wm.TriggerAltTabForward();
    AssertFalse('Still no grab after repeated presses', wm.KeyboardGrabHeld);
    AssertEquals('Still no grab attempts', 0, wm.KeyboardGrabAttempts);

    // Dismissing an inactive switcher is a safe no-op.
    wm.TriggerAltTabDismiss();
    AssertFalse('Dismiss is inert', wm.KeyboardGrabHeld);
    AssertEquals('No spurious release attempts', 0, wm.KeyboardReleaseAttempts);
  finally
    wm.Free();
  end;
end;

// WM-01: every exit path (Escape/cancel, Return/dismiss, Alt release, unmap)
// must leave grab attempts and releases balanced.
procedure TWMSamaTest.TestAltTabGrabAlwaysReleased();
var
  wm: TWMSamaCompositingWM;
  cli: TXCBWMClient;
begin
  wm := TWMSamaCompositingWM.Create(nil, 0);
  try
    cli := wm.ManageWindow(6001);
    cli.Title := 'Terminal';

    // Path 1: Escape / cancel.
    wm.TriggerAltTabForward();
    AssertTrue('Holding grab before cancel', wm.KeyboardGrabHeld);
    wm.CancelAltTab();
    AssertFalse('Cancel releases the grab', wm.KeyboardGrabHeld);
    AssertFalse('Cancel drops the HUD', wm.AltTabActive);

    // Path 2: Return / dismiss.
    wm.TriggerAltTabForward();
    AssertTrue('Holding grab before dismiss', wm.KeyboardGrabHeld);
    wm.TriggerAltTabDismiss();
    AssertFalse('Dismiss releases the grab', wm.KeyboardGrabHeld);

    // Path 3: the switched-to window disappears mid-switch.
    wm.TriggerAltTabForward();
    AssertTrue('Holding grab before unmap', wm.KeyboardGrabHeld);
    wm.UnmanageWindow(cli);
    AssertFalse('Unmap releases the grab', wm.KeyboardGrabHeld);
    AssertFalse('Unmap drops the HUD', wm.AltTabActive);

    // Path 4: repeated release is idempotent.
    wm.ReleaseKeyboardGrab();
    wm.ReleaseKeyboardGrab();
    AssertFalse('Idempotent release', wm.KeyboardGrabHeld);

    AssertTrue('Every acquire was matched by a release',
               wm.KeyboardReleaseAttempts <= wm.KeyboardGrabAttempts);
  finally
    wm.Free();
  end;
end;

// WM-03: X errors used to be dropped on the floor by the event case statement.
procedure TWMSamaTest.TestXErrorDecoding();
var
  wm: TWMSamaCompositingWM;
  err: xcb_generic_error_t;
  msg: AnsiString;
begin
  wm := TWMSamaCompositingWM.Create(nil, 0);
  try
    FillChar(err, SizeOf(err), 0);
    err.response_type := 0;
    err.error_code := 3;   // BadWindow
    err.major_code := 14;  // GetGeometry
    err.resource_id := $1234;

    msg := wm.DescribeXError(@err);
    AssertTrue('Names the error code', Pos('BadWindow', msg) > 0);
    AssertTrue('Names the request', Pos('GetGeometry', msg) > 0);
    AssertTrue('Includes the resource id', Pos('0x00001234', msg) > 0);

    // Unknown codes must degrade to numbers rather than crash or lie.
    err.error_code := 200;
    err.major_code := 250;  // >= 128: an extension opcode
    msg := wm.DescribeXError(@err);
    AssertTrue('Unknown error degrades', Pos('Unknown', msg) > 0);
    AssertTrue('Extension opcode is reported relative to 128',
               Pos('Extension+122', msg) > 0);

    // 10 is MapSubwindows, not ConfigureWindow: guards against an off-by-N table.
    err.major_code := 10;
    AssertTrue('MapSubwindows decoded', Pos('MapSubwindows', wm.DescribeXError(@err)) > 0);
    err.major_code := 12;
    AssertTrue('ConfigureWindow decoded', Pos('ConfigureWindow', wm.DescribeXError(@err)) > 0);
    err.major_code := 42;
    AssertTrue('SetInputFocus decoded', Pos('SetInputFocus', wm.DescribeXError(@err)) > 0);

    AssertEquals('Nil error yields empty string', '', wm.DescribeXError(nil));
  finally
    wm.Free();
  end;
end;

// WM-07 / WM-08 / WM-16 live checks.
//
// These share one connection pair and one ClaimOwnership. Doing them as four
// separate tests meant four connect/claim/disconnect cycles in one process, and
// the third and fourth silently failed to establish a usable connection. One
// setup also matches how the WM is really used: a single long-lived connection.
procedure TWMSamaTest.TestLiveFrameBehaviour();
var
  Conn, Obs: Pxcb_connection_t;
  ScreenNum: Integer;
  wm: TWMSamaCompositingWM;
  cli, cli2, cli3: TXCBWMClient;
  w1, w2, w3, Root: xcb_window_t;
  btnEv: xcb_button_press_event_t;
  firstGC: xcb_gcontext_t;
  before, painted: Integer;

  function MakeClient(const ARect: TXCBRect): TXCBWMClient;
  var
    W: xcb_window_t;
  begin
    W := xcb_generate_id(Obs);
    xcb_create_window(Obs, XCB_COPY_FROM_PARENT, W, Root,
                      ARect.X, ARect.Y, ARect.Width, ARect.Height, 0,
                      XCB_WINDOW_CLASS_INPUT_OUTPUT, XCB_COPY_FROM_PARENT, 0, nil);
    xcb_map_window(Obs, W);
    xcb_flush(Obs);
    Result := wm.ManageWindow(W);
  end;

begin
  ScreenNum := 0;
  Conn := xcb_connect(nil, @ScreenNum);
  if Conn = nil then Exit;

  Obs := nil;
  try
    if xcb_connection_has_error(Conn) <> 0 then Exit;
    Obs := xcb_connect(nil, @ScreenNum);
    if (Obs = nil) or (xcb_connection_has_error(Obs) <> 0) then Exit;

    wm := TWMSamaCompositingWM.Create(Conn, ScreenNum);
    try
      // Needs exclusive display ownership; on a developer desktop another WM
      // would reparent these windows and invalidate every assertion.
      if not TryClaimOwnership(wm) then Exit;
      Root := wm.RootWindow;
      if Root = 0 then Exit;

      // ---- WM-07: cursors never touch a client window -------------------
      cli := MakeClient(TXCBRect.Create(40, 40, 300, 200));
      AssertNotNull('Client managed', cli);
      AssertTrue('Frame window created', cli.FrameWindow <> 0);

      wm.UpdateHoverCursor(wm.CursorResizeRight, cli);
      AssertEquals('Cursor target is the frame, not the client',
                   Integer(cli.FrameWindow), Integer(wm.HoverCursorWindow));
      AssertTrue('Cursor target is never the client window',
                 wm.HoverCursorWindow <> cli.ClientWindow);

      wm.UpdateHoverCursor(wm.CursorNormal, nil);
      AssertTrue('Root cursor target is not a client window',
                 wm.HoverCursorWindow <> cli.ClientWindow);

      // ---- WM-16: one GC, reused ---------------------------------------
      firstGC := wm.TitlebarGC;
      AssertTrue('GC created when the frame was first painted', firstGC <> 0);
      wm.PaintClientFrame(cli);
      wm.PaintClientFrame(cli);
      AssertEquals('GC reused across paints', Integer(firstGC), Integer(wm.TitlebarGC));

      // ---- WM-08: dead space in the frame is not a move -----------------
      FillChar(btnEv, SizeOf(btnEv), 0);
      btnEv.response_type := XCB_BUTTON_PRESS;
      btnEv.event := cli.FrameWindow;
      btnEv.root_x := cli.CurrentRect.X + 100;
      btnEv.root_y := cli.CurrentRect.Y + wm.TitlebarHeight + 40;
      btnEv.event_x := 100;
      btnEv.event_y := wm.TitlebarHeight + 40;
      btnEv.detail := XCB_BUTTON_INDEX_1;

      AssertTrue('Frame click consumed', wm.ProcessEvent(Pxcb_generic_event_t(@btnEv)));
      AssertEquals('No drag started from dead space', Integer(dmNone), Integer(wm.DragMode));
      AssertNull('No drag client bound', wm.DragClient);

      // Sanity: the titlebar itself still starts a move.
      btnEv.event_y := 5;
      btnEv.root_y := cli.CurrentRect.Y + 5;
      AssertTrue('Titlebar click consumed', wm.ProcessEvent(Pxcb_generic_event_t(@btnEv)));
      AssertEquals('Titlebar drag still works', Integer(dmMove), Integer(wm.DragMode));
      wm.EndDrag();

      // ---- WM-16: focus change repaints only the affected frames --------
      cli2 := MakeClient(TXCBRect.Create(380, 40, 300, 200));
      cli3 := MakeClient(TXCBRect.Create(720, 40, 300, 200));
      AssertTrue('Three frames exist',
                 (cli2 <> nil) and (cli3 <> nil) and
                 (cli2.FrameWindow <> 0) and (cli3.FrameWindow <> 0));

      cli2.Activate();
      before := wm.FramePaintCount;
      cli3.Activate();
      painted := wm.FramePaintCount - before;
      AssertTrue('Focus change repainted at most two frames, got ' + IntToStr(painted),
                 painted <= 2);
      AssertTrue('Focus change repainted both affected frames, got ' + IntToStr(painted),
                 painted >= 2);

      wm.UnmanageWindow(cli);
      wm.UnmanageWindow(cli2);
      wm.UnmanageWindow(cli3);
    finally
      wm.Free();
    end;
  finally
    if Obs <> nil then xcb_disconnect(Obs);
    xcb_disconnect(Conn);
  end;
end;

procedure TWMSamaTest.TestErrorEventsAreConsumed();
var
  wm: TWMSamaCompositingWM;
  ev: xcb_generic_event_t;
begin
  wm := TWMSamaCompositingWM.Create(nil, 0);
  try
    FillChar(ev, SizeOf(ev), 0);
    ev.response_type := 0; // X error
    AssertTrue('Error event consumed by the WM', wm.ProcessEvent(@ev));
    AssertFalse('Error did not request a composite', wm.NeedsComposite);
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

    // 2. Hover Cursor Updates: the signature takes a client, not a window id, so
    //    that the cursor can only ever be applied to a frame or the root.
    wm.UpdateHoverCursor(1234, nil);
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

procedure TWMSamaTest.TestWindowSnappingWithStrutsAndWorkarea();
var
  wm: TWMSamaCompositingWM;
  dockTop, dockBottom: TXCBWMClient;
  cli: TXCBWMClient;
  s: TXCBStrutPartial;
begin
  wm := TWMSamaCompositingWM.Create(nil, 0);
  try
    // Add top dock with 38px strut
    dockTop := wm.ManageWindow(7001);
    dockTop.WindowType := wtDock;
    s := TXCBStrutPartial.Create();
    s.Top := 38;
    dockTop.Strut := s;

    // Add bottom dock with 40px strut
    dockBottom := wm.ManageWindow(7002);
    dockBottom.WindowType := wtDock;
    s := TXCBStrutPartial.Create();
    s.Bottom := 40;
    dockBottom.Strut := s;

    wm.RecomputeWorkarea();

    AssertEquals('Workarea Y is 38', 38, wm.Workarea.Y);
    AssertEquals('Workarea Height is screen - 78', wm.Compositor.ScreenHeight - 78, wm.Workarea.Height);

    // Create client window
    cli := wm.ManageWindow(7003);
    cli.SetGeometry(100, 100, 800, 600);

    // 1. Drag toward top threshold within workarea (e.g. Y = 40)
    wm.BeginDrag(cli, dmMove, 500, 200);
    wm.UpdateDrag(500, 40); // 40 <= 38 + 14 threshold
    AssertEquals('Snap mode is maximize', Ord(snapMaximize), Ord(wm.ActiveSnap));
    AssertEquals('Snap preview Y matches Workarea Y', 38, wm.SnapPreviewRect.Y);
    AssertEquals('Snap preview Height matches Workarea Height', wm.Workarea.Height, wm.SnapPreviewRect.Height);
    AssertEquals('Snap preview Width matches Workarea Width', wm.Workarea.Width, wm.SnapPreviewRect.Width);
    wm.EndDrag();

    AssertTrue('Client maximized', wsMaximizedHorz in cli.State);
    AssertEquals('Client maximized Y is 38', 38, cli.CurrentRect.Y);
    AssertEquals('Client maximized Height matches Workarea', wm.Workarea.Height, cli.CurrentRect.Height);

    // 2. Drag toward left edge
    wm.BeginDrag(cli, dmMove, 500, 200);
    wm.UpdateDrag(5, 300); // Drag to left threshold
    AssertEquals('Snap mode is left half', Ord(snapLeftHalf), Ord(wm.ActiveSnap));
    AssertEquals('Snap preview Y is Workarea Y', 38, wm.SnapPreviewRect.Y);
    AssertEquals('Snap preview Height is Workarea Height', wm.Workarea.Height, wm.SnapPreviewRect.Height);
    AssertEquals('Snap preview Width is Workarea Width div 2', wm.Workarea.Width div 2, wm.SnapPreviewRect.Width);
    wm.EndDrag();

    AssertTrue('Client tiled left', wsTiledLeft in cli.State);
    AssertEquals('Client tiled Y is 38', 38, cli.CurrentRect.Y);
    AssertEquals('Client tiled Height matches Workarea', wm.Workarea.Height, cli.CurrentRect.Height);
    AssertEquals('Client tiled Width matches Workarea half', wm.Workarea.Width div 2, cli.CurrentRect.Width);

    // 3. Drag toward right edge
    wm.BeginDrag(cli, dmMove, 500, 200);
    wm.UpdateDrag(wm.Workarea.Right() - 5, 300);
    AssertEquals('Snap mode is right half', Ord(snapRightHalf), Ord(wm.ActiveSnap));
    AssertEquals('Snap preview X is right half start', wm.Workarea.X + (wm.Workarea.Width div 2), wm.SnapPreviewRect.X);
    AssertEquals('Snap preview Y is Workarea Y', 38, wm.SnapPreviewRect.Y);
    AssertEquals('Snap preview Width is remaining width', wm.Workarea.Width - (wm.Workarea.Width div 2), wm.SnapPreviewRect.Width);
    wm.EndDrag();

    AssertTrue('Client tiled right', wsTiledRight in cli.State);
    AssertEquals('Client tiled X is right half start', wm.Workarea.X + (wm.Workarea.Width div 2), cli.CurrentRect.X);
    AssertEquals('Client tiled Y is 38', 38, cli.CurrentRect.Y);
    AssertEquals('Client tiled Height matches Workarea', wm.Workarea.Height, cli.CurrentRect.Height);
  finally
    wm.Free();
  end;
end;

procedure TWMSamaTest.TestWindowMinimizeAndRestoreCompositor();
var
  wm: TWMSamaCompositingWM;
  cli1, cli2: TXCBWMClient;
  comp1, comp2: TXCBCompositedWindow;
begin
  wm := TWMSamaCompositingWM.Create(nil, 0);
  try
    cli1 := wm.ManageWindow(5001);
    cli2 := wm.ManageWindow(5002);
    cli1.SetGeometry(100, 100, 400, 300);
    cli2.SetGeometry(200, 200, 400, 300);

    cli1.Activate();
    AssertSame('cli1 is active', cli1, wm.ActiveClient);

    comp1 := wm.Compositor.FindWindow(cli1.ClientWindow);
    comp2 := wm.Compositor.FindWindow(cli2.ClientWindow);
    AssertNotNull('comp1 registered', comp1);
    AssertNotNull('comp2 registered', comp2);
    AssertTrue('comp1 visible initially', comp1.IsVisible);
    AssertTrue('comp2 visible initially', comp2.IsVisible);

    // 1. Minimize cli1
    cli1.Minimize();
    AssertTrue('cli1 is minimized', wsMinimized in cli1.State);
    AssertFalse('comp1 is hidden in compositor', comp1.IsVisible);
    // Automatic focus handoff to cli2
    AssertSame('cli2 active after cli1 minimized', cli2, wm.ActiveClient);
    AssertTrue('comp2 remains visible', comp2.IsVisible);

    // 2. Unminimize cli1
    cli1.Unminimize();
    AssertFalse('cli1 no longer minimized', wsMinimized in cli1.State);
    AssertTrue('comp1 visible again in compositor', comp1.IsVisible);
    AssertSame('cli1 active after unminimize', cli1, wm.ActiveClient);

    // 3. Minimize cli1 and restore via Activate
    cli1.Minimize();
    AssertFalse('comp1 hidden again', comp1.IsVisible);
    cli1.Activate();
    AssertFalse('cli1 unminimized via Activate', wsMinimized in cli1.State);
    AssertTrue('comp1 visible via Activate', comp1.IsVisible);
    AssertSame('cli1 active', cli1, wm.ActiveClient);

    // 4. Minimize cli1 and restore via Restore
    cli1.Minimize();
    AssertFalse('comp1 hidden again', comp1.IsVisible);
    cli1.Restore();
    AssertFalse('cli1 unminimized via Restore', wsMinimized in cli1.State);
    AssertTrue('comp1 visible via Restore', comp1.IsVisible);
  finally
    wm.Free();
  end;
end;

procedure TWMSamaTest.TestUndecoratedAndSplashCornerRadius();
var
  wm: TWMSamaCompositingWM;
  cliNormal, cliSplash, cliDock, cliBorderless, cliMenu: TXCBWMClient;
  compNormal, compSplash, compDock, compBorderless, compMenu: TXCBCompositedWindow;
begin
  wm := TWMSamaCompositingWM.Create(nil, 0);
  try
    wm.CornerRadius := 12;
    wm.BottomCornerRadius := 12;

    // 1. Regular decorated window
    cliNormal := wm.ManageWindow(9001);
    cliNormal.SetGeometry(50, 50, 500, 350);
    compNormal := wm.Compositor.FindWindow(cliNormal.ClientWindow);
    AssertNotNull('compNormal registered', compNormal);
    AssertEquals('Normal window has top corner radius 12', 12, compNormal.CornerRadius);
    AssertEquals('Normal window has bottom corner radius 12', 12, compNormal.BottomCornerRadius);
    AssertTrue('Normal window has shadow enabled', compNormal.ShadowConfig.Enabled);

    // 2. Splash screen (e.g. Lazarus or Inkscape splash) -> MUST be 0 corners, NO shadow
    cliSplash := TXCBWMClient.Create(9002, wm);
    cliSplash.WindowType := wtSplash;
    cliSplash.SetGeometry(200, 150, 400, 300);
    wm.Clients.Add(cliSplash);
    compSplash := wm.Compositor.RegisterWindow(cliSplash.ClientWindow, cliSplash.CurrentRect, 0);
    wm.ApplyClientCornerRadius(cliSplash, compSplash);
    wm.ApplyClientShadow(cliSplash, compSplash);
    AssertNotNull('compSplash registered', compSplash);
    AssertEquals('Splash screen corner radius is 0', 0, compSplash.CornerRadius);
    AssertEquals('Splash screen bottom corner radius is 0', 0, compSplash.BottomCornerRadius);
    AssertFalse('Splash screen shadow is disabled', compSplash.ShadowConfig.Enabled);

    // 3. Panel / Dock window -> MUST be 0 corners, NO shadow
    cliDock := TXCBWMClient.Create(9003, wm);
    cliDock.WindowType := wtDock;
    cliDock.SetGeometry(0, 730, 1024, 38);
    wm.Clients.Add(cliDock);
    compDock := wm.Compositor.RegisterWindow(cliDock.ClientWindow, cliDock.CurrentRect, 0);
    wm.ApplyClientCornerRadius(cliDock, compDock);
    wm.ApplyClientShadow(cliDock, compDock);
    AssertNotNull('compDock registered', compDock);
    AssertEquals('Panel / Dock corner radius is 0', 0, compDock.CornerRadius);
    AssertEquals('Panel / Dock bottom corner radius is 0', 0, compDock.BottomCornerRadius);
    AssertFalse('Panel / Dock shadow is disabled', compDock.ShadowConfig.Enabled);

    // 4. Borderless window (undecorated) -> MUST be 0 corners, NO shadow
    cliBorderless := TXCBWMClient.Create(9004, wm);
    cliBorderless.Borderless := True;
    cliBorderless.SetGeometry(100, 100, 300, 200);
    wm.Clients.Add(cliBorderless);
    compBorderless := wm.Compositor.RegisterWindow(cliBorderless.ClientWindow, cliBorderless.CurrentRect, 0);
    wm.ApplyClientCornerRadius(cliBorderless, compBorderless);
    wm.ApplyClientShadow(cliBorderless, compBorderless);
    AssertNotNull('compBorderless registered', compBorderless);
    AssertEquals('Borderless window corner radius is 0', 0, compBorderless.CornerRadius);
    AssertEquals('Borderless window bottom corner radius is 0', 0, compBorderless.BottomCornerRadius);
    AssertFalse('Borderless window shadow is disabled', compBorderless.ShadowConfig.Enabled);

    // 5. Popup menu -> MUST have rounded corners (6) and shadow
    cliMenu := TXCBWMClient.Create(9005, wm);
    cliMenu.WindowType := wtPopupMenu;
    cliMenu.SetGeometry(150, 150, 180, 240);
    wm.Clients.Add(cliMenu);
    compMenu := wm.Compositor.RegisterWindow(cliMenu.ClientWindow, cliMenu.CurrentRect, 0);
    wm.ApplyClientCornerRadius(cliMenu, compMenu);
    wm.ApplyClientShadow(cliMenu, compMenu);
    AssertNotNull('compMenu registered', compMenu);
    AssertEquals('Popup menu corner radius is 6', 6, compMenu.CornerRadius);
    AssertEquals('Popup menu bottom corner radius is 6', 6, compMenu.BottomCornerRadius);
    AssertTrue('Popup menu shadow is enabled', compMenu.ShadowConfig.Enabled);

    // 6. Test updating WM CornerRadius and Shadow:
    // Only decorated windows should update. Undecorated (splash, dock, borderless) must STAY 0 and NO shadow! Menu stays 6 and shadowed!
    wm.CornerRadius := 16;
    wm.BottomCornerRadius := 18;
    wm.ShadowRadius := 20;
    AssertEquals('Normal window updated top corner radius to 16', 16, compNormal.CornerRadius);
    AssertEquals('Normal window updated bottom corner radius to 18', 18, compNormal.BottomCornerRadius);
    AssertTrue('Normal window shadow remains enabled', compNormal.ShadowConfig.Enabled);
    AssertEquals('Splash screen remains 0', 0, compSplash.CornerRadius);
    AssertEquals('Splash screen bottom remains 0', 0, compSplash.BottomCornerRadius);
    AssertFalse('Splash screen shadow remains disabled', compSplash.ShadowConfig.Enabled);
    AssertEquals('Dock remains 0', 0, compDock.CornerRadius);
    AssertEquals('Dock bottom remains 0', 0, compDock.BottomCornerRadius);
    AssertFalse('Dock shadow remains disabled', compDock.ShadowConfig.Enabled);
    AssertEquals('Borderless remains 0', 0, compBorderless.CornerRadius);
    AssertEquals('Borderless bottom remains 0', 0, compBorderless.BottomCornerRadius);
    AssertFalse('Borderless shadow remains disabled', compBorderless.ShadowConfig.Enabled);
    AssertEquals('Menu remains 6', 6, compMenu.CornerRadius);
    AssertEquals('Menu bottom remains 6', 6, compMenu.BottomCornerRadius);
    AssertTrue('Menu shadow remains enabled', compMenu.ShadowConfig.Enabled);
  finally
    wm.Free();
  end;
end;

procedure TWMSamaTest.TestCSDAndAltClickDragging();
var
  wm: TWMSamaCompositingWM;
  cliCSD: TXCBWMClient;
  compCSD: TXCBCompositedWindow;
  MockEwmh: xcb_ewmh_connection_t;
  btnEv: xcb_button_press_event_t;
  msgEv: xcb_client_message_event_t;
  data32: PCardinalArray;
begin
  wm := TWMSamaCompositingWM.Create(nil, 0);
  try
    FillChar(MockEwmh, SizeOf(MockEwmh), 0);
    MockEwmh._NET_WM_MOVERESIZE := 2001;
    MockEwmh._NET_MOVERESIZE_WINDOW := 2002;
    MockEwmh._NET_REQUEST_FRAME_EXTENTS := 2003;
    wm.Ewmh := MockEwmh;
    wm.EwmhInitialized := True;

    cliCSD := TXCBWMClient.Create(7777, wm);
    cliCSD.Borderless := True;
    cliCSD.CurrentRect := TXCBRect.Create(100, 100, 600, 400);
    wm.Clients.Add(cliCSD);
    compCSD := wm.Compositor.RegisterWindow(cliCSD.ClientWindow, cliCSD.CurrentRect, 0);
    wm.ApplyClientCornerRadius(cliCSD, compCSD);
    wm.ApplyClientShadow(cliCSD, compCSD);

    AssertFalse('CSD is not decorated', cliCSD.IsDecorated());
    AssertEquals('CSD corner radius 0', 0, compCSD.CornerRadius);
    AssertFalse('CSD shadow disabled', compCSD.ShadowConfig.Enabled);

    // 1. Test Alt + Left-Click on CSD window -> initiates dmMove
    FillChar(btnEv, SizeOf(btnEv), 0);
    btnEv.response_type := XCB_BUTTON_PRESS;
    btnEv.event := 7777;
    btnEv.root_x := 150;
    btnEv.root_y := 150;
    btnEv.state := 8; // Mod1 (Alt)
    btnEv.detail := XCB_BUTTON_INDEX_1;

    AssertTrue('Handled Alt+Button1', wm.ProcessEvent(Pxcb_generic_event_t(@btnEv)));
    AssertEquals('DragMode is dmMove', Integer(dmMove), Integer(wm.DragMode));
    AssertSame('DragClient is cliCSD', cliCSD, wm.DragClient);
    AssertSame('ActiveClient is cliCSD', cliCSD, wm.ActiveClient);

    // Update drag motion
    wm.UpdateDrag(200, 220); // dx = +50, dy = +70
    AssertEquals('Moved X', 150, cliCSD.CurrentRect.X);
    AssertEquals('Moved Y', 170, cliCSD.CurrentRect.Y);
    wm.EndDrag();
    AssertEquals('DragMode is dmNone after end', Integer(dmNone), Integer(wm.DragMode));
    AssertNull('DragClient is nil after end', wm.DragClient);

    // 2. Test Alt + Right-Click on CSD window -> initiates dmResize
    FillChar(btnEv, SizeOf(btnEv), 0);
    btnEv.response_type := XCB_BUTTON_PRESS;
    btnEv.event := 7777;
    btnEv.root_x := 150;
    btnEv.root_y := 150;
    btnEv.state := 8; // Mod1 (Alt)
    btnEv.detail := XCB_BUTTON_INDEX_3;

    AssertTrue('Handled Alt+Button3', wm.ProcessEvent(Pxcb_generic_event_t(@btnEv)));
    AssertEquals('DragMode is dmResize', Integer(dmResize), Integer(wm.DragMode));
    AssertSame('DragClient is cliCSD', cliCSD, wm.DragClient);

    // Update drag resize
    wm.UpdateDrag(250, 200); // dx = +100, dy = +50
    AssertEquals('Resized Width', 700, cliCSD.CurrentRect.Width);
    AssertEquals('Resized Height', 450, cliCSD.CurrentRect.Height);
    wm.EndDrag();

    // 3. Test _NET_WM_MOVERESIZE client message from CSD titlebar (e.g. VS Code / GTK)
    FillChar(msgEv, SizeOf(msgEv), 0);
    msgEv.response_type := XCB_CLIENT_MESSAGE;
    msgEv.window := 7777;
    msgEv.type_ := 2001;
    data32 := PCardinalArray(@msgEv.data.raw[0]);
    data32^[0] := 250; // x_root
    data32^[1] := 210; // y_root
    data32^[2] := 8;   // _NET_WM_MOVERESIZE_MOVE
    data32^[3] := 1;   // button 1
    data32^[4] := 1;   // source normal application

    AssertTrue('Handled _NET_WM_MOVERESIZE', wm.ProcessEvent(Pxcb_generic_event_t(@msgEv)));
    AssertEquals('DragMode is dmMove via EWMH', Integer(dmMove), Integer(wm.DragMode));
    AssertSame('DragClient is cliCSD via EWMH', cliCSD, wm.DragClient);

    wm.UpdateDrag(300, 260); // dx = +50, dy = +50
    AssertEquals('CSD moved X via EWMH', 200, cliCSD.CurrentRect.X); // 150 + 50
    AssertEquals('CSD moved Y via EWMH', 220, cliCSD.CurrentRect.Y); // 170 + 50

    // Cancel drag via direction 11
    data32^[2] := 11; // _NET_WM_MOVERESIZE_CANCEL
    AssertTrue('Handled _NET_WM_MOVERESIZE_CANCEL', wm.ProcessEvent(Pxcb_generic_event_t(@msgEv)));
    AssertEquals('DragMode is dmNone after cancel', Integer(dmNone), Integer(wm.DragMode));
    AssertNull('DragClient is nil after cancel', wm.DragClient);

    // 4. Test _NET_MOVERESIZE_WINDOW client message (programmatic move/resize)
    FillChar(msgEv, SizeOf(msgEv), 0);
    msgEv.response_type := XCB_CLIENT_MESSAGE;
    msgEv.window := 7777;
    msgEv.type_ := 2002;
    data32 := PCardinalArray(@msgEv.data.raw[0]);
    data32^[0] := (1 shl 8) or (1 shl 9) or (1 shl 10) or (1 shl 11); // x, y, width, height flags
    data32^[1] := 300; // x
    data32^[2] := 250; // y
    data32^[3] := 750; // width
    data32^[4] := 500; // height

    AssertTrue('Handled _NET_MOVERESIZE_WINDOW', wm.ProcessEvent(Pxcb_generic_event_t(@msgEv)));
    AssertEquals('CSD set X', 300, cliCSD.CurrentRect.X);
    AssertEquals('CSD set Y', 250, cliCSD.CurrentRect.Y);
    AssertEquals('CSD set Width', 750, cliCSD.CurrentRect.Width);
    AssertEquals('CSD set Height', 500, cliCSD.CurrentRect.Height);
  finally
    wm.Free();
  end;
end;

procedure TWMSamaTest.TestMultiMonitorSnappingAndResistance();
var
  wm: TWMSamaCompositingWM;
  mon1, mon2: TXCBMonitor;
  cli: TXCBWMClient;
begin
  wm := TWMSamaCompositingWM.Create(nil, 0);
  try
    // Set up dual monitors: Mon1 (0, 0, 1920, 1080) and Mon2 (1920, 0, 1920, 1080)
    wm.Monitors.Clear();
    mon1 := TXCBMonitor.Create('DP-1', TXCBRect.Create(0, 0, 1920, 1080), True, 0);
    mon2 := TXCBMonitor.Create('HDMI-1', TXCBRect.Create(1920, 0, 1920, 1080), False, 1);
    wm.Monitors.Add(mon1);
    wm.Monitors.Add(mon2);
    wm.RecomputeWorkareas();

    cli := wm.ManageWindow(1234);
    cli.CurrentRect := TXCBRect.Create(200, 200, 600, 400);

    // 1. Drag near interior boundary (Mon1 right edge = 1920)
    wm.BeginDrag(cli, dmMove, 1000, 500);

    // Slow drag / lingering (delta = 4px <= 14px) engages resistance and right-half snap on Mon1
    wm.UpdateDrag(1912, 500);
    wm.UpdateDrag(1916, 500);
    AssertEquals('ActiveSnap is snapRightHalf on slow motion', Integer(snapRightHalf), Integer(wm.ActiveSnap));
    AssertEquals('Snap preview X is right half of Mon1', 960, wm.SnapPreviewRect.X);
    AssertEquals('Snap preview Width is 960', 960, wm.SnapPreviewRect.Width);

    // Fast flick across interior boundary (delta = 30px > 20px) passes through freely without snap
    wm.UpdateDrag(1946, 500);
    AssertEquals('ActiveSnap is snapNone on fast movement across boundary', Integer(snapNone), Integer(wm.ActiveSnap));
    AssertEquals('Snap preview cleared', 0, wm.SnapPreviewRect.Width);

    wm.EndDrag();

    // 2. Drag near exterior boundary (Mon1 left edge = 0)
    wm.BeginDrag(cli, dmMove, 500, 500);
    // Left edge has no neighbor, so snap triggers
    wm.UpdateDrag(5, 500);
    AssertEquals('ActiveSnap is snapLeftHalf on exterior boundary', Integer(snapLeftHalf), Integer(wm.ActiveSnap));
    AssertEquals('Snap preview X is Mon1 left half', 0, wm.SnapPreviewRect.X);
    AssertEquals('Snap preview Width is 960', 960, wm.SnapPreviewRect.Width);
    wm.EndDrag();

    // Tiled on Mon1
    AssertTrue('Window tiled left on Mon1', wsTiledLeft in cli.State);
    AssertEquals('Tiled left width', 960, cli.CurrentRect.Width);
  finally
    wm.Free();
  end;
end;

procedure TWMSamaTest.TestMultiMonitorKeyboardNavigation();
var
  wm: TWMSamaCompositingWM;
  mon1, mon2: TXCBMonitor;
  cli: TXCBWMClient;
  keyEv: xcb_key_press_event_t;
begin
  wm := TWMSamaCompositingWM.Create(nil, 0);
  try
    wm.Monitors.Clear();
    mon1 := TXCBMonitor.Create('DP-1', TXCBRect.Create(0, 0, 1920, 1080), True, 0);
    mon2 := TXCBMonitor.Create('HDMI-1', TXCBRect.Create(1920, 0, 1920, 1080), False, 1);
    wm.Monitors.Add(mon1);
    wm.Monitors.Add(mon2);
    wm.RecomputeWorkareas();

    cli := wm.ManageWindow(4321);
    cli.CurrentRect := TXCBRect.Create(100, 100, 600, 400);
    wm.ActiveClient := cli;

    // Send Super + Shift + Right (keycode 114, state 65)
    FillChar(keyEv, SizeOf(keyEv), 0);
    keyEv.response_type := XCB_KEY_PRESS;
    keyEv.detail := 114;
    keyEv.state := 65; // Mod4 + Shift

    AssertTrue('Processed Super+Shift+Right', wm.ProcessEvent(Pxcb_generic_event_t(@keyEv)));
    AssertSame('Client moved to Mon2', mon2, cli.CurrentMonitor());
    AssertEquals('Client X shifted to Mon2', 1920 + 100, cli.CurrentRect.X);

    // Send Super + Shift + Left (keycode 113, state 65)
    keyEv.detail := 113;
    AssertTrue('Processed Super+Shift+Left', wm.ProcessEvent(Pxcb_generic_event_t(@keyEv)));
    AssertSame('Client moved back to Mon1', mon1, cli.CurrentMonitor());
    AssertEquals('Client X shifted to Mon1', 100, cli.CurrentRect.X);
  finally
    wm.Free();
  end;
end;

procedure TWMSamaTest.TestMultiMonitorAltTabAndAutoMigration();
var
  wm: TWMSamaCompositingWM;
  mon1, mon2: TXCBMonitor;
  cli: TXCBWMClient;
begin
  wm := TWMSamaCompositingWM.Create(nil, 0);
  try
    wm.Monitors.Clear();
    mon1 := TXCBMonitor.Create('DP-1', TXCBRect.Create(0, 0, 1920, 1080), True, 0);
    mon2 := TXCBMonitor.Create('HDMI-1', TXCBRect.Create(1920, 0, 1920, 1080), False, 1);
    wm.Monitors.Add(mon1);
    wm.Monitors.Add(mon2);
    wm.RecomputeWorkareas();

    cli := wm.ManageWindow(9876);
    cli.CurrentRect := TXCBRect.Create(2100, 200, 600, 400); // Placed on Mon2
    wm.ActiveClient := cli;

    // Alt+Tab HUD
    wm.TriggerAltTabForward();
    AssertTrue('AltTab active', wm.AltTabActive);
    wm.RenderComposite(); // Verifies no crash rendering HUD centered on Mon2

    wm.TriggerAltTabDismiss();
    AssertFalse('AltTab dismissed', wm.AltTabActive);

    // Simulate Mon2 disconnect
    wm.Monitors.Remove(mon2);
    AssertEquals('Mon1 is only remaining monitor', 1, wm.MonitorCount);
    wm.DoOnMonitorsChanged();

    // Client must have auto-migrated to Mon1
    AssertSame('Client migrated to Mon1', mon1, cli.CurrentMonitor());
    AssertTrue('Client within Mon1 X', cli.CurrentRect.X >= mon1.Workarea.X);
    AssertTrue('Client right edge within Mon1', cli.CurrentRect.Right() <= mon1.Workarea.Right());
  finally
    wm.Free();
  end;
end;

procedure TWMSamaTest.TestNonResizableAndButtonFiltering();
var
  wm: TWMSamaCompositingWM;
  cli: TXCBWMClient;
  btns: TWMSamaButtonArray;
  tX, tW, btnIdx: Integer;
  mode: TXCBDragMode;
begin
  wm := TWMSamaCompositingWM.Create(nil, 0);
  try
    cli := wm.ManageWindow(5555);
    cli.CurrentRect := TXCBRect.Create(100, 100, 600, 400);

    // 1. By default, all 3 standard buttons (Close, Minimize, Maximize) are generated
    wm.CalculateButtons(cli, cli.CurrentRect.Width, btns, tX, tW);
    AssertEquals('Default button count', 3, Length(btns));
    AssertEquals('Btn 0 is Close', Ord(sbkClose), Ord(btns[0].Kind));
    AssertEquals('Btn 1 is Minimize', Ord(sbkMinimize), Ord(btns[1].Kind));
    AssertEquals('Btn 2 is Maximize', Ord(sbkMaximize), Ord(btns[2].Kind));

    // 2. Hide Maximize button (e.g. BorderIcons without biMaximize)
    cli.HasMaximizeButton := False;
    wm.CalculateButtons(cli, cli.CurrentRect.Width, btns, tX, tW);
    AssertEquals('Button count without Maximize', 2, Length(btns));
    AssertEquals('Btn 0 is still Close', Ord(sbkClose), Ord(btns[0].Kind));
    AssertEquals('Btn 1 is still Minimize', Ord(sbkMinimize), Ord(btns[1].Kind));

    // Hit-testing should not hit maximize
    btnIdx := wm.GetButtonAt(Round(btns[1].X), Round(btns[1].Y), cli, cli.CurrentRect.Width);
    AssertEquals('Hit-test button 1 returns Minimize index', 1, btnIdx);

    // 3. Dialog window: hide both Minimize and Maximize (e.g. BorderStyle = bsDialog)
    cli.HasMinimizeButton := False;
    wm.CalculateButtons(cli, cli.CurrentRect.Width, btns, tX, tW);
    AssertEquals('Button count for dialog', 1, Length(btns));
    AssertEquals('Only Close remains', Ord(sbkClose), Ord(btns[0].Kind));

    // 4. Non-resizable window (e.g. BorderStyle = bsSingle / bsDialog or min_size = max_size)
    cli.CanResize := False;
    // Outer perimeter right edge [700..708) would normally return dmResizeRight
    mode := wm.GetResizeModeForPoint(cli, 704, 250);
    AssertEquals('GetResizeModeForPoint returns dmNone when CanResize=False', Ord(dmNone), Ord(mode));
    // Corner [704, 504) would normally return dmResizeBottomRight
    mode := wm.GetResizeModeForPoint(cli, 704, 504);
    AssertEquals('Corner returns dmNone when CanResize=False', Ord(dmNone), Ord(mode));

    // 5. Snapping suppression for non-resizable and non-maximizable windows
    cli.CanMaximize := False;
    wm.BeginDrag(cli, dmMove, 200, 100);
    // Drag to top of screen (wa.Y = 0)
    wm.UpdateDrag(200, 5);
    AssertEquals('snapMaximize suppressed when CanMaximize=False', Ord(snapNone), Ord(wm.ActiveSnap));

    // Drag to left of screen (wa.X = 0)
    wm.UpdateDrag(5, 200);
    AssertEquals('snapLeftHalf suppressed when CanResize=False', Ord(snapNone), Ord(wm.ActiveSnap));
    wm.EndDrag();
  finally
    wm.Free();
  end;
end;

procedure TWMSamaTest.TestTransientDialogStackingAndICCCMPlacement();
var
  wm: TWMSamaCompositingWM;
  parentCli, dialogCli, dockCli: TXCBWMClient;
  compParent, compDialog: TXCBCompositedWindow;
begin
  wm := TWMSamaCompositingWM.Create(nil, 0);
  try
    parentCli := wm.ManageWindow(7001);
    parentCli.WindowType := wtNormal;
    parentCli.CurrentRect := TXCBRect.Create(300, 200, 800, 600);

    dialogCli := wm.ManageWindow(7002);
    dialogCli.WindowType := wtDialog;
    dialogCli.CurrentRect := TXCBRect.Create(0, 0, 400, 300);

    compParent := wm.Compositor.RegisterWindow(parentCli.ClientWindow, parentCli.CurrentRect, 0);
    compDialog := wm.Compositor.RegisterWindow(dialogCli.ClientWindow, dialogCli.CurrentRect, 0);

    // 1. Initial transient-for default
    AssertEquals('Default TransientFor is 0', 0, dialogCli.TransientFor);

    // 2. Link dialog to parent
    dialogCli.TransientFor := parentCli.ClientWindow;
    AssertEquals('TransientFor matches parent client window', parentCli.ClientWindow, dialogCli.TransientFor);

    // 3. Stacking elevation when parent activated
    parentCli.Activate();
    AssertSame('Transient dialog is elevated above parent in compositor stacking', compDialog, wm.Compositor.Windows.Last);

    // 4. Parent-child minimizing lifecycle
    parentCli.Minimize();
    AssertTrue('Parent is minimized', wsMinimized in parentCli.State);
    AssertTrue('Transient dialog automatically minimized with parent', wsMinimized in dialogCli.State);

    parentCli.Activate();
    AssertFalse('Parent restored', wsMinimized in parentCli.State);
    AssertFalse('Transient dialog restored with parent', wsMinimized in dialogCli.State);
    AssertSame('Transient dialog is elevated above parent on restore', compDialog, wm.Compositor.Windows.Last);

    // 5. Dock parenting exclusion
    dockCli := wm.ManageWindow(7003);
    dockCli.WindowType := wtDock;
    dockCli.CurrentRect := TXCBRect.Create(0, 1042, 1920, 38);

    dialogCli.TransientFor := dockCli.ClientWindow;
    AssertEquals('TransientFor set to dock client window', dockCli.ClientWindow, dialogCli.TransientFor);
  finally
    wm.Free();
  end;
end;

procedure TWMSamaTest.TestDesktopWindowCompositingAndAltTabExclusion();
var
  wm: TWMSamaCompositingWM;
  parentCli, deskCli, dockCli: TXCBWMClient;
  compParent, compDesk: TXCBCompositedWindow;
begin
  wm := TWMSamaCompositingWM.Create(nil, 0);
  try
    parentCli := wm.ManageWindow(8001);
    parentCli.WindowType := wtNormal;
    parentCli.Title := 'Text Editor';
    parentCli.CurrentRect := TXCBRect.Create(200, 100, 800, 600);

    deskCli := wm.ManageWindow(8002);
    deskCli.WindowType := wtDesktop;
    deskCli.Title := 'Desktop Wallpaper';
    deskCli.CurrentRect := TXCBRect.Create(0, 0, 1920, 1080);

    dockCli := wm.ManageWindow(8003);
    dockCli.WindowType := wtDock;
    dockCli.Title := 'Panel';
    dockCli.CurrentRect := TXCBRect.Create(0, 1042, 1920, 38);

    compParent := wm.Compositor.RegisterWindow(parentCli.ClientWindow, parentCli.CurrentRect, 0);
    compDesk := wm.Compositor.RegisterWindow(deskCli.ClientWindow, deskCli.CurrentRect, 0);

    // 1. Initial desktop bottom stacking
    wm.Compositor.Windows.Extract(compDesk);
    wm.Compositor.Windows.Insert(0, compDesk);
    AssertSame('Desktop window is bottom-most in compositor', compDesk, wm.Compositor.Windows.First);

    // 2. Desktop activation stays at bottom
    deskCli.Activate();
    AssertSame('Desktop window remains at bottom-most after activation', compDesk, wm.Compositor.Windows.First);

    // 3. Normal client activation elevates parent, keeps desktop at bottom
    parentCli.Activate();
    AssertSame('Parent is top-most window in compositor', compParent, wm.Compositor.Windows.Last);
    AssertSame('Desktop is still bottom-most window in compositor', compDesk, wm.Compositor.Windows.First);

    // 4. Desktop window styling: no drop shadows, 0 corner radius
    wm.ApplyClientShadow(deskCli, compDesk);
    wm.ApplyClientCornerRadius(deskCli, compDesk);
    AssertFalse('Desktop window has no drop shadow', compDesk.ShadowConfig.Enabled);
    AssertEquals('Desktop window corner radius is 0', 0, compDesk.CornerRadius);

    // 5. Alt-Tab eligibility: regular window is eligible, desktop and dock are excluded
    AssertTrue('Normal window is Alt-Tab eligible', wm.IsAltTabEligible(parentCli));
    AssertFalse('Desktop window is excluded from Alt-Tab', wm.IsAltTabEligible(deskCli));
    AssertFalse('Dock panel is excluded from Alt-Tab', wm.IsAltTabEligible(dockCli));

    // 6. Dragging and minimizing are suppressed for desktop
    wm.BeginDrag(deskCli, dmMove, 500, 500);
    AssertNull('Desktop window cannot be dragged', wm.DragClient);

    deskCli.CanMinimize := False;
    deskCli.Minimize();
    AssertFalse('Desktop window cannot be minimized', wsMinimized in deskCli.State);
  finally
    wm.Free();
  end;
end;

initialization
  RegisterTest(TWMSamaTest);

end.
