# finder.nvim

A composable fuzzy finder for Neovim. Pickers chain together — pipe Files into Grep, Grep into Commits, etc. No dependencies beyond Neovim 0.10+.

## Usage

```lua
require("finder").setup({
  -- defaults shown
  sep = " > ",
  list_height = 10,
  pickers = {
    Files = "finder.builtin.files",
    Grep = "finder.builtin.grep",
    Commits = "finder.builtin.commits",
    File = "finder.builtin.file",
  },
})
```

Run `:Finder` to open. That's it.

## How it works

Finder has two modes: **picker select** and **prompt**.

1. You start in **picker select**. The bar shows available pickers with their unique prefix highlighted. Type the prefix (or enough of the name) and press the separator key to select it.
2. You enter **prompt** mode. Type your query — results filter live.
3. Press `<CR>` or `<Tab>` twice on a result to either open it or push it once as input to the next picker in the chain.
4. The chain is shown in the bar: `Files > Grep > ...`. You can backspace and navigate through it to edit or remove earlier stages.

### Keybindings

| Key | Action |
|---|---|
| `<CR>` / `<Tab>` | Confirm selection — open file or push it forward to the next picker |
| `<Esc>` | Clear selection, or close finder |
| `<BS>` | At column 1: navigate back through the filter chain |
| `<Up>` / `<C-k>` | Select previous item |
| `<Down>` / `<C-j>` | Select next item |

### Data flow

Each picker declares what data types it **accepts** and what it **produces**. Only pickers compatible with the current output type are shown.

```
None ──→ Files ──→ FileList ──→ Grep ──→ GrepList
                              ──→ Commits ──→ Commits
```

Types defined in `state.lua`:

```lua
DataType = {
  None = 0,     -- initial state, no input
  FileList = 1, -- list of file paths
  GrepList = 2, -- list of file:line:content entries
  Commits = 3,  -- list of commit lines
  File = 4,     -- single file
}
```

## Built-in pickers

| Picker | Accepts | Produces | What it does |
|---|---|---|---|
| **Files** | `None`, `FileList` | `FileList` | Fuzzy-finds files using `fd`, `rg`, or `find`. Uses `fzf` for filtering if available. |
| **Grep** | `None`, `FileList`, `GrepList`, `File` | `GrepList` | Searches file contents with `rg` or `grep`. Can narrow within previous grep results. |
| **Commits** | `None`, `FileList` | `Commits` | Shows git log. Optionally scoped to files from a previous picker. |
| **File** | `File`, `FileList` | `GrepList` | (Hidden) Opens a single file's lines as grep-style entries. Used internally when you select a file and chain into Grep. |

## Writing your own picker

A picker is a Lua module that returns a table with:

```lua
local DataType = require("finder.state").DataType

local M = {}

-- Which data types this picker can receive as input.
-- DataType.None means it can be a starting picker.
M.accepts = { DataType.None, DataType.FileList }

-- What data type this picker outputs.
M.produces = DataType.FileList

-- Optional: hide from the picker menu (used for internal pickers like File).
-- M.hidden = true

-- The filter function. Called on every keystroke.
--   query: string — the user's current input
--   items: string[]|nil — output from the previous picker in the chain (nil if first)
-- Must return: items, err
--   items: string[] — filtered results
--   err: string|nil — set to abort with an error
function M.filter(query, items)
  -- your logic here
  return results
end

return M
```

### Register it

```lua
require("finder").setup({
  pickers = {
    -- keep the defaults
    Files = "finder.builtin.files",
    Grep = "finder.builtin.grep",
    Commits = "finder.builtin.commits",
    -- add yours
    Buffers = "finder.pickers.buffers",
  },
})
```

### Example: buffer picker

```lua
-- lua/finder/pickers/buffers.lua
local fn = vim.fn
local api = vim.api
local DataType = require("finder.state").DataType
local utils = require("finder.utils")

local M = {}
M.accepts = { DataType.None }
M.produces = DataType.FileList

function M.filter(query, _)
  local bufs = {}
  for _, b in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(b) then
      local name = api.nvim_buf_get_name(b)
      if name ~= "" then
        table.insert(bufs, fn.fnamemodify(name, ":."))
      end
    end
  end
  if not query or query == "" then return bufs end
  return utils.fuzzy_filter(bufs, query)
end

return M
```

Since it produces `FileList`, you can chain `Grep` or `Commits` after it.

### Custom data types

The built-in types use IDs 0–4. Register your own with a hardcoded ID to keep it stable and unique:

```lua
local state = require("finder.state")
state.register_type("Diagnostics", 100)
```

This adds `Diagnostics = 100` to `state.DataType`. Errors if the name or ID is already taken by a different registration. Re-registering the same name + ID pair is safe.

Pick IDs that won't collide — use a high range for your plugin (e.g. 100+).

```lua
-- your picker
M.accepts = { state.DataType.None }
M.produces = state.DataType.Diagnostics

-- another picker that consumes it
M.accepts = { state.DataType.Diagnostics }
```

### Item format conventions

- **FileList**: one file path per entry (`src/init.lua`)
- **GrepList**: `file:line:content` per entry (`src/init.lua:42:local M = {}`)
- **Commits**: free-form text, typically `hash message`

If your picker produces `GrepList`, file preview and jump-to-line work automatically.
