local fn = vim.fn
local state = require("finder.src.state")
local DataType = state.DataType
local utils = require("finder.src.utils")

local M = {}
M.accepts = { DataType.None, DataType.FileList, DataType.GrepList, DataType.Dir, DataType.DirList, DataType.Commits }
M.produces = DataType.FileList
M.actions = utils.file_open_actions

local file_cache, cache_key_prev = nil, nil
local cache_generation = 0

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

function M.enter()
  file_cache = nil
  cache_key_prev = nil
  cache_generation = cache_generation + 1
end

function M.filter(query, items)
  if not query or query == "" then return {} end

  if items and #items > 0 and (utils.is_commits(items) or utils.is_grep(items)) then
    items = utils.extract_files(items)
    return sort_by_frecency(utils.filter_items(items, query))
  end

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
          for i, f in ipairs(result) do result[i] = cwd .. "/" .. f end
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
