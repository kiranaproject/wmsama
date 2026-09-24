program TestRunner;

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, fpcunit, testregistry, consoletestrunner,
  wmsama.test;

var
  Application: TTestRunner;
begin
  Application := TTestRunner.Create(nil);
  try
    Application.Initialize();
    Application.Run();
  finally
    Application.Free();
  end;
end.
