# finder.nvim

A composable fuzzy finder for Neovim where filters chain together.

## Goal

An easy-to-edit, visually parseable search engine where you can combine multiple filters.

## Architecture

- **Input field** at the bottom of the window for typing queries
- **Bar line** above it showing active filters and available pickers
- **Space** overlay for rendering the results list and file preview
- **Pickers** are independent Lua modules that accept typed input and produce typed output, chained via `accepts`/`produces`

### Files

- `init.lua` — entry point, setup, open/close
- `state.lua` — shared state, Mode/DataType enums, defaults, `register_type`
- `input.lua` — input buffer, keymaps, text change handling
- `render.lua` — results list, preview window, bar rendering
- `evaluate.lua` — runs the filter chain, resolves valid pickers
- `space.lua` — overlay window management (resize, set_line)
- `utils.lua` — fuzzy filter, item parsing, file opening, highlight matching
- `builtin/` — built-in pickers (files, grep, commits, file)

### Data types

Pickers declare `accepts` (list of DataType) and `produces` (single DataType). Only pickers compatible with the current chain output are shown.

Built-in types: `None` (0), `FileList` (1), `GrepList` (2), `Commits` (3), `File` (4). External plugins register new types via `state.register_type(name, id)` with a hardcoded numeric ID.

## Project rules

- Do not create functions that are only used once — inline them
- Do not add comments, only comments that describe complicated sections
- Keep everything as small as possible
- No external dependencies beyond Neovim 0.10+

## Technical specification

- Single input field, always in insert mode
- Bar line shows: filter chain on the left, available pickers on the right (in picker mode)
- `<CR>` and `<Tab>` both confirm — open file or push result forward to next picker
- `<BS>` at column 1 navigates back through filter chain
- `<Esc>` clears selection first, then closes on second press
- File preview with treesitter highlighting appears above the results list
- Results are fuzzy-filtered; uses `fzf`, `fd`, `rg` when available, falls back to built-in Lua
- Items follow format conventions: FileList = paths, GrepList = `file:line:content`, Commits = free text
