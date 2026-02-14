local fn = vim.fn
local cmd = vim.cmd

local M = {}

function M.is_git_repo()
  return fn.executable("git") == 1 and fn.systemlist("git rev-parse --is-inside-work-tree 2>/dev/null")[1] == "true"
end

function M.pad(str, w)
  return #str >= w and str or str .. string.rep(" ", w - #str)
end

function M.parse_item(item)
  local file, line_num, content = item:match("^([^:]+):(%d+):(.*)$")
  if not file then file = item end
  return file, tonumber(line_num), content
end

function M.is_git_repo()
  return fn.executable("git") == 1 and fn.systemlist("git rev-parse --is-inside-work-tree 2>/dev/null")[1] == "true"
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
      local s, e = M.find_match(line, query)
      if s and e and e > s then
        local om = (state.opts or state.defaults).open_mode or {}
        local pos = om.pos or "begin"
        local mmode = om.mode or "normal"
        if mmode == "visual" then
          if pos == "end" then
            vim.api.nvim_win_set_cursor(0, { line_num, s })
            cmd("normal! v")
            vim.api.nvim_win_set_cursor(0, { line_num, e - 1 })
          else
            vim.api.nvim_win_set_cursor(0, { line_num, e - 1 })
            cmd("normal! v")
            vim.api.nvim_win_set_cursor(0, { line_num, s })
          end
        elseif mmode == "insert" then
          vim.api.nvim_win_set_cursor(0, { line_num, pos == "end" and e or s })
          cmd("startinsert")
        else
          vim.api.nvim_win_set_cursor(0, { line_num, pos == "end" and (e - 1) or s })
        end
      end
    end
    local state = require("finder.state")
    local abs = fn.fnamemodify(file, ":p")
    state.frecency[abs] = state.frecency[abs] or { count = 0, last_access = 0 }
    state.frecency[abs].count = state.frecency[abs].count + 1
    state.frecency[abs].last_access = os.time()
  end
end

function M.find_match(text, query, byte_offset)
  if not query or query == "" then return nil end
  local toggles = require("finder.state").toggles or {}
  byte_offset = byte_offset or 0

  if toggles.regex then
    local flags = toggles.case and "\\C" or "\\c"
    local wp = toggles.word and "\\<" or ""
    local ws = toggles.word and "\\>" or ""
    local ok, re = pcall(vim.regex, flags .. wp .. query .. ws)
    if not ok then return nil end
    local sub = byte_offset > 0 and text:sub(byte_offset + 1) or text
    local s, e = re:match_str(sub)
    if not s or e <= s then return nil end
    return byte_offset + s, byte_offset + e
  end

  local q_pat, plain
  if toggles.word then
    local escaped = query:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    q_pat = "%f[%w_]" .. (toggles.case and escaped or escaped:lower()) .. "%f[^%w_]"
    plain = false
  else
    q_pat = toggles.case and query or query:lower()
    plain = true
  end
  local search_text = toggles.case and text or text:lower()
  local s, e = search_text:find(q_pat, byte_offset + 1, plain)
  if not s then return nil end
  return s - 1, e
end

function M.matches(text, query)
  if not query or query == "" then return false end
  local tokens = vim.split(query, "%s+", { trimempty = true })
  if #tokens == 0 then return false end
  for _, tok in ipairs(tokens) do
    if not M.find_match(text, tok) then return false end
  end
  return true
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
  local tokens = vim.split(query, "%s+", { trimempty = true })
  if #tokens == 0 then return { { text, base_hl } } end
  local marks = {}
  for _, tok in ipairs(tokens) do
    local pos = 0
    while pos < #text do
      local s, e = M.find_match(text, tok, pos)
      if not s or e <= s then break end
      table.insert(marks, { s, e })
      pos = e
    end
  end
  table.sort(marks, function(a, b) return a[1] < b[1] end)
  local merged = {}
  for _, m in ipairs(marks) do
    if #merged > 0 and m[1] <= merged[#merged][2] then
      merged[#merged][2] = math.max(merged[#merged][2], m[2])
    else
      table.insert(merged, { m[1], m[2] })
    end
  end
  local result = {}
  local pos = 0
  for _, m in ipairs(merged) do
    if m[1] > pos then table.insert(result, { text:sub(pos + 1, m[1]), base_hl }) end
    table.insert(result, { text:sub(m[1] + 1, m[2]), "FinderHighlight" })
    pos = m[2]
  end
  if pos < #text then table.insert(result, { text:sub(pos + 1), base_hl }) end
  if #result == 0 then return { { text, base_hl } } end
  return result
end

function M.is_commits(items)
  return items and #items > 0 and items[1]:match('^[0-9a-f]+\t') ~= nil
end

function M.is_grep(items)
  return items and #items > 0 and items[1]:match('^[^:]+:%d+:') ~= nil
end

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
