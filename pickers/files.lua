local fn = vim.fn
local DataType = require("finder").DataType

local M = {}
M.accepts = { DataType.None, DataType.FileList }
M.produces = DataType.FileList

local file_cache, cache_cwd = nil, nil

function M.filter(query, items)
  if not query or query == "" then return {} end

  if not items then
    local cwd = fn.getcwd()
    if not file_cache or cache_cwd ~= cwd then
      if fn.executable("fd") == 1 then
        file_cache = fn.systemlist("fd --type f --hidden --follow --exclude .git")
      elseif fn.executable("rg") == 1 then
        file_cache = fn.systemlist("rg --files --hidden --glob '!.git'")
      else
        file_cache = fn.systemlist("find . -type f -not -path '*/.git/*' | sed 's|^\\./||'")
      end
      cache_cwd = cwd
    end
    items = file_cache
  end

  if fn.executable("fzf") == 1 then
    local result = fn.systemlist(string.format("echo %s | fzf --filter=%s 2>/dev/null",
      fn.shellescape(table.concat(items, "\n")), fn.shellescape(query)))
    if #result > 0 then return result end
  end

  local pattern = ".*" .. query:gsub(".", function(c)
    return c:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0") .. ".*"
  end)
  local matches = {}
  for _, file in ipairs(items) do
    if file:lower():match(pattern:lower()) then table.insert(matches, file) end
  end
  return matches
end

return M
