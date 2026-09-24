unit wmsama.test;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  Floria.XCB,
  Floria.XCB.WM;

type
  TWMSamaTest = class(TTestCase)
  published
    procedure TestWMCreation();
    procedure TestDesktopConfiguration();
  end;

implementation

procedure TWMSamaTest.TestWMCreation();
var
  wm: TXCBWindowManager;
begin
  wm := TXCBWindowManager.Create(nil, 0);
  try
    AssertNotNull('WM instance created', wm);
    AssertFalse('Offline by default', wm.IsRunning);
  finally
    wm.Free();
  end;
end;

procedure TWMSamaTest.TestDesktopConfiguration();
var
  wm: TXCBWindowManager;
begin
  wm := TXCBWindowManager.Create(nil, 0);
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

initialization
  RegisterTest(TWMSamaTest);

end.
