local fn = vim.fn
local DataType = require("finder.state").DataType

local M = {}
M.accepts = { DataType.File, DataType.FileList, DataType.GrepList }
M.produces = DataType.GrepList
M.hidden = true
M.actions = {
  ["<C-v>"] = function(item) local u = require("finder.utils"); local f, l = u.parse_item(item); u.open_file_at_line(f, l, "vsplit") end,
  ["<C-x>"] = function(item) local u = require("finder.utils"); local f, l = u.parse_item(item); u.open_file_at_line(f, l, "split") end,
  ["<C-t>"] = function(item) local u = require("finder.utils"); local f, l = u.parse_item(item); u.open_file_at_line(f, l, "tabedit") end,
}

function M.filter(_, items)
  if not items or #items ~= 1 then
    return nil, "file picker needs exactly one file"
  end
  
  local input = items[1]
  local file = input:match("^([^:]+)") or input
  
  if fn.filereadable(file) ~= 1 or fn.isdirectory(file) == 1 then
    return nil, "cannot read file"
  end

  local lines = fn.readfile(file)
  local results = {}
  for line_num, line_content in ipairs(lines) do
    table.insert(results, string.format("%s:%d:%s", file, line_num, line_content))
  end
  return results
end

return M
