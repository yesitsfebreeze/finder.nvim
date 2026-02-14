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
  state.space = create_space()
  state.picks = evaluate_mod.get_pickers()
  state.sel = nil
  render.render_list()
  render.update_bar(state.mode == Mode.PROMPT and (state.prompts[state.idx] or "") or "")
  state.input = create_input()
end

function M.setup(opts)
  state.opts = vim.tbl_deep_extend("force", state.defaults, opts or {})
  api.nvim_create_user_command("Finder", M.enter, {})
end

return M
