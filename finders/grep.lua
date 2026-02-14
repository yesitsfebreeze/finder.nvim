local fn = vim.fn
local state = require("finder.src.state")
local DataType = state.DataType
local utils = require("finder.src.utils")

local M = {}
M.accepts = { DataType.None, DataType.FileList, DataType.GrepList, DataType.File, DataType.Dir, DataType.DirList, DataType.Commits }
M.produces = DataType.GrepList
M.actions = require("finder.src.utils").grep_query_open_actions

local function strip_dot_prefix(result)
  local cleaned = {}
  if result.code <= 1 and result.stdout then
    for line in result.stdout:gmatch("[^\n]+") do
      if line ~= "" then
        table.insert(cleaned, (line:gsub("^%./", "")))
      end
    end
  end
  return cleaned
end

local run_async = utils.async_filter(function(query, ctx)
  local toggles = state.toggles or {}
  local dirs, files = ctx.dirs, ctx.files

  local extra_flags = ""
  if toggles.case then extra_flags = extra_flags .. " -s" end
  if not toggles.case then extra_flags = extra_flags .. " -i" end
  if toggles.word then extra_flags = extra_flags .. " -w" end
  if not toggles.regex then extra_flags = extra_flags .. " -F" end

  if fn.executable("rg") == 1 then
    if dirs then
      return string.format("rg --line-number --no-heading --color=never --hidden --glob '!.git'%s %s %s", extra_flags, fn.shellescape(query), dirs)
    elseif files then
      return string.format("rg --with-filename --line-number --no-heading --color=never%s %s %s", extra_flags, fn.shellescape(query), files)
    else
      return string.format("rg --line-number --no-heading --color=never --hidden --glob '!.git'%s %s", extra_flags, fn.shellescape(query))
    end
  elseif fn.executable("grep") == 1 then
    local grep_flags = ""
    if not toggles.case then grep_flags = grep_flags .. " -i" end
    if toggles.word then grep_flags = grep_flags .. " -w" end
    if not toggles.regex then grep_flags = grep_flags .. " -F" end
    if dirs then
      return string.format("grep -rn --color=never --exclude-dir=.git%s %s %s", grep_flags, fn.shellescape(query), dirs)
    elseif files then
      return string.format("grep -Hn --color=never%s %s %s", grep_flags, fn.shellescape(query), files)
    else
      return string.format("grep -rn --color=never --exclude-dir=.git%s %s .", grep_flags, fn.shellescape(query))
    end
  end
  return nil
end, strip_dot_prefix)

function M.filter(query, items)

  local toggles = state.toggles or {}

  if items and #items > 0 and utils.is_commits(items) then
    state.stop_loading()
    local diff_lines = utils.commits_to_grep(items)
    return utils.filter_items(diff_lines, query)
  end

  if items and #items > 0 and utils.is_grep(items) then
    state.stop_loading()
    local filtered = {}
    for _, item in ipairs(items) do
      local content = item:match("^[^:]+:%d+:(.*)$")
      if content and utils.matches(content, query) then
        table.insert(filtered, item)
      end
    end
    return filtered
  end

  local dirs, files
  if items and #items > 0 then
    if fn.isdirectory(items[1]) == 1 then
      dirs = table.concat(vim.tbl_map(fn.shellescape, items), " ")
    else
      local set = {}
      for _, item in ipairs(items) do
        set[item:match("^([^:]+)") or item] = true
      end
      files = table.concat(vim.tbl_map(fn.shellescape, vim.tbl_keys(set)), " ")
    end
  end

  if fn.executable("rg") ~= 1 and fn.executable("grep") ~= 1 then
    return nil, "no grep tool"
  end

  return run_async(query, { dirs = dirs, files = files })
end

return M
