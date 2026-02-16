local api = vim.api
local o = vim.o

local state = require("finder.src.state")
local Mode = state.Mode
local create_space = require("space")
local evaluate_mod = require("finder.src.evaluate")
local render = require("finder.src.render")
local create_input = require("finder.src.input")
local utils = require("finder.src.utils")

local M = {}

local frecency_path = vim.fn.stdpath("data") .. "/finder_frecency.json"
local FRECENCY_EPOCH = 1700000000

function M.close()
  local entries = {}
  for k, v in pairs(state.frecency) do
    table.insert(entries, { path = k, count = v.count, last_access = v.last_access })
  end
  table.sort(entries, function(a, b)
    return (a.count * math.max(1, a.last_access - FRECENCY_EPOCH)) > (b.count * math.max(1, b.last_access - FRECENCY_EPOCH))
  end)
  local pruned = {}
  for i = 1, math.min(#entries, 500) do
    pruned[entries[i].path] = { count = entries[i].count, last_access = entries[i].last_access }
  end
  local ok, encoded = pcall(vim.json.encode, pruned)
  if ok then vim.fn.writefile({ encoded }, frecency_path) end
  render.close_preview()
  state.stop_loading()
  if state.input then state.input.close() end
  if state.space then state.space.close() end
  o.cmdheight = state.cmdh or 1
  state.input, state.space = nil, nil
  state.origin = nil
end

function M.enter()
  state.close = M.close
  if vim.fn.filereadable(frecency_path) == 1 then
    local raw = table.concat(vim.fn.readfile(frecency_path), "\n")
    local fok, data = pcall(vim.json.decode, raw)
    if fok and type(data) == "table" then state.frecency = data
    else state.frecency = {} end
  else state.frecency = {} end

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
  state.result_cache = {}
  -- Notify loaded pickers to clear stale caches
  local opts = state.opts or state.defaults
  for _, picker_path in pairs(opts.pickers) do
    local loaded = package.loaded[picker_path]
    if loaded and type(loaded.enter) == "function" then
      loaded.enter()
    end
  end
  require("finder.src.theme").apply()
  state.space = create_space()
  state.picks = evaluate_mod.get_pickers()
  state.sel = nil
  state.multi_sel = {}
  local fn = vim.fn
  state.in_git = utils.is_git_repo()
  state.toggles.gitfiles = state.in_git
  render.render_list()
  render.update_bar(state.mode == Mode.PROMPT and (state.prompts[state.idx] or "") or "")
  state.input = create_input()
end

function M.enter_fresh()
  state.filters = {}
  state.prompts = {}
  state.filter_inputs = {}
  state.idx = 0
  state.mode = Mode.PICKER
  M.enter()
end

function M.enter_with(keys)
  M.enter()
  vim.schedule(function()
    api.nvim_feedkeys(api.nvim_replace_termcodes(keys, true, false, true), "t", false)
  end)
end

function M.setup(opts)
  _G.Finder = M
  state.opts = vim.tbl_deep_extend("force", state.defaults, opts or {})
  api.nvim_create_user_command("Finder", M.enter, {})
end

state.opts = vim.tbl_deep_extend("force", state.defaults, {})

return M
