unit wmsama.test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Floria.XCB,
  Floria.XCB.WM,
  Floria.XCB.WM.Compositor,
  Floria.Image.Core,
  wmsama.core;

type
  TWMSamaTest = class(TTestCase)
  published
    procedure TestWMCreation();
    procedure TestDesktopConfiguration();
    procedure TestCompositorConfiguration();
    procedure TestClientCompositorIntegration();
    procedure TestFrameMetricsAndTitlebar();
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
    AssertEquals('Default titlebar height', 28, wm.TitlebarHeight);
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
begin
  wm := TWMSamaCompositingWM.Create(nil, 0);
  try
    metrics := wm.FrameMetrics;
    AssertEquals('FrameMetrics titlebar height', 28, metrics.TitlebarHeight);
    AssertEquals('FrameMetrics top inset matches titlebar + border', 29, metrics.Insets.Top);

    // Update titlebar height
    wm.TitlebarHeight := 32;
    AssertEquals('Updated titlebar height', 32, wm.TitlebarHeight);
    metrics := wm.FrameMetrics;
    AssertEquals('FrameMetrics titlebar height updated', 32, metrics.TitlebarHeight);
  finally
    wm.Free();
  end;
end;

initialization
  RegisterTest(TWMSamaTest);

end.
