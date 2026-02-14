local fn = vim.fn
local DataType = require("finder.state").DataType
local utils = require("finder.utils")

local M = {}
M.accepts = { DataType.None, DataType.FileList, DataType.GrepList, DataType.DirList, DataType.Commits }
M.produces = DataType.DirList

local dir_cache, cache_cwd = nil, nil

function M.filter(query, items)
  if not query or query == "" then return {} end

  -- Extract directories from non-dir input types
  if items and #items > 0 and (utils.is_commits(items) or utils.is_grep(items)
    or (fn.isdirectory(items[1]) ~= 1 and fn.filereadable(items[1]) == 1)) then
    items = utils.extract_dirs(items)
    return utils.filter_items(items, query)
  end

  local is_dir = items and #items > 0 and fn.isdirectory(items[1]) == 1
  if not items or is_dir then
    local dirs = is_dir and items or { fn.getcwd() }
    local cache_key = table.concat(dirs, "\0")
    if not dir_cache or cache_cwd ~= cache_key then
      dir_cache = {}
      for _, cwd in ipairs(dirs) do
        local result
        if fn.executable("fd") == 1 then
          result = fn.systemlist(string.format("fd --type d --hidden --follow --exclude .git . %s", fn.shellescape(cwd)))
        else
          result = fn.systemlist(string.format("find %s -type d -not -path '*/.git/*' | sed 's|^\\./||'", fn.shellescape(cwd)))
        end
        vim.list_extend(dir_cache, result)
      end
      cache_cwd = cache_key
    end
    items = dir_cache
  end

  return utils.filter_items(items, query)
end

return M
