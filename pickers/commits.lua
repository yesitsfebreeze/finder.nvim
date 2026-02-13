local fn = vim.fn
local DataType = require("finder").DataType

local M = {}
M.accepts = { DataType.None, DataType.FileList }
M.produces = DataType.Commits

function M.filter(query, items)
  if fn.executable("git") ~= 1 then
    return nil, "git not found"
  end

  local cmd
  local format = "%h %s"

  if items and #items > 0 then
    local files = table.concat(vim.tbl_map(fn.shellescape, items), " ")
    cmd = string.format("git log --oneline --pretty=format:'%s' -- %s 2>/dev/null", format, files)
  else
    cmd = string.format("git log --oneline --pretty=format:'%s' 2>/dev/null", format)
  end

  local results = fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then
    return nil, "git log failed"
  end

  if not query or query == "" then
    return results
  end

  local pattern = ".*" .. query:gsub(".", function(c)
    return c:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0") .. ".*"
  end)

  local matches = {}
  for _, line in ipairs(results) do
    if line:lower():match(pattern:lower()) then
      table.insert(matches, line)
    end
  end

  return matches
end

return M
