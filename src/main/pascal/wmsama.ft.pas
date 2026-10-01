unit WMSama.FT;

{$mode objfpc}{$H+}

interface

uses
  ctypes, SysUtils, Classes, dynlibs,
  Floria.Canvas.Agg;

const
  // Window button kinds (matching Ft.Widget.Buttons / ft.h)
  FT_WINDOW_BUTTON_CLOSE    = 0; // '×' vector cross with scarlet glowing halo
  FT_WINDOW_BUTTON_MINIMIZE = 1; // '—' horizontal dash with amber halo
  FT_WINDOW_BUTTON_MAXIMIZE = 2; // Dual outward chevrons with emerald halo
  FT_WINDOW_BUTTON_RESTORE  = 3; // Dual inward chevrons with emerald halo
  FT_WINDOW_BUTTON_SHADE    = 4; // '▴' rollup chevron
  FT_WINDOW_BUTTON_PIN      = 5; // '•' pin / stick indicator
  FT_WINDOW_BUTTON_MENU     = 6; // '☰' hamburger menu
  FT_WINDOW_BUTTON_ADD      = 7; // '+' new tab / add button

  // Window button styles (matching Ft.Widget.Buttons / ft.h)
  FT_WINDOW_BUTTON_CIRCLE   = 0; // Circular pill/halo (macOS traffic lights, modern tabs)
  FT_WINDOW_BUTTON_SQUIRCLE = 1; // Rounded rectangle (modern GTK / GNOME header bar)
  FT_WINDOW_BUTTON_SQUARE   = 2; // Flat rectangle (traditional Windows caption button)

  // Button interactive states
  FT_BUTTON_STATE_NORMAL    = 0;
  FT_BUTTON_STATE_HOVERED   = 1;
  FT_BUTTON_STATE_PRESSED   = 2;

type
  // Dynamic procedure signatures exported by libft.so
  Tft_window_button_draw = procedure(canvas: Pointer; bx, by, bw, bh: Double;
                                     kind: cint32; style: cint32; state: cint32;
                                     dark_mode: cint32; glyph_arm: Double;
                                     hover_progress: Double); cdecl;

  Tft_theme_get = function(): PAnsiChar; cdecl;
  Tft_theme_set = function(name: PAnsiChar): cint32; cdecl;
  Tft_theme_get_dark_mode = function(): cint32; cdecl;
  Tft_theme_set_dark_mode = procedure(dark_mode: cint32); cdecl;
  Tft_theme_get_corner_radius = function(): Double; cdecl;

function FloriaToolkitLoaded(): Boolean;
function InitFloriaToolkit(const AOverridePath: AnsiString = ''): Boolean;
procedure CloseFloriaToolkit();

procedure FtDrawWindowButton(Canvas: TFloriaCanvasAgg; BX, BY, BW, BH: Double;
                             AKind: Integer; AStyle: Integer; AState: Integer;
                             ADarkMode: Boolean; AGlyphArm: Double = 0.0;
                             AHoverProgress: Double = -1.0);

implementation

var
  gLibHandle: TLibHandle = NilHandle;
  gFtWindowButtonDraw: Tft_window_button_draw = nil;
  gFtThemeGet: Tft_theme_get = nil;
  gFtThemeSet: Tft_theme_set = nil;
  gFtThemeGetDarkMode: Tft_theme_get_dark_mode = nil;
  gFtThemeSetDarkMode: Tft_theme_set_dark_mode = nil;
  gFtThemeGetCornerRadius: Tft_theme_get_corner_radius = nil;

function FloriaToolkitLoaded(): Boolean;
begin
  Result := (gLibHandle <> NilHandle) and Assigned(gFtWindowButtonDraw);
end;

function TryLoadFrom(const APath: AnsiString): Boolean;
begin
  Result := False;
  if (APath = '') or not FileExists(APath) then Exit;

  gLibHandle := LoadLibrary(APath);
  if gLibHandle <> NilHandle then
  begin
    gFtWindowButtonDraw := Tft_window_button_draw(GetProcedureAddress(gLibHandle, 'ft_window_button_draw'));
    gFtThemeGet := Tft_theme_get(GetProcedureAddress(gLibHandle, 'ft_theme_get'));
    gFtThemeSet := Tft_theme_set(GetProcedureAddress(gLibHandle, 'ft_theme_set'));
    gFtThemeGetDarkMode := Tft_theme_get_dark_mode(GetProcedureAddress(gLibHandle, 'ft_theme_get_dark_mode'));
    gFtThemeSetDarkMode := Tft_theme_set_dark_mode(GetProcedureAddress(gLibHandle, 'ft_theme_set_dark_mode'));
    gFtThemeGetCornerRadius := Tft_theme_get_corner_radius(GetProcedureAddress(gLibHandle, 'ft_theme_get_corner_radius'));

    if Assigned(gFtWindowButtonDraw) then
    begin
      Result := True;
      Exit;
    end
    else
    begin
      UnloadLibrary(gLibHandle);
      gLibHandle := NilHandle;
    end;
  end;
end;

function InitFloriaToolkit(const AOverridePath: AnsiString): Boolean;
var
  exeDir: AnsiString;
  candidates: array[0..5] of AnsiString;
  i: Integer;
begin
  if FloriaToolkitLoaded() then Exit(True);

  exeDir := ExtractFilePath(ParamStr(0));
  candidates[0] := AOverridePath;
  candidates[1] := exeDir + 'libft.so';
  candidates[2] := exeDir + '../floria-toolkit/target/libft.so';
  candidates[3] := '/home/afumi/Documents/projects/kirana/floria-toolkit/target/libft.so';
  candidates[4] := '/home/afumi/.pasbuild/repository/ft/0.0.1-SNAPSHOT/x86_64-linux-3.2.3/libft.so';
  candidates[5] := 'libft.so';

  for i := 0 to High(candidates) do
  begin
    if TryLoadFrom(candidates[i]) then
      Exit(True);
  end;

  // Try direct dynamic linker lookup
  gLibHandle := LoadLibrary('libft.so');
  if gLibHandle <> NilHandle then
  begin
    gFtWindowButtonDraw := Tft_window_button_draw(GetProcedureAddress(gLibHandle, 'ft_window_button_draw'));
    if Assigned(gFtWindowButtonDraw) then
      Exit(True);
    UnloadLibrary(gLibHandle);
    gLibHandle := NilHandle;
  end;

  Result := False;
end;

procedure CloseFloriaToolkit();
begin
  if gLibHandle <> NilHandle then
  begin
    UnloadLibrary(gLibHandle);
    gLibHandle := NilHandle;
  end;
  gFtWindowButtonDraw := nil;
  gFtThemeGet := nil;
  gFtThemeSet := nil;
  gFtThemeGetDarkMode := nil;
  gFtThemeSetDarkMode := nil;
  gFtThemeGetCornerRadius := nil;
end;

procedure FtDrawWindowButton(Canvas: TFloriaCanvasAgg; BX, BY, BW, BH: Double;
                             AKind: Integer; AStyle: Integer; AState: Integer;
                             ADarkMode: Boolean; AGlyphArm: Double;
                             AHoverProgress: Double);
var
  dmInt: cint32;
  cenX, cenY, r: Double;
begin
  if Canvas = nil then Exit;

  if FloriaToolkitLoaded() then
  begin
    if ADarkMode then dmInt := 1 else dmInt := 0;
    gFtWindowButtonDraw(Canvas, BX, BY, BW, BH, AKind, AStyle, AState, dmInt, AGlyphArm, AHoverProgress);
  end
  else
  begin
    // High-quality fallback rendering when libft.so is not yet loaded
    cenX := BX + BW * 0.5;
    cenY := BY + BH * 0.5;
    r := (BW * 0.5) - 1.0;
    case AKind of
      FT_WINDOW_BUTTON_CLOSE:
        Canvas.DrawCircle(cenX, cenY, r, 255 / 255, 95 / 255, 86 / 255, 1.0);
      FT_WINDOW_BUTTON_MINIMIZE:
        Canvas.DrawCircle(cenX, cenY, r, 255 / 255, 189 / 255, 46 / 255, 1.0);
      FT_WINDOW_BUTTON_MAXIMIZE, FT_WINDOW_BUTTON_RESTORE:
        Canvas.DrawCircle(cenX, cenY, r, 39 / 255, 201 / 255, 63 / 255, 1.0);
      FT_WINDOW_BUTTON_SHADE, FT_WINDOW_BUTTON_PIN, FT_WINDOW_BUTTON_MENU:
        Canvas.DrawCircle(cenX, cenY, r, 56 / 255, 128 / 255, 235 / 255, 1.0);
    else
      Canvas.DrawCircle(cenX, cenY, r, 120 / 255, 120 / 255, 120 / 255, 1.0);
    end;
  end;
end;

finalization
  CloseFloriaToolkit();

end.
