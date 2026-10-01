program wmsama;

// wmsama
// ======
// X11 Compositing Window Manager powered by florialib (Floria.XCB.WM & Floria.XCB.WM.Compositor)
// Designed for Samarinda Desktop Environment.

{$mode objfpc}{$H+}

uses
  SysUtils, BaseUnix,
  Floria.XCB,
  Floria.XCB.WM,
  Floria.XCB.WM.Compositor,
  wmsama.core;

var
  WM                : TWMSamaCompositingWM;
  Conn              : Pxcb_connection_t;
  ScreenNum         : Integer;
  DisplayStr        : AnsiString;
  PDisplay          : PAnsiChar;
  CompositorEnabled : Boolean;
  BlurEnabled       : Boolean;
  BlurRadius        : Integer;
  ShadowRadius      : Integer;
  ShadowOpacity     : Single;
  I                 : Integer;
  Arg               : AnsiString;

procedure PrintUsage();
begin
  WriteLn('Usage: wmsama [options]');
  WriteLn('');
  WriteLn('Options:');
  WriteLn('  --help                 Show this help message');
  WriteLn('  --version              Show wmsama version');
  WriteLn('  --display <name>       Target X11 display (e.g. :2)');
  WriteLn('  --no-compositor        Run as pure reparenting WM without compositing');
  WriteLn('  --blur                 Enable real-time frosted glass backdrop blur');
  WriteLn('  --blur-radius <int>    Backdrop blur radius (default: 15)');
  WriteLn('  --shadow-radius <int>  Drop shadow radius (default: 14)');
  WriteLn('  --shadow-opacity <flt> Drop shadow opacity (default: 0.35)');
end;

procedure SigHandler(Sig: LongInt); cdecl;
begin
  WriteLn('');
  WriteLn('[wmsama] Received signal (', Sig, '). Terminating gracefully...');
  if WM <> nil then
    WM.Stop();
  Halt(0);
end;

begin
  WriteLn('wmsama — X11 Compositing Window Manager (Samarinda DE)');
  WriteLn('Powered by florialib, AggPas & XCB');

  DisplayStr := '';
  CompositorEnabled := True;
  BlurEnabled := False;
  BlurRadius := 15;
  ShadowRadius := 14;
  ShadowOpacity := 0.35;

  I := 1;
  while I <= ParamCount do
  begin
    Arg := ParamStr(I);
    if (Arg = '--help') or (Arg = '-h') then
    begin
      PrintUsage();
      Halt(0);
    end
    else if (Arg = '--version') or (Arg = '-v') then
    begin
      WriteLn('wmsama 0.0.1-SNAPSHOT');
      Halt(0);
    end
    else if Arg = '--no-compositor' then
      CompositorEnabled := False
    else if Arg = '--blur' then
      BlurEnabled := True
    else if (Arg = '--blur-radius') and (I < ParamCount) then
    begin
      Inc(I);
      BlurRadius := StrToIntDef(ParamStr(I), 15);
    end
    else if (Arg = '--shadow-radius') and (I < ParamCount) then
    begin
      Inc(I);
      ShadowRadius := StrToIntDef(ParamStr(I), 14);
    end
    else if (Arg = '--shadow-opacity') and (I < ParamCount) then
    begin
      Inc(I);
      ShadowOpacity := StrToFloatDef(ParamStr(I), 0.35);
    end
    else if (Arg = '--display') and (I < ParamCount) then
    begin
      Inc(I);
      DisplayStr := ParamStr(I);
    end
    else
    begin
      WriteLn(StdErr, 'Warning: Unrecognized option: ', Arg);
    end;
    Inc(I);
  end;

  // Setup signal handling
  fpSignal(SIGINT, SignalHandler(@SigHandler));
  fpSignal(SIGTERM, SignalHandler(@SigHandler));

  // Connect to X11 server
  ScreenNum := 0;
  if DisplayStr <> '' then
    PDisplay := PAnsiChar(DisplayStr)
  else
    PDisplay := nil;

  Conn := xcb_connect(PDisplay, @ScreenNum);
  if (Conn = nil) or (xcb_connection_has_error(Conn) <> 0) then
  begin
    WriteLn(StdErr, 'Error: Unable to connect to X11 display (', DisplayStr, ').');
    Halt(1);
  end;

  try
    WM := TWMSamaCompositingWM.Create(Conn, ScreenNum);
    try
      WM.BlurEnabled := BlurEnabled;
      WM.BlurRadius := BlurRadius;
      WM.ShadowRadius := ShadowRadius;
      WM.ShadowOpacity := ShadowOpacity;

      WriteLn('Virtual Desktops: ', WM.DesktopCount);
      WriteLn('Active Desktop:   ', WM.CurrentDesktop);
      WriteLn('Compositor:       ', CompositorEnabled);
      if CompositorEnabled then
      begin
        WriteLn('  Backdrop Blur:  ', BlurEnabled, ' (Radius: ', BlurRadius, 'px)');
        WriteLn('  Drop Shadows:   Enabled (Radius: ', ShadowRadius, 'px, Opacity: ', Format('%.2f', [ShadowOpacity]), ')');
      end;

      if not WM.ClaimOwnership() then
      begin
        WriteLn(StdErr, 'Error: Another window manager is already managing this screen.');
        Halt(1);
      end;
      WriteLn('Successfully claimed window manager ownership.');

      WM.InitEWMH();

      if CompositorEnabled then
      begin
        if WM.StartCompositor() then
          WriteLn('Compositing subsystem successfully initialized.')
        else
          WriteLn(StdErr, 'Warning: Compositing extensions (Composite/Damage) unavailable. Running uncomposited.');
      end;

      WM.ScanWindows();
      WriteLn('wmsama ready and entering event loop.');

      WM.Run();
    finally
      WM.Free();
      WM := nil;
    end;
  finally
    xcb_disconnect(Conn);
  end;
end.
