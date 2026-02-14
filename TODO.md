# finder.nvim TODO

## High Priority

- [x] **Debounce `TextChangedI`** — every keystroke fires `evaluate()` + `render_list()` synchronously. Add `vim.defer_fn` debounce with cancellation to avoid hammering the event loop on expensive pickers (grep, LSP symbols).
- [x] **Don't auto-select single picker match** — when `#state.picks == 1`, the user is immediately committed to that picker. Require `Tab`/`CR` confirmation or add a short delay so typing "fi" doesn't lock into "files" before you can type "find_replace".
- [x] **Error reporting on picker load failures** — `pcall(require, picker_path)` failures are silently swallowed everywhere. Add `vim.notify(..., vim.log.levels.WARN)` so broken picker configs are debuggable.

## Features

- [ ] **Resume** — reopen finder with the last state (filters, query, selection). Telescope's most-used feature after basic find.
- [ ] **Query history** — `<C-p>`/`<C-n>` to cycle previous queries per picker type.
- [ ] **Sorting indicator** — surface current sort order, allow toggling it.
- [ ] **Enforce `min_query`** — currently only the placeholder (`???`) is displayed but `evaluate()` still fires. Skip evaluation when input length < `min_query`.
- [ ] **Per-item preview scroll cache** — `preview_scroll` resets on selection change. Remember scroll position per item.

## Layout / UX

- [ ] **Configurable input position** — input window is hardcoded to bottom of space, 1 row, full width. Support top-positioned input, centered float, etc.
- [ ] **Guard `BufLeave` close behavior** — `BufLeave` → `vim.schedule(close)` kills finder if anything briefly leaves the buffer (e.g. split-opening a preview). Make this smarter.
- [ ] **Guard `sep` in `feedkeys`** — if `sep` is `/` this conflicts with search mode. Document or validate the separator character.

## Code Quality

- [ ] **Fix variable shadowing** — `fn` is `vim.fn` at module scope but `fn` appears as parameter/field names in closures. Rename to avoid fragility.
