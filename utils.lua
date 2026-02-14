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

function M.open_file_at_line(file, line_num)
  if fn.filereadable(file) == 1 then
    cmd("edit " .. fn.fnameescape(file))
    if line_num then
      cmd("normal! " .. line_num .. "G")
      cmd("normal! zz")
    end
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

return M
