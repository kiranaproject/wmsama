# Object Pascal Coding Conventions & Architectural Standards

All Pascal source files and test suites in this project follow strict Object Pascal coding conventions shared across the Kirana/Floria ecosystem.

---

## 1. Compiler Directives & Dialect

Every unit begins with:

```pascal
unit WMSama.<Subsystem>.<Role>;

{$mode objfpc}{$H+}
{$modeswitch advancedrecords} // When advanced record methods or static class functions are needed
```

- **Dialect**: `{$mode objfpc}` (Free Pascal object-oriented Pascal mode).
- **Strings**: `{$H+}` enables long `AnsiString` by default.
- **Advanced Records**: `{$modeswitch advancedrecords}` enables methods and constructors on `record` types.

---

## 2. Mandatory Empty Parentheses `()` on Zero-Parameter Routines

To unambiguously distinguish callable routines from fields and properties:

### 2.1 Routine Declarations
Every zero-parameter `procedure`, `function`, `constructor`, or `destructor` declaration **must** include empty parentheses `()`:

```pascal
// Correct
procedure Invalidate(); virtual;
function GetChildCount(): Integer;
constructor Create();
destructor Destroy(); override;

// Incorrect — do NOT omit parentheses
procedure Invalidate;
function GetChildCount: Integer;
constructor Create;
destructor Destroy; override;
```

### 2.2 Routine Call Sites
Every call to a zero-parameter routine **must** include empty parentheses `()`:

```pascal
// Correct
List := TObjectList.Create();
try
  Invalidate();
  inherited Destroy();
finally
  List.Free();
end;

// Incorrect — do NOT omit parentheses
List := TObjectList.Create;
Invalidate;
inherited Destroy;
List.Free;
```

*Note: Properties and record fields do not use parentheses: `Btn.Visible := True;`.*

---

## 3. Comment Conventions

Free Pascal does **not** support nested `{}` block comments. Any `{` or `}` inside a `{ ... }` comment confuses the compiler parser and causes spurious syntax errors or file truncation.

- **Always use `//` line comments** for inline documentation, code comments, and section dividers.
- **Use `(* ... *)`** only when writing multi-line block comments that must contain `{}` characters in their text.
- **Never** write `{ }` comments that contain `{`, `}`, `[`, or `]`.

```pascal
// Correct:
// Section divider comment
// Simple block with contents: curly-brace or paren block.

// Correct multi-line:
(* Comment explaining { and } block tokens. *)

// Incorrect:
{ A block with { or } inside will corrupt the parser }
```

---

## 4. Identifier Casing & Naming Conventions

| Element | Format | Prefix / Rule | Example |
|---|---|---|---|
| **Unit Filenames** | Lowercase | Dot-separated lowercase `.pas` | `wmsama.core.pas`, `floria.xcb.wm.pas` |
| **Unit Declarations** | PascalCase | Declared inside file header | `unit WMSama.Core;` |
| **Classes / Records** | PascalCase | `T` prefix | `TWMClient`, `TFloriaRect` |
| **Interfaces** | PascalCase | `I` prefix | `IWMEventHandler`, `ICSSElement` |
| **Private Fields** | PascalCase | `F` prefix | `FWindow`, `FTitle`, `FFrame` |
| **Arguments / Params** | PascalCase | `A` prefix | `const ATitle: string; AWidth: Integer` |
| **Constants** | **ALL_CAPS** | Underscore separated | `MAX_CLIENTS`, `DEFAULT_BORDER_WIDTH` |
| **Enum Types** | PascalCase | `T` prefix | `TWindowState`, `TClientType` |
| **Enum Values** | Mixed | 2–3 letter lowercase prefix | `wsNormal`, `wsMaximized`, `ctDialog` |
| **Properties** | PascalCase | Maps to `F` field | `property Width: Integer read FWidth;` |
| **Local Variables** | PascalCase | Clear descriptive names | `CurrentClient`, `ResolvedRect` |
| **Language Keywords** | Lowercase | Lowercase keywords throughout | `begin`, `end`, `var`, `procedure`, `function` |

---

## 5. Block Formatting & Indentation

- **Indent**: 2 spaces per indentation level. **Never use tab characters.**
- `begin` appears on a **new line**, aligned under its controlling keyword.
- `end` aligns vertically with its matching `begin`.

```pascal
// Correct
if ClientCount > MAX_CLIENTS then
begin
  ShowWarning();
  LogEvent('Maximum clients reached');
end;

// Incorrect — do not place begin on same line
if ClientCount > MAX_CLIENTS then begin
    ShowWarning();
end;
```

Single-statement branches omit `begin`/`end` and indent by 2 spaces:

```pascal
if IsMaximized then
  Restore()
else
  Maximize();
```

---

## 6. Memory Ownership & Collections

### 6.1 `TObjectList` in `Contnrs`
`TObjectList` in Free Pascal lives in the **`Contnrs`** unit, not `Classes`:

```pascal
uses Classes, Contnrs, SysUtils, ...;
```

### 6.2 Cascading Lifetime Hierarchy
Every composite node or list owns its items (`FreeObjects = True`):

```pascal
FClients := TObjectList.Create(True); // OwnsObjects = True
try
  // ...
finally
  FClients.Free(); // Automatically cascades and frees all TWMClient objects
end;
```

### 6.3 Resource Cleanup & Exception Handling
- Wrap object lifecycles immediately in `try..finally Free()` blocks.
- Always catch specific exception classes, never blank `except end` blocks:

```pascal
try
  PerformOperation();
except
  on E: EXCBConnectionError do
    HandleDisconnect(E.Message);
  on E: Exception do
  begin
    LogError('Unexpected error: ' + E.Message);
    raise;
  end;
end;
```

---

## 7. FPC-Specific Gotchas & Traps

### 7.1 Loop Underflow on Unsigned Types
Never decrement unsigned types (`Byte`, `Word`, `Cardinal`) down to 0 in `while` loops. When an unsigned type drops below 0, it wraps to 255 or 65535, causing infinite loops.
- Use signed `Integer` for loop bounds.
- Use `for L := MaxLevel downto MinLevel do` instead of `while L >= MinLevel do Dec(L)`.

### 7.2 Interface Method Calling Convention on Linux
FPC on Linux uses **`cdecl`** calling convention for interface methods (not `stdcall`):

```pascal
type
  TMyListener = class(TObject, IMyInterface)
  private
    function QueryInterface(constref IID: TGUID; out Obj): HResult; cdecl;
    function _AddRef(): Integer; cdecl;
    function _Release(): Integer; cdecl;
  end;
```

### 7.3 Shared Library Position-Independent Code (`-Cg` / `-fPIC`)
When compiling units that will be linked into shared libraries (`.so`), ensure `-Cg` is enabled in `fpc.cfg` or compiler options to prevent `relocation R_X86_64_PC32 against symbol ... can not be used when making a shared object` errors.

### 7.4 Self-Registering Codecs & Initialization Order
Units that register themselves dynamically in an `initialization` block (like image codecs) must not be imported in the implementation section of their registry core unit to prevent FPC's initialization dependency graph from wiping registrations.

---

## 8. Pasbuild & Tool Invariants

- **`project.xml` is the only project descriptor**: Pasbuild uses `project.xml`. There is no `pasbuild.json` or YAML file.
- **`find_by_name` Requires `Pattern`**: Always supply `Pattern: "*"` when calling `find_by_name`, even when filtering by `Extensions` or `Type`.
- **Tool Call Metadata**: Every tool call must include both `toolSummary` (noun phrase) and `toolAction` (verb phrase).
