local fn = vim.fn
local state = require("finder.state")
local DataType = state.DataType
local utils = require("finder.utils")

local M = {}
M.accepts = { DataType.None, DataType.FileList, DataType.Dir, DataType.DirList }
M.produces = DataType.FileList
M.actions = {
  ["<C-v>"] = function(item) utils.open_file_at_line(item, nil, "vsplit") end,
  ["<C-x>"] = function(item) utils.open_file_at_line(item, nil, "split") end,
  ["<C-t>"] = function(item) utils.open_file_at_line(item, nil, "tabedit") end,
}

local file_cache, cache_key_prev = nil, nil

local function sort_by_frecency(filtered)
  local frecency = state.frecency or {}
  local now = os.time()
  local scored = {}
  for _, item in ipairs(filtered) do
    local abs = fn.fnamemodify(item, ":p")
    local entry = frecency[abs]
    if entry then
      local age = math.max(1, now - entry.last_access)
      local recency_weight = 1 / (1 + age / 3600)
      scored[item] = entry.count * recency_weight
    end
  end
  if not next(scored) then return filtered end
  table.sort(filtered, function(a, b)
    return (scored[a] or 0) > (scored[b] or 0)
  end)
  return filtered
end

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

  return sort_by_frecency(utils.filter_items(items, query))
end

return M
