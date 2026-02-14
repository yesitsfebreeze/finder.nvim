local api = vim.api
local o = vim.o

local state = require("finder.state")
local Mode = state.Mode
local create_space = require("finder.space")
local evaluate_mod = require("finder.evaluate")
local render = require("finder.render")
local create_input = require("finder.input")

local M = {}

local frecency_path = vim.fn.stdpath("data") .. "/finder_frecency.json"

local function load_frecency()
  if vim.fn.filereadable(frecency_path) == 1 then
    local raw = table.concat(vim.fn.readfile(frecency_path), "\n")
    local ok, data = pcall(vim.json.decode, raw)
    if ok and type(data) == "table" then
      state.frecency = data
      return
    end
  end
  state.frecency = {}
end

local function save_frecency()
  local entries = {}
  for k, v in pairs(state.frecency) do
    table.insert(entries, { path = k, count = v.count, last_access = v.last_access })
  end
  table.sort(entries, function(a, b)
    return (a.count * math.max(1, a.last_access - 1700000000)) > (b.count * math.max(1, b.last_access - 1700000000))
  end)
  local pruned = {}
  for i = 1, math.min(#entries, 500) do
    pruned[entries[i].path] = { count = entries[i].count, last_access = entries[i].last_access }
  end
  local ok, encoded = pcall(vim.json.encode, pruned)
  if ok then
    vim.fn.writefile({ encoded }, frecency_path)
  end
end

function M.close()
  save_frecency()
  render.close_preview()
  if state.loading_timer then
    state.loading_timer:stop()
    state.loading_timer:close()
    state.loading_timer = nil
  end
  state.loading = false
  if state.input then state.input.close() end
  if state.space then state.space.close() end
  o.cmdheight = state.cmdh or 1
  state.input, state.space = nil, nil
  state.origin = nil
end

function M.enter()
  state.close = M.close
  load_frecency()

  -- Capture origin buffer context before opening finder
  local buf = api.nvim_get_current_buf()
  local name = api.nvim_buf_get_name(buf)
  local pos = api.nvim_win_get_cursor(0)
  if name and name ~= "" and vim.fn.filereadable(name) == 1 then
    state.origin = { file = name, line = pos[1], col = pos[2], buf = buf }
  else
    state.origin = nil
  end

  if #state.filters > 0 then
    state.mode, state.idx = Mode.PROMPT, #state.filters
    evaluate_mod.evaluate()
  else
    state.mode, state.idx = Mode.PICKER, 0
    state.items = {}
    state.current_type = state.DataType.None
  end
  state.cmdh = o.cmdheight
  o.cmdheight = 0
  package.loaded["finder.theme"] = nil
  require("finder.theme").apply()
  state.space = create_space()
  state.picks = evaluate_mod.get_pickers()
  state.sel = nil
  state.multi_sel = {}
  local fn = vim.fn
  state.in_git = fn.executable("git") == 1 and fn.systemlist("git rev-parse --is-inside-work-tree 2>/dev/null")[1] == "true"
  state.toggles.gitfiles = state.in_git
  render.render_list()
  render.update_bar(state.mode == Mode.PROMPT and (state.prompts[state.idx] or "") or "")
  state.input = create_input()
end

function M.setup(opts)
  _G.Finder = M
  state.opts = vim.tbl_deep_extend("force", state.defaults, opts or {})
  api.nvim_create_user_command("Finder", M.enter, {})
end

state.opts = vim.tbl_deep_extend("force", state.defaults, {})

return M
