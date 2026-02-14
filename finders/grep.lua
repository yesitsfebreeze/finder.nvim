local fn = vim.fn
local state = require("finder.state")
local DataType = state.DataType
local utils = require("finder.utils")

local M = {}
M.accepts = { DataType.None, DataType.FileList, DataType.GrepList, DataType.File, DataType.Dir, DataType.DirList, DataType.Commits }
M.produces = DataType.GrepList
M.actions = {
  ["<C-v>"] = function(item) local u = require("finder.utils"); local s = require("finder.state"); local f, l = u.parse_item(item); u.open_file_at_line(f, l, "vsplit", s.prompts[s.idx]) end,
  ["<C-x>"] = function(item) local u = require("finder.utils"); local s = require("finder.state"); local f, l = u.parse_item(item); u.open_file_at_line(f, l, "split", s.prompts[s.idx]) end,
  ["<C-t>"] = function(item) local u = require("finder.utils"); local s = require("finder.state"); local f, l = u.parse_item(item); u.open_file_at_line(f, l, "tabedit", s.prompts[s.idx]) end,
}

local pending = { job = nil, cmd = nil, cache = {} }

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

  if pending.cache[cmd] then
    local result = pending.cache[cmd]
    pending.cache = {}
    state.stop_loading()
    return result
  end

  if pending.job then
    pcall(function() pending.job:kill() end)
    pending.job = nil
  end

  pending.cmd = cmd
  pending.cache = {}
  state.start_loading()

  pending.job = vim.system(
    { "sh", "-c", cmd .. " 2>/dev/null" },
    { text = true },
    function(result)
      vim.schedule(function()
        if pending.cmd ~= cmd then return end
        if not state.space then state.stop_loading(); return end

        local cleaned = {}
        if result.code <= 1 and result.stdout then
          for line in result.stdout:gmatch("[^\n]+") do
            if line ~= "" then
              table.insert(cleaned, (line:gsub("^%./", "")))
            end
          end
        end

        pending.cache = { [cmd] = cleaned }
        pending.job = nil

        require("finder.evaluate").evaluate()
        local r = require("finder.render")
        r.render_list()
        r.update_bar(state.prompts[state.idx] or "")
      end)
    end
  )

  return {}, "async"
end

return M
