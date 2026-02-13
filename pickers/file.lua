local fn = vim.fn
local DataType = require("finder").DataType

local M = {}
M.accepts = { DataType.File, DataType.FileList }
M.produces = DataType.GrepList
M.hidden = true

function M.filter(query, items)
  if not items or #items ~= 1 then
    return nil, "file picker needs exactly one file"
  end
  
  local input = items[1]
  
  local file = input:match("^([^:]+):(%d+):(%d+)$")
  if not file then
    file = input:match("^([^:]+):(%d+)")
  end
  if not file then
    file = input
  end
  
  if fn.filereadable(file) ~= 1 or fn.isdirectory(file) == 1 then
    return nil, "cannot read file"
  end
  
  local lines = fn.readfile(file)
  local results = {}
  
  for line_num, line_content in ipairs(lines) do
    local formatted = string.format("%s:%d:%s", file, line_num, line_content)
    table.insert(results, formatted)
  end
  
  return results
end

return M
