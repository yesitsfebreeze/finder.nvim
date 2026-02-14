# finder.nvim TODO

## Part 1: Fix Weaknesses

### Step 1 — Extract layout constants from `render_list()`
- Replace scattered magic numbers (`4`, `wh - 3`, `0.4`) with a local layout table computed at the top of `render_list()`
- Add `file_width_ratio` field to `defaults` in `state.lua` (default `0.4`)
- Variable names document intent — no comments needed

### Step 2 — Reuse preview buffer/window
- Track `preview_state.file` and `preview_state.range`
- If unchanged across renders, skip recreation entirely
- If only range changes (same file), update lines + reposition window via `nvim_win_set_config` instead of close/reopen
- Only `close_preview()` when selection moves to non-previewable item or finder closes

### Step 3 — Break `render_list()` into local closures
- Per project rules: no standalone single-use functions, use closures inside `render_list()`
- `local render_preview = function() ... end`
- `local render_items = function() ... end`
- `local render_status = function() ... end`
- Main body: compute layout → `render_preview()` → `render_items()` → `render_status()`
- ~130 lines → ~4 focused blocks of ~30 lines each

### Step 4 — Make odd-height logic explicit
- Rename `max_visible` computation variable to `centered_height`
- Self-documenting: centering the selected item requires odd count

---

## Part 2: New Features

### Step 5 — Async/streaming results
- Add optional `filter_async(query, items, on_results)` to picker interface
- `on_results(results, is_complete)` receives chunks
- Use `vim.fn.jobstart()` with `on_stdout` to stream lines
- Add `M.evaluate_async()` in `evaluate.lua`:
  - Sync pickers run normally in chain
  - Last picker uses `filter_async` if available
  - Accumulates into `state.items`, re-renders via `vim.schedule()`
  - Stores job ID in `state.active_job` (killed on next keystroke)
- In `input.lua` `TextChangedI`: kill `state.active_job` before new eval
- Convert `grep.lua` first (biggest win), then `files.lua`
- Keep `filter()` as sync fallback for custom pickers

### Step 6 — Result caching
- Add `state.result_cache = {}` keyed by `filter_name .. "\0" .. query .. "\0" .. input_hash`
- Check cache before calling `picker.filter()` in `evaluate.lua`
- Invalidate on: toggle change, chain change, `filter_inputs` change
- `files.lua`: extend existing file-list cache to also cache per-query filtered results (LRU ~20)
- `grep.lua`: cache raw `rg` output per query; when user appends chars, filter cached results client-side (subset filtering); re-run only when query shortened or toggles change

### Step 7 — Preview scrolling
- Add `state.preview_scroll = 0` in `state.lua`
- In `render.lua` preview computation, add `preview_scroll` to `start_line`/`end_line` offset
- Reset to `0` whenever `state.sel` changes
- Keymaps in `input.lua`:
  - `<C-s>` — scroll preview down (increment, clamp to file length)
  - `<C-w>` — scroll preview up (decrement, clamp to 0)

### Step 8 — Custom actions per picker
- Add optional `actions` table to picker interface:
  ```lua
  M.actions = {
    ["<C-v>"] = function(item) utils.open_file_at_line(item, nil, "vsplit") end,
    ["<C-t>"] = function(item) utils.open_file_at_line(item, nil, "tabedit") end,
  }
  ```
- Extend `utils.open_file_at_line` to accept optional `open_cmd` parameter (default `"edit"`)
- In `input.lua`, register picker action keymaps after standard keymaps; re-register when `state.idx` changes
- Default actions for file-producing pickers: `<C-v>` (vsplit), `<C-x>` (split), `<C-t>` (tabedit)
- No conflict: toggles stay on `<C-1>`..`<C-4>`

### Step 9 — Frecency/MRU sorting
- Frecency file at `stdpath("data") .. "/finder_frecency.json"`
- Track `{ [filepath] = { count = N, last_access = timestamp } }`
- In `utils.open_file_at_line`, bump count + update timestamp after opening
- In `files.lua`, after filtering, sort by `score = count * recency_weight` (time-decayed)
- Load once per session in `init.lua` `M.enter()`, write back on close
- Cap at ~500 entries, prune lowest-scored

---

## Verification Checklist
- [ ] Steps 1-4: Open finder, verify identical rendering. Test preview, grep, empty, multi-select, terminal resize.
- [ ] Step 5: Grep in large repo — UI responsive, results stream in, new keystroke cancels old search.
- [ ] Step 6: Type Files query, backspace, retype — instant. Toggling case/word busts cache.
- [ ] Step 7: Select file, `<C-s>`/`<C-w>` scrolls preview. Changing selection resets scroll.
- [ ] Step 8: `<C-v>` opens vsplit, `<C-t>` opens new tab.
- [ ] Step 9: Open/select files repeatedly, reopen Files — recently used rank higher.

## Key Decisions
- **Async:** `vim.fn.jobstart` over `vim.uv.spawn` — simpler, handles stdout line-buffering natively
- **Frecency storage:** JSON over SQLite — no deps, sufficient for ~500 entries
- **Refactoring:** Local closures inside `render_list()` per project rule against single-use functions
- **Toggle keys:** Keep `<C-1>`..`<C-4>`, no conflict with new `<C-v>`/`<C-x>`/`<C-t>` actions
