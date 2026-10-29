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

**Display-exclusive tests skip themselves when a WM is running.** A stray `wmsama` reparents the
test windows and produces spurious failures — this wasted real time during WM-05/WM-06, where
`TestClientsSurviveManagerShutdown` "failed" purely because a leftover WM on the same display was
managing the client. Those tests now call `ClaimOwnership` and skip on `BadAccess` (see
`florialib@7953ae7`), so the suite is green on a normal desktop *and* exercises the assertions on
a clean display. Still worth running against a fresh Xephyr when touching lifetime or grab code.

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
| WM-02 | **P0** | Grabs | Pointer grab result is never checked before entering drag | `☑` |
| WM-03 | **P0** | Diagnostics | All X errors are silently discarded | `☑` |
| WM-04 | **P0** | Loop | `Stop()` is a no-op; signal path is async-unsafe | `☑` |
| WM-05 | P1 | Input | Root event mask incomplete → dead code and stale focus | `☑` |
| WM-06 | P1 | Input | Hardcoded keycodes/modifier masks; no `MappingNotify` | `☑` |
| WM-07 | P1 | Input | Hover cursor is written onto client windows | `☑` |
| WM-08 | P1 | Input | Unhandled frame clicks fall through into a move-drag | `☑` |
| WM-09 | — | Loop | ~~`Expose` is painted twice~~ **withdrawn — claim did not reproduce** | `⊘` |
| WM-10 | P1 | Input | Alt+Tab is off-by-one and not MRU-ordered | `☑` |
| WM-11 | P1 | Loop | Unbounded event drain can starve presentation | `☑` |
| WM-12 | P2 | Present | Synchronous full-surface present on the event thread | `☑` |
| WM-13 | P2 | Lifetime | Damage never subtracted for skipped windows | `☑` |
| WM-14 | P2 | Diagnostics | `IsDamageNotify` can alias X error events (type 0) | `☑` |
| WM-15 | P2 | Structure | Two render paths; `RenderComposite` is dead code | `☑` |
| WM-16 | P2 | Present | Per-paint GC create/free churn | `☑` |
| WM-17 | P1 | Lifetime | WM exit destroys every reparented client | `☑` |

**Totals:** 4 × P0 (all done), 8 × P1 (7 done), 4 × P2 (all done), 1 withdrawn.
Plus **WM-18** and **WM-19** (found by profiling after the audit items closed).

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

### ☑ WM-02 — Pointer grab result is never checked before entering drag

**Where:** **[florialib]** `src/main/pascal/floria.xcb.wm.pas` — `BeginDrag`, `OnDragGrabFailed`

**What happens:** `xcb_grab_pointer_reply()` was freed without inspecting `reply^.status`, and
`FDragClient` / `FDragMode` were assigned *before* the grab was attempted. On failure the WM
believed it was dragging but did not own the pointer.

**Observable failure:** a window glued to the cursor until the next click. Most likely trigger is
`_NET_WM_MOVERESIZE`, where a client-initiated move can collide with an existing grab, or
`XCB_GRAB_STATUS_ALREADY_GRABBED` after a lost release.

**Fix (landed):**
- Drag state is committed only after `XCB_GRAB_STATUS_SUCCESS`.
- A stale grab is dropped (`xcb_ungrab_pointer`) when the status is `ALREADY_GRABBED`.
- A missing reply (connection gone) also aborts the drag rather than proceeding.
- New `OnDragGrabFailed` hook reports the `XCB_GRAB_STATUS_*` value (255 when no reply) so the
  shell can log it.
- Offline managers (`FConn = nil`) still enter drag state, preserving headless testability.

**Acceptance — verified 2026-10-28:**
1. ☑ `TestDragGrabFailureDoesNotCommitDrag`: a second connection holds the pointer, the WM's grab
   is refused, and `DragMode` stays `dmNone` with `DragClient = nil`.
2. ☑ The test was proven sensitive by sabotage: restoring the old ordering makes it fail with
   `expected: <0> but was: <1>`.
3. ☑ All existing drag/resize tests (8 directions, tiled, legacy `dmResize`) still pass.

**Test:** `TestDragGrabFailureDoesNotCommitDrag` (live X required; skips when unavailable).

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

### ☑ WM-04 — `Stop()` is a no-op; the signal path is async-unsafe

**Where:** **[florialib]** `floria.xcb.wm.pas` — `Run`, `Stop`, `RequestShutdown`, `PumpEventsOnce`,
`CreateWakeupPipe`, `DrainWakeupPipe`, `CloseWakeupPipe`, `DoOnTick`;
`wmsama.core.pas` `Run`/`DoOnTick`; `wmsama.pas` `SigHandler`

**What happens:** the loop was `while FIsRunning` wrapped around a blocking `xcb_wait_for_event`,
and `wmsama` overrode `Run()` with `while True`, so `Stop()` had no effect at all. The signal
handler called `WriteLn` and `Halt(0)` while blocked in the pump; `Halt` skips every `finally`
block, so `WM.Free()`, `xcb_disconnect`, and the compositor teardown never ran.

**Fix (landed):**
- Pump is `select()` over `{xcb_get_file_descriptor, self-pipe}` with a 16 ms tick.
- `RequestShutdown` sets a flag and writes one byte to a non-blocking self-pipe — no allocation,
  no stdio, no locks. Safe from a signal handler.
- `PumpEventsOnce` drains with `xcb_poll_for_event` **before** selecting. That primitive reads
  the socket with a zero timeout, so bytes xcb has buffered but not yet parsed cannot leave
  `select()` blind. (`xcb_poll_for_queued_event` only inspects the parsed queue and would miss
  them.) This is a robustness choice, not a fix for an observed stall — see the correction below.
- `DoOnTick` gives the shell a tick source (used for presentation now, available for animation
  and HUD auto-dismiss later).
- `wmsama` no longer overrides the loop; it only supplies `DoOnTick`.

**Acceptance — verified 2026-10-28:**
1. ☑ `SIGTERM` → exit status 0 in **10–66 ms** across 3 runs (target: < 100 ms).
2. ☑ Double `SIGINT` 50 ms apart → clean exit, no crash, no double free.
3. ☑ `Stop()`/`RequestShutdown()` from a test actually terminates `Run()`
   (`TestPumpWithoutConnection`, `TestShutdownRequestSetsFlags`).
4. ☑ Self-pipe is non-blocking on both ends and safe to drain when empty
   (`TestWakeupPipeLifecycle`).

**Known limitation:** `SIGTERM` during a drag leaves the pointer grab to be released by the
server on disconnect, which is correct but not explicit. If drag cancellation ever matters for
animation, ungrab in `RequestShutdown` — it cannot be done from the handler itself.

**Correction (2026-10-28):** while working on WM-06 the pump *appeared* to stall — MappingNotify
events seemed to sit unprocessed for seconds until unrelated traffic arrived, and a `select()`
trace showed repeated timeouts. That diagnosis was wrong. FPC buffers `StdErr`, so the debug
lines were simply not flushed; the events were being handled promptly all along. The evidence is
that the pre-change and post-change binaries behave identically under an A/B test with explicit
`Flush`. Debug output now goes through one `DebugLog` helper that flushes. The primitive change
was kept because it is more robust, but it fixed no demonstrated bug.

### ☑ WM-17 — WM exit destroys every reparented client *(found while fixing WM-04)*

**Where:** **[florialib]** `floria.xcb.wm.pas` — `TXCBWindowManager.Destroy`

**What happens:** `Destroy` freed `FClients` without reparenting anything. Frame windows are
children of the root window and belong to the WM's connection, so when the WM exits the server
destroys them — and every client reparented inside them dies with them. `UnparentClient` existed
but was never called on shutdown.

**Observable failure:** killing or restarting the window manager closes every application. Since
WM-04 makes teardown actually run, this surfaced immediately: `xterm` exited with the WM in 3/3
runs.

**Fix (landed):**
- Every reparented client is handed back to the root window before teardown; minimized clients
  stay unmapped.
- The teardown is round-tripped (`xcb_get_input_focus` reply) before the connection closes.

**The round-trip is load-bearing, and this was verified, not assumed.** A plain `xcb_flush` is
**not** sufficient — the reparent can still be lost when the connection closes. Measured by
sabotage:

| Variant | `TestClientsSurviveManagerShutdown` |
| :--- | :--- |
| No unparent (pre-fix) | **fails** |
| Unparent + flush only | **fails** |
| Unparent + flush + round-trip | **passes** |

**Acceptance — verified 2026-10-28:**
1. ☑ `xterm` survives WM exit in 3/3 live runs (previously died 3/3).
2. ☑ WM restart after `SIGTERM` reclaims ownership with the client still present — the session
   survives a WM restart.
3. ☑ `TestClientsSurviveManagerShutdown` uses **two connections**: the client window belongs to an
   observer connection, exactly like a real application. An earlier version created the client on
   the WM's own connection and was worthless — disconnecting destroyed it regardless of
   reparenting. Worth remembering for any X lifetime test.

---

## 3. Phase 1 — Conformance and Predictability

These are the items that turn "it works on my machine with xterm" into "it behaves like a
window manager".

### ☑ WM-05 — Root event mask incomplete → dead code and stale focus

**Where:** **[florialib]** `floria.xcb.wm.pas` — `ClaimOwnership` mask, `ManageWindow` client
mask, `SyncActiveClientFromFocus`, `ProcessEvent` (`XCB_FOCUS_IN` / `XCB_FOCUS_OUT`)

**What happened:** the root mask selected `SUBSTRUCTURE_REDIRECT | SUBSTRUCTURE_NOTIFY |
STRUCTURE_NOTIFY | PROPERTY_CHANGE | BUTTON_PRESS | POINTER_MOTION`. It omitted
`BUTTON_RELEASE`, `ENTER_WINDOW`, `LEAVE_WINDOW` and `FOCUS_CHANGE`. There was no focus handling
anywhere in the base class — no `FocusIn`/`FocusOut`, and `SetInputFocus` appeared only inside
`TXCBWMClient.Activate`.

**Observable failure:** if any client called `XSetInputFocus` directly, or focus reverted,
`ActiveClient` went stale: wrong titlebar highlight, wrong `_NET_ACTIVE_WINDOW`, wrong Alt+Tab
target. The `leaveEv^.event = Screen^.root` check in `wmsama` was also unreachable, because root
never selected Leave.

**Fix (landed):**
- Root mask now includes `BUTTON_RELEASE`, `ENTER_WINDOW`, `LEAVE_WINDOW`, `FOCUS_CHANGE`.
- Client windows additionally select `FOCUS_CHANGE`. Event masks are per-connection, so this does
  not interfere with the application's own selection.
- `SyncActiveClientFromFocus` adopts externally-set focus: it updates `FActiveClient`, the
  `wsFocused` flag, EWMH state and fires `DoOnClientActivated`, but deliberately does **not**
  raise the window or re-assert focus — doing so would fight the client that just took focus.
- `FSyncingFocus` suppresses the manager's own `FocusIn` echoes.
- `PointerRoot` / `None` focus details are ignored, so the last active client stays shown rather
  than blanking.

**Acceptance — verified 2026-10-28:**
1. ☑ Live: `xdotool windowfocus` on window B, then A, both adopted —
   `_NET_ACTIVE_WINDOW` followed each time without the WM being asked.
2. ☑ `TestRootEventMaskIncludesFocusAndRelease` reads the root's actual `your_event_mask` and
   asserts FOCUS_CHANGE / BUTTON_RELEASE / ENTER_WINDOW / LEAVE_WINDOW / SUBSTRUCTURE_REDIRECT.
   Sabotage-verified: dropping FOCUS_CHANGE from the mask fails it.
3. ☑ `TestFocusInSyncsActiveClient` — externally focused client becomes active, flags swap.
   Sabotage-verified: neutering the sync fails it.
4. ☑ `TestFocusInIgnoresPointerRootAndSelf` — PointerRoot, self-focus and `FSyncingFocus` are
   all no-ops.

---

### ☑ WM-06 — Hardcoded keycodes and modifier masks; no `MappingNotify`

**Where:** **[florialib]** `floria.xcb.wm.pas` — `KeysymToKeycode`, `KeycodeToModifierMask`,
`ResolveKeyBindings`, `RebindGlobalKeys`, `XCB_MAPPING_NOTIFY` branch;
`wmsama.core.pas` — `GrabGlobalKeys`, `RebindGlobalKeys`, key handling in `ProcessEvent`

**What happened:** raw keycodes and modifier bits were baked in — `TAB_KEYCODE = 23`,
`SPACE_KEYCODE = 65`, arrows `111-116`, `MOD_ALT = 8`, `MOD_SUPER_SHIFT = 65`. These are
evdev/US assumptions.

**Observable failure:** Alt+Tab did nothing on a non-US layout; Super+Shift+Arrow moved the wrong
window or nothing. A layout switch at runtime silently killed every grab, because a passive grab
on a keycode that is no longer mapped never fires.

**Fix (landed):**
- `KeysymToKeycode` scans every keysym column via `xcb_get_keyboard_mapping` (a keysym can be
  reachable only through a shift level), matching Xlib's `XKeysymToKeycode`.
- `KeycodeToModifierMask` reads `xcb_get_modifier_mapping` instead of assuming Mod1 = Alt and
  Mod4 = Super. Falls back to those constants only when the map yields nothing.
- `ResolveKeyBindings` populates Tab, Space, arrows, Escape, Return, Alt_L/Alt_R plus the four
  modifier masks, and is called from `ClaimOwnership` so an already-active layout is honoured.
- `XCB_MAPPING_NOTIFY` re-resolves and calls `RebindGlobalKeys`, which ungrabs
  (`XCB_GRAB_ANY` + `XCB_MOD_MASK_ANY`) and re-grabs.
- The old evdev constants survive in exactly one place: an explicitly commented offline fallback
  for headless tests, where there is no server to query.

**Acceptance — verified 2026-10-28:**
1. ☑ `TestKeysymResolutionQueriesServer` cross-checks the resolved Tab keycode against a fresh
   query and asserts an unmapped keysym resolves to 0 — an assertion no constant table can pass.
2. ☑ `TestKeyBindingsResolveToValidBits` — every mask is a single bit and the four lock
   combinations are distinct.
3. ☑ `TestMappingNotifyRebindsKeys` — a synthetic MappingNotify triggers exactly one
   `RebindGlobalKeys` call.
4. ☑ Live: `xmodmap -e "keycode 38 = z Z z Z"` produced
   `[wmsama] key bindings re-resolved after mapping change`, and Alt+Tab still worked afterwards.
5. ⚠ **Not** verified: an actual layout switch (`setxkbmap fr`) — Xephyr silently ignores XKB
   layout uploads, so the keymap never changed. Needs a real X server to confirm.

---

### ☑ WM-07 — Hover cursor is written onto client windows

**Where:** `wmsama.core.pas` — `UpdateHoverCursor`, its call sites, `XCB_LEAVE_NOTIFY`

**What happened:** `UpdateHoverCursor` applied the cursor to `AEventWindow`, which for a motion
event delivered on a client window is the *client window*. X resolves the cursor from the
innermost window under the pointer, so this permanently replaced the application's own cursor.
The Leave handler then reset the tracking fields without restoring anything.

**Observable failure:** the I-beam in a terminal became `left_ptr`; a browser's hand cursor over a
link became an arrow. Subtle, permanent, and immediately obvious to anyone using the desktop for
real work.

**Fix (landed):**
- The signature takes a `TXCBWMClient` instead of a window id, so **a client window is not even
  expressible as a cursor target**. Only a frame or the root can be addressed.
- Passing `nil` targets the root.
- Leaving a decorated frame restores that frame's cursor, and the previously decorated window is
  reset when the target changes, so a resize cursor does not linger on an abandoned frame.

**Acceptance — verified 2026-10-28:**
1. ☑ **Measured on screen** with `XFixesGetCursorImage`, pointer over the terminal text area:
   - old build (cursor written to the client): **24×24 hotspot 3,1** — an arrow, I-beam destroyed
   - new build: **9×16 hotspot 4,8** — the I-beam, preserved
2. ☑ Frame margin shows the 24×24 arrow, and moving back over the text restores the I-beam.
3. ☑ `TestLiveFrameBehaviour` asserts `HoverCursorWindow` is the frame, never the client window.
   Sabotage-verified: restoring the old target makes it fail.

**Note:** the earlier draft of this item expected a cursor-count check via `xrestop`. The XFixes
measurement is stronger — it reads the cursor actually rendered, rather than inferring from
resource counts.

---

### ☑ WM-08 — Unhandled frame clicks fall through into a move-drag

**Where:** `wmsama.core.pas` — the frame-click branch (`XCB_BUTTON_PRESS`, cases A–F)

**What happened:** the frame branch handled cases A–F and then fell out of the case statement,
reaching `inherited ProcessEvent`, whose `XCB_BUTTON_PRESS` handler runs an unconditional
`BeginDrag(Cli, dmMove, ...)` when the event window is the frame. A click that matched nothing
still started a window move.

**Observable failure:** mostly masked by frame geometry today, but a landmine: any change to
insets, corner radii or button hit-testing would turn "click on dead space in the titlebar" into
an unintended move. It also made the branch's intent unreadable.

**Fix (landed):** `Exit(True)` after case F. The frame click is consumed whether or not a case
matched; the base class's fallback drag is now unreachable from `wmsama`.

**Acceptance — verified 2026-10-28:**
1. ☑ A button-1 press on the frame below the titlebar (zero border width) leaves `DragMode` at
   `dmNone` with no drag client.
2. ☑ A press in the titlebar still starts `dmMove` — the guard did not swallow legitimate drags.
3. ☑ Sabotage-verified: removing the `Exit(True)` fails the test with
   `expected: <0> but was: <1>`.

---

### ☑ WM-11 — Unbounded event drain can starve presentation

**Where:** **[florialib]** `floria.xcb.wm.pas` — `PumpEventsOnce`, both drain loops

**What happened:** each pump cycle drained `xcb_poll_for_event` until it returned `nil`. A client
emitting a continuous stream — `ConfigureNotify` storms during a resize, or a 60 Hz video
generating damage — kept the loop non-empty indefinitely, so `DoOnTick` (and therefore
`RenderComposite`) never ran.

**Fix (landed):** capped at `MAX_EVENTS_PER_PUMP` (64) per cycle, in both the pre-select drain and
the post-select drain. Remaining events stay queued and are picked up by the next cycle, whose
pre-select drain reads them before blocking.

**Acceptance — verified 2026-10-29:**
1. ☑ 300 queued events: one cycle processes ≤ 64 and the rest remain reachable.
2. ☑ A second cycle continues draining — the cap defers, it does not drop.
3. ☑ Sabotage-verified: removing the cap processes all **300** in one cycle and fails the test.

**Note on making this test sensitive:** two earlier versions passed with the cap removed. Counting
leftover events is unreliable because events arrive incrementally, so a drain stops at a natural
gap. The working version counts events actually processed, and generates them with
`SubstructureRedirect` deliberately *not* claimed — with it active, maps become MapRequests and the
event count depends on window-management behaviour.

---

### ☑ WM-12 — Synchronous full-surface present on the event thread

**Where:** **[florialib]** `floria.xcb.wm.compositor.pas` — `CompositeScene`, `PresentToScreen`,
`ComputePresentRect`, `UploadRect`, `SetOverlayRect`, `BuildSnapshot`, `SnapshotChanged`

**What happened:** every frame did a full-screen Agg redraw, a full-window `xcb_get_image` per dirty
window, and a full-screen `xcb_put_image` to the root. At 1280×800 that is 4 MB uploaded per frame.

**Fix (landed):**
- **Scene snapshot.** Each pass records order, geometry, visibility, opacity, corner radii, shadow
  and blur settings. A content-only change presents partially; any structural change forces a full
  screen, because it can alter pixels outside the damage rects (a shadow left behind by a moved
  window, a window uncovered by a reorder). Deriving this from a snapshot rather than trusting the
  shell to flag changes means a reorder nobody reported still forces a full present.
- **`UploadRect`** copies the sub-rectangle into a tight buffer, because `xcb_put_image` needs
  contiguous rows while the scene image has full-screen stride.
- **Overlay tracking.** HUDs are drawn in `OnAfterRender`, after the scene, so they are invisible to
  the snapshot. `SetOverlayRect` lets the shell declare its overlay bounds; the compositor unions
  the previous and current bounds into the dirty region.

**Measured — 2026-10-29, live compositor at 1280×800:**

| Frame | Present rect | Uploaded |
| :--- | :--- | :--- |
| first / structural | 1280×800 | 4,096,000 B |
| content change | 600×400 | 960,000 B (**4.3× less**) |
| HUD appears / dismisses / moves | 300×120 … union | 144,000 B, stays partial |

**Acceptance — verified 2026-10-29:**
1. ☑ `TestContentDamagePresentsPartially` — content damage is partial, matches the window rect,
   uploads far less than a full screen, and two damaged windows union into one rect.
2. ☑ `TestStructuralChangeForcesFullPresent` — geometry, reorder, visibility, styling and removal
   each force a full present. A control case first proves content-only *is* partial, so the full
   presents are caused by the structural change and not by an absence of damage.
3. ☑ `TestOverlayRectDrivesPartialPresent` — a HUD appearing, dismissing and moving all stay
   partial, and the dirty rect covers both old and new positions.
4. ☑ `TestInvalidateForcesFullPresent` — background change, explicit `Invalidate()` and `Resize()`.

**Defect introduced and fixed during this work.** The first version presented partially without
tracking overlays. Everything passed — 690 tests green — while the live desktop left ghost pixels
where a dismissed window menu had been. It was found by screenshotting a real session, not by the
suite. A/B evidence: with `SetOverlayRect` removed, a dismissed window menu leaves its pixels on
screen; with it, the same sequence is clean. **Partial present is only sound if every pixel that can
change is accounted for, and overlays are the part the scene does not own.**

**Not done:** rendering still happens on the event thread, and `xcb_get_image` per damaged window is
still a round-trip inside the handler. Moving render off the input path (second connection or render
thread) remains the next step if input latency becomes a problem; the dirty-rect work above is its
prerequisite and is now in place.

---

### ☑ WM-13 — Damage never subtracted for skipped windows

**Where:** **[florialib]** `floria.xcb.wm.compositor.pas` — `CompositeScene`,
`TXCBCompositedWindow.SubtractDamage` / `ClearDamage`

**What happened:** `CompositeScene` skipped windows that were `not IsVisible` or had zero geometry
*before* reaching `ClearDamage()`, and `ClearDamage` was only reached when `Pixmap <> 0`. Every
skipped window kept accumulating damage regions in the server.

**Fix (landed):** subtraction is now unconditional for every registered window, performed before any
decision to skip. It is separated from the local dirty flag — `SubtractDamage` clears the server
region, `ClearDamage` does that plus `FIsDirty := False` — so a skipped window stays dirty and
re-fetches when it reappears.

**Acceptance — verified 2026-10-29:**
1. ☑ Three windows (visible, hidden, zero-sized): all three subtract damage, on every pass.
2. ☑ A hidden window keeps its local dirty flag for its next appearance.
3. ☑ Sabotage-verified: subtracting only after the visibility check yields **1** instead of 3.

---

### ☑ WM-14 — `IsDamageNotify` can alias X error events

**Where:** **[florialib]** `floria.xcb.wm.compositor.pas` — `IsDamageNotify`, `QueryExtensions`

**What happened:** the predicate compared `(response_type and $7F)` against
`FDamageEventBase + XCB_DAMAGE_NOTIFY`, where `XCB_DAMAGE_NOTIFY` is 0. With an unresolved event
base the expression degenerated to `= 0`, matching X **error** events. `QueryExtensions` also set
`FHasDamage` on the version reply alone, even when the extension query then reported it absent —
which is exactly how the base could stay 0 while `FHasDamage` was true.

**Fix (landed):**
- `IsDamageNotify` requires `FDamageEventBase <> 0`.
- `QueryExtensions` claims the extension only once the event base is resolved, so `HasDamage`
  implies a usable base. Both halves are present: the invariant, plus defence in depth.

**Acceptance — verified 2026-10-29:**
1. ☑ Offline (unresolved base) an error event is not a damage notify and is not consumed as one.
2. ☑ Live: `HasDamage` implies `DamageEventBase <> 0`, and an error event still does not match.
3. ☑ This also protects WM-03: `wmsama` handles errors before the damage check, and the underlying
   predicate no longer misroutes them for any other consumer.

**Note:** the guard half cannot be exercised without a test-only backdoor into a private field,
which is not worth adding to production code. The tests assert the invariant (`HasDamage` implies a
resolved base) rather than the unreachable state.

---

### ☑ WM-16 — Per-paint GC create/free churn

**Where:** `wmsama.core.pas` — `PaintClientFrame`, `PaintAllFrames`, `DoOnClientActivated`

**What happened:** `PaintClientFrame` allocated a GC, called `put_image`, freed the GC and
flushed — per paint. `DoOnClientActivated` called `PaintAllFrames()` on every focus change, so one
click with 20 windows meant 20 GC create/free pairs, 20 `put_image` calls and 20 flushes inside the
event handler.

**Fix (landed):**
- One GC cached for the WM's lifetime. It is created against the root window, which is valid for
  every frame because they share the root and depth. Freed in the destructor.
- `PaintClientFrame` no longer flushes; `PaintAllFrames` and the focus-change path flush once per
  batch.
- A focus change repaints only the frame that lost focus and the one that gained it. The previous
  active client is tracked in `FLastActiveClient` and cleared in `DoOnClientUnmapped` so it cannot
  dangle.

**Acceptance — verified 2026-10-28:**
1. ☑ `TitlebarGC` is created once and is unchanged across repeated paints.
   Sabotage-verified: recreating per paint fails with a differing handle.
2. ☑ With three windows, a focus change repaints exactly two frames. Sabotage-verified: restoring
   `PaintAllFrames()` reports 3.
3. ☑ `FramePaintCount` exposed for the assertion; incremented in `PaintClientFrame`.

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

### ☑ WM-18 — Drop shadow re-rasterized every frame

**Where:** **[florialib]** `floria.xcb.wm.compositor.pas` — `EnsureShadowCache`,
`InvalidateShadowCache`, `PaintedRect`

**What happened:** `CompositeScene` called `DrawShadow` for every window on every frame.
`DrawShadow` expands a rounded rect across up to 8 blur passes. The rendered shadow depends only
on width, height, radius, offset, blur and opacity — **never on position** — so essentially all of
that work was recomputing an identical image.

**Measured before the fix** (1920×1080, one window, per frame):

| Size | compose | share from shadow |
| :--- | :--- | :--- |
| 800×600 | 65.5 ms | 86% |
| 1920×1080 | 259 ms | 91% |

**Fix (landed):** rasterize once into an image sized to the window plus shadow margin, then blit
per frame. Validity is decided by comparing a key (w, h, radius, offset, blur, opacity) against the
current settings rather than by invalidation calls at each mutation site — a missed invalidation
would silently render a stale shadow, and a key comparison cannot be missed.

**Equivalence — verified, not assumed:** compared against the previous per-frame rendering over a
1920×1080 scene:
- window interior: **identical**
- differences confined to the shadow gradient
- max channel delta **5 of 255** (2%)

The delta scales with pass count — blur 2 → delta 1, blur 4 → 3, blur 8 → 5 — and plateaus at the
8-pass cap. That is 8-bit rounding accumulated across the blends, not a systematic error. Prototype
measurement of the blit vs re-rasterize: **7.0–7.5× faster** at every size.

**Acceptance — verified 2026-10-29:**
1. ☑ `TestShadowCacheInvalidatesOnResize` — built once, reused when nothing changed, rebuilt on
   resize, radius change and offset change. Sabotage-verified: disabling the key comparison leaves
   the build count at 1 and fails.
2. ☑ `TestShadowCacheDisabledWhenNoShadow` — disabled or zero-opacity shadows allocate nothing.
3. ☑ Live session: shadow present and correct on screen.

**Note:** the cache counts builds (`ShadowBuildCount`). Comparing image pointers is unreliable —
the freed image's address is immediately reused by its replacement, which made the first version of
the test pass regardless.

---

### ☑ WM-19 — Compose covered the whole screen every frame

**Where:** **[florialib]** `floria.xcb.wm.compositor.pas` — `CompositeScene`;
**[florialib]** `floria.image.core.pas` — `ClearRect`

**What happened:** `CompositeScene` cleared the entire scene image and drew every window on every
frame, regardless of what had changed — O(screen) work per frame.

**Fix (landed):**
- The scene snapshot is evaluated **before** rendering (it depends only on window state, not on
  rendering), so a content-only change composes just the dirty region. Structural changes still
  compose the full screen.
- `FPrevOverlayRect` is unioned into the compose region, so a dismissed or moved HUD is actually
  erased rather than left as stale pixels.
- Windows are still all walked (their server damage must be subtracted) but drawing is clipped to
  the region.
- **`ClearRect` added to `TFloriaImage`.** `Clear()` always fills the whole image and ignores the
  canvas clip, so it cannot be used for a partial recompose — everything outside the region must
  keep its previous pixels.

**Measured at 1920×1080, one full-screen window:**

| Stage | before | after |
| :--- | :--- | :--- |
| compose | 235–259 ms | **35 ms** |
| total frame | 255–276 ms | **43 ms** |

≈6× at 1080p, ≈7× at 800×600 (65 ms → 9 ms).

**Acceptance — verified 2026-10-29:**
1. ☑ `TestComposeRegionTracksDirtyRect` — content-only composes a sub-region; a structural change
   returns to the full screen. Sabotage-verified (disabling the region yields `x=0`, width 800).
2. ☑ `TestClearRectLeavesOutsideUntouched` — every pixel inside filled, none outside touched, and
   out-of-bounds rectangles clamp. Sabotage-verified: making it fill the whole image reports 7500
   wrongly-touched pixels.
3. ☑ Live: typing, dragging, overlapping windows and HUD dismissal all render correctly.

---

### ☐ WM-20 — Window renders black after another window is dragged across it

**Severity:** P1 (cosmetic but highly visible)
**Status:** two-surface refactor **done** (`florialib@d476226`); remediation options **tested
empirically** and none is acceptable. Closing as a documented limitation.

The client loses its offscreen content and is never told to repaint. No mechanism available to a
window manager restores it except a substantial resize, which is too disruptive to ship.

### What was built

The compositor now uses a **two-surface model**: each window's frame decorations and its client
content are captured from separate offscreen pixmaps, with separate damage objects, and drawn
frame-then-client inside **one** rounded clip.

Measured while building it:
- **One clip vs two**: clipping per surface leaves a **1px seam** at the titlebar/client boundary
  (122 pixels, up to 63/255 off). One clip around both draws is **pixel-identical** to the old
  single-surface rendering, including when the corner radius exceeds the titlebar height.
- **Client position** is read from the server rather than assumed from frame insets.

Verified visually: `xterm` and `xeyes` both render with content, rounded corners and shadow intact.

### What it did not fix

The artifact persists, and the two-surface model let us see why: **the client surface itself is
black**. The compositor is faithfully drawing a client that has not painted.

Evidence, all from the dump harness:
1. Baseline: client surface is complete.
2. After an overlap drag: client surface is black below ~row 72, while the frame surface correctly
   shows titlebar + background. The model is working; the source is empty.
3. **The live pixmap is black too** — `name_window_pixmap` on the client, read outside the WM,
   gives the same black rows. Not a caching problem.
4. **Ctrl-L restores it.** So xterm *can* repaint; it simply was not asked to.
5. A **synthetic Expose does not work** — apps correctly ignore `send_event` Exposes.
6. **xeyes is unaffected.** Dragging it over another window and back leaves its surface intact. So
   this is xterm-specific behaviour, not a general X or Composite property.
7. Reproduces with `REDIRECT_MANUAL` and `REDIRECT_AUTOMATIC`, with nested redirection, and with a
   client resize after redirection. All four tested.

### Empirical test of remediation options

Built a probe (`repaintprobe`) that puts a client back into the broken state, applies one
remediation, and measures whether the client's offscreen content returns. Swept against xterm.

| Method | Result |
| :--- | :--- |
| control (nothing) | no change |
| synthetic `Expose` | no change |
| synthetic `ConfigureNotify`, same size/position | no change |
| **`XClearArea` with `exposures=1`** | **no change** |
| real 1px resize, then back | no change |
| `unmap` + `map` | no change |
| **substantial shrink, then grow** | **REPAINTED** (37.1% → 73.5%) |

Two of those results are worth pulling out.

**`XClearArea` is not a dead end at the protocol level.** Verified against `xev`: it delivers
**real** `Expose` events (`synthetic NO`, 4 of them for one call). So the mechanism works — xterm
receives them and still does not repaint. That rules out "the WM cannot generate a real Expose" and
points at xterm ignoring Expose in this state.

**A 1px resize only repaints the newly exposed strip.** That explains why the earlier ad-hoc resize
test appeared to do nothing: it was working, just on one column. A *substantial* shrink forces a
full re-layout and does restore the window.

### What the client actually receives

Instrumented with `xev` under wmsama, covering and uncovering it:

- **Expose events after cover+uncover: 0.** The client is never told to repaint.
- Visibility events: 4.

So the chain is: no Expose on uncover → client never repaints → its offscreen pixmap stays as the
server left it.

### Ruled out by controlled harnesses

Each of these was tested in isolation and does **not** reproduce the loss:

- reparenting the client *after* it is mapped (wmsama's order) vs creating it inside the frame
- nested redirection (frame redirected *and* client redirected)
- `REDIRECT_MANUAL` vs `REDIRECT_AUTOMATIC`
- resizing the client after redirecting it
- the synthetic `ConfigureNotify` wmsama sends on every move (disabling it changed nothing)
- **xterm with no window manager at all**: redirect + cover + uncover leaves its content intact
  (73.1% throughout)

That last one is the important boundary: this is not "xterm is broken with Composite", it is
"xterm under a reparenting compositor". And `xeyes` under the same wmsama does **not** lose content,
so it is not a general property of clients either.

### Conclusion: do not ship a remedy

The only method that works is a substantial shrink-and-grow, and it is not acceptable as a default:

- it is plainly visible (the window jumps to half size and back)
- it disrupts application layout — scroll position, terminal reflow, widget re-layout
- it would fire on every uncover, which is constant in normal use (alt-tab, moving windows)

Making it opt-in behind a flag was considered and rejected: a flag that makes windows visibly jump
is not a feature, and nobody would leave it on.

**WM-20 stays open as a documented limitation.** It is cosmetic, it is recoverable by any real
interaction (a keystroke restores the window), and the remaining cause is inside xterm's handling of
being uncovered under a reparenting compositor — which the WM cannot influence through any
mechanism available to it.

### A bug in the probe itself, worth recording

The first sweep reported `0.0%` for every application and every method — a full table of
meaningless results. The probe had a local variable `w` (window width) shadowing the global `W`
(the window id), because **FPC is case-insensitive**. Every geometry query was therefore asking
about window 0.

Same family as the earlier `Screen`/`SetUp` collision and the `FrameWindow`-that-holds-a-client
naming: a name that reads correctly and means something else. Fixed by renaming to `gw`/`gh`. The
lesson is not "be careful" — it is that a measurement harness needs a sanity check against a
known-good case before its output is trusted, which is what caught it (`pixdump` said 73.5% on the
same window the probe called 0.0%).

### Diagnostic harness (keep it)

`Super+Shift+D` (with `WMSAMA_DUMP_DIR`) writes `scene.raw`, `scene.txt`, and per-window
`frame-<id>.raw` / `client-<id>.raw`. See the README's Diagnostics section. It has now paid for
itself twice: it disproved the present-path theory, and it isolated this bug to the client surface.

---

### ☑ WM-21 — Window position forgotten after maximize + tile

**Severity:** P1 (window could end up partly off-screen)
**Found by:** user report after using it normally — not by any test.

**Symptom:** maximize a window, drag it to a screen edge to tile it, then restore. The window
lands wherever the drag ended rather than where it started, often partly off-screen. Measured:
restored at `-117,-83` instead of `200,166`.

**Cause:** un-maximizing mid-drag is implemented as `Restore()` followed by `Move()`. `Move()`
correctly updates `RestoredRect` because the window is floating again by then, and `TileLeft` /
`TileRight` update it a second time. The pre-drag position was overwritten twice before the user
ever got to restore it, so "restore" restored the drag.

**Fix:** capture `RestoredRect` in `BeginDrag` and put it back in `EndDrag` when the drag ends in a
snap. A drag that does **not** snap still updates `RestoredRect` normally — dropping a window
somewhere new is how the user moves it, and that must keep working.

**Verified live**, with and without `shellsama`'s panel (workarea 1280×800 vs 1280×762):

| Sequence | Result |
| :--- | :--- |
| floating → maximize → tile → restore | returns to the original position |
| floating drag to edge → restore | returns to the pre-drag position |
| non-snapping drag, then maximize/restore | returns to the dropped position |

**Tests:** 33 → 35, both new tests failing with the fix removed.

**Note on the investigation:** the offline state machine was traced through five
maximize/tile/restore sequences first, and `RestoredRect` looked correct in every one. That was
misleading, because the corruption happens in the *drag* path (`UpdateDrag`), which the offline
trace never exercised. The live reproduction was what localised it.

**Note on the user's hypothesis:** it was suggested this might be caused by running `shellsama`
alongside `wmsama` (its panel changes the workarea). It is not — the bug reproduces with no panel
at all, and is in fact slightly *worse* without one. The panel only changes the workarea that
maximize and tile are computed against, which behaves correctly.

---

### ☑ WM-22 — Some applications lose their size after tiling

**Severity:** P1 (window does not return to its size)
**Found by:** user report, with the observation that **xterm was fine and MATE Terminal was not**.
That asymmetry was the whole lead.

**Symptom:** tile a MATE Terminal window, then restore it. It comes back at its tiled size instead
of its floating size. Measured on the user's session: floating `814x693`, tiled `512x730`,
restored `504x756` — neither the original nor the tiled size, which is the tell.

**Cause:** GTK applications snap their size to the resize increments advertised in
`WM_NORMAL_HINTS` (`mate-terminal`: increments 10×21, base 14×29). Resizing one while tiled makes it
send a `ConfigureRequest` for its own increment-snapped tiled size. Both `ConfigureRequest` branches
in `ProcessEvent` saved that request as `RestoredRect`, destroying the restore target.

Instrumented on a live session, the smoking gun:

```
CFG-REQ(tiled) client=4194311 req=0,0 504x756 saved-before=814x693
```

`xterm` advertises increments too (6×13) but does **not** re-assert its geometry after a resize, so
it sends no request and was unaffected. That is exactly the asymmetry the user noticed.

**Fix:** a maximized or tiled window is not floating, so the application has no say in its geometry.
The request is answered with a synthetic `ConfigureNotify` describing the real geometry and
otherwise ignored — the behaviour of Mutter and KWin.

**Tradeoff, deliberate:** an application that programmatically sets its size while maximized, hoping
to un-maximize to that size, is now ignored. The old behaviour supported that, and an existing test
asserted it (citing a "Lazarus debug stop"), but it is not standard and it breaks the far more common
case above. That test now asserts the corrected behaviour and records why the expectation changed.

**Verified live** on the user's `:1` session with `shellsama`'s panel (workarea 1024×730):

| Sequence | Result |
| :--- | :--- |
| floating `200,66 814x693` → tile left → restore | `200,66 814x693` |
| → tile right → restore | `200,66 814x693` |
| → maximize → restore | `200,66 814x693` |
| xterm, same sequences | unchanged (was already correct) |

**Tests:** 695 → 696. The new test and the updated one both fail with the fix removed
(`expected 200, got -1`).

**Method note:** the offline state machine had already been traced for WM-21 and looked correct,
which is why this needed the live instrumented run. Logging the actual `ConfigureRequest` while
tiled — rather than reasoning about which apps "should" send one — turned a guess about GTK into a
measurement in one step.

---

## 5. Deliberate Non-Goals## 5. Deliberate Non-Goals## 5. Deliberate Non-Goals## 5. Deliberate Non-Goals## 5. Deliberate Non-Goals

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
- **The `select()`-based pump.** Do not reintroduce `xcb_wait_for_event` in `Run()`: it cannot be
  interrupted, which is what made `Stop()` a no-op. If a blocking wait is ever needed, wait on the
  pipe as well.
- **The teardown round-trip in `TXCBWindowManager.Destroy`.** It looks like a redundant sync and
  will look like an obvious "cleanup" to a future reader. It is not: without it the reparents are
  lost at disconnect and every application dies. See WM-17 for the measurement.

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
| 2026-10-28 | WM-02 | done | `f6a1584` | Drag state committed only after `XCB_GRAB_STATUS_SUCCESS`; stale grab dropped; `OnDragGrabFailed` hook. Sabotage-verified: old ordering fails the new test |
| 2026-10-28 | WM-04 | done | `f6a1584` + `8d7f1cf` | select() over X socket + self-pipe; `RequestShutdown` is async-signal-safe; `DoOnTick` tick source. Live: SIGTERM exits in 10–66 ms, status 0. Double SIGINT clean |
| 2026-10-28 | WM-05 | done | `5baa9a2` + `a6082c6` | Root mask gains FOCUS_CHANGE/BUTTON_RELEASE/ENTER/LEAVE; `SyncActiveClientFromFocus` adopts external focus without fighting it. Sabotage-verified mask + sync tests. Live: direct `XSetInputFocus` tracked both directions |
| 2026-10-28 | WM-06 | done | `5baa9a2` + `a6082c6` | Keysyms resolved from `xcb_get_keyboard_mapping`, modifiers from `xcb_get_modifier_mapping`, `MappingNotify` re-grabs. Live remap logged + Alt+Tab survived. **Layout switch itself unverified** (Xephyr ignores XKB uploads) |
| 2026-10-28 | WM-10 | done | `5baa9a2` + `a6082c6` | MRU list; first press = previous window. Caught a self-inflicted regression (index 0 made Alt+Tab inert) in live testing, not in the unit test |
| 2026-10-28 | — | correction | — | "Pump stall" was FPC stderr buffering, not a stuck queue. A/B test showed identical behaviour. Debug output now flushes via `DebugLog`; the `xcb_poll_for_event` change was kept as robustness only |
| 2026-10-28 | WM-07 | done | `c4c0c48` | Cursor target is now a client handle, so a client window is not expressible. Measured with XFixesGetCursorImage: old build 24x24 arrow over xterm text, new build 9x16 I-beam. Sabotage-verified |
| 2026-10-28 | WM-08 | done | `c4c0c48` | Frame branch consumes the click; base-class fallback move unreachable. Sabotage-verified |
| 2026-10-28 | WM-16 | done | `c4c0c48` | One cached GC, one flush per batch, focus change repaints 2 frames not all. Sabotage-verified both |
| 2026-10-29 | WM-22 | done | `77d620d` | **Found by user report, with the xterm-vs-mate-terminal asymmetry as the lead.** GTK snaps to resize increments and re-asserts geometry while tiled, which overwrote RestoredRect. Instrumented to confirm (req 504x756 vs saved 814x693) rather than assumed. Geometry requests from non-floating windows are now ignored. Tests +1, and an existing test's expectation corrected |
| 2026-10-29 | WM-21 | done | `a5a6134` | **Found by user report.** Maximize + drag-to-tile + restore restored the drag position instead of the original (measured -117,-83 vs 200,166). Pre-drag rect is now captured at BeginDrag and reinstated only when a snap occurred. Verified with and without shellsama's panel; tests +2, both failing without the fix |
| 2026-10-29 | WM-20 | limitation | `d476226` | Two-surface refactor done; then swept every remediation empirically. Synthetic Expose, same-size ConfigureNotify, XClearArea (which does deliver real Expose, verified with xev), 1px resize and remap all fail; only a substantial shrink-and-grow works, and it is too disruptive to ship. xterm with no WM is unaffected, xeyes is unaffected under wmsama — so it is xterm-specific under a reparenting compositor. Documented rather than patched |
| 2026-10-29 | WM-18 | done | `7b16006` | Shadow cached instead of re-rasterized per frame: 86-91% of compose time. Pixel-equivalence verified (max delta 5/255, scales with pass count = rounding). ~7x on the shadow |
| 2026-10-29 | WM-19 | done | `7b16006` | Compose clipped to the damage region; `ClearRect` added. 1080p compose 235-259 ms -> 35 ms |
| 2026-10-29 | WM-14 | done | `9dd22fe` | Event base must be non-zero; `HasDamage` now implies a resolved base. Offline + live assertions |
| 2026-10-29 | WM-13 | done | `9dd22fe` | Damage subtracted unconditionally, split from the dirty flag. Sabotage-verified (1 vs 3) |
| 2026-10-29 | WM-12 | done | `9dd22fe` | Partial present via scene snapshot. Measured 960 KB vs 4 MB per content frame. **Ghost-overlay defect introduced and fixed** — caught by screenshot, not tests |
| 2026-10-29 | WM-11 | done | `9dd22fe` | 64-event batch cap. Two earlier test versions were insensitive; the working one counts processed events with redirect unclaimed |
| 2026-10-28 | WM-17 | done | `f6a1584` | **New finding.** Clients were destroyed with the WM. Now unparented + round-tripped before disconnect; xterm survives 3/3 (was 3/3 dead); WM restart preserves the session. Flush alone proven insufficient |
| | | | | |
