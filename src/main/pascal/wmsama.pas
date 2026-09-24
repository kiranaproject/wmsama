program wmsama;

// wmsama
// ======
// X11 Reparenting Window Manager powered by florialib (Floria.XCB.WM)

{$mode objfpc}{$H+}

uses
  SysUtils,
  Floria.XCB,
  Floria.XCB.WM;

var
  WM: TXCBWindowManager;
  Conn: Pxcb_connection_t;
  ScreenNum: Integer;
begin
  WriteLn('wmsama — X11 Window Manager (Powered by florialib)');

  if (ParamCount > 0) and (ParamStr(1) = '--version') then
  begin
    WriteLn('wmsama 0.0.1-SNAPSHOT');
    Halt(0);
  end;

  // Attempt XCB connection
  Conn := xcb_connect(nil, @ScreenNum);
  if (Conn = nil) or (xcb_connection_has_error(Conn) <> 0) then
  begin
    WriteLn(StdErr, 'Note: Cannot connect to X11 server.');
    Halt(1);
  end;

  try
    WM := TXCBWindowManager.Create(Conn, ScreenNum);
    try
      WriteLn('Configured virtual desktops: ', WM.DesktopCount);
      WriteLn('Active desktop index:        ', WM.CurrentDesktop);

      if not WM.ClaimOwnership() then
      begin
        WriteLn(StdErr, 'Error: Another window manager is already managing this screen.');
        Halt(1);
      end;

      WriteLn('Successfully claimed window manager ownership.');
      WM.InitEWMH();
      WM.ScanWindows();
      WriteLn('Ready to manage clients.');
    finally
      WM.Free();
    end;
  finally
    xcb_disconnect(Conn);
  end;
end.
