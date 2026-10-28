# wmsama Event Loop & Input Path Roadmap

**Scope:** correctness and robustness of the event pump, input routing, grab ownership,
X resource lifetime, and the compositor present path.

**Baseline audited:** `wmsama@a5f5629` (2026-10-21), `florialib@8d52670` (2026-10-25)
**Audit date:** 2026-10-28

This document is the tracking surface for that work. Every item has a stable ID, the exact
code location it refers to, the observable failure it causes, and an acceptance check that can
be run without reading the diff. Update the status column and the [Progress Log](#7-progress-log)
as work lands — do not delete completed rows, the history is the point.

---

## 0. How to Use This Document

### Status legend

| Mark | Meaning |
| :--- | :--- |
| `☐` | Not started |
| `◐` | In progress (note the owner and date in the progress log) |
| `☑` | Done and verified against the acceptance check |
| `⊘` | Deferred or rejected (record *why* in the progress log) |

### Rules of engagement

1. **One item per change.** No item is "done" until its acceptance check passes, not when the
   diff compiles.
2. **Cross-repo items are called out.** Items marked **[florialib]** change shared code consumed
   by `wmsama`, `floria-toolkit`, and any future shell. They need a separate review pass and must
   not silently change behavior for other consumers.
3. **Tests come with the fix**, not after. Where an item cannot be covered by the FPCUnit suite
   (anything requiring a live X server), the acceptance check is a manual Xephyr recipe — run it,
   don't assume it.
4. **Never "fix" a symptom by widening a grab or mask** without recording why in the log.

### Verification harness

Most items need a real X server. The nested-server recipe:

```bash
# 1. Nested server
Xephyr :2 -screen 1280x800 -ac &

# 2. Run wmsama with diagnostics
cd wmsama
pasbuild compile
DISPLAY=:2 ./target/wmsama --display :2

# 3. Clients to exercise the input paths
DISPLAY=:2 xterm &
DISPLAY=:2 xcalc &
DISPLAY=:2 xclock &
```

Two leak/lifetime tools worth wiring into the loop early:

```bash
# Server-side resource growth (pixmaps, GCs, damage objects, cursors)
xrestop -display :2

# Client-side heap: build the test binary with -gh
fpc -gh ... # or add -gh to project.xml test options
```

---

## 1. Findings Summary

Severity is about *user-visible damage*, not code smell.

| ID | Sev | Area | Title | Status |
| :--- | :--- | :--- | :--- | :--- |
| WM-01 | **P0** | Grabs | Alt+Tab leaks the keyboard grab on an empty desktop | `☑` |
| WM-02 | **P0** | Grabs | Pointer grab result is never checked before entering drag | `☐` |
| WM-03 | **P0** | Diagnostics | All X errors are silently discarded | `☑` |
| WM-04 | **P0** | Loop | `Stop()` is a no-op; signal path is async-unsafe | `☐` |
| WM-05 | P1 | Input | Root event mask incomplete → dead code and stale focus | `☐` |
| WM-06 | P1 | Input | Hardcoded keycodes/modifier masks; no `MappingNotify` | `☐` |
| WM-07 | P1 | Input | Hover cursor is written onto client windows | `☐` |
| WM-08 | P1 | Input | Unhandled frame clicks fall through into a move-drag | `☐` |
| WM-09 | — | Loop | ~~`Expose` is painted twice~~ **withdrawn — claim did not reproduce** | `⊘` |
| WM-10 | P1 | Input | Alt+Tab is off-by-one and not MRU-ordered | `◐` |
| WM-11 | P1 | Loop | Unbounded event drain can starve presentation | `☐` |
| WM-12 | P2 | Present | Synchronous full-surface present on the event thread | `☐` |
| WM-13 | P2 | Lifetime | Damage never subtracted for skipped windows | `☐` |
| WM-14 | P2 | Diagnostics | `IsDamageNotify` can alias X error events (type 0) | `☐` |
| WM-15 | P2 | Structure | Two render paths; `RenderComposite` is dead code | `☑` |
| WM-16 | P2 | Present | Per-paint GC create/free churn | `☐` |

**Totals:** 4 × P0 (2 done), 7 × P1 (1 partial), 4 × P2 (1 done), 1 withdrawn.

> **Audit correction (2026-10-28):** WM-09 was a false positive. The expose branch
> never painted anything — it marked the compositor window damaged and fell through
> to the inherited handler, which painted exactly once. The claim "painted twice"
> was wrong. No code change was made, and the item is retained here as withdrawn
> rather than deleted so the correction is visible.

---

## 2. Phase 0 — Stop the Bleeding

These four are small, self-contained, and convert a class of silent misbehavior into either
correct behavior or a log line. Do them before any feature work.

### ☑ WM-01 — Alt+Tab leaks the keyboard grab on an empty desktop

**Where:** `src/main/pascal/wmsama.core.pas` — `TriggerAltTabForward`, `AcquireKeyboardGrab`,
`ReleaseKeyboardGrab`, `CancelAltTab`, `TriggerAltTabDismiss`
(was `2391-2401`, `2175-2195`, `2413-2427`, `2456-2467`)

**What happens:** `xcb_grab_keyboard()` is issued *before* `TriggerAltTabForward()`, but that
procedure returned early when there were no eligible windows
(`if eligibleList.Count <= 0 then Exit;`) without setting `FAltTabActive`. Every ungrab site —
Escape, Return, Alt release — was gated on `FAltTabActive`. The grab was therefore never released.

**Observable failure:** press Alt+Tab on an empty desktop and the WM swallows every keystroke
system-wide until an Alt+Tab succeeds. From a user's perspective the desktop is frozen.

**Fix (landed):**
- The candidate list is resolved *first*; on an empty desktop no grab is attempted at all.
- `FKeyboardGrabHeld` is now the single source of truth, driven only by
  `AcquireKeyboardGrab` / `ReleaseKeyboardGrab`. Every exit path funnels through
  `ReleaseKeyboardGrab`, which is idempotent.
- The `xcb_grab_keyboard_reply` status is checked; a refused grab no longer marks the switcher
  active.
- `CancelAltTab` (Escape) is now distinct from `TriggerAltTabDismiss` (activate selection), so
  cancel no longer activates the highlighted window.
- A client unmapped mid-switch cancels the switcher instead of leaving the HUD pointing at a
  dead client.

**Acceptance — verified 2026-10-28:**
1. ☑ Empty Xephyr session, two Alt+Tab presses, then `xev` → **1 KeyPress received**.
   The pre-fix binary (built from `HEAD` in a scratch copy) → **0 KeyPress received**.
   This is the reproduction and the proof of fix.
2. ☑ Two `xterm` clients, three Alt+Tab presses, dismiss via Alt release → WM alive,
   keyboard functional, stderr clean.
3. ☑ Unit tests `TestAltTabEmptyDesktopDoesNotGrab` (grab never even attempted) and
   `TestAltTabGrabAlwaysReleased` (cancel / dismiss / unmap / idempotent release).

**Note:** a headless WM (`Connection = nil`) reports `KeyboardGrabHeld = True` on acquire,
because there is no server to contend with. This keeps the state machine testable and is
documented in `AcquireKeyboardGrab`.

---

### ☐ WM-02 — Pointer grab result is never checked before entering drag

**Where:** **[florialib]** `src/main/pascal/floria.xcb.wm.pas:4516-4552` (reply freed at `4547-4549`)

**What happens:** `xcb_grab_pointer_reply()` is freed without inspecting `reply^.status`, and
`FDragClient` / `FDragMode` are assigned *before* the grab is attempted. On failure the WM
believes it is dragging but does not own the pointer. Because the root mask does not select
`BUTTON_RELEASE` (see WM-05), the terminating release may never be delivered.

**Observable failure:** a window glued to the cursor until the next click. Most likely trigger is
`_NET_WM_MOVERESIZE` (`4236-4273`), where a client-initiated move can collide with an existing
grab, or `XCB_GRAB_STATUS_ALREADY_GRABBED` after a lost release.

**Fix:**
- On `status <> XCB_GRAB_STATUS_SUCCESS`: do not enter drag state, log the status, optionally
  `xcb_ungrab_pointer` and retry once.
- Assign `FDragClient`/`FDragMode` only after a successful grab.
- Do the same for the keyboard grab in WM-01.

**Acceptance:**
1. `xdotool`-driven drag of a window while a second client holds the pointer → WM logs the
   failure and does not move the window.
2. Normal drag/resize across all 8 directions still works in Xephyr.
3. `_NET_WM_MOVERESIZE` from a GTK app (e.g. `xterm` with Alt+drag, or `gtk3-demo`) does not
   strand the window.

**Test:** unit test injecting a fake grab result; assert `DragMode = dmNone` on failure.

---

### ☑ WM-03 — All X errors are silently discarded

**Where:** `src/main/pascal/wmsama.core.pas` — `ProcessEvent` (error branch), `DescribeXError`,
`LogXError`, `XErrorName`, `XRequestName`; `WMSAMA_DEBUG` read in the constructor

**What happens:** `xcb_request_check` was used only in `ClaimOwnership`
(`floria.xcb.wm.pas:1827`). Everywhere else — `xcb_get_geometry`,
`xcb_composite_name_window_pixmap`, `xcb_damage_create`, `xcb_grab_*`, `xcb_put_image` — errors
arrive as events with `response_type = 0` and were dropped by the `case evType of` with no
matching branch.

**Observable failure:** `BadWindow` on a destroyed override-redirect popup, `BadMatch` on a
failed pixmap name, `BadAccess` on a refused grab — all invisible. Failures surfaced later as
cosmetic glitches with no trace to their origin.

**Fix (landed):**
- `ProcessEvent` handles `response_type = 0` **before** the damage check, so an error can never be
  reinterpreted as a damage notification (see WM-14 for the underlying alias).
- `DescribeXError` renders `error name / request name / minor / resource id / sequence`.
- The request-name table covers the full core protocol opcode range (1–120) and reports
  extension opcodes as `Extension+N` (opcode − 128).
- Output goes to **stderr**, which is unbuffered, so it appears immediately even when stdout is
  redirected to a file.

**Acceptance — verified 2026-10-28:**
1. ☑ Provoked a real error on a live connection (`xcb_create_window` with a bad parent, then
   `xcb_get_geometry` on the destroyed id) and fed the event through `ProcessEvent`:
   `[wmsama] event loop: X error BadWindow (3) on request CreateWindow (1) minor=0 resource=0x00000000 seq=1`
2. ☑ Three clients plus an Alt+Tab cycle for 60 s with `WMSAMA_DEBUG=1` → stderr empty.
3. ☑ Unknown codes degrade to numbers (`Unknown`, `Extension+122`) without crashing —
   covered by `TestXErrorDecoding`.
4. ☑ `TestErrorEventsAreConsumed` asserts the event is consumed and does not request a composite.

---

### ☐ WM-04 — `Stop()` is a no-op; the signal path is async-unsafe

**Where:** `src/main/pascal/wmsama.core.pas:2951-2997` (`while True` at `2966`);
`src/main/pascal/wmsama.pas:64-70`; **[florialib]** `floria.xcb.wm.pas:4414-4437`

**What happens:** the override of `Run()` loops on `while True` and never consults `FIsRunning`,
so the inherited `Stop()` (`4434-4437`) has no effect on the actual pump. The signal handler then
calls `WriteLn` (allocates, not async-signal-safe) and `Halt(0)` while the process is blocked in
`xcb_wait_for_event`. `Halt` skips the `finally` blocks in `wmsama.pas`, so `WM.Free()`,
`xcb_disconnect`, and every compositor teardown path are skipped.

**Observable failure:** `SIGTERM` leaves the X connection and every server-side resource to be
reaped by the server; the compositor's `DisableCompositing` never runs, so subwindow
redirection can be left in an inconsistent state. `Stop()` cannot be used for restart-in-place.

**Fix:**
- Loop condition: `while FIsRunning and not FTerminated`.
- Signal handler: set a flag and `fpWrite` one byte to a self-pipe (the only async-safe actions).
- Pump: `select()` on `{xcb_get_file_descriptor(Connection), pipe_read}` with a timeout; drain
  X events when the socket is readable, exit when the pipe fires.
- Keep the timeout so future work (snap animation, HUD auto-dismiss) has a tick source.

**Acceptance:**
1. `SIGTERM` → process exits 0 within 100 ms, `xcb_disconnect` runs (verify with a log line in
   the destructor), no `BadWindow` flood on the server afterwards.
2. `SIGINT` twice in a row does not crash or double-free.
3. `xrestop` shows resource count returning to baseline after exit.
4. `WM.Stop()` from a timer callback actually terminates `Run()`.

**Test:** unit test the pump with a socketpair standing in for the X connection.

---

## 3. Phase 1 — Conformance and Predictability

These are the items that turn "it works on my machine with xterm" into "it behaves like a
window manager".

### ☐ WM-05 — Root event mask incomplete → dead code and stale focus

**Where:** **[florialib]** `src/main/pascal/floria.xcb.wm.pas:1813-1818`;
dead check at `src/main/pascal/wmsama.core.pas:2542-2545`

**What happens:** the root mask selects `SUBSTRUCTURE_REDIRECT | SUBSTRUCTURE_NOTIFY |
STRUCTURE_NOTIFY | PROPERTY_CHANGE | BUTTON_PRESS | POINTER_MOTION`. It omits `BUTTON_RELEASE`,
`ENTER_WINDOW`, `LEAVE_WINDOW`, and `FOCUS_CHANGE`.

Consequences:
- `leaveEv^.event = Screen^.root` at `2542` **can never be true** — root never selects Leave. The
  branch that resets `CurrentRootCursor` is dead code.
- There is no `FocusIn`/`FocusOut` handling anywhere in `floria.xcb.wm.pas` (verified: no
  `FOCUS_CHANGE`, no `SetInputFocus` outside `TXCBWMClient.Activate` at `1043`). If any client
  calls `XSetInputFocus` directly, or focus reverts, `ActiveClient` goes stale: wrong titlebar
  highlight, wrong Alt+Tab target, wrong `_NET_ACTIVE_WINDOW`.

**Fix:**
- Add the missing masks on the root.
- Handle `FOCUS_CHANGE` on the root: when focus lands on a known client window, sync
  `ActiveClient` without re-raising; when focus leaves to `PointerRoot`/`None`, keep the last
  active client but stop claiming `wsFocused` on it.
- Implement ICCCM focus semantics properly: `WM_TAKE_FOCUS` vs. direct `SetInputFocus`, with
  `CurrentTime` replaced by the event timestamp where one exists.

**Acceptance:**
1. `xdotool windowfocus <other-window>` → titlebar highlight follows.
2. Run `xev` and click another window → focus reverts correctly, no stale active window.
3. A client that sets focus on itself does not desync `_NET_ACTIVE_WINDOW`
   (`xprop -root _NET_ACTIVE_WINDOW`).

**Test:** unit test `ActiveClient` sync given a synthetic `FocusIn`/`FocusOut` sequence.

---

### ☐ WM-06 — Hardcoded keycodes and modifier masks; no `MappingNotify`

**Where:** `src/main/pascal/wmsama.core.pas:334-380` (`TAB_KEYCODE = 23`, `SPACE = 65`,
arrows `111-116`, `MOD_ALT = 8`, `MOD_SUPER_SHIFT = 65`), consumers at `2391`, `2402`, `2428-2429`,
`2460`

**What happens:** raw keycodes and modifier bits are baked in. These are evdev/US-layout
assumptions. On a non-US layout the grabs silently bind to the wrong keys.

**Observable failure:** Alt+Tab does nothing on a Dvorak/AZERTY/Japanese layout; Super+Shift+Arrow
moves the wrong window or nothing.

**Fix:**
- Resolve keysyms (`XK_Tab`, `XK_space`, `XK_Left`…) to keycodes via
  `xcb_get_keyboard_mapping`, covering the whole keycode range (a keysym can map to several
  keycodes).
- Read the real Alt/Super masks from `xcb_get_modifier_mapping` instead of assuming
  `Mod1 = 8`, `Mod4 = 64`.
- Handle `XCB_MAPPING_NOTIFY` → ungrab all, re-resolve, re-grab. Without this, a layout switch
  silently kills every grab because passive grabs on unmapped keycodes stop firing.

**Acceptance:**
1. `setxkbmap fr` then Alt+Tab still switches windows.
2. `setxkbmap us` at runtime while wmsama runs → grabs still work (proves `MappingNotify`).
3. Super+Shift+Arrow moves the active window to the adjacent monitor under a remapped Mod4.

**Test:** unit test the keysym→keycode resolution table against a captured mapping fixture.

---

### ☐ WM-07 — Hover cursor is written onto client windows

**Where:** `src/main/pascal/wmsama.core.pas:2107-2139`, called from `2527-2530`

**What happens:** `UpdateHoverCursor` calls `SetWindowCursor(targetWin, ACursor)` where
`targetWin := AEventWindow`. For motion events delivered on a client window, that is the
*client window*, so the WM overwrites the application's own cursor. `SetWindowCursor`
(`floria.xcb.wm.pas:1795-1801`) is a plain `XDefineCursor` with no ownership concept.

**Observable failure:** the I-beam in a terminal becomes `left_ptr`; a browser's hand cursor over
a link becomes an arrow. Subtle, permanent, and immediately noticeable to anyone who uses the
desktop for real work.

Additionally, the Leave handler (`2537-2541`) resets `FHoverCursor := 0` without restoring the
previous cursor, so the "already applied" cache can claim a state that is not on screen.

**Fix:**
- Cursor state belongs on the **frame** window and the root only. Never write a cursor onto
  `ClientWindow`.
- On leaving a frame, restore the frame's own cursor (not the client's).
- Track cursor ownership explicitly (`FCurrentCursorWindow` + `FCurrentCursor`) so restore is
  exact rather than inferred.

**Acceptance:**
1. `xterm` shows an I-beam over its text area while wmsama runs.
2. Hovering a window edge shows the directional resize cursor; moving into the client restores
   the client's cursor within one motion event.
3. Firefox (or `gtk3-demo`) link hover shows a hand cursor.
4. `xrestop` shows cursor count stable across 5 minutes of hovering.

**Test:** unit test the cursor state machine (frame-only writes, correct restore sequence).

---

### ☐ WM-08 — Unhandled frame clicks fall through into a move-drag

**Where:** `src/main/pascal/wmsama.core.pas:2755-2840`; fallthrough target
`floria.xcb.wm.pas:4088-4113` (specifically `4104-4110`)

**What happens:** the frame-click branch has cases A–E. If none matches, control reaches the
`inherited ProcessEvent`, whose `XCB_BUTTON_PRESS` handler unconditionally calls
`BeginDrag(Cli, dmMove, ...)` on button 1 when the event window is the frame. So a click that the
derived class deliberately declined still starts a move.

**Observable failure:** currently mostly masked by frame geometry, but it is a landmine — any
future change to frame insets, corner radii, or button hit-testing turns "click on dead space in
the titlebar" into an unintended window move. It also makes the frame branch's intent
unreadable.

**Fix:** `Exit(True)` at the end of the frame branch, after the button was consumed. The base
class's fallback drag should be unreachable from `wmsama` and ideally removed from `florialib`
once no consumer relies on it.

**Acceptance:**
1. Click in every pixel class of the titlebar (buttons, title text, padding, 1 px from the edge)
   → no unintended moves.
2. Clicking the frame below the titlebar with a non-zero border width starts a resize, not a move.
3. Regression test: the base-class fallback is not reached (assert via a counter in a test
   subclass).

**Test:** unit test that every frame hit-test path returns a consumed result.

---

### ⊘ WM-09 — ~~`Expose` is painted twice~~ (withdrawn, claim did not reproduce)

**Where:** `src/main/pascal/wmsama.core.pas` `XCB_EXPOSE` branch vs.
`floria.xcb.wm.pas:4130-4137`

**What the audit claimed:** the expose branch marked the compositor window damaged without
`Exit(True)`, then fell through to the inherited handler, so the frame was painted twice.

**What is actually there:** the expose branch never paints at all — it calls `MarkDamaged` and
`RequestComposite`, then falls through to `inherited ProcessEvent`, whose expose handler calls
`DoOnFramePaint` → `PaintClientFrame` exactly once. Total: **one** paint, which is correct, since
an expose means the frame's content was lost and must be repainted.

**Resolution:** no code change. An attempted rewrite was reverted after the claim failed to
reproduce. Recorded here rather than deleted so the correction stays visible: the audit produced
one false positive out of sixteen findings, and the roadmap is the place to say so.

**Note for the future:** if `--no-compositor` support is ever dropped, this branch can be
simplified, but not before.

---

### ◐ WM-10 — Alt+Tab is off-by-one and not MRU-ordered

**Where:** `src/main/pascal/wmsama.core.pas` — `TriggerAltTabForward`, `GetAltTabEligibleClients`

**What happens:** `FAltTabIndex` was initialised to 0 and then immediately advanced with
`(FAltTabIndex + 1) mod eligibleList.Count`, so the first press highlighted the *second* entry.
Separately, `GetAltTabEligibleClients` walks `Clients` in creation order — there is no MRU list,
so the switcher order is unrelated to what the user just used.

**Observable failure:** Alt+Tab jumps to a random-ish window rather than "the previous window",
which is the one behavior users have hard-wired.

**Progress:**
- ☑ **Off-by-one fixed** (landed with WM-01, since the same code path was restructured). The
  index now only advances on subsequent presses; the first press selects index 0.
  `TestAltTabSwitcher` was updated to encode the corrected semantics.
- ☐ **MRU ordering still outstanding.** `GetAltTabEligibleClients` continues to use creation
  order. Remaining work: maintain an MRU list updated in `DoOnClientActivated` (move-to-front),
  pruned in `DoOnClientUnmapped`, and apply `IsAltTabEligible` to the MRU list rather than to
  `Clients`.

**Acceptance (remaining):**
1. With A→B→C focused in that order, one Alt+Tab selects B.
2. Alt+Tab, release, Alt+Tab → returns to C (toggle behavior).
3. Minimizing a window removes it from the cycle and does not shift the selection.
4. Docks, tooltips, menus, and `wtDesktop` never appear in the HUD.

**Test:** unit test the MRU list and index progression with a synthetic activation sequence.

---

### ☐ WM-11 — Unbounded event drain can starve presentation

**Where:** `src/main/pascal/wmsama.core.pas:2978-2987`

**What happens:** after the blocking wait, the inner `while True` drains via
`xcb_poll_for_event` until it returns `nil`. A client emitting a continuous stream —
`ConfigureNotify` storms during a resize, or a 60 Hz video generating damage — keeps that loop
non-empty indefinitely, so `CompositeScene`/`PresentToScreen` at `2990-2995` never run.

**Observable failure:** video playback or a rapidly resizing window appears frozen while the WM
is "busy", then catches up in a burst.

**Fix:** cap the batch (`for i := 1 to 64 do ...`) or time-box it (`Now()` budget of ~8 ms).
Unprocessed events stay queued and are handled next iteration; the present step always runs.

**Acceptance:**
1. Play a 60 Hz video in `mpv` inside Xephyr → smooth, no freezes, present rate tracks damage.
2. Hold a window resize → the frame follows the pointer without multi-second stalls.
3. Instrument: present count per second stays within 5% of damage-event rate under load.

**Test:** unit test the batch limiter with a synthetic event source.

---

## 4. Phase 2 — The Ceiling

Nothing here is broken in the P0 sense. These items set how good the WM can feel, and they are
the ones that most benefit from a deliberate design rather than incremental patching.

### ☐ WM-12 — Synchronous full-surface present on the event thread

**Where:** **[florialib]** `floria.xcb.wm.compositor.pas:314-362` (`FetchImage`),
`681-766` (`CompositeScene`), `768-789` (`PresentToScreen`)

**What happens:** each presented frame does:
1. a full-screen Agg redraw including a blurred shadow per window (`CompositeScene`);
2. a full-window `xcb_get_image` **round-trip** per dirty window (`FetchImage`);
3. a full-screen `xcb_put_image` to the root (`PresentToScreen`).

At 1920×1080 that is roughly 8 MB down plus 8 MB up per frame, with a blocking round-trip
executed *inside* the event handler — and during a drag, with the pointer grabbed.

**Observable failure:** resize/move lag; a stall long enough to look like a hang on slow X
transports (X forwarding, VNC, nested X). The grab-held round-trip is also a deadlock surface.

**Fix (staged):**
1. Track damage rectangles per window; fetch and present only those.
2. Cache the shadow per window size instead of re-rasterizing every frame.
3. Move rendering off the input path: a second X connection (or a render thread) with a
   dirty-flag handoff and a single present per vsync.
4. Only then consider GPU/EGL presentation.

**Acceptance:**
1. 4 windows at 1920×1080: idle CPU < 2%; drag CPU < 15%.
2. Dragging a window over another produces no visible tearing or stutter at 60 Hz.
3. `xrestop` pixmap count constant during a 5-minute drag/hover session.
4. No blocking X round-trip on the input path (instrument round-trip count per input event → 0).

**Test:** benchmark harness recording present latency and round-trips per frame.

---

### ☐ WM-13 — Damage never subtracted for skipped windows

**Where:** **[florialib]** `floria.xcb.wm.compositor.pas:702-713` vs. `364-379`

**What happens:** `CompositeScene` skips windows that are `not IsVisible` or have zero geometry
*before* reaching `ClearDamage()`, and `ClearDamage` is itself only reached when `Pixmap <> 0`.
Each skipped window keeps accumulating damage in the X server.

**Observable failure:** unbounded server-side damage-region growth for every minimized, shaded, or
off-desktop window; a full re-fetch when it reappears.

**Fix:** subtract damage unconditionally for every registered window each pass, regardless of
visibility, and destroy the damage object when a window is hidden for long enough that tracking
it is pointless (re-create on show).

**Acceptance:**
1. Minimize 10 windows and leave the session idle for 10 minutes → `xrestop` memory flat.
2. Restoring a minimized window does one bounded fetch, not a full-screen one.
3. Shaded windows (see `ToggleShade`) do not grow damage.

**Test:** unit test `ClearDamage` invocation count equals registered-window count per pass.

---

### ☐ WM-14 — `IsDamageNotify` can alias X error events

**Where:** **[florialib]** `floria.xcb.wm.compositor.pas:604-609`, called first at
`wmsama.core.pas:2379`

**What happens:**
`(AEvent^.response_type and $7F) = FDamageEventBase + XCB_DAMAGE_NOTIFY` with
`XCB_DAMAGE_NOTIFY = 0`. If `FHasDamage` is true while `FDamageEventBase` is still 0 — which
`QueryExtensions` (`453-494`) permits, since it sets `FHasDamage` whenever the version reply
succeeds and only fills `FDamageEventBase` if the extension query reports `present` — the
expression matches **error events (type 0)**.

Because the damage check runs before everything else in `ProcessEvent`, errors would be handed to
`HandleDamageNotify` and reinterpreted as garbage drawables.

**Observable failure:** rare, but it is a silent correctness trap that will also sabotage WM-03
(the error handler would never see its events). Fix this *before* adding error logging.

**Fix:** require `FDamageEventBase <> 0` in `IsDamageNotify`, and treat "version reply OK but
extension absent" as `FHasDamage := False`.

**Acceptance:**
1. Unit test: synthesize a type-0 event with `FDamageEventBase = 0` → `IsDamageNotify` returns
   `False`.
2. With WM-03 in place, errors reach the error handler and damage notifications do not.

**Test:** as above; pure unit test, no X server.

---

### ☑ WM-15 — Two render paths; `RenderComposite` is dead code

**Where:** `src/main/pascal/wmsama.core.pas` — `RenderComposite` and `Run`

**What happens:** `RenderComposite` implemented the present sequence, and `Run` inlined the same
three statements instead of calling it. The initial present was a third copy.

**Observable failure:** none today. The cost was that any change to presentation (damage
tracking, vsync, threading) would have to be applied in three places, and the compiled-in method
gave a false impression that callers existed.

**Fix (landed):** `Run` and the initial paint both call `RenderComposite`, which owns the
`FCompositorEnabled` / `FNeedsComposite` / `FCompositor <> nil` guards. There is now exactly one
present path — verified by grep: `CompositeScene` and `PresentToScreen` each appear once outside
the compositor unit, both inside `RenderComposite`.

**Acceptance:** ☑ `grep -n "PresentToScreen\|CompositeScene" src/main/pascal/*.pas` yields only
the two lines inside `RenderComposite`; behaviour unchanged (29 tests green, live session clean).

---

### ☐ WM-16 — Per-paint GC create/free churn

**Where:** `src/main/pascal/wmsama.core.pas:1892-1901`; amplification at `1235`
(`PaintAllFrames` in `DoOnClientActivated`)

**What happens:** `PaintClientFrame` allocates a GC, calls `put_image`, then frees the GC and
flushes — on every paint. `DoOnClientActivated` calls `PaintAllFrames()` on every focus change, so
one click with 20 windows means 20 GC create/free pairs, 20 `put_image` calls, and 20 flushes,
all inside the event handler.

**Observable failure:** focus-change latency that scales with window count; unnecessary server
churn.

**Fix:** cache one GC per connection (or per frame window) for the WM's lifetime, reuse it, and
flush once at the end of a paint batch. Additionally, make focus changes repaint only the
previously active and newly active frames — not all of them.

**Acceptance:**
1. 20 open windows: click between two of them → at most 2 frames repainted (instrument count).
2. GC count in `xrestop` constant across 100 focus changes.
3. `xcb_flush` count per input event ≤ 1 (instrument).

**Test:** unit test the repaint-set computation for a focus change.

---

## 5. Deliberate Non-Goals

Recorded so they are not re-litigated, and so a future contributor does not "fix" them by
accident.

- **Wayland.** Out of scope by project policy (`GEMINI.md`): native X11/XCB only.
- **Replacing the two-stage pump** (`wait` → `drain` → `present`). The shape is correct; WM-11
  only bounds the drain.
- **Override-redirect compositing.** Registering popups/menus/tooltips in the compositor and
  floating them to the top (`wmsama.core.pas:2842-2887`) is intentional and works.
- **Snap-after-`EndDrag` ordering.** `EndDrag` (`2076-2105`) calls `inherited EndDrag()` first
  (which saves `RestoredRect` while the window is still floating) and applies maximize/tile
  afterwards. That ordering is correct — do not "simplify" it.
- **`wtDesktop` pinned to the bottom of the compositor stack.** Verified correct in
  `DoOnClientMapped` (`989-1029`) and `DoOnClientActivated` (`1134-1237`).

---

## 6. Definition of Done (per item)

An item may be marked `☑` only when all of the following hold:

1. The acceptance checks in this document have been run and passed, with the date recorded.
2. A regression test exists, or a documented reason why the behavior is untestable without a
   live server — in which case the Xephyr recipe is added to the item.
3. `pasbuild test` is green.
4. For **[florialib]** items: `pasbuild test` in `florialib` is green, and the change has been
   checked against the other consumers (`floria-toolkit`, `floriajs` embedding) for behavior
   drift.
5. No new `xrestop` growth over a 5-minute idle session.
6. The Progress Log row is filled in with the commit hash.

---

## 7. Progress Log

Append-only. One row per landed item (or per significant investigation that changed the plan).

| Date | ID | Status | Commit | Notes / evidence |
| :--- | :--- | :--- | :--- | :--- |
| 2026-10-28 | — | audit | `wmsama@a5f5629` / `florialib@8d52670` | Baseline event-loop audit; 16 findings recorded |
| 2026-10-28 | WM-09 | **withdrawn** | — | Audit false positive: the expose branch never painted; only the inherited handler did, once. Attempted rewrite reverted. 15 valid findings remain |
| 2026-10-28 | WM-01 | done | `bcf6a85` | Candidate list resolved before grabbing; single `Acquire`/`Release` pair; grab status checked. Proof: pre-fix binary → 0 `KeyPress` at `xev` after empty-desktop Alt+Tab; fixed → 1. Tests +2 |
| 2026-10-28 | WM-03 | done | `bcf6a85` | Errors decoded before the damage check, stderr, `WMSAMA_DEBUG`. Live `BadWindow` decoded; clean session silent. Tests +2. Request-name table corrected against the core protocol (an earlier draft had 10/12/40–43 wrong) |
| 2026-10-28 | WM-15 | done | `bcf6a85` | Single present path via `RenderComposite`; grep-verified |
| 2026-10-28 | WM-10 | partial | `bcf6a85` | Off-by-one fixed (first press = index 0). MRU ordering still open |
| | | | | |
