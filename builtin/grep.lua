local fn = vim.fn
local DataType = require("finder.state").DataType

local M = {}
M.accepts = { DataType.None, DataType.FileList, DataType.GrepList, DataType.File }
M.produces = DataType.GrepList

function M.filter(query, items)
  if not query or query == "" then 
    return items or {}
  end

  if items and #items > 0 and items[1]:match("^[^:]+:%d+:") then
    local filtered = {}
    local lower_query = query:lower()
    for _, item in ipairs(items) do
      local content = item:match("^[^:]+:%d+:(.*)$")
      if content and content:lower():find(lower_query, 1, true) then
        table.insert(filtered, item)
      end
    end
    return filtered
  end

  local files = nil
  if items and #items > 0 then
    local set = {}
    for _, item in ipairs(items) do
      set[item:match("^([^:]+)") or item] = true
    end
    files = table.concat(vim.tbl_map(fn.shellescape, vim.tbl_keys(set)), " ")
  end

  local cmd
  if fn.executable("rg") == 1 then
    cmd = files
      and string.format("rg --with-filename --line-number --no-heading --color=never %s %s", fn.shellescape(query), files)
      or string.format("rg --line-number --no-heading --color=never --hidden --glob '!.git' %s", fn.shellescape(query))
  elseif fn.executable("grep") == 1 then
    cmd = files
      and string.format("grep -Hn --color=never %s %s", fn.shellescape(query), files)
      or string.format("grep -rn --color=never --exclude-dir=.git %s .", fn.shellescape(query))
  else
    return nil, "no grep tool"
  end

  local results = fn.systemlist(cmd .. " 2>/dev/null")
  if vim.v.shell_error > 1 then return nil, "grep failed" end

  local cleaned = {}
  for _, line in ipairs(results) do
    if line ~= "" then table.insert(cleaned, (line:gsub("^%./", ""))) end
  end
  return cleaned
end

return M
