local fn = vim.fn
local state = require("finder.src.state")
local DataType = state.DataType
local utils = require("finder.src.utils")

local M = {}

function M.filter_with_direction(query, direction)
  if not query or query == "" then return {} end

  local ctx = state.origin
  if not ctx then return nil, "no origin buffer" end

  local file = ctx.file
  local cursor = ctx.line
  local lines = fn.readfile(file)
  if not lines or #lines == 0 then return nil, "cannot read file" end

  local matches = {}
  for i, line in ipairs(lines) do
    if utils.matches(line, query) then
      table.insert(matches, { lnum = i, text = line })
    end
  end

  if direction == "down" then
    -- Forward wrap: lines >= cursor ascending, then lines < cursor ascending
    table.sort(matches, function(a, b)
      local a_fwd = a.lnum >= cursor
      local b_fwd = b.lnum >= cursor
      if a_fwd and b_fwd then return a.lnum < b.lnum end
      if a_fwd then return true end
      if b_fwd then return false end
      return a.lnum < b.lnum
    end)
  else
    -- Backward wrap: lines <= cursor descending, then lines > cursor descending
    table.sort(matches, function(a, b)
      local a_bwd = a.lnum <= cursor
      local b_bwd = b.lnum <= cursor
      if a_bwd and b_bwd then return a.lnum > b.lnum end
      if a_bwd then return true end
      if b_bwd then return false end
      return a.lnum > b.lnum
    end)
  end

  local results = {}
  for _, m in ipairs(matches) do
    table.insert(results, string.format("%s:%d:%s", file, m.lnum, m.text))
  end
  return results
end

return M
