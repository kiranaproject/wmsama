---
name: wmsama-builder
description: Builds, tests, and verifies the Samarinda Desktop Environment (wmsama) — a modern X11 window manager, compositing manager, and desktop shell powered by Florialib and Floria Toolkit.
version: 1.0.0
triggers:
  - build wmsama
  - compile wmsama
  - test wmsama
  - test wmsama xephyr
  - run wmsama
  - wmsama compositor
  - samarinda de
---

# Samarinda Desktop Environment (`wmsama`) Build & Development Skill

Orchestrates the build pipeline, unit tests, and nested Xephyr visual verification for **wmsama** (the Samarinda Desktop Environment and Compositing Window Manager) powered by **Florialib** and **Floria Toolkit**.

---

## 1. Prerequisites & Dependencies

- **Free Pascal Compiler (`fpc` >= 3.2.0)**
- **PasBuild (`pasbuild` >= 1.9.0)**: Project build orchestrator reading `project.xml`.
- **X11 Libraries**: `libxcb`, `libxcb-composite`, `libxcb-damage`, `libxcb-render`, `libxcb-shape`, `libxcb-xfixes`, `libxcb-randr`, `libxcb-ewmh`, `libxcb-icccm`, `libEGL`, `libGL`.
- **Xephyr (`/usr/bin/Xephyr`)**: Nested X server for visual WM development, debugging, and isolation.
- **Florialib (`florialib:0.0.1-SNAPSHOT`)**: Core vector graphics (AggPas), image processing (blur, PMA, PNG), EGL acceleration, and XCB WM/Compositor subsystems.
- **Floria Toolkit (`floria-toolkit`)**: Dotted-namespace UI widgets (`Ft.Widget.*`), theming (`Ft.Theme`), vector icons (`Ft.Icons`), and dialogs.

---

## 2. Build & Test Commands

| Action | Command | Description |
| :--- | :--- | :--- |
| **Compile Executable** | `./build.sh` or `pasbuild compile` | Compiles `wmsama` binary to `target/wmsama` |
| **Run Unit Tests** | `./build.sh test` or `pasbuild test` | Compiles and executes test suite `TestRunner` |
| **Clean Artifacts** | `./build.sh clean` or `pasbuild clean` | Cleans `target/` build directory |
| **Import libft.so** | `./copy-libft.sh` | Copies `libft.so` from `../floria-toolkit/target/` |

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
- **Unit Filenames**: Strictly lowercase, dot-separated: `wmsama.<subsystem>.<role>.pas` (e.g. `wmsama.core.wm.pas`, `wmsama.shell.panel.pas`).
- **Unit Header Names**: PascalCase dotted namespace: `unit WMSama.Core.WM;`.
- **Indentation**: Exactly 2 spaces, no tabs.
- **Comments**: Use `//` line comments; avoid nested `{}` comments.
- **Memory Safety**: Pair every heap allocation with `try..finally Free()`.

---

## 5. Samarinda DE Architecture & Roadmap

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Samarinda Desktop Environment                      │
├────────────────────────────────────┬────────────────────────────────────┤
│         Core Window Manager        │         Compositing Manager        │
│          (WMSama.Core.WM)          │      (WMSama.Core.Compositor)      │
│  - Root SubstructureRedirect       │  - XComposite Manual Redirection   │
│  - ICCCM (Delete Window, Focus)    │  - XDamage Dirty Rect Tracking     │
│  - EWMH (Desktops, Active, Type)   │  - Soft Gaussian Drop Shadows      │
│  - Interactive Move / Resize       │  - Frosted Glass Backdrop Blur     │
│  - Window Frame Decorators         │  - EGL Tear-Free Swapchain         │
├────────────────────────────────────┴────────────────────────────────────┤
│                       Desktop Shell Components                          │
│  - Top / Bottom Panel (WMSama.Shell.Panel)                              │
│  - Application Launcher / Start Menu (WMSama.Shell.Launcher)            │
│  - Taskbar / Window Switcher (WMSama.Shell.Taskbar)                     │
│  - System Tray & Status Indicators (WMSama.Shell.Tray)                  │
├─────────────────────────────────────────────────────────────────────────┤
│                   Foundational Libraries & Engines                      │
│  - Florialib: AggPas 2D vector engine, XCB bindings, PMA, Image Blur    │
│  - Floria Toolkit: Modern CSS theming, Amamizu Liquid Glass, SVG icons  │
└─────────────────────────────────────────────────────────────────────────┘
```

### Next Implementation Steps
1. **WM + Compositor Integration**: Wire `TXCBWindowManager` and `TXCBCompositor` into a unified main loop in `wmsama.pas`.
2. **Desktop Shell Panel (`wmsama.shell.panel.pas`)**: Build a dock window (`_NET_WM_WINDOW_TYPE_DOCK`) using Floria Toolkit widgets (app menu launcher, taskbar window buttons, clock).
3. **Amamizu Liquid Glass Theme**: Apply frosted glass backdrop blur and semi-transparent liquid glass styling to the panel, docks, and window titlebars.
