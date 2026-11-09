unit WMSama.FT;

{$mode objfpc}{$H+}

interface

uses
  ctypes, SysUtils, Classes, Math, dynlibs,
  Floria.Canvas.Agg, Floria.Font;

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

  // Popup menu canvas rendering procedures
  Tft_menu_plate_draw = procedure(canvas: Pointer; x, y, w, h: Double; radius: Double; dark_mode: cint32); cdecl;
  Tft_menu_header_draw = procedure(canvas: Pointer; x, y, w, h: Double; title: PChar; dark_mode: cint32); cdecl;
  Tft_menu_item_draw = procedure(canvas: Pointer; x, y, w, h: Double; caption: PChar; shortcut: PChar; icon: PChar; hovered, enabled, checked, dark_mode: cint32); cdecl;
  Tft_menu_separator_draw = procedure(canvas: Pointer; x, y, w: Double; dark_mode: cint32); cdecl;
  Tft_theme_get_menu_color = procedure(color_kind: cint32; dark_mode: cint32; out_r, out_g, out_b: PDouble); cdecl;

function FloriaToolkitLoaded(): Boolean;
function InitFloriaToolkit(const AOverridePath: AnsiString = ''): Boolean;
procedure CloseFloriaToolkit();

procedure FtDrawWindowButton(Canvas: TFloriaCanvasAgg; BX, BY, BW, BH: Double;
                             AKind: Integer; AStyle: Integer; AState: Integer;
                             ADarkMode: Boolean; AGlyphArm: Double = 0.0;
                             AHoverProgress: Double = -1.0);

procedure FtDrawMenuPlate(Canvas: TFloriaCanvasAgg; X, Y, W, H, ARadius: Double; ADarkMode: Boolean);
procedure FtDrawMenuHeader(Canvas: TFloriaCanvasAgg; X, Y, W, H: Double; const ATitle: string; ADarkMode: Boolean);
procedure FtDrawMenuItem(Canvas: TFloriaCanvasAgg; X, Y, W, H: Double; const ACaption, AShortcut, AIcon: string; AHovered, AEnabled, AChecked, ADarkMode: Boolean);
procedure FtDrawMenuSeparator(Canvas: TFloriaCanvasAgg; X, Y, W: Double; ADarkMode: Boolean);

implementation

var
  gLibHandle: TLibHandle = NilHandle;
  gFtWindowButtonDraw: Tft_window_button_draw = nil;
  gFtThemeGet: Tft_theme_get = nil;
  gFtThemeSet: Tft_theme_set = nil;
  gFtThemeGetDarkMode: Tft_theme_get_dark_mode = nil;
  gFtThemeSetDarkMode: Tft_theme_set_dark_mode = nil;
  gFtThemeGetCornerRadius: Tft_theme_get_corner_radius = nil;
  gFtMenuPlateDraw: Tft_menu_plate_draw = nil;
  gFtMenuHeaderDraw: Tft_menu_header_draw = nil;
  gFtMenuItemDraw: Tft_menu_item_draw = nil;
  gFtMenuSeparatorDraw: Tft_menu_separator_draw = nil;
  gFtThemeGetMenuColor: Tft_theme_get_menu_color = nil;

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
    gFtMenuPlateDraw := Tft_menu_plate_draw(GetProcedureAddress(gLibHandle, 'ft_menu_plate_draw'));
    gFtMenuHeaderDraw := Tft_menu_header_draw(GetProcedureAddress(gLibHandle, 'ft_menu_header_draw'));
    gFtMenuItemDraw := Tft_menu_item_draw(GetProcedureAddress(gLibHandle, 'ft_menu_item_draw'));
    gFtMenuSeparatorDraw := Tft_menu_separator_draw(GetProcedureAddress(gLibHandle, 'ft_menu_separator_draw'));
    gFtThemeGetMenuColor := Tft_theme_get_menu_color(GetProcedureAddress(gLibHandle, 'ft_theme_get_menu_color'));

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
  gFtMenuPlateDraw := nil;
  gFtMenuHeaderDraw := nil;
  gFtMenuItemDraw := nil;
  gFtMenuSeparatorDraw := nil;
  gFtThemeGetMenuColor := nil;
end;

procedure FtDrawWindowButton(Canvas: TFloriaCanvasAgg; BX, BY, BW, BH: Double;
                             AKind: Integer; AStyle: Integer; AState: Integer;
                             ADarkMode: Boolean; AGlyphArm: Double;
                             AHoverProgress: Double);
var
  dmInt: cint32;
  cenX, cenY, r: Double;
  prog: Double;
  normR, normG, normB, normBdR, normBdG, normBdB: Double;
  hovR, hovG, hovB, curR, curG, curB, outlineA: Double;
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

    if AHoverProgress >= 0.0 then
      prog := Max(0.0, Min(1.0, AHoverProgress))
    else if (AState = FT_BUTTON_STATE_HOVERED) or (AState = FT_BUTTON_STATE_PRESSED) then
      prog := 1.0
    else
      prog := 0.0;

    if ADarkMode then
    begin
      normR := 0.22; normG := 0.24; normB := 0.26;
      normBdR := 0.32; normBdG := 0.35; normBdB := 0.38;
    end
    else
    begin
      normR := 245 / 255; normG := 247 / 255; normB := 250 / 255;
      normBdR := 204 / 255; normBdG := 209 / 255; normBdB := 217 / 255;
    end;

    case AKind of
      FT_WINDOW_BUTTON_CLOSE:
      begin
        hovR := 255 / 255; hovG := 95 / 255; hovB := 86 / 255;
      end;
      FT_WINDOW_BUTTON_MINIMIZE:
      begin
        hovR := 255 / 255; hovG := 189 / 255; hovB := 46 / 255;
      end;
      FT_WINDOW_BUTTON_MAXIMIZE, FT_WINDOW_BUTTON_RESTORE:
      begin
        hovR := 39 / 255; hovG := 201 / 255; hovB := 63 / 255;
      end;
      FT_WINDOW_BUTTON_SHADE, FT_WINDOW_BUTTON_PIN, FT_WINDOW_BUTTON_MENU:
      begin
        hovR := 56 / 255; hovG := 128 / 255; hovB := 235 / 255;
      end;
    else
      hovR := 120 / 255; hovG := 120 / 255; hovB := 120 / 255;
    end;

    if AState = FT_BUTTON_STATE_PRESSED then
    begin
      curR := hovR * 0.75;
      curG := hovG * 0.75;
      curB := hovB * 0.75;
    end
    else
    begin
      curR := normR + (hovR - normR) * prog;
      curG := normG + (hovG - normG) * prog;
      curB := normB + (hovB - normB) * prog;
    end;

    if (AState <> FT_BUTTON_STATE_PRESSED) and (prog > 0.005) then
    begin
      Canvas.DrawCircle(cenX, cenY, r + 2.5 * prog, hovR, hovG, hovB, 0.20 * prog);
      Canvas.DrawCircle(cenX, cenY, r + 1.2 * prog, hovR, hovG, hovB, 0.40 * prog);
    end;

    Canvas.DrawCircle(cenX, cenY, r, curR, curG, curB, 1.0);
    outlineA := (1.0 - prog);
    if outlineA > 0.01 then
      Canvas.DrawCircleOutline(cenX, cenY, r, 1.0, normBdR, normBdG, normBdB, outlineA);
  end;
end;

procedure FtDrawMenuPlate(Canvas: TFloriaCanvasAgg; X, Y, W, H, ARadius: Double; ADarkMode: Boolean);
var
  dmInt: cint32;
  rad: Double;
begin
  if Canvas = nil then Exit;
  if ARadius >= 0.0 then rad := ARadius else rad := 6.0;

  if Assigned(gFtMenuPlateDraw) then
  begin
    if ADarkMode then dmInt := 1 else dmInt := 0;
    gFtMenuPlateDraw(Canvas, X, Y, W, H, rad, dmInt);
  end
  else
  begin
    if ADarkMode then
    begin
      // Matches Floria Toolkit dark menu background #2e333b and border #4d5461
      Canvas.DrawShadow(Round(X), Round(Y), Round(W), Round(H), rad, 0.0, 3.0, 10.0, 0.0, 0.0, 0.0, 0.35);
      Canvas.DrawRoundedRect(Round(X), Round(Y), Round(W), Round(H), rad, 0.18, 0.20, 0.23, 0.98);
      Canvas.DrawRoundedRectOutline(Round(X), Round(Y), Round(W), Round(H), rad, 1.0, 0.30, 0.33, 0.38, 0.90);
    end
    else
    begin
      // Matches Floria Toolkit light menu background #fafeff and border #d9dee6
      Canvas.DrawShadow(Round(X), Round(Y), Round(W), Round(H), rad, 0.0, 3.0, 10.0, 0.0, 0.0, 0.0, 0.16);
      Canvas.DrawRoundedRect(Round(X), Round(Y), Round(W), Round(H), rad, 0.98, 0.99, 1.00, 0.98);
      Canvas.DrawRoundedRectOutline(Round(X), Round(Y), Round(W), Round(H), rad, 1.0, 0.85, 0.87, 0.90, 0.90);
    end;
  end;
end;

procedure FtDrawMenuHeader(Canvas: TFloriaCanvasAgg; X, Y, W, H: Double; const ATitle: string; ADarkMode: Boolean);
var
  dmInt: cint32;
begin
  if (Canvas = nil) or (ATitle = '') then Exit;

  if Assigned(gFtMenuHeaderDraw) then
  begin
    if ADarkMode then dmInt := 1 else dmInt := 0;
    gFtMenuHeaderDraw(Canvas, X, Y, W, H, PChar(ATitle), dmInt);
  end
  else
  begin
    if ADarkMode then
      Canvas.DrawTextLeft(X + 10, Y, W - 20, H, ATitle, nil, 0.55, 0.58, 0.65)
    else
      Canvas.DrawTextLeft(X + 10, Y, W - 20, H, ATitle, nil, 0.45, 0.48, 0.55);
  end;
end;

procedure FtDrawMenuItem(Canvas: TFloriaCanvasAgg; X, Y, W, H: Double;
                         const ACaption, AShortcut, AIcon: string;
                         AHovered, AEnabled, AChecked, ADarkMode: Boolean);
var
  dmInt, hovInt, enInt, chkInt: cint32;
  txtR, txtG, txtB, shortR, shortG, shortB: Double;
  fnt: TFloriaFont;
  sw, ty: Double;
begin
  if Canvas = nil then Exit;

  if Assigned(gFtMenuItemDraw) then
  begin
    if ADarkMode then dmInt := 1 else dmInt := 0;
    if AHovered then hovInt := 1 else hovInt := 0;
    if AEnabled then enInt := 1 else enInt := 0;
    if AChecked then chkInt := 1 else chkInt := 0;
    gFtMenuItemDraw(Canvas, X, Y, W, H, PChar(ACaption), PChar(AShortcut), PChar(AIcon),
                    hovInt, enInt, chkInt, dmInt);
  end
  else
  begin
    if AHovered and AEnabled then
    begin
      // Floria Toolkit primary accent hover pill #3b82f6
      Canvas.DrawRoundedRect(Round(X + 3), Round(Y + 1), Round(W - 6), Round(H - 2), 4.0, 0.23, 0.51, 0.96, 1.0);
      txtR := 1.0; txtG := 1.0; txtB := 1.0;
      shortR := 0.85; shortG := 0.92; shortB := 1.0;
    end
    else if not AEnabled then
    begin
      if ADarkMode then
      begin
        txtR := 0.44; txtG := 0.44; txtB := 0.48;
        shortR := 0.44; shortG := 0.44; shortB := 0.48;
      end
      else
      begin
        txtR := 0.58; txtG := 0.64; txtB := 0.72;
        shortR := 0.58; shortG := 0.64; shortB := 0.72;
      end;
    end
    else
    begin
      if ADarkMode then
      begin
        txtR := 0.90; txtG := 0.91; txtB := 0.92;
        shortR := 0.55; shortG := 0.58; shortB := 0.65;
      end
      else
      begin
        txtR := 0.12; txtG := 0.14; txtB := 0.17;
        shortR := 0.55; shortG := 0.58; shortB := 0.65;
      end;
    end;

    if AIcon <> '' then
      Canvas.DrawTextLeft(X + 8, Y, 16, H, AIcon, nil, txtR, txtG, txtB)
    else if AChecked then
      Canvas.DrawTextLeft(X + 8, Y, 16, H, '✓', nil, txtR, txtG, txtB);

    Canvas.DrawTextLeft(X + 26, Y, W - 32, H, ACaption, nil, txtR, txtG, txtB);

    if AShortcut <> '' then
    begin
      fnt := FloriaGetSystemFont();
      if fnt <> nil then
      begin
        sw := fnt.GetTextWidth(AShortcut);
        ty := Round(Y + (H / 2.0) + (fnt.Ascent - fnt.Descent) / 2.0);
        Canvas.DrawText(Round(X + W - sw - 12), ty, AShortcut, fnt, shortR, shortG, shortB);
      end;
    end;
  end;
end;

procedure FtDrawMenuSeparator(Canvas: TFloriaCanvasAgg; X, Y, W: Double; ADarkMode: Boolean);
var
  dmInt: cint32;
begin
  if Canvas = nil then Exit;

  if Assigned(gFtMenuSeparatorDraw) then
  begin
    if ADarkMode then dmInt := 1 else dmInt := 0;
    gFtMenuSeparatorDraw(Canvas, X, Y, W, dmInt);
  end
  else
  begin
    if ADarkMode then
      Canvas.DrawRect(Round(X + 6), Round(Y), Round(W - 12), 1, 0.26, 0.28, 0.32)
    else
      Canvas.DrawRect(Round(X + 6), Round(Y), Round(W - 12), 1, 0.88, 0.90, 0.92);
  end;
end;

finalization
  CloseFloriaToolkit();

end.
