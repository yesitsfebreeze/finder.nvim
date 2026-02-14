local api = vim.api
local fn = vim.fn
local cmd = vim.cmd
local keymap = vim.keymap
local bo = vim.bo
local wo = vim.wo

local state = require("finder.state")
local Mode = state.Mode
local DataType = state.DataType
local create_space = require("finder.space")
local evaluate_mod = require("finder.evaluate")
local render = require("finder.render")
local utils = require("finder.utils")

local function create_input()
  local opts = state.opts or state.defaults
  local keys = opts.keys
  local NS = api.nvim_create_namespace("finder_input")
  local st = { buf = nil, win = nil }

  local function bind(k, fn_ref)
    local bindings = type(k) == "table" and k or { k }
    for _, b in ipairs(bindings) do keymap.set("i", b, fn_ref, { buffer = st.buf }) end
  end

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
    local widths = render.get_widths(input)

    local pre = ""
    if #state.prompts > 0 then
      local parts = {}
      local count = state.mode == Mode.PICKER and #state.prompts or state.idx - 1
      for i = 1, count do table.insert(parts, utils.pad(state.prompts[i], widths[i] or #state.prompts[i])) end
      if #parts > 0 then pre = table.concat(parts, opts.sep) .. opts.sep end
    end
    local pre_virt = { { "   ", "Normal" } }
    if pre ~= "" then table.insert(pre_virt, { pre, "FinderInactive" }) end
    api.nvim_buf_set_extmark(st.buf, NS, 0, 0, {
      virt_text = pre_virt, virt_text_pos = "inline", right_gravity = false,
    })

    if state.mode == Mode.PROMPT and state.idx < #state.prompts then
      local parts = {}
      for i = state.idx + 1, #state.prompts do
        table.insert(parts, utils.pad(state.prompts[i], widths[i] or #state.prompts[i]))
      end
      if #parts > 0 then
        local line = api.nvim_buf_get_lines(st.buf, 0, 1, false)[1] or ""
        api.nvim_buf_set_extmark(st.buf, NS, 0, #line, {
          virt_text = { { opts.sep .. table.concat(parts, opts.sep), "FinderInactive" } },
          virt_text_pos = "inline", right_gravity = true,
        })
      end
    end

    if state.mode == Mode.PROMPT and state.idx > 0 then
      local cur_filter = state.filters[state.idx]
      local picker_path = opts.pickers[cur_filter]
      if picker_path then
        local pok, picker = pcall(require, picker_path)
        if pok and picker and picker.min_query then
          local remaining = math.max(0, picker.min_query - #input)
          if remaining > 0 then
            local line = api.nvim_buf_get_lines(st.buf, 0, 1, false)[1] or ""
            api.nvim_buf_set_extmark(st.buf, NS, 0, #line, {
              virt_text = { { string.rep("?", remaining), "FinderInactive" } },
              virt_text_pos = "inline", right_gravity = true,
            })
          end
        end
      end
    end

    local toggle_labels = { { "case", "Aa" }, { "word", "ab" }, { "regex", ".*" } }
    if state.in_git then table.insert(toggle_labels, { "gitfiles", ".g" }) end
    local tvirt = {}
    for i, t in ipairs(toggle_labels) do
      if i > 1 then table.insert(tvirt, { " ", "Normal" }) end
      table.insert(tvirt, { t[2], state.toggles[t[1]] and "FinderHighlight" or "FinderText" })
    end
    api.nvim_buf_set_extmark(st.buf, NS, 0, 0, {
      virt_text = tvirt, virt_text_pos = "right_align",
    })
  end

  local active_action_keys = {}
  local function register_picker_actions()
    for _, key in ipairs(active_action_keys) do
      pcall(keymap.del, "i", key, { buffer = st.buf })
    end
    active_action_keys = {}

    if state.mode ~= Mode.PROMPT or state.idx < 1 then return end
    local cur_filter = state.filters[state.idx]
    if not cur_filter then return end
    local picker_path = opts.pickers[cur_filter]
    if not picker_path then return end
    local pok, picker = pcall(require, picker_path)
    if not pok or not picker or not picker.actions then return end

    for key, action_fn in pairs(picker.actions) do
      table.insert(active_action_keys, key)
      keymap.set("i", key, function()
        local target_idx = state.sel or (#state.items > 0 and 1 or nil)
        if not target_idx or not state.items[target_idx] then return end
        state.close()
        action_fn(state.items[target_idx])
      end, { buffer = st.buf })
    end
  end

  local function nav_back(del)
    if fn.col(".") > 1 then return false end

    if state.mode == Mode.PICKER then
      if #state.filters > 0 then
        state.mode, state.idx = Mode.PROMPT, #state.filters
        local txt = state.prompts[state.idx] or ""
        set(txt, true); render.update_bar(txt); update_virt()
        register_picker_actions()
      end
      return true
    end

    local cur = get()
    if del and cur == "" and state.idx > 0 then
      table.remove(state.filters, state.idx)
      table.remove(state.prompts, state.idx)
      table.remove(state.filter_inputs, state.idx)
      state.idx = state.idx - 1
      evaluate_mod.evaluate()
      state.mode, state.picks = Mode.PICKER, evaluate_mod.get_pickers()
      clear(); render.update_bar("")
      render.render_list(); update_virt()
      register_picker_actions()
      return true
    end

    if state.idx > 1 then
      state.prompts[state.idx] = cur
      state.idx = state.idx - 1
      local txt = state.prompts[state.idx] or ""
      set(txt, true); evaluate_mod.evaluate(); render.render_list(); render.update_bar(txt); update_virt()
      register_picker_actions()
    end
    return true
  end

  local function sel_up()
    state.sel = state.sel and (state.sel < #state.items and state.sel + 1 or state.sel) or 1
    state.preview_scroll = 0
    render.render_list()
  end

  local function sel_down()
    if state.sel == 1 then state.sel = nil
    elseif state.sel then state.sel = state.sel - 1 end
    state.preview_scroll = 0
    render.render_list()
  end

  st.buf = api.nvim_create_buf(false, true)
  bo[st.buf].bufhidden, bo[st.buf].buftype = "wipe", "nofile"
  local init = (state.mode == Mode.PROMPT and state.idx > 0) and (state.prompts[state.idx] or "") or ""
  api.nvim_buf_set_lines(st.buf, 0, -1, false, { init })
  update_virt()

  st.win = api.nvim_open_win(st.buf, true, {
    relative = "win", win = state.space.orig(),
    width = api.nvim_win_get_width(state.space.orig()), height = 1,
    row = state.space.win_height(), col = 0, style = "minimal", focusable = true,
  })
  wo[st.win].winhighlight = "Normal:Normal,NormalFloat:Normal"

  register_picker_actions()

  local function open_item()
    if state.mode == Mode.PICKER then
      if state.pending_open then
        local po = state.pending_open
        state.pending_open = nil
        state.close()
        po.fn(po.item)
        return
      end
      api.nvim_feedkeys(opts.sep, "n", false)
      return
    end
    local target_idx = state.sel or (#state.items > 0 and 1 or nil)
    if not target_idx then state.close(); return end

    local selected = {}
    if next(state.multi_sel) then
      local idxs = vim.tbl_keys(state.multi_sel)
      table.sort(idxs)
      for _, i in ipairs(idxs) do
        if state.items[i] then table.insert(selected, state.items[i]) end
      end
    else
      table.insert(selected, state.items[target_idx])
    end

    local picker_path = opts.pickers[state.filters[state.idx]]
    local pok, picker = pcall(require, picker_path)
    if pok and picker and picker.on_open then
      state.close()
      picker.on_open(selected[1])
      return
    end

    state.close()
    for _, item in ipairs(selected) do
      local file, line_num = utils.parse_item(item)
      utils.open_file_at_line(file, line_num)
    end
  end

  local function push_forward()
    if state.mode == Mode.PICKER then
      api.nvim_feedkeys(opts.sep, "n", false)
      return
    end
    state.pending_open = nil
    local selected_items = {}
    if next(state.multi_sel) then
      local idxs = vim.tbl_keys(state.multi_sel)
      table.sort(idxs)
      for _, i in ipairs(idxs) do
        if state.items[i] then table.insert(selected_items, state.items[i]) end
      end
    else
      local target_idx = state.sel or (#state.items == 1 and 1 or nil)
      if not target_idx or not state.items[target_idx] then return end
      table.insert(selected_items, state.items[target_idx])
    end
    local item = selected_items[1]

    if state.current_type == DataType.Dir then
      state.filter_inputs[state.idx + 1] = { items = selected_items, type = DataType.Dir }
      state.current_type = DataType.Dir
      state.items = {}
      local cur_picker_path = opts.pickers[state.filters[state.idx]]
      local pok, picker = pcall(require, cur_picker_path)
      if pok and picker and picker.on_open then
        state.pending_open = { fn = picker.on_open, item = item }
      end
      state.mode = Mode.PICKER
      state.picks = evaluate_mod.get_pickers()
      state.sel = nil
      render.render_list()
      render.update_bar("")
      update_virt()
      clear()
      return
    end

    local file = utils.parse_item(item)
    local forward_items = {}
    for _, sel_item in ipairs(selected_items) do
      table.insert(forward_items, (utils.parse_item(sel_item)))
    end

    state.idx = state.idx + 1
    state.filter_inputs[state.idx] = { items = forward_items, type = DataType.FileList }
    table.insert(state.filters, "Grep")
    table.insert(state.prompts, "")

    local prev_picker_path = opts.pickers[state.filters[#state.filters - 1]]
    local pok, picker = pcall(require, prev_picker_path)
    if pok and picker and picker.on_open then
      state.pending_open = { fn = picker.on_open, item = file }
    end

    state.mode = Mode.PROMPT
    state.sel = nil
    evaluate_mod.evaluate()
    render.render_list()
    render.update_bar("")
    update_virt()
    clear()
    register_picker_actions()
  end

  local function step_back()
    if state.mode == Mode.PICKER and #state.filters > 0 then
      table.remove(state.filters, #state.filters)
      table.remove(state.prompts, #state.prompts)
      if state.filter_inputs[state.idx] then state.filter_inputs[state.idx] = nil end
      state.idx = math.max(0, state.idx - 1)
      state.pending_open = nil
      evaluate_mod.evaluate()
      if state.idx > 0 then
        state.mode = Mode.PROMPT
        local txt = state.prompts[state.idx] or ""
        set(txt, true); render.update_bar(txt)
        register_picker_actions()
      else
        state.picks = evaluate_mod.get_pickers()
        render.update_bar("")
      end
      render.render_list(); update_virt()
      return
    end
    if state.mode == Mode.PROMPT and state.idx > 0 then
      table.remove(state.filters, state.idx)
      table.remove(state.prompts, state.idx)
      if state.filter_inputs[state.idx] then state.filter_inputs[state.idx] = nil end
      state.idx = state.idx - 1
      evaluate_mod.evaluate()
      state.mode, state.picks = Mode.PICKER, evaluate_mod.get_pickers()
      clear(); render.update_bar("")
      render.render_list(); update_virt()
    end
  end

  keymap.set("i", "<CR>", open_item, { buffer = st.buf })
  keymap.set("i", "<Tab>", push_forward, { buffer = st.buf })
  keymap.set("i", "<S-Tab>", step_back, { buffer = st.buf })

  keymap.set("i", "<Esc>", function()
    if state.sel or next(state.multi_sel) then
      state.sel = nil; state.multi_sel = {}; render.render_list()
    else state.close() end
  end, { buffer = st.buf })

  for key, del in pairs({ ["<BS>"] = true, ["<Left>"] = false }) do
    keymap.set("i", key, function()
      if not nav_back(del) then
        api.nvim_feedkeys(api.nvim_replace_termcodes(key, true, false, true), "n", false)
      end
    end, { buffer = st.buf })
  end

  keymap.set("i", "<Right>", function()
    local line = get()
    if fn.col(".") <= #line then
      api.nvim_feedkeys(api.nvim_replace_termcodes("<Right>", true, false, true), "n", false)
      return
    end
    if state.mode == Mode.PROMPT and state.idx < #state.filters then
      state.prompts[state.idx], state.idx = line, state.idx + 1
      local txt = state.prompts[state.idx] or ""
      set(txt, false); render.update_bar(txt); update_virt()
    end
  end, { buffer = st.buf })

  bind(keys.sel_down, sel_down)
  bind(keys.sel_up, sel_up)

  bind(keys.preview_down, function()
    state.preview_scroll = (state.preview_scroll or 0) + 3
    render.render_list()
  end)

  bind(keys.preview_up, function()
    state.preview_scroll = math.max(0, (state.preview_scroll or 0) - 3)
    render.render_list()
  end)

  local function make_toggle(key, name)
    bind(key, function()
      state.toggles[name] = not state.toggles[name]
      state.result_cache = {}
      evaluate_mod.evaluate(); render.render_list()
      render.update_bar(get()); update_virt()
    end)
  end
  make_toggle(keys.toggle_case, "case")
  make_toggle(keys.toggle_word, "word")
  make_toggle(keys.toggle_regex, "regex")
  bind(keys.toggle_gitfiles, function()
    if not state.in_git then return end
    state.toggles.gitfiles = not state.toggles.gitfiles
    state.result_cache = {}
    evaluate_mod.evaluate(); render.render_list()
    render.update_bar(get()); update_virt()
  end)

  bind(keys.multi_add, function()
    local idx = state.sel or (#state.items > 0 and 1 or nil)
    if not idx then return end
    state.multi_sel[idx] = true
    sel_up()
  end)

  bind(keys.multi_remove, function()
    local idx = state.sel or (#state.items > 0 and 1 or nil)
    if not idx then return end
    state.multi_sel[idx] = nil
    sel_up()
  end)

  api.nvim_create_autocmd("TextChangedI", {
    buffer = st.buf,
    callback = function()
      local input = get()
      if state.mode == Mode.PICKER then
        state.pending_open = nil
        local all = evaluate_mod.get_pickers()
        state.picks = input == "" and all or vim.tbl_filter(function(n)
          return n:lower():sub(1, #input) == input:lower()
        end, all)
        render.update_bar(input)
        if #state.picks == 1 then
          state.idx = state.idx + 1
          table.insert(state.filters, state.picks[1])
          table.insert(state.prompts, "")
          state.mode, state.picks = Mode.PROMPT, {}
          evaluate_mod.evaluate()
          clear()
          render.render_list(); render.update_bar(""); update_virt()
          register_picker_actions()
        end
      else
        state.prompts[state.idx] = input
        evaluate_mod.evaluate()
        render.render_list(); render.update_bar(input); update_virt()
      end
    end
  })

  local aug = api.nvim_create_augroup("FinderResize", { clear = true })
  api.nvim_create_autocmd("VimResized", {
    group = aug,
    callback = function()
      if state.space then
        state.space.close()
        state.space = create_space()
        render.render_list()
        if st.win and api.nvim_win_is_valid(st.win) then
          api.nvim_win_set_config(st.win, {
            relative = "win", win = state.space.orig(),
            width = api.nvim_win_get_width(state.space.orig()), height = 1,
            row = state.space.win_height(), col = 0,
          })
        end
      end
    end
  })

  api.nvim_create_autocmd("BufLeave", {
    buffer = st.buf,
    callback = function()
      vim.schedule(function() if state.close then state.close() end end)
    end,
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

return create_input
