local fn = vim.fn
local state = require("finder.state")
local DataType = state.DataType
local utils = require("finder.utils")

local M = {}
M.accepts = { DataType.None }
M.produces = DataType.GrepList
M.actions = {
  ["<C-v>"] = function(item) local f, l = utils.parse_item(item); utils.open_file_at_line(f, l, "vsplit", state.prompts[state.idx]) end,
  ["<C-x>"] = function(item) local f, l = utils.parse_item(item); utils.open_file_at_line(f, l, "split", state.prompts[state.idx]) end,
  ["<C-t>"] = function(item) local f, l = utils.parse_item(item); utils.open_file_at_line(f, l, "tabedit", state.prompts[state.idx]) end,
}
M.min_query = 1

function M.filter(query, _)
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

  -- Sort: lines <= cursor descending, then lines > cursor descending (backward wrap)
  table.sort(matches, function(a, b)
    local a_bwd = a.lnum <= cursor
    local b_bwd = b.lnum <= cursor
    if a_bwd and b_bwd then return a.lnum > b.lnum end
    if a_bwd then return true end
    if b_bwd then return false end
    return a.lnum > b.lnum
  end)

  local results = {}
  for _, m in ipairs(matches) do
    table.insert(results, string.format("%s:%d:%s", file, m.lnum, m.text))
  end
  return results
end

return M
