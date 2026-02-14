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

function M.fuzzy_filter(items, query)
  local pattern = ".*" .. query:gsub(".", function(c)
    return c:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0") .. ".*"
  end)
  local matches = {}
  for _, item in ipairs(items) do
    if item:lower():match(pattern:lower()) then table.insert(matches, item) end
  end
  return matches
end

function M.highlight_matches(text, query, base_hl, fuzzy)
  if not query or query == "" then
    return { { text, base_hl } }
  end

  local result = {}
  local lower_text = text:lower()
  local lower_query = query:lower()

  if fuzzy then
    local pos = 1
    local qi = 1
    while pos <= #text and qi <= #lower_query do
      local char = lower_query:sub(qi, qi)
      local found = lower_text:find(char, pos, true)
      if found then
        if found > pos then
          table.insert(result, { text:sub(pos, found - 1), base_hl })
        end
        table.insert(result, { text:sub(found, found), "FinderMatch" })
        pos = found + 1
        qi = qi + 1
      else
        break
      end
    end
    if pos <= #text then
      table.insert(result, { text:sub(pos), base_hl })
    end
  else
    local pos = 1
    while pos <= #text do
      local start_pos, end_pos = lower_text:find(lower_query, pos, true)
      if start_pos then
        if start_pos > pos then
          table.insert(result, { text:sub(pos, start_pos - 1), base_hl })
        end
        table.insert(result, { text:sub(start_pos, end_pos), "FinderMatch" })
        pos = end_pos + 1
      else
        table.insert(result, { text:sub(pos), base_hl })
        break
      end
    end
  end

  if #result == 0 then
    return { { text, base_hl } }
  end
  return result
end

return M
