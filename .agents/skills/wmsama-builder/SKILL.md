---
name: wmsama-builder
description: Builds, tests, and verifies wmsama — a dedicated modern X11 Window Manager and Compositing Manager powered by Florialib and AggPas.
version: 1.1.0
triggers:
  - build wmsama
  - compile wmsama
  - test wmsama
  - test wmsama xephyr
  - run wmsama
  - wmsama compositor
---

# `wmsama` — Unique X11 Window Manager & Compositor

Build pipeline, test suites, and nested Xephyr execution skill for **wmsama**, the dedicated X11 Reparenting Window Manager and Compositing Manager powered by **Florialib**.

> [!NOTE]
> Desktop Shell components (docks, top panels, taskbars, application launchers, system tray) are housed in the companion project **`../shellsama`**. `wmsama` focuses purely on window management, client frame decorations, EWMH/ICCCM protocols, XComposite redirection, drop shadows, and tear-free presentation.

---

## 1. Prerequisites & Dependencies

- **Free Pascal Compiler (`fpc` >= 3.2.0)**
- **PasBuild (`pasbuild` >= 1.9.0)**: Reads `project.xml`.
- **X11 Libraries**: `libxcb`, `libxcb-composite`, `libxcb-damage`, `libxcb-render`, `libxcb-shape`, `libxcb-xfixes`, `libxcb-randr`, `libxcb-ewmh`, `libxcb-icccm`, `libEGL`, `libGL`.
- **Xephyr (`/usr/bin/Xephyr`)**: Nested X server for visual WM development, debugging, and isolation.
- **Florialib (`florialib:0.0.1-SNAPSHOT`)**: Core vector graphics (AggPas), image processing (blur, PMA, PNG), EGL acceleration, and XCB WM/Compositor subsystems.

---

## 2. Build & Test Commands

| Action | Command | Description |
| :--- | :--- | :--- |
| **Compile Executable** | `./build.sh` or `pasbuild compile` | Compiles `wmsama` binary to `target/wmsama` |
| **Run Unit Tests** | `./build.sh test` or `pasbuild test` | Compiles and executes test suite `TestRunner` |
| **Clean Artifacts** | `./build.sh clean` or `pasbuild clean` | Cleans `target/` build directory |

---

## 3. Nested Testing with Xephyr

Because X11 restricts root window redirection (`SubstructureRedirect`) to a single window manager, `wmsama` must **never** be run directly on the host display (`:0`). Always run and test inside a nested **Xephyr** instance:

### 3.1 Interactive Xephyr Session Recipe

```bash
# 1. Start Xephyr on virtual display :2
Xephyr -br -ac -noreset -screen 1280x720x24 -resizeable :2 &
XEPHYR_PID=$!

# 2. Start wmsama Window Manager / Compositor inside :2
DISPLAY=:2 ./target/wmsama &
WM_PID=$!

# 3. Launch test client applications inside :2
DISPLAY=:2 ../floria-toolkit/target/example_c_button_icons &
DISPLAY=:2 ../floria-toolkit/target/example_c_form_controls &
DISPLAY=:2 ../floria-toolkit/target/example_c_file_dialog &

# 4. Clean teardown when finished
kill -9 $WM_PID $XEPHYR_PID 2>/dev/null || true
wait $XEPHYR_PID 2>/dev/null || true
```

---

## 4. Object Pascal System Rules & Coding Standards

All Pascal units and test suites in `wmsama` must adhere strictly to these conventions:

### 4.1 Mandatory Empty Parentheses `()`
Every routine declaration and call site taking zero parameters **must** include empty parentheses:
```pascal
// Correct
procedure Invalidate(); virtual;
function GetDesktopCount(): Integer;
constructor Create();
destructor Destroy(); override;

// Call sites
WM.ScanWindows();
WM.InitEWMH();
inherited Destroy();
List.Free();
```

### 4.2 File & Unit Naming
- **Unit Filenames**: Strictly lowercase, dot-separated: `wmsama.<subsystem>.<role>.pas` (e.g. `wmsama.core.wm.pas`, `wmsama.core.compositor.pas`).
- **Unit Header Names**: PascalCase dotted namespace: `unit WMSama.Core.WM;`.
- **Indentation**: Exactly 2 spaces, no tabs.
- **Comments**: Use `//` line comments; avoid nested `{}` comments.
- **Memory Safety**: Pair every heap allocation with `try..finally Free()`.

---

## 5. `wmsama` Core Architecture & Roadmap

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    wmsama (Compositing Window Manager)                  │
├────────────────────────────────────┬────────────────────────────────────┤
│         Core Window Manager        │         Compositing Manager        │
│          (WMSama.Core.WM)          │      (WMSama.Core.Compositor)      │
│  - Root SubstructureRedirect       │  - XComposite Manual Redirection   │
│  - ICCCM (Delete Window, Focus)    │  - XDamage Dirty Rect Tracking     │
│  - EWMH (Desktops, Active, Type)   │  - Soft Gaussian Drop Shadows      │
│  - Interactive Move / Resize       │  - Frosted Glass Backdrop Blur     │
│  - Vector Titlebars & Frame Dots   │  - EGL Tear-Free Presentation      │
├────────────────────────────────────┴────────────────────────────────────┤
│                    Foundational Florialib Subsystems                    │
│  - Floria.XCB.WM: Base reparenting WM, ICCCM, EWMH                      │
│  - Floria.XCB.WM.Compositor: TXCBCompositor, TXCBCompositedWindow       │
│  - Floria.Canvas.Agg: High-DPI vector rendering, AggPas curves          │
│  - Floria.Image.Blur: Fast box/Gaussian blur for frosted glass & shadow │
│  - Floria.EGL: Tear-free swapchain hardware presentation                │
└─────────────────────────────────────────────────────────────────────────┘
```

### Next Implementation Steps
1. **WM + Compositor Integration**: Wire `TXCBWindowManager` and `TXCBCompositor` into a unified main loop in `wmsama.pas`.
2. **Modern Vector Titlebar Decorator**: Draw vector rounded top corners, title text, and macOS/Amamizu-style close/minimize/maximize buttons via `OnFramePaint`.
3. **EWMH Struts & Workarea**: Respect `_NET_WM_STRUT_PARTIAL` from `shellsama` dock panels so maximized client windows do not overlap the panel.
