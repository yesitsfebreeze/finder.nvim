local api = vim.api
local o = vim.o

local state = require("finder.state")
local Mode = state.Mode
local create_space = require("finder.space")
local evaluate_mod = require("finder.evaluate")
local render = require("finder.render")
local create_input = require("finder.input")

local M = {}

function M.close()
  render.close_preview()
  if state.input then state.input.close() end
  if state.space then state.space.close() end
  o.cmdheight = state.cmdh or 1
  state.input, state.space = nil, nil
end

function M.enter()
  state.close = M.close

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
  state.opts = vim.tbl_deep_extend("force", state.defaults, opts or {})
  api.nvim_create_user_command("Finder", M.enter, {})
end

return M
