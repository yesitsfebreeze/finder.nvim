local state = require("finder.state")
local DataType = state.DataType

local M = {}

function M.get_pickers()
  local opts = state.opts or state.defaults
  local all_pickers = vim.tbl_keys(opts.pickers)
  table.sort(all_pickers)

  local current_type = state.current_type or DataType.None
  local valid = {}
  for _, name in ipairs(all_pickers) do
    local ok, picker = pcall(require, opts.pickers[name])
    if ok and picker and not picker.hidden and vim.tbl_contains(picker.accepts or { DataType.None }, current_type) then
      table.insert(valid, name)
    end
  end
  return valid
end

function M.evaluate()
  state.filter_error = nil

  if #state.filters == 0 then
    state.items = {}
    state.current_type = DataType.None
    return
  end

  local items = nil
  local current_type = DataType.None
  local opts = state.opts or state.defaults

  for i, filter_name in ipairs(state.filters) do
    local query = state.prompts[i] or ""
    local picker_path = opts.pickers[filter_name]

    if not picker_path then
      state.filter_error = "Unknown picker: " .. filter_name
      state.items = {}
      return
    end

    if state.filter_inputs[i] then
      items = state.filter_inputs[i].items
      current_type = state.filter_inputs[i].type
    end

    local ok, picker = pcall(require, picker_path)
    if not ok or not picker or not picker.filter then
      state.filter_error, state.items = "Malformed Filter", {}; return
    end

    if not vim.tbl_contains(picker.accepts or { DataType.None }, current_type) then
      state.filter_error = "Invalid input type for " .. filter_name
      state.items = {}
      return
    end

    local result, err = picker.filter(query, items)
    if err or result == nil then
      state.filter_error, state.items = "Malformed Filter", {}; return
    end

    items = result
    current_type = picker.produces or DataType.FileList
  end

  state.items = items or {}
  state.current_type = current_type
  state.sel = nil
  state.multi_sel = {}
end

return M
