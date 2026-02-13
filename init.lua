local api = vim.api
local fn = vim.fn
local cmd = vim.cmd
local keymap = vim.keymap
local bo = vim.bo
local wo = vim.wo
local o = vim.o

local Mode = { PICKER = 1, PROMPT = 2 }

local DataType = {
  None = 0,
  FileList = 1,
  GrepList = 2,
  Commits = 3,
  File = 4,
}

local M = { filters = {}, prompts = {}, filter_inputs = {}, mode = Mode.PICKER, idx = 0, items = {}, sel = nil }
M.DataType = DataType

local defaults = {
  sep = " > ",
  list_height = 10,
  pickers = {
    Files = "finder.pickers.files",
    Grep = "finder.pickers.grep",
    Commits = "finder.pickers.commits",
    File = "finder.pickers.file",
  },
}

local function create_space()
  local orig_win = api.nvim_get_current_win()
  local win_height = api.nvim_win_get_height(orig_win)
  local width = api.nvim_win_get_width(orig_win)
  local ns = api.nvim_create_namespace("finder.space")
  local height = 4

  local buf = api.nvim_create_buf(false, true)
  bo[buf].bufhidden, bo[buf].buftype = "wipe", "nofile"
  api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn["repeat"]({""}, height))

  local win = api.nvim_open_win(buf, false, {
    relative = "win", win = orig_win,
    width = width, height = height,
    row = win_height - height, col = 0, style = "minimal", focusable = false, zindex = 10,
  })
  wo[win].winhighlight = "Normal:Normal,NormalFloat:Normal"

  return {
    height = function() return height end,
    win_height = function() return win_height end,
    orig = function() return orig_win end,
    resize = function(_, new_height)
      new_height = math.min(new_height, win_height)
      if new_height == height then return end
      height = new_height
      if buf and api.nvim_buf_is_valid(buf) then
        api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn["repeat"]({""}, height))
      end
      if win and api.nvim_win_is_valid(win) then
        api.nvim_win_set_config(win, {
          relative = "win", win = orig_win,
          width = width, height = height,
          row = win_height - height, col = 0,
        })
      end
    end,
    set_line = function(_, lnum, virt)
      if not (buf and api.nvim_buf_is_valid(buf) and win and api.nvim_win_is_valid(win)) then return end
      local target = math.max(0, math.min(lnum, height) - 1)
      for _, mark in ipairs(api.nvim_buf_get_extmarks(buf, ns, {target, 0}, {target, -1}, {})) do
        api.nvim_buf_del_extmark(buf, ns, mark[1])
      end
      api.nvim_buf_set_extmark(buf, ns, target, 0, { virt_text = virt, virt_text_pos = "overlay" })
    end,
    close = function()
      if win and api.nvim_win_is_valid(win) then api.nvim_win_close(win, true) end
    end,
  }
end

local function get_pickers()
  local all_pickers = vim.tbl_keys((M.opts or defaults).pickers)
  table.sort(all_pickers)

  local current_type = M.current_type or DataType.None
  local valid = {}
  for _, name in ipairs(all_pickers) do
    local picker_path = (M.opts or defaults).pickers[name]
    local ok, picker = pcall(require, picker_path)
    if ok and picker and not picker.hidden then
      local accepts = picker.accepts or { DataType.None }
      for _, t in ipairs(accepts) do
        if t == current_type then
          table.insert(valid, name)
          break
        end
      end
    end
  end
  return valid
end

local function get_widths(input)
  local widths = {}
  for i = 1, math.max(#M.filters, #M.prompts) do
    local plen = M.prompts[i] and #M.prompts[i] or 0
    if input and M.mode == Mode.PROMPT and i == M.idx then plen = #input end
    widths[i] = math.max(M.filters[i] and #M.filters[i] or 0, plen)
  end
  return widths
end

local function pad(str, w)
  return #str >= w and str or str .. string.rep(" ", w - #str)
end

local function update_bar(input)
  if not M.space then return end
  local opts, widths = M.opts or defaults, get_widths(input)
  local virt = { { "?? ", "FinderPrefix" } }

  for i, filter in ipairs(M.filters) do
    table.insert(virt, { pad(filter, widths[i] or #filter), "FinderInactive" })
    table.insert(virt, { opts.sep, "FinderInactive" })
  end
  if M.mode == Mode.PICKER then
    local pickers = M.picks or get_pickers()
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

  M.space:set_line(M.space.height(), virt)
end

local function evaluate()
  M.filter_error = nil

  if #M.filters == 0 then
    M.items = {}
    M.current_type = DataType.None
    return
  end

  local items = nil
  local current_type = DataType.None

  for i, filter_name in ipairs(M.filters) do
    local query = M.prompts[i] or ""
    local picker_path = (M.opts or defaults).pickers[filter_name]
    
    if not picker_path then
      M.filter_error = "Unknown picker: " .. filter_name
      M.items = {}
      return
    end

    if M.filter_inputs[i] then
      items = M.filter_inputs[i].items
      current_type = M.filter_inputs[i].type
    end

    local ok, picker = pcall(require, picker_path)
    if not ok or not picker or not picker.filter then
      M.filter_error, M.items = "Malformed Filter", {}; return
    end

    local accepts = picker.accepts or { DataType.None }
    local valid_input = false
    for _, t in ipairs(accepts) do
      if t == current_type then valid_input = true; break end
    end
    if not valid_input then
      M.filter_error = "Invalid input type for " .. filter_name
      M.items = {}
      return
    end

    local result, err = picker.filter(query, items)
    if err or result == nil then
      M.filter_error, M.items = "Malformed Filter", {}; return
    end

    items = result
    current_type = picker.produces or DataType.FileList
  end

  M.items = items or {}
  M.current_type = current_type
  M.sel = nil
end

local function highlight_matches(text, query, base_hl, fuzzy)
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

local function parse_item(item)
  local file, line_num, content = item:match("^([^:]+):(%d+):(.*)$")
  if not file then file = item end
  return file, tonumber(line_num), content
end

local function open_file_at_line(file, line_num)
  if fn.filereadable(file) == 1 then
    cmd("edit " .. fn.fnameescape(file))
    if line_num then
      cmd("normal! " .. line_num .. "G")
      cmd("normal! zz")
    end
  end
end

local function is_single_file_list(items)
  if #items == 0 then return false end
  local first_file = items[1]:match("^([^:]+)")
  for _, item in ipairs(items) do
    local f = item:match("^([^:]+)")
    if f ~= first_file then return false end
  end
  return true
end

local function render_list()
  if not M.space then return end
  local n = #M.items
  local win_width = api.nvim_win_get_width(M.space.orig())
  local max_height = M.space.win_height()

  local opts = M.opts or defaults
  local h = math.floor(opts.list_height)
  local max_visible = h % 2 == 0 and h + 1 or h
  local visible = math.min(n, max_visible)
  local active = M.sel or 1
  local half = math.floor(visible / 2)
  local top_idx = math.max(1, math.min(active - half, n - visible + 1))

  local preview_item = M.items[M.sel or 1]
  local max_preview = max_height - visible - 5
  local preview_info = nil
  if preview_item then
    local file, line_num = parse_item(preview_item)

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
        preview_info = { lines = lines, start_line = start_line, end_line = end_line, match_line = line_num }
      end
    end
  end
  local preview_lines = preview_info and (preview_info.end_line - preview_info.start_line + 1) or 0
  local has_top_sep = preview_lines > 0 and preview_lines < max_preview

  local needed_height = visible + preview_lines + 4 + (preview_lines > 0 and 1 or 0) + (has_top_sep and 1 or 0)
  M.space:resize(needed_height)
  local wh = M.space.height()

  for i = 1, wh - 1 do M.space:set_line(i, {}) end

  if M.filter_error then
    M.space:set_line(wh - 2, { { M.filter_error, "ErrorMsg" } })
    update_bar(M.mode == Mode.PROMPT and (M.prompts[M.idx] or "") or "")
    return
  end

  if n == 0 then
    update_bar(M.mode == Mode.PROMPT and (M.prompts[M.idx] or "") or "")
    return
  end

  local preview_bottom = wh - 5 - visible
  local query = M.prompts[#M.prompts] or ""
  
  if preview_info and preview_bottom > 0 and preview_lines > 0 then
    local lines_to_show = preview_info.end_line - preview_info.start_line + 1
    local display_start = preview_bottom - lines_to_show + 1

    local max_lnum_w = #tostring(preview_info.end_line)
    for i = preview_info.start_line, preview_info.end_line do
      local lnum_display = display_start + (i - preview_info.start_line)
      local line_content = preview_info.lines[i] or ""
      if #line_content > win_width - max_lnum_w - 2 then
        line_content = line_content:sub(1, win_width - max_lnum_w - 3) .. "…"
      end
      local is_match = preview_info.match_line and i == preview_info.match_line
      local lnum_str = string.format("%" .. max_lnum_w .. "d ", i)

      local virt = { { lnum_str, "LineNr" } }
      if is_match and query ~= "" then
        for _, v in ipairs(highlight_matches(line_content, query, "Normal", false)) do
          table.insert(virt, v)
        end
      else
        table.insert(virt, { line_content, "Normal" })
      end
      M.space:set_line(lnum_display, virt)
    end
    M.space:set_line(wh - 4 - visible, { { string.rep("─", win_width), "FinderInactive" } })
    if has_top_sep then
      M.space:set_line(1, { { string.rep("─", win_width), "FinderInactive" } })
    end
  end

  local max_w = #tostring(n)

  for i = 0, visible - 1 do
    local idx = top_idx + i
    local lnum = wh - 4 - i
    local is_sel = M.sel and idx == M.sel
    local num = string.format("%" .. max_w .. "d ", idx)
    local hl = is_sel and "Visual" or "Normal"

    local item = M.items[idx]
    local file, line_num, content = parse_item(item)

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

      local content_virt = highlight_matches(display_content, query, hl, false)

      local virt = { { num, is_sel and "Visual" or "LineNr" } }
      for _, v in ipairs(content_virt) do table.insert(virt, v) end
      table.insert(virt, { padding, hl })
      table.insert(virt, { file_display, is_sel and "Visual" or "FinderInactive" })
      M.space:set_line(lnum, virt)
    else
      local item_virt = highlight_matches(item, query, hl, true)
      local virt = { { num, is_sel and "Visual" or "LineNr" } }
      for _, v in ipairs(item_virt) do table.insert(virt, v) end
      M.space:set_line(lnum, virt)
    end
  end

  M.space:set_line(wh - 2, { { string.format("%d/%d", active, n), "FinderPrefix" } })
  update_bar(M.mode == Mode.PROMPT and (M.prompts[M.idx] or "") or "")
end

local function create_input()
  local opts = M.opts or defaults
  local NS = api.nvim_create_namespace("finder_input")
  local st = { buf = nil, win = nil }

  local function get()
    if not st.buf or not api.nvim_buf_is_valid(st.buf) then return "" end
    return api.nvim_buf_get_lines(st.buf, 0, 1, false)[1] or ""
  end

  local function clear()
    if st.buf and api.nvim_buf_is_valid(st.buf) then
      api.nvim_buf_set_lines(st.buf, 0, -1, false, { "" })
    end
  end

  local function set(text, at_end)
    if st.buf and api.nvim_buf_is_valid(st.buf) then
      api.nvim_buf_set_lines(st.buf, 0, -1, false, { text })
      api.nvim_win_set_cursor(0, {1, at_end and #text or 0})
    end
  end

  local function update_virt()
    if not st.buf or not api.nvim_buf_is_valid(st.buf) then return end
    local input = get()
    api.nvim_buf_clear_namespace(st.buf, NS, 0, -1)
    local widths = get_widths(input)

    local pre = ""
    if #M.prompts > 0 then
      local parts = {}
      local count = M.mode == Mode.PICKER and #M.prompts or M.idx - 1
      for i = 1, count do table.insert(parts, pad(M.prompts[i], widths[i] or #M.prompts[i])) end
      if #parts > 0 then pre = table.concat(parts, opts.sep) .. opts.sep end
    end
    local pre_virt = { { "   ", "Normal" } }
    if pre ~= "" then table.insert(pre_virt, { pre, "FinderInactive" }) end
    api.nvim_buf_set_extmark(st.buf, NS, 0, 0, {
      virt_text = pre_virt, virt_text_pos = "inline", right_gravity = false,
    })

    if M.mode == Mode.PROMPT and M.idx < #M.prompts then
      local parts = {}
      for i = M.idx + 1, #M.prompts do
        table.insert(parts, pad(M.prompts[i], widths[i] or #M.prompts[i]))
      end
      if #parts > 0 then
        local line = api.nvim_buf_get_lines(st.buf, 0, 1, false)[1] or ""
        api.nvim_buf_set_extmark(st.buf, NS, 0, #line, {
          virt_text = { { opts.sep .. table.concat(parts, opts.sep), "FinderInactive" } },
          virt_text_pos = "inline", right_gravity = true,
        })
      end
    end
  end

  local function parse(input)
    if M.mode == Mode.PICKER then
      local all = get_pickers()
      M.picks = input == "" and all or vim.tbl_filter(function(n)
        return n:lower():sub(1, #input) == input:lower()
      end, all)
      update_bar(input)
      if #M.picks == 1 then
        M.idx = M.idx + 1
        table.insert(M.filters, M.picks[1])
        table.insert(M.prompts, "")
        M.mode, M.picks = Mode.PROMPT, {}
        evaluate(); render_list(); update_bar(""); update_virt(); clear()
      end
    else
      M.prompts[M.idx] = input
      evaluate(); render_list(); update_bar(input); update_virt()
    end
  end

  local function nav_back(del)
    if fn.col(".") > 1 then return false end

    if M.mode == Mode.PICKER then
      if #M.filters > 0 then
        M.mode, M.idx = Mode.PROMPT, #M.filters
        local txt = M.prompts[M.idx] or ""
        set(txt, true); update_bar(txt); update_virt()
      end
      return true
    end

    local cur = get()
    if del and cur == "" and M.idx > 0 then
      table.remove(M.filters, M.idx)
      table.remove(M.prompts, M.idx)
      table.remove(M.filter_inputs, M.idx)
      M.idx = M.idx - 1
      if M.idx == 0 then
        M.current_type = DataType.None
        M.mode, M.picks = Mode.PICKER, get_pickers()
        clear(); update_bar("")
      else
        local txt = M.prompts[M.idx] or ""
        set(txt, true); update_bar(txt)
      end
      evaluate(); render_list(); update_virt()
      return true
    end

    if M.idx > 1 then
      M.prompts[M.idx] = cur
      M.idx = M.idx - 1
      local txt = M.prompts[M.idx] or ""
      set(txt, true); evaluate(); render_list(); update_bar(txt); update_virt()
    end
    return true
  end

  local function nav_fwd()
    local line = get()
    if fn.col(".") <= #line then return false end
    if M.mode == Mode.PROMPT and M.idx < #M.filters then
      M.prompts[M.idx], M.idx = line, M.idx + 1
      local txt = M.prompts[M.idx] or ""
      set(txt, false); update_bar(txt); update_virt()
    end
    return true
  end

  local function sel_up()
    M.sel = M.sel and (M.sel < #M.items and M.sel + 1 or M.sel) or 1
    render_list()
  end

  local function sel_down()
    if M.sel == 1 then M.sel = nil
    elseif M.sel then M.sel = M.sel - 1 end
    render_list()
  end

  api.nvim_set_hl(0, "FinderPrefix", { fg = "#80a0ff", bold = true, default = true })
  api.nvim_set_hl(0, "FinderInactive", { link = "Comment", default = true })
  api.nvim_set_hl(0, "FinderMatch", { link = "Search", default = true })

  st.buf = api.nvim_create_buf(false, true)
  bo[st.buf].bufhidden, bo[st.buf].buftype = "wipe", "nofile"
  local init = (M.mode == Mode.PROMPT and M.idx > 0) and (M.prompts[M.idx] or "") or ""
  api.nvim_buf_set_lines(st.buf, 0, -1, false, { init })
  update_virt()

  st.win = api.nvim_open_win(st.buf, true, {
    relative = "win", win = M.space.orig(),
    width = api.nvim_win_get_width(M.space.orig()), height = 1,
    row = M.space.win_height(), col = 0, style = "minimal", focusable = true,
  })
  wo[st.win].winhighlight = "Normal:Normal,NormalFloat:Normal"

  keymap.set("i", "<Tab>", function()
    if M.mode == Mode.PROMPT then
      M.mode, M.picks = Mode.PICKER, get_pickers()
      update_bar(""); update_virt(); clear()
    else
      api.nvim_feedkeys(opts.sep, "n", false)
    end
  end, { buffer = st.buf })

  keymap.set("i", "<Esc>", function()
    if M.sel then M.sel = nil; render_list() else M.close() end
  end, { buffer = st.buf })
  keymap.set("i", "<CR>", function()
    local target_idx = M.sel or (#M.items == 1 and 1 or nil)
    if target_idx and M.items[target_idx] then
      local item = M.items[target_idx]
      local file, line_num = parse_item(item)
      
      if M.current_type == DataType.GrepList then
        M.close()
        open_file_at_line(file, line_num)
      else
        if is_single_file_list(M.items) then
          M.close()
          open_file_at_line(file, line_num)
        else
          local file_spec = line_num and string.format("%s:%s", file, line_num) or file
          
          M.idx = M.idx + 1
          
          M.filter_inputs[M.idx] = { items = { file_spec }, type = DataType.File }
          
          local display_name = fn.fnamemodify(file, ":t")
          table.insert(M.filters, "File")
          table.insert(M.prompts, display_name)
          
          evaluate()
          
          M.mode = Mode.PICKER
          M.picks = get_pickers()
          M.sel = nil
          render_list()
          update_bar("")
          update_virt()
          clear()
        end
      end
    else
      M.close()
    end
  end, { buffer = st.buf })

  for key, del in pairs({ ["<BS>"] = true, ["<Left>"] = false }) do
    keymap.set("i", key, function()
      if not nav_back(del) then
        api.nvim_feedkeys(api.nvim_replace_termcodes(key, true, false, true), "n", false)
      end
    end, { buffer = st.buf })
  end

  keymap.set("i", "<Right>", function()
    if not nav_fwd() then
      api.nvim_feedkeys(api.nvim_replace_termcodes("<Right>", true, false, true), "n", false)
    end
  end, { buffer = st.buf })

  for _, k in ipairs({ "<C-j>", "<Down>" }) do keymap.set("i", k, sel_down, { buffer = st.buf }) end
  for _, k in ipairs({ "<C-k>", "<Up>" }) do keymap.set("i", k, sel_up, { buffer = st.buf }) end

  api.nvim_create_autocmd("TextChangedI", {
    buffer = st.buf,
    callback = function() parse(get()) end
  })

  local aug = api.nvim_create_augroup("FinderResize", { clear = true })
  api.nvim_create_autocmd("VimResized", {
    group = aug,
    callback = function()
      if M.space then
        M.space.close()
        M.space = create_space()
        render_list()
        if st.win and api.nvim_win_is_valid(st.win) then
          api.nvim_win_set_config(st.win, {
            relative = "win", win = M.space.orig(),
            width = api.nvim_win_get_width(M.space.orig()), height = 1,
            row = M.space.win_height(), col = 0,
          })
        end
      end
    end
  })

  cmd("startinsert!")

  return {
    close = function()
      api.nvim_del_augroup_by_name("FinderResize")
      if st.win and api.nvim_win_is_valid(st.win) then api.nvim_win_close(st.win, true) end
      st.win, st.buf = nil, nil
      cmd("stopinsert")
    end,
  }
end

function M.enter()
  if #M.filters > 0 then
    M.mode, M.idx = Mode.PROMPT, #M.filters
    evaluate()  -- Set current_type based on existing filters
  else
    M.mode, M.idx = Mode.PICKER, 0
    M.items = {}
    M.current_type = DataType.None
  end
  M.cmdh = o.cmdheight
  o.cmdheight = 0
  M.space = create_space()
  M.picks = get_pickers()
  M.sel = nil
  render_list()
  update_bar(M.mode == Mode.PROMPT and (M.prompts[M.idx] or "") or "")
  M.input = create_input()
end

function M.close()
  if M.input then M.input.close() end
  if M.space then M.space.close() end
  o.cmdheight = M.cmdh or 1
  M.input, M.space = nil, nil
end

function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", defaults, opts or {})
  api.nvim_create_user_command("Finder", M.enter, {})
end

return M
