local fn = vim.fn
local state = require("finder.state")
local DataType = state.DataType

local M = {}
M.accepts = { DataType.None, DataType.FileList, DataType.GrepList, DataType.File, DataType.Dir, DataType.DirList }
M.produces = DataType.GrepList
M.actions = {
  ["<C-v>"] = function(item) local u = require("finder.utils"); local f, l = u.parse_item(item); u.open_file_at_line(f, l, "vsplit") end,
  ["<C-x>"] = function(item) local u = require("finder.utils"); local f, l = u.parse_item(item); u.open_file_at_line(f, l, "split") end,
  ["<C-t>"] = function(item) local u = require("finder.utils"); local f, l = u.parse_item(item); u.open_file_at_line(f, l, "tabedit") end,
}

M.min_query = 3

function M.filter(query, items)
  if not query or #query < M.min_query then
    return {}
  end

  local toggles = state.toggles or {}

  if items and #items > 0 and items[1]:match("^[^:]+:%d+:") then
    local utils = require("finder.utils")
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

  local extra_flags = ""
  if toggles.case then extra_flags = extra_flags .. " -s" end
  if not toggles.case then extra_flags = extra_flags .. " -i" end
  if toggles.word then extra_flags = extra_flags .. " -w" end
  if not toggles.regex then extra_flags = extra_flags .. " -F" end

  local cmd
  if fn.executable("rg") == 1 then
    if dirs then
      cmd = string.format("rg --line-number --no-heading --color=never --hidden --glob '!.git'%s %s %s", extra_flags, fn.shellescape(query), dirs)
    elseif files then
      cmd = string.format("rg --with-filename --line-number --no-heading --color=never%s %s %s", extra_flags, fn.shellescape(query), files)
    else
      cmd = string.format("rg --line-number --no-heading --color=never --hidden --glob '!.git'%s %s", extra_flags, fn.shellescape(query))
    end
  elseif fn.executable("grep") == 1 then
    local grep_flags = ""
    if not toggles.case then grep_flags = grep_flags .. " -i" end
    if toggles.word then grep_flags = grep_flags .. " -w" end
    if not toggles.regex then grep_flags = grep_flags .. " -F" end
    if dirs then
      cmd = string.format("grep -rn --color=never --exclude-dir=.git%s %s %s", grep_flags, fn.shellescape(query), dirs)
    elseif files then
      cmd = string.format("grep -Hn --color=never%s %s %s", grep_flags, fn.shellescape(query), files)
    else
      cmd = string.format("grep -rn --color=never --exclude-dir=.git%s %s .", grep_flags, fn.shellescape(query))
    end
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
