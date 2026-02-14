# Code Review — finder.nvim

**Date:** 2026-02-14
**Scope:** Full repository (~2,600 lines across 24 files)

---

## Summary

A well-designed, composable fuzzy finder for Neovim with a clean data-flow architecture. The picker chaining concept is genuinely novel. Code is generally readable and lean for what it accomplishes. The main concerns are: repeated code patterns that should be centralized, stale README documentation, and a few architectural choices that could bite as the project grows.

---

## Findings

### 1. Duplicated `on_open` in `commits.lua` and `commit_grep.lua` — **70/100**

Both files define identical `on_open` functions:

```lua
function M.on_open(item)
  local hash = item:match('^([^\t]+)')
  utils.show_commit(hash)
end
```

**Files:** `finders/commits.lua:43-46`, `finders/commit_grep.lua:34-37`

**Recommendation:** Both are already calling `utils.show_commit()`. Extract the hash-and-show pattern into a single reusable function in `utils.lua`, e.g.:

```lua
function M.open_commit(item)
  M.show_commit(item:match('^([^\t]+)'))
end
```

---

### 2. Hash extraction pattern repeated 4+ times — **55/100**

The pattern `item:match('^([^\t]+)')` (extract commit hash from tab-delimited line) appears in:

- `finders/commits.lua:on_open`
- `finders/commit_grep.lua:on_open`
- `src/utils.lua:extract_files` (line ~167)
- `src/utils.lua:commits_to_grep` (line ~290)

**Recommendation:** Add a `utils.extract_hash(item)` helper.

---

### 3. `seen/out` deduplication pattern repeated — **45/100**

The pattern of building a `seen = {}` / `out = {}` table to deduplicate a list appears at least 3 times in `src/utils.lua` (`extract_files` twice, `extract_dirs` once).

**Recommendation:** Extract a generic `utils.dedupe(list)` or `utils.dedupe_by(list, key_fn)`.

---

### 4. `state.opts or state.defaults` repeated 7 times — **40/100**

This defensive access appears in `init.lua`, `input.lua`, `evaluate.lua` (×2), `render.lua` (×2), and `utils.lua`. Since `init.lua` already sets `state.opts` unconditionally at module load, the `or state.defaults` fallback is dead code in normal operation.

**Files:** `init.lua:70`, `input.lua:16`, `evaluate.lua:9,43`, `render.lua:34,88`, `utils.lua:32`

**Recommendation:** Either always guarantee `state.opts` is set (it already is at `init.lua:90`), or add a `state.get_opts()` function to centralize the fallback.

---

### 5. Magic number `1048576` (1 MB) used in two files — **35/100**

The max file size check `1048576` appears in both `src/render.lua:117` and `finders/file.lua:23` with no named constant.

**Recommendation:** Define `local MAX_FILE_SIZE = 1048576` in `state.lua` or `utils.lua` and reference it.

---

### 6. `is_commits()` / `is_grep()` heuristics vs `state.current_type` — **60/100**

`utils.is_commits()` and `utils.is_grep()` detect data types by pattern-matching the first item's string format. But the system already tracks `state.current_type` as a proper enum. The heuristic functions are used in `files.lua` and `grep.lua` to handle mixed input types — but this is fragile: if a filename starts with a hex string followed by a tab, it would be misclassified as a commit.

**Files:** `src/utils.lua:142-148`, `finders/files.lua:46`, `finders/grep.lua:60,66`

**Recommendation:** Pass `current_type` into `filter()` (or make it available via state) and branch on the enum instead of sniffing content.

---

### 7. `picker_load_failures` is permanent and never cleared — **65/100**

In `src/evaluate.lua`, once a picker fails to `require()`, it's added to `picker_load_failures` (a module-level table) and permanently skipped for the rest of the Neovim session. If a user is developing a picker and it errors on first load, they must restart Neovim.

**File:** `src/evaluate.lua:6`

**Recommendation:** Clear `picker_load_failures` in `M.enter()` or when the user runs `:Finder` again, allowing hot-reload during development.

---

### 8. README documentation is outdated — **75/100**

Multiple mismatches between README and actual code:

| README says | Code actually does |
|---|---|
| `<C-i>` interact mode | Not in default keys |
| `<C-g>` git toggle | Default is `<C-4>` |
| `<C-s>` case toggle | Default is `<C-1>`, `<C-s>` is preview scroll |
| `<C-w>` word toggle | Default is `<C-2>`, `<C-w>` is preview scroll |
| `<C-x>` regex toggle | Default is `<C-3>`, `<C-x>` is split-open action |
| Pickers table lists 6 | Actually 12 pickers (missing Recent, Diagnostics, Symbols, Changes, /down, ?up) |
| Custom picker example: `require("finder.state")` | Correct path: `require("finder.src.state")` |
**File:** `README.md`

**Recommendation:** Audit and update the entire README to match current defaults and feature set.

---

### 9. `_G.Finder = M` pollutes global namespace — **50/100**

In `init.lua:85`, `setup()` sets `_G.Finder = M`. This is a convenience but considered bad practice for plugins. It can collide with other plugins or user code.

**File:** `init.lua:85`

**Recommendation:** Remove `_G.Finder` and let users access the module through `require("finder")`.

---

### 10. `state.lua` is a mutable global singleton with no encapsulation — **55/100**

Every module reads and writes `state` fields directly. There's no validation, no setter functions, and no way to know which modules modify which fields without grepping. This makes reasoning about state transitions difficult.

**File:** `src/state.lua`

**Recommendation:** For a project this size it works, but consider at minimum:
- Document which modules are allowed to write which fields (as comments)
- Add setter functions for critical state like `sel`, `mode`, `items` that also handle side effects (e.g., resetting `multi_sel` when `items` changes)

---

### 11. `input.lua` is a 568-line monolithic closure — **50/100**

The `create_input()` function is a single 550+ line closure containing all input handling, keybinding registration, autocmd setup, and picker action management. It's the hardest file to navigate in the codebase.

**File:** `src/input.lua`

**Recommendation:** Extract logical sections into named functions or sub-modules:
- Keybinding setup
- Text change handler / debounce logic
- Picker selection logic
- Navigation (forward/back) logic

---

### 12. `sessions.lua` calls `get_session_map()` twice — **30/100**

`filter()` calls `get_session_map()` to list sessions, and `on_open()` calls it again to look up the session file for the selected item. The result isn't cached between calls.

**File:** `finders/sessions.lua:35,43`

**Recommendation:** Cache the session map in a module-level variable, cleared on `enter()`.

---

### 13. Missing `vim.v.shell_error` checks after `fn.systemlist` — **60/100**

Several finders call `fn.systemlist()` without checking if the command succeeded:

- `finders/files.lua:58-65` — `fd`, `rg`, `find` calls
- `finders/dirs.lua:29-34` — `fd`, `find` calls
- `src/utils.lua:extract_files` — `git show` call (line ~170)

If the external command fails (e.g., `fd` not installed, git error), the results silently include error messages as items.

**Recommendation:** Check `vim.v.shell_error ~= 0` after system calls and handle failures gracefully.

---

### 14. `symbols.lua` eagerly loads unloaded buffers — **45/100**

In `resolve_buffers()`, for files that don't have an existing buffer, the code calls `fn.bufadd()` + `fn.bufload()`. This triggers buffer loading, FileType detection, and potentially LSP attachment for every file — which can be expensive if chaining from a large file list.

**File:** `finders/symbols.lua:142-145`

**Recommendation:** Consider limiting to already-loaded buffers, or adding a max-files cap, or making the loading async.

---

### 15. Redundant `require` in `grep.lua` — **15/100**

```lua
-- Line 4: already required
local utils = require("finder.src.utils")
-- Line 9: redundant require of the same module
M.actions = require("finder.src.utils").grep_query_open_actions
```

**File:** `finders/grep.lua:4,9`

**Recommendation:** Use `M.actions = utils.grep_query_open_actions`.

---

### 16. `toggles.gitfiles` reset on every `enter()` — **35/100**

In `init.lua:78`, `state.toggles.gitfiles = state.in_git` overwrites the user's previous toggle state every time finder opens. If a user in a git repo prefers to search all files, they must toggle it off each session.

**File:** `init.lua:78`

**Recommendation:** Only set the default on first run, or make the initial state configurable.

---

### 17. `FRECENCY_EPOCH` magic number undocumented — **20/100**

`FRECENCY_EPOCH = 1700000000` in `init.lua:15` is a Unix timestamp (Nov 14, 2023) used in scoring but has no comment explaining its purpose.

**File:** `init.lua:15`

**Recommendation:** Add a comment: `-- Baseline timestamp for frecency scoring (avoids overflow with old timestamps)`

---

### 18. `result_cache` is unbounded within a session — **40/100**

`state.result_cache` is cleared on `enter()` but can grow without limit during a single finder session as the user types different queries. Each unique combination of picker + query + items + toggles creates a new cache entry.

**File:** `src/state.lua:49`, `src/evaluate.lua:79-84`

**Recommendation:** Add an LRU eviction strategy or cap the cache size (e.g., keep last 50 entries).

---

### 19. `diagnostics.lua` defines its own displayer inline — **25/100**

Most pickers delegate their display logic to `src/display.lua`, but `diagnostics.lua` creates its own displayer instance and defines a `display()` function inline. This is somewhat inconsistent but reasonable since the display needs severity-based highlighting.

**File:** `finders/diagnostics.lua:35-53`

**Recommendation:** Minor — could move the diagnostic displayer to `src/display.lua` for consistency, but current approach is acceptable.

---

### 20. `render.lua` preview reloads file from disk every render cycle — **50/100**

In `render_list()`, the preview section calls `fn.readfile(file, "", 5000)` on every render. While there's a window/buffer reuse optimization for the preview window, the file content is re-read from disk each time the list re-renders (which happens on every keystroke after debounce).

**File:** `src/render.lua:118`

**Recommendation:** Cache the file content per-file and invalidate on file change or when the preview target changes.

---

### 21. No type annotations or LuaLS annotations — **30/100**

The codebase has no `---@param`, `---@return`, or `---@class` annotations. Adding LuaLS (lua-language-server) type annotations would improve IDE support, catch bugs early, and serve as inline documentation.

**Recommendation:** Add `---@type`, `---@param`, and `---@return` annotations to public APIs at minimum.

---

### 22. `search.lua` origin capture could be stale — **40/100**

`search.lua` reads `state.origin` (set once in `init.lua:enter()`) to know which file/line to search. If the user has modified the file since opening finder, the line content from `fn.readfile()` could mismatch the buffer contents.

**File:** `finders/search.lua:10-11`

**Recommendation:** Read from the buffer (`nvim_buf_get_lines`) instead of disk (`fn.readfile`) when the buffer is loaded.

---

## Score Summary

| # | Finding | Importance |
|---|---|---|
| 1 | Duplicated `on_open` in commit pickers | 70/100 |
| 2 | Hash extraction pattern repeated 4× | 55/100 |
| 3 | `seen/out` dedup pattern repeated | 45/100 |
| 4 | `state.opts or state.defaults` repeated 7× | 40/100 |
| 5 | Magic number `1048576` in two files | 35/100 |
| 6 | Heuristic type detection vs enum | 60/100 |
| 7 | `picker_load_failures` permanent blacklist | 65/100 |
| 8 | README outdated / incorrect keybindings | 75/100 |
| 9 | `_G.Finder` global pollution | 50/100 |
| 10 | `state.lua` mutable singleton | 55/100 |
| 11 | `input.lua` monolithic 568-line closure | 50/100 |
| 12 | `sessions.lua` redundant `get_session_map()` | 30/100 |
| 13 | Missing shell error checks | 60/100 |
| 14 | `symbols.lua` eager buffer loading | 45/100 |
| 15 | Redundant `require` in `grep.lua` | 15/100 |
| 16 | `toggles.gitfiles` reset on every open | 35/100 |
| 17 | `FRECENCY_EPOCH` undocumented magic | 20/100 |
| 18 | Unbounded `result_cache` | 40/100 |
| 19 | Inline displayer in diagnostics | 25/100 |
| 20 | Preview reads file from disk every render | 50/100 |
| 21 | No LuaLS type annotations | 30/100 |
| 22 | `search.lua` reads from disk not buffer | 40/100 |

---

## What's done well

- **Composable data-flow architecture** — the `accepts`/`produces` system is clean and extensible.
- **Lean codebase** — ~2,600 lines for a full fuzzy finder with 12 pickers, preview, multi-select, frecency, async filtering, treesitter highlighting in previews.
- **No heavy dependencies** — graceful fallback chains (`fd` → `rg` → `find`).
- **Async filtering** via `vim.system` with proper cancellation of in-flight jobs.
- **Frecency scoring** with persistence — a nice touch for file ordering.
- **`search_up` / `search_down`** sharing a base via `search.lua` — good DRY pattern.
- **`display.lua` column layout system** — reusable, handles truncation and alignment cleanly.
