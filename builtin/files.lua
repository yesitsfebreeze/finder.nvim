local fn = vim.fn
local state = require("finder.state")
local DataType = state.DataType
local utils = require("finder.utils")

local M = {}
M.accepts = { DataType.None, DataType.FileList, DataType.Dir, DataType.DirList }
M.produces = DataType.FileList

local file_cache, cache_key_prev = nil, nil

function M.filter(query, items)
  if not query or query == "" then return {} end

  local toggles = state.toggles or {}
  local is_dir = items and #items > 0 and fn.isdirectory(items[1]) == 1
  if not items or is_dir then
    local dirs = is_dir and items or { fn.getcwd() }
    local gitfiles = toggles.gitfiles and state.in_git
    local cache_key = (gitfiles and "git:" or "") .. table.concat(dirs, "\0")
    if not file_cache or cache_key_prev ~= cache_key then
      file_cache = {}
      for _, cwd in ipairs(dirs) do
        local result
        if gitfiles then
          result = fn.systemlist(string.format("git -C %s ls-files --cached --others --exclude-standard", fn.shellescape(cwd)))
        elseif fn.executable("fd") == 1 then
          result = fn.systemlist(string.format("fd --type f --hidden --follow --exclude .git . %s", fn.shellescape(cwd)))
        elseif fn.executable("rg") == 1 then
          result = fn.systemlist("rg --files --hidden --glob '!.git' " .. fn.shellescape(cwd))
        else
          result = fn.systemlist(string.format("find %s -type f -not -path '*/.git/*' | sed 's|^\\./||'", fn.shellescape(cwd)))
        end
        vim.list_extend(file_cache, result)
      end
      cache_key_prev = cache_key
    end
    items = file_cache
  end

  return utils.filter_items(items, query)
end

return M
