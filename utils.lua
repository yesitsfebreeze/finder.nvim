local fn = vim.fn
local cmd = vim.cmd

local M = {}

function M.pad(str, w)
  return #str >= w and str or str .. string.rep(" ", w - #str)
end

function M.parse_item(item)
  local file, line_num, content = item:match("^([^:]+):(%d+):(.*)$")
  if not file then file = item end
  return file, tonumber(line_num), content
end

function M.open_file_at_line(file, line_num, open_cmd, query)
  if fn.filereadable(file) == 1 then
    cmd((open_cmd or "edit") .. " " .. fn.fnameescape(file))
    if line_num then
      cmd("normal! " .. line_num .. "G")
      cmd("normal! zz")
    end
    if query and query ~= "" and line_num then
      local line = vim.api.nvim_get_current_line()
      local toggles = require("finder.state").toggles or {}
      local s, e
      if toggles.regex then
        local flags = toggles.case and "\\C" or "\\c"
        local wp = toggles.word and "\\<" or ""
        local ws = toggles.word and "\\>" or ""
        local ok, re = pcall(vim.regex, flags .. wp .. query .. ws)
        if ok then s, e = re:match_str(line) end
      else
        local plain = not toggles.word
        local q_pat
        if toggles.word then
          local escaped = query:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
          q_pat = "%f[%w_]" .. (toggles.case and escaped or escaped:lower()) .. "%f[^%w_]"
        else
          q_pat = toggles.case and query or query:lower()
        end
        local search_line = toggles.case and line or line:lower()
        s, e = search_line:find(q_pat, 1, plain)
        if s then s, e = s - 1, e end
      end
      if s and e and e > s then
        vim.api.nvim_win_set_cursor(0, { line_num, s })
        cmd("normal! v")
        vim.api.nvim_win_set_cursor(0, { line_num, e - 1 })
      end
    end
    local state = require("finder.state")
    local abs = fn.fnamemodify(file, ":p")
    state.frecency[abs] = state.frecency[abs] or { count = 0, last_access = 0 }
    state.frecency[abs].count = state.frecency[abs].count + 1
    state.frecency[abs].last_access = os.time()
  end
end

function M.matches(text, query)
  local toggles = require("finder.state").toggles or {}

  if toggles.regex then
    local flags = toggles.case and "\\C" or "\\c"
    local wp = toggles.word and "\\<" or ""
    local ws = toggles.word and "\\>" or ""
    local ok, re = pcall(vim.regex, flags .. wp .. query .. ws)
    if not ok then return false end
    return re:match_str(text) ~= nil
  end

  if toggles.word then
    local escaped = query:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    local pattern = "%f[%w_]" .. escaped .. "%f[^%w_]"
    local t = toggles.case and text or text:lower()
    local q = toggles.case and pattern or pattern:lower()
    return t:find(q) ~= nil
  end

  local t = toggles.case and text or text:lower()
  local q = toggles.case and query or query:lower()
  return t:find(q, 1, true) ~= nil
end

function M.filter_items(items, query)
  if not query or query == "" then return items end
  local filtered = {}
  for _, item in ipairs(items) do
    if M.matches(item, query) then table.insert(filtered, item) end
  end
  return filtered
end

function M.highlight_matches(text, query, base_hl)
  if not query or query == "" then return { { text, base_hl } } end

  local toggles = require("finder.state").toggles or {}
  local result = {}

  if toggles.regex then
    local flags = toggles.case and "\\C" or "\\c"
    local wp = toggles.word and "\\<" or ""
    local ws = toggles.word and "\\>" or ""
    local ok, re = pcall(vim.regex, flags .. wp .. query .. ws)
    if not ok then return { { text, base_hl } } end
    local pos = 1
    while pos <= #text do
      local s, e = re:match_str(text:sub(pos))
      if not s or e <= s then
        table.insert(result, { text:sub(pos), base_hl })
        break
      end
      if s > 0 then table.insert(result, { text:sub(pos, pos + s - 1), base_hl }) end
      table.insert(result, { text:sub(pos + s, pos + e - 1), "FinderHighlight" })
      pos = pos + e
    end
  else
    local lower_text = toggles.case and text or text:lower()
    local q, plain
    if toggles.word then
      local escaped = query:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
      q = "%f[%w_]" .. (toggles.case and escaped or escaped:lower()) .. "%f[^%w_]"
      plain = false
    else
      q = toggles.case and query or query:lower()
      plain = true
    end
    local pos = 1
    while pos <= #text do
      local s, e = lower_text:find(q, pos, plain)
      if s then
        if s > pos then table.insert(result, { text:sub(pos, s - 1), base_hl }) end
        table.insert(result, { text:sub(s, e), "FinderHighlight" })
        pos = e + 1
      else
        table.insert(result, { text:sub(pos), base_hl })
        break
      end
    end
  end

  if #result == 0 then return { { text, base_hl } } end
  return result
end

--- Detect whether items look like commits (tab-separated git log output).
function M.is_commits(items)
  return items and #items > 0 and items[1]:match('^[0-9a-f]+\t') ~= nil
end

--- Detect whether items look like grep results (file:line:content).
function M.is_grep(items)
  return items and #items > 0 and items[1]:match('^[^:]+:%d+:') ~= nil
end

--- Extract unique file paths from any item format.
--- Handles: commits → git show --name-only, grep → file from file:line:content,
--- plain file list, directories (returned as-is).
---@param items string[]
---@return string[]
function M.extract_files(items)
  if not items or #items == 0 then return {} end

  if M.is_commits(items) then
    local hashes = {}
    for _, item in ipairs(items) do
      local h = item:match('^([^\t]+)')
      if h then table.insert(hashes, h) end
    end
    local args = table.concat(vim.tbl_map(fn.shellescape, hashes), ' ')
    local result = fn.systemlist('git show --name-only --pretty=format: ' .. args .. ' 2>/dev/null')
    local seen, out = {}, {}
    for _, f in ipairs(result) do
      if f ~= '' and not seen[f] then
        seen[f] = true
        table.insert(out, f)
      end
    end
    return out
  end

  if M.is_grep(items) then
    local seen, out = {}, {}
    for _, item in ipairs(items) do
      local f = item:match('^([^:]+)')
      if f and not seen[f] then
        seen[f] = true
        table.insert(out, f)
      end
    end
    return out
  end

  return items
end

--- Extract unique directory paths from any item format.
---@param items string[]
---@return string[]
function M.extract_dirs(items)
  if not items or #items == 0 then return {} end
  local files = M.extract_files(items)
  local seen, out = {}, {}
  for _, f in ipairs(files) do
    local dir = fn.isdirectory(f) == 1 and f or fn.fnamemodify(f, ':h')
    if dir ~= '' and dir ~= '.' and not seen[dir] then
      seen[dir] = true
      table.insert(out, dir)
    end
  end
  return out
end

--- Parse commit diffs into file:line:content grep-style entries.
---@param items string[]  commit items (tab-separated)
---@return string[]
function M.commits_to_grep(items)
  local hashes = {}
  for _, item in ipairs(items) do
    local h = item:match('^([^\t]+)')
    if h then table.insert(hashes, h) end
  end
  local diff_lines = {}
  for _, hash in ipairs(hashes) do
    local diff = fn.systemlist('git show --pretty=format: ' .. fn.shellescape(hash) .. ' 2>/dev/null')
    local file, lnum = nil, 0
    for _, line in ipairs(diff) do
      local nf = line:match('^%+%+%+ b/(.+)$')
      if nf then file = nf; lnum = 0 end
      local hs = line:match('^@@ %-[%d,]+ %+(%d+)')
      if hs then lnum = tonumber(hs) - 1 end
      if file and lnum >= 0 then
        local ch = line:sub(1, 1)
        if ch == '+' and not line:match('^%+%+%+') then
          lnum = lnum + 1
          table.insert(diff_lines, string.format('%s:%d:%s', file, lnum, line:sub(2)))
        elseif ch == ' ' then
          lnum = lnum + 1
          table.insert(diff_lines, string.format('%s:%d:%s', file, lnum, line:sub(2)))
        elseif ch ~= '-' and not line:match('^diff ') and not line:match('^index ')
          and not line:match('^@@') and not line:match('^%-%-%- ') then
          lnum = lnum + 1
        end
      end
    end
  end
  return diff_lines
end

return M
