local fn = vim.fn
local DataType = require("finder.src.state").DataType

local M = {}
M.accepts = { DataType.File, DataType.FileList, DataType.GrepList }
M.produces = DataType.GrepList
M.hidden = true
M.actions = require("finder.src.utils").grep_open_actions

function M.filter(_, items)
  if not items or #items ~= 1 then
    return nil, "file picker needs exactly one file"
  end
  
  local input = items[1]
  local file = input:match("^([^:]+)") or input
  
  if fn.filereadable(file) ~= 1 or fn.isdirectory(file) == 1 then
    return nil, "cannot read file"
  end

  local fsize = fn.getfsize(file)
  if fsize > 1048576 then
    return nil, "file too large for preview"
  end

  local lines = fn.readfile(file)
  local results = {}
  for line_num, line_content in ipairs(lines) do
    table.insert(results, string.format("%s:%d:%s", file, line_num, line_content))
  end
  return results
end

return M
