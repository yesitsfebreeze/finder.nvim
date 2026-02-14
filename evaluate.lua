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
    if not ok then
      vim.notify("Finder: failed to load picker '" .. name .. "': " .. tostring(picker), vim.log.levels.WARN)
    elseif picker and not picker.hidden and vim.tbl_contains(picker.accepts or { DataType.None }, current_type) then
      table.insert(valid, name)
    end
  end
  return valid
end

function M.evaluate()
  state.filter_error = nil
  state.loading = false

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
    if not ok then
      vim.notify("Finder: failed to load picker '" .. filter_name .. "': " .. tostring(picker), vim.log.levels.WARN)
      state.filter_error, state.items = "Malformed Filter", {}; return
    end
    if not picker or not picker.filter then
      state.filter_error, state.items = "Malformed Filter", {}; return
    end

    if not vim.tbl_contains(picker.accepts or { DataType.None }, current_type) then
      state.filter_error = "Invalid input type for " .. filter_name
      state.items = {}
      return
    end

    if #query < 2 then
      state.items = {}
      state.current_type = picker.produces or DataType.FileList
      state.sel = nil
      state.multi_sel = {}
      return
    end

    local toggles = state.toggles or {}
    local ck = filter_name .. "\0" .. query .. "\0" .. (items and table.concat(items, "\0") or "") .. "\0"
      .. (toggles.case and "C" or "c") .. (toggles.word and "W" or "w")
      .. (toggles.regex and "R" or "r") .. (toggles.gitfiles and "G" or "g")
    if state.result_cache[ck] then
      items = state.result_cache[ck]
      current_type = picker.produces or DataType.FileList
    else
      local result, err = picker.filter(query, items)
      if err == "async" then
        state.items = result or {}
        state.current_type = picker.produces or DataType.FileList
        state.sel = nil
        state.multi_sel = {}
        return
      end
      if err or result == nil then
        state.filter_error, state.items = "Malformed Filter", {}; return
      end
      state.result_cache[ck] = result
      items = result
      current_type = picker.produces or DataType.FileList
    end
  end

  state.items = items or {}
  state.current_type = current_type
  state.sel = nil
  state.multi_sel = {}
end

return M
