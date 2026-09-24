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
