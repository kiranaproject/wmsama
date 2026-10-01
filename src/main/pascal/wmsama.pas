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
  WMSama.FT,
  wmsama.core;

var
  WM                 : TWMSamaCompositingWM;
  Conn               : Pxcb_connection_t;
  ScreenNum          : Integer;
  DisplayStr         : AnsiString;
  PDisplay           : PAnsiChar;
  CompositorEnabled  : Boolean;
  BlurEnabled        : Boolean;
  BlurRadius         : Integer;
  ShadowRadius       : Integer;
  ShadowOpacity      : Single;
  CornerRadius       : Integer;
  BottomCornerRadius : Integer;
  ButtonStyle        : Integer;
  ButtonStyleStr     : AnsiString;
  ButtonAlignmentStr : AnsiString;
  ButtonLayoutStr    : AnsiString;
  ThemeDark          : Boolean;
  LibFtPath          : AnsiString;
  I                  : Integer;
  Arg                : AnsiString;

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
  WriteLn('  --corner-radius <int>  Window top corner radius (default: 12)');
  WriteLn('  --bottom-radius <int>  Window bottom corner radius (default: 12)');
  WriteLn('  --button-style <style> Window button style: circle, squircle, square (default: circle)');
  WriteLn('  --buttons-left         Align window buttons to the left (macOS style)');
  WriteLn('  --buttons-right        Align window buttons to the right (Windows/GNOME/KDE style)');
  WriteLn('  --button-alignment <a> Window button alignment: left, right (default: left)');
  WriteLn('  --button-layout <lay>  Custom window button layout (<left>:<right>, e.g. "menu:shade,pin,minimize,maximize,close")');
  WriteLn('  --theme <theme>        Window theme: dark, light (default: dark)');
  WriteLn('  --libft <path>         Path to libft.so shared library');
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
  CornerRadius := 12;
  BottomCornerRadius := 12;
  ButtonStyle := FT_WINDOW_BUTTON_CIRCLE;
  ButtonStyleStr := 'circle';
  ThemeDark := True;
  LibFtPath := '';

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
    else if (Arg = '--corner-radius') and (I < ParamCount) then
    begin
      Inc(I);
      CornerRadius := StrToIntDef(ParamStr(I), 12);
    end
    else if (Arg = '--bottom-radius') and (I < ParamCount) then
    begin
      Inc(I);
      BottomCornerRadius := StrToIntDef(ParamStr(I), 12);
    end
    else if (Arg = '--button-style') and (I < ParamCount) then
    begin
      Inc(I);
      ButtonStyleStr := LowerCase(ParamStr(I));
      if ButtonStyleStr = 'squircle' then
        ButtonStyle := FT_WINDOW_BUTTON_SQUIRCLE
      else if ButtonStyleStr = 'square' then
        ButtonStyle := FT_WINDOW_BUTTON_SQUARE
      else
      begin
        ButtonStyle := FT_WINDOW_BUTTON_CIRCLE;
        ButtonStyleStr := 'circle';
      end;
    end
    else if Arg = '--buttons-left' then
    begin
      ButtonAlignmentStr := 'left';
    end
    else if Arg = '--buttons-right' then
    begin
      ButtonAlignmentStr := 'right';
    end
    else if (Arg = '--button-alignment') and (I < ParamCount) then
    begin
      Inc(I);
      ButtonAlignmentStr := LowerCase(ParamStr(I));
    end
    else if (Arg = '--button-layout') and (I < ParamCount) then
    begin
      Inc(I);
      ButtonLayoutStr := ParamStr(I);
    end
    else if (Arg = '--theme') and (I < ParamCount) then
    begin
      Inc(I);
      if LowerCase(ParamStr(I)) = 'light' then
        ThemeDark := False
      else
        ThemeDark := True;
    end
    else if (Arg = '--libft') and (I < ParamCount) then
    begin
      Inc(I);
      LibFtPath := ParamStr(I);
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

  // Initialize Floria Toolkit integration (libft.so)
  if InitFloriaToolkit(LibFtPath) then
    WriteLn('Floria Toolkit:   Integrated (vector styling active)')
  else
    WriteLn('Floria Toolkit:   Fallback mode (using AggPas built-in render)');

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
      WM.CornerRadius := CornerRadius;
      WM.BottomCornerRadius := BottomCornerRadius;
      WM.WindowButtonStyle := ButtonStyle;
      WM.ThemeDarkMode := ThemeDark;

      if ButtonLayoutStr <> '' then
        WM.ButtonLayout := ButtonLayoutStr
      else if ButtonAlignmentStr = 'right' then
        WM.ButtonAlignment := baRight
      else if ButtonAlignmentStr = 'left' then
        WM.ButtonAlignment := baLeft;

      WriteLn('Virtual Desktops: ', WM.DesktopCount);
      WriteLn('Active Desktop:   ', WM.CurrentDesktop);
      WriteLn('Button Style:     ', ButtonStyleStr);
      WriteLn('Button Layout:    ', WM.ButtonLayout);
      if WM.ButtonAlignment = baRight then
        WriteLn('Button Alignment: Right')
      else
        WriteLn('Button Alignment: Left');
      WriteLn('Theme Dark Mode:  ', ThemeDark);
      WriteLn('Compositor:       ', CompositorEnabled);
      if CompositorEnabled then
      begin
        WriteLn('  Corner Radii:   Top: ', CornerRadius, 'px, Bottom: ', BottomCornerRadius, 'px');
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
