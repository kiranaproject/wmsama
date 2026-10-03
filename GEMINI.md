# wmsama — Project Rules

## Object Pascal Coding Conventions

All code in this project must adhere strictly to the conventions documented in [`.agents/rules/pascal_conventions.md`](.agents/rules/pascal_conventions.md):
- **Mandatory `()`**: Every zero-parameter procedure, function, constructor, or destructor declaration and call site must have `()`.
- **Unit Filenames & Declarations**: Unit filenames are lowercase dot-separated (`wmsama.<subsystem>.<role>.pas`), while the unit name declared inside the header is PascalCase (`unit WMSama.<Subsystem>.<Role>;`).
- **Formatting**: 2 spaces indent, no tabs, `begin` on a new line aligned with controlling keyword.
- **Comments**: Use `//` line comments; never use nested `{}` block comments.
- **Memory**: `TObjectList` from `Contnrs` with `OwnsObjects = True`. Always pair allocation with `try..finally Free()`.

## Build & Tool Invariants

- **`project.xml`** is the only project descriptor used by Pasbuild (`pasbuild.json` does not exist).
- **`find_by_name` Requires `Pattern`**: Always supply `Pattern: "*"` even when specifying `Extensions` or `Type`.
- **Required Metadata**: Every tool call must include both `toolSummary` (2–5 word noun phrase) and `toolAction` (2–5 word verb phrase).

## Window Interaction & Control Invariants

- **Button Click Lifecycle (Release-Within-Bounds)**:
  - Titlebar control buttons (close, minimize, maximize, shade, pin, menu) must **never** execute actions on mouse press (`XCB_BUTTON_PRESS`).
  - `BUTTON_PRESS` records `FPressedButton` and enters `FT_BUTTON_STATE_PRESSED`.
  - `MOTION_NOTIFY` toggles visual state between normal and pressed as cursor leaves or re-enters button bounds during drag.
  - Actions execute **strictly on `BUTTON_RELEASE` within the originating button's bounds**. Releasing outside cancels with zero side-effects.
- **Content Area Protection**:
  - `GetResizeModeForPoint` strictly returns `dmNone` for all coordinates within client content area (`ARootY >= wy + FTitlebarHeight`), ensuring text selection from column 0 in terminals or editors is never interrupted by resize dragging.

## Compositor & Visual Styling Invariants

- **Subtle & Balanced Drop Shadows (MATE Style)**:
  - Window shadows must be balanced evenly around all 4 edges of the window with subtle opacity and minimal offset:
    - Active: `Radius: 14px`, `OffsetY: 1px`, `Opacity: 0.22`.
    - Inactive: `Radius: 10px`, `OffsetY: 1px`, `Opacity: 0.14`.
    - Popups / Menus: `Radius: 10px`, `OffsetY: 1px`, `Opacity: 0.20`.

