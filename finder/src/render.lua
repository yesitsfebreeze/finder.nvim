local api = vim.api
local fn = vim.fn
local bo = vim.bo
local wo = vim.wo

local state = require("finder.src.state")
local Mode = state.Mode
local evaluate_mod = require("finder.src.evaluate")
local utils = require("finder.src.utils")

local M = {}
local preview_state = { buf = nil, win = nil, file = nil, start_line = nil, end_line = nil }

function M.close_preview()
  if preview_state.win and api.nvim_win_is_valid(preview_state.win) then
    api.nvim_win_close(preview_state.win, true)
  end
  preview_state.win, preview_state.buf = nil, nil
  preview_state.file, preview_state.start_line, preview_state.end_line, preview_state.match_line = nil, nil, nil, nil
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
  local virt = {}

  for i, filter in ipairs(state.filters) do
    table.insert(virt, { utils.pad(filter, widths[i] or #filter), "FinderInactive" })
    if i < #state.filters or state.mode == Mode.PICKER then
      table.insert(virt, { opts.sep, "FinderInactive" })
    end
  end

  local n = #state.items
  local active = state.sel or (n > 0 and 1 or 0)
  local multi_count = vim.tbl_count(state.multi_sel)
  if n > 0 or multi_count > 0 then
    local count_str = multi_count > 0
      and string.format(" %d/%d [%d] ", active, n, multi_count)
      or string.format(" %d/%d ", active, n)
    table.insert(virt, { count_str, "FinderCount" })
  end

  if state.mode == Mode.INTERACT then
    table.insert(virt, { "INTERACT", "FinderHighlight" })
    table.insert(virt, { "  <CR>=rename  <C-d>=delete  <Esc>=cancel", "FinderInactive" })
  elseif state.mode == Mode.PICKER then
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
      table.insert(virt, { name:sub(1, len), "FinderColor" })
      table.insert(virt, { name:sub(len + 1), "FinderText" })
      if i < #pickers then table.insert(virt, { "  ", "FinderText" }) end
    end
  end

  state.space:set_line(state.space.height(), virt)
end

function M.render_list()
  if not state.space then return end
  local n = #state.items
  local opts = state.opts or state.defaults

  local layout = {
    win_width = api.nvim_win_get_width(state.space.orig()),
    max_height = state.space.win_height(),
    centered_height = (function()
      local h = math.floor(opts.list_height)
      return h % 2 == 0 and h + 1 or h
    end)(),
    file_width_ratio = opts.file_width_ratio or 0.4,
    bar_lines = 1,
    section_sep = opts.section_sep or {},
  }
  layout.sep_size = #layout.section_sep

  local visible = math.min(n, layout.centered_height)
  local active = state.sel or (n > 0 and 1 or 0)
  local half = math.floor(visible / 2)
  local top_idx = math.max(1, math.min(active - half, n - visible + 1))

  local preview_item = state.items[state.sel or 1]
  -- reserve space: bar + bottom_sep + items + mid_sep (for when preview exists)
  local max_preview = layout.max_height - layout.bar_lines - layout.sep_size - visible - layout.sep_size
  local preview_info = nil
  if max_preview > 0 and preview_item then
    local file, line_num = utils.parse_item(preview_item)

    if fn.filereadable(file) == 1 and fn.isdirectory(file) ~= 1 then
      local fsize = fn.getfsize(file)
      if fsize > 0 and fsize < 1048576 then
        local lines = fn.readfile(file, "", 5000)
        if #lines > 0 then
          local preview_lines = math.min(#lines, max_preview)
          local scroll = state.preview_scroll or 0
          local start_line, end_line
          if line_num and line_num > 0 then
            local half_preview = math.floor(preview_lines / 2)
            start_line = math.max(1, line_num - half_preview + scroll)
            end_line = start_line + preview_lines - 1
            if end_line > #lines then
              end_line = #lines
              start_line = math.max(1, end_line - preview_lines + 1)
            end
          else
            start_line = math.max(1, 1 + scroll)
            end_line = math.min(#lines, start_line + preview_lines - 1)
          end
          state.preview_scroll = start_line - (line_num and line_num > 0 and math.max(1, line_num - math.floor(preview_lines / 2)) or 1)
          preview_info = { file = file, lines = lines, start_line = start_line, end_line = end_line, match_line = line_num, total_lines = #lines }
        end
      end
    end
  end
  local preview_line_count = preview_info and (preview_info.end_line - preview_info.start_line + 1) or 0
  local mid_sep = preview_line_count > 0 and layout.sep_size or 0
  local content = layout.bar_lines + layout.sep_size + visible + mid_sep + preview_line_count
  local top_sep = (content + layout.sep_size <= layout.max_height) and layout.sep_size or 0
  local needed_height = content + top_sep
  state.space:resize(needed_height)
  local wh = state.space.height()

  if not preview_info then M.close_preview() end
  for i = 1, wh - 1 do state.space:set_line(i, {}) end

  if state.filter_error then
    state.space:set_line(wh - layout.bar_lines - layout.sep_size, { { state.filter_error, "FinderError" } })
    M.update_bar(state.mode == Mode.PROMPT and (state.prompts[state.idx] or "") or "")
    return
  end

  if n == 0 then
    if state.loading then
      local dots = string.rep(".", (state.loading_frame % 3) + 1)
      state.space:set_line(wh - layout.bar_lines - layout.sep_size, { { " " .. dots, "FinderInactive" } })
    end
    M.update_bar(state.mode == Mode.PROMPT and (state.prompts[state.idx] or "") or "")
    return
  end

  -- zone positions (line numbers, bottom of each zone)
  local items_bottom = wh - layout.bar_lines - layout.sep_size
  local mid_sep_bottom = items_bottom - visible
  local preview_bottom = mid_sep_bottom - mid_sep
  local top_sep_bottom = preview_bottom - preview_line_count
  local query = state.prompts[#state.prompts] or ""

  local render_section_sep_at = function(bottom_line, hl)
    hl = hl or "FinderSeparator"
    for i, s in ipairs(layout.section_sep) do
      local lnum = bottom_line - layout.sep_size + i
      if lnum >= 1 and lnum < wh then
        if s ~= "" and vim.fn.strcharlen(s) == 1 then
          state.space:set_line(lnum, { { string.rep(s, layout.win_width), hl } })
        else
          state.space:set_line(lnum, { { s, hl } })
        end
      end
    end
  end

  local render_seps = function()
    if layout.sep_size == 0 then return end
    render_section_sep_at(wh - layout.bar_lines)
    if mid_sep > 0 then render_section_sep_at(mid_sep_bottom) end
    if top_sep > 0 then render_section_sep_at(top_sep_bottom) end
  end

  local render_preview = function()
    if not (preview_info and preview_bottom > 0 and preview_line_count > 0) then return end
    local lines_to_show = preview_info.end_line - preview_info.start_line + 1
    local display_start = preview_bottom - lines_to_show + 1
    local preview_row = layout.max_height - wh + display_start - 1

    local same_file = preview_state.file == preview_info.file
    local same_range = same_file and preview_state.start_line == preview_info.start_line and preview_state.end_line == preview_info.end_line
    local same_match = same_range and preview_state.match_line == preview_info.match_line
    local can_reuse_win = same_file and preview_state.buf and api.nvim_buf_is_valid(preview_state.buf)
      and preview_state.win and api.nvim_win_is_valid(preview_state.win)

    local function apply_match_highlights(pbuf, content)
      local ns = api.nvim_create_namespace("finder_preview")
      api.nvim_buf_clear_namespace(pbuf, ns, 0, -1)
      if not preview_info.match_line then return end
      local match_row = preview_info.match_line - preview_info.start_line
      api.nvim_buf_set_extmark(pbuf, ns, match_row, 0, { line_hl_group = "CursorLine" })
      local match_content = content[match_row + 1]
      if not match_content or not query or query == "" then return end
      local s, e = utils.find_match(match_content, query)
      if s and e and e > s then
        api.nvim_buf_set_extmark(pbuf, ns, match_row, s, { end_col = e, hl_group = "FinderHighlight" })
      end
    end

    if can_reuse_win and same_range then
      api.nvim_win_set_config(preview_state.win, {
        relative = "win", win = state.space.orig(),
        width = layout.win_width, height = lines_to_show,
        row = preview_row, col = 0,
      })
      if not same_match then
        local content = api.nvim_buf_get_lines(preview_state.buf, 0, -1, false)
        apply_match_highlights(preview_state.buf, content)
        preview_state.match_line = preview_info.match_line
      end
    else
      M.close_preview()

      local pbuf = api.nvim_create_buf(false, true)
      bo[pbuf].bufhidden = "wipe"
      local content = {}
      for i = preview_info.start_line, preview_info.end_line do
        local line = (preview_info.lines[i] or ""):gsub("\n", "")
        table.insert(content, line)
      end
      api.nvim_buf_set_lines(pbuf, 0, -1, false, content)

      local ft = vim.filetype.match({ filename = preview_info.file, buf = pbuf })
      if ft then
        bo[pbuf].filetype = ft
        pcall(vim.treesitter.start, pbuf)
      end

      local pwin = api.nvim_open_win(pbuf, false, {
        relative = "win", win = state.space.orig(),
        width = layout.win_width, height = lines_to_show,
        row = preview_row, col = 0,
        style = "minimal", focusable = false, zindex = 20,
      })
      wo[pwin].winhighlight = "Normal:FinderPreviewBG,NormalFloat:FinderPreviewBG"
      wo[pwin].number = true
      wo[pwin].signcolumn = "no"
      wo[pwin].statuscolumn = "%=%{v:lnum+" .. (preview_info.start_line - 1) .. "} "

      apply_match_highlights(pbuf, content)

      preview_state.buf, preview_state.win = pbuf, pwin
      preview_state.file = preview_info.file
      preview_state.start_line = preview_info.start_line
      preview_state.end_line = preview_info.end_line
      preview_state.match_line = preview_info.match_line
    end

    if state.mode == Mode.PROMPT and state.idx > 0 and preview_state.buf and api.nvim_buf_is_valid(preview_state.buf) then
      local pname = state.filters[state.idx]
      local ppath = pname and opts.pickers[pname]
      if ppath then
        local pok, p = pcall(require, ppath)
        if pok and p and p.decorate_preview then
          p.decorate_preview(preview_state.buf, preview_info.file, preview_info.start_line, preview_info.end_line)
        end
      end
    end

  end

  local render_items = function()
    local max_w = #tostring(n)

    local picker_display
    if state.mode == Mode.PROMPT and state.idx > 0 then
      local pname = state.filters[state.idx]
      local ppath = pname and opts.pickers[pname]
      if ppath then
        local pok, p = pcall(require, ppath)
        if pok and p then picker_display = p.display end
      end
    end

    for i = 0, visible - 1 do
      local idx = top_idx + i
      local lnum = items_bottom - i
      local is_sel = state.sel and idx == state.sel
      local is_multi = state.multi_sel[idx]
      local marker = is_multi and "+" or " "
      local num = string.format("%s%" .. max_w .. "d ", marker, idx)
      local num_hl = is_sel and "FinderHighlight" or is_multi and "FinderColor" or "FinderInactive"

      local item = state.items[idx]

      if picker_display then
        local virt = { { num, num_hl } }
        local display_virt = picker_display(item, {
          width = layout.win_width - #num,
          is_sel = is_sel,
          query = query,
        })
        for _, v in ipairs(display_virt) do table.insert(virt, v) end
        state.space:set_line(lnum, virt)
      else
        local hl = is_sel and "FinderHighlight" or "FinderText"
        local file, line_num, content = utils.parse_item(item)

        if file and content then
          local prefix_len = #num
          local available = layout.win_width - prefix_len - 2
          local filename = fn.fnamemodify(file, ":t")
          local display_file
          if is_sel then
            display_file = file
          else
            local max_file_width = math.floor(available * layout.file_width_ratio)
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

          local content_virt = utils.highlight_matches(display_content, query, hl)

          local virt = { { num, num_hl } }
          for _, v in ipairs(content_virt) do table.insert(virt, v) end
          table.insert(virt, { padding, hl })
          table.insert(virt, { file_display, is_sel and "FinderHighlight" or "FinderInactive" })
          state.space:set_line(lnum, virt)
        else
          local item_virt = utils.highlight_matches(item, query, hl)
          local virt = { { num, num_hl } }
          for _, v in ipairs(item_virt) do table.insert(virt, v) end
          state.space:set_line(lnum, virt)
        end
      end
    end
  end

  local render_status = function()
    M.update_bar(state.mode == Mode.PROMPT and (state.prompts[state.idx] or "") or "")
  end

  render_preview()
  render_seps()
  render_items()
  render_status()
end

return M
