local api = vim.api
local fn = vim.fn
local bo = vim.bo
local wo = vim.wo

local state = require("finder.state")
local Mode = state.Mode
local evaluate_mod = require("finder.evaluate")
local utils = require("finder.utils")

local M = {}
local preview_state = { buf = nil, win = nil }

function M.close_preview()
  if preview_state.win and api.nvim_win_is_valid(preview_state.win) then
    api.nvim_win_close(preview_state.win, true)
  end
  preview_state.win, preview_state.buf = nil, nil
end

function M.get_widths(input)
  local widths = {}
  for i = 1, math.max(#state.filters, #state.prompts) do
    local plen = state.prompts[i] and #state.prompts[i] or 0
    if input and state.mode == Mode.PROMPT and i == state.idx then plen = #input end
    widths[i] = math.max(state.filters[i] and #state.filters[i] or 0, plen)
  end
  return widths
end

function M.update_bar(input)
  if not state.space then return end
  local opts = state.opts or state.defaults
  local widths = M.get_widths(input)
  local virt = { { "?? ", "FinderPrefix" } }

  for i, filter in ipairs(state.filters) do
    table.insert(virt, { utils.pad(filter, widths[i] or #filter), "FinderInactive" })
    table.insert(virt, { opts.sep, "FinderInactive" })
  end
  if state.mode == Mode.PICKER then
    local pickers = state.picks or evaluate_mod.get_pickers()
    local prefixes = {}
    for i, name in ipairs(pickers) do
      local len = 1
      while len <= #name do
        local pre = name:sub(1, len)
        local unique = true
        for j, other in ipairs(pickers) do
          if i ~= j and other:sub(1, len) == pre then unique = false; break end
        end
        if unique then break end
        len = len + 1
      end
      prefixes[name] = len
    end
    for i, name in ipairs(pickers) do
      local len = prefixes[name]
      table.insert(virt, { name:sub(1, len), "FinderPrefix" })
      table.insert(virt, { name:sub(len + 1), "Normal" })
      if i < #pickers then table.insert(virt, { "  ", "Normal" }) end
    end
  end

  state.space:set_line(state.space.height(), virt)
end

function M.render_list()
  if not state.space then return end
  local n = #state.items
  local win_width = api.nvim_win_get_width(state.space.orig())
  local max_height = state.space.win_height()

  local opts = state.opts or state.defaults
  local h = math.floor(opts.list_height)
  local max_visible = h % 2 == 0 and h + 1 or h
  local visible = math.min(n, max_visible)
  local active = state.sel or (n > 0 and 1 or 0)
  local half = math.floor(visible / 2)
  local top_idx = math.max(1, math.min(active - half, n - visible + 1))

  local preview_item = state.items[state.sel or 1]
  local max_preview = max_height - visible - 5
  local preview_info = nil
  if preview_item then
    local file, line_num = utils.parse_item(preview_item)

    if fn.filereadable(file) == 1 and fn.isdirectory(file) ~= 1 then
      local lines = fn.readfile(file)
      if #lines > 0 then
        local preview_lines = math.min(#lines, max_preview)
        local start_line, end_line
        if line_num and line_num > 0 then
          local half_preview = math.floor(preview_lines / 2)
          start_line = math.max(1, line_num - half_preview)
          end_line = start_line + preview_lines - 1
          if end_line > #lines then
            end_line = #lines
            start_line = math.max(1, end_line - preview_lines + 1)
          end
        else
          start_line, end_line = 1, preview_lines
        end
        preview_info = { file = file, lines = lines, start_line = start_line, end_line = end_line, match_line = line_num }
      end
    end
  end
  local preview_lines = preview_info and (preview_info.end_line - preview_info.start_line + 1) or 0
  local has_top_sep = preview_lines > 0 and preview_lines < max_preview

  local needed_height = visible + preview_lines + 4 + (preview_lines > 0 and 1 or 0) + (has_top_sep and 1 or 0)
  state.space:resize(needed_height)
  local wh = state.space.height()

  M.close_preview()
  for i = 1, wh - 1 do state.space:set_line(i, {}) end

  if state.filter_error then
    state.space:set_line(wh - 2, { { state.filter_error, "ErrorMsg" } })
    M.update_bar(state.mode == Mode.PROMPT and (state.prompts[state.idx] or "") or "")
    return
  end

  if n == 0 then
    state.space:set_line(wh - 2, { { string.format("%d/%d", active, n), "FinderPrefix" } })
    M.update_bar(state.mode == Mode.PROMPT and (state.prompts[state.idx] or "") or "")
    return
  end

  local preview_bottom = wh - 5 - visible
  local query = state.prompts[#state.prompts] or ""
  
  if preview_info and preview_bottom > 0 and preview_lines > 0 then
    local lines_to_show = preview_info.end_line - preview_info.start_line + 1
    local display_start = preview_bottom - lines_to_show + 1

    local pbuf = api.nvim_create_buf(false, true)
    bo[pbuf].bufhidden = "wipe"
    local content = {}
    for i = preview_info.start_line, preview_info.end_line do
      table.insert(content, preview_info.lines[i] or "")
    end
    api.nvim_buf_set_lines(pbuf, 0, -1, false, content)

    local ft = vim.filetype.match({ filename = preview_info.file, buf = pbuf })
    if ft then
      bo[pbuf].filetype = ft
      pcall(vim.treesitter.start, pbuf)
    end

    local preview_row = state.space.win_height() - wh + display_start - 1
    local pwin = api.nvim_open_win(pbuf, false, {
      relative = "win", win = state.space.orig(),
      width = win_width, height = lines_to_show,
      row = preview_row, col = 0,
      style = "minimal", focusable = false, zindex = 20,
    })
    wo[pwin].winhighlight = "Normal:Normal,NormalFloat:Normal"
    wo[pwin].number = true
    wo[pwin].signcolumn = "no"
    wo[pwin].statuscolumn = "%=%{v:lnum+" .. (preview_info.start_line - 1) .. "} "

    if preview_info.match_line then
      local ns = api.nvim_create_namespace("finder_preview")
      api.nvim_buf_set_extmark(pbuf, ns, preview_info.match_line - preview_info.start_line, 0, {
        line_hl_group = "CursorLine",
      })
    end

    preview_state.buf, preview_state.win = pbuf, pwin
    state.space:set_line(wh - 4 - visible, { { string.rep("─", win_width), "FinderInactive" } })
    if has_top_sep then
      state.space:set_line(1, { { string.rep("─", win_width), "FinderInactive" } })
    end
  end

  local max_w = #tostring(n)

  for i = 0, visible - 1 do
    local idx = top_idx + i
    local lnum = wh - 4 - i
    local is_sel = state.sel and idx == state.sel
    local num = string.format(" %" .. max_w .. "d ", idx)
    local hl = is_sel and "Visual" or "Normal"

    local item = state.items[idx]
    local file, line_num, content = utils.parse_item(item)

    if file and content then
      local prefix_len = #num
      local available = win_width - prefix_len - 2
      local filename = fn.fnamemodify(file, ":t")
      local display_file
      if is_sel then
        display_file = file
      else
        local max_file_width = math.floor(available * 0.4)
        if #filename > max_file_width then
          display_file = filename
        elseif #file <= max_file_width then
          display_file = file
        else
          local remaining = max_file_width - #filename - 1
          if remaining > 3 then
            display_file = file:sub(1, remaining - 2) .. "…/" .. filename
          else
            display_file = filename
          end
        end
      end
      local file_display = " " .. display_file
      local content_width = available - #file_display
      local display_content = content
      if #content > content_width then
        display_content = content:sub(1, content_width - 1) .. "…"
      end
      local padding = string.rep(" ", math.max(0, available - #display_content - #file_display))

      local content_virt = utils.highlight_matches(display_content, query, hl, false)

      local virt = { { num, is_sel and "Visual" or "LineNr" } }
      for _, v in ipairs(content_virt) do table.insert(virt, v) end
      table.insert(virt, { padding, hl })
      table.insert(virt, { file_display, is_sel and "Visual" or "FinderInactive" })
      state.space:set_line(lnum, virt)
    else
      local item_virt = utils.highlight_matches(item, query, hl, true)
      local virt = { { num, is_sel and "Visual" or "LineNr" } }
      for _, v in ipairs(item_virt) do table.insert(virt, v) end
      state.space:set_line(lnum, virt)
    end
  end

  local count_prefix = string.rep(" ", max_w + 1)
  state.space:set_line(wh - 2, { { count_prefix .. string.format("%d/%d", active, n), "FinderPrefix" } })
  M.update_bar(state.mode == Mode.PROMPT and (state.prompts[state.idx] or "") or "")
end

return M
