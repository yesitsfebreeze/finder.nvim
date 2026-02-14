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
  end

  local function nav_back(del)
    if fn.col(".") > 1 then return false end

    if state.mode == Mode.PICKER then
      if #state.filters > 0 then
        state.mode, state.idx = Mode.PROMPT, #state.filters
        local txt = state.prompts[state.idx] or ""
        set(txt, true); render.update_bar(txt); update_virt()
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
      return true
    end

    if state.idx > 1 then
      state.prompts[state.idx] = cur
      state.idx = state.idx - 1
      local txt = state.prompts[state.idx] or ""
      set(txt, true); evaluate_mod.evaluate(); render.render_list(); render.update_bar(txt); update_virt()
    end
    return true
  end

  local function sel_up()
    state.sel = state.sel and (state.sel < #state.items and state.sel + 1 or state.sel) or 1
    render.render_list()
  end

  local function sel_down()
    if state.sel == 1 then state.sel = nil
    elseif state.sel then state.sel = state.sel - 1 end
    render.render_list()
  end

  api.nvim_set_hl(0, "FinderPrefix", { fg = "#80a0ff", bold = true, default = true })
  api.nvim_set_hl(0, "FinderInactive", { link = "Comment", default = true })
  api.nvim_set_hl(0, "FinderMatch", { link = "Search", default = true })

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

  local function confirm()
    if state.mode == Mode.PICKER then
      api.nvim_feedkeys(opts.sep, "n", false)
      return
    end
    local target_idx = state.sel or (#state.items == 1 and 1 or nil)
    if target_idx and state.items[target_idx] then
      local item = state.items[target_idx]
      local file, line_num = utils.parse_item(item)
      
      if state.current_type == DataType.GrepList then
        state.close()
        utils.open_file_at_line(file, line_num)
      else
        local first_file = state.items[1] and state.items[1]:match("^([^:]+)")
        local all_same = first_file and not vim.iter(state.items):any(function(v)
          return (v:match("^([^:]+)") or v) ~= first_file
        end)
        if all_same then
          state.close()
          utils.open_file_at_line(file, line_num)
        else
          state.idx = state.idx + 1
          state.filter_inputs[state.idx] = { items = { file }, type = DataType.FileList }
          table.insert(state.filters, "Grep")
          table.insert(state.prompts, fn.fnamemodify(file, ":t"))
          
          evaluate_mod.evaluate()
          
          state.mode = Mode.PICKER
          state.picks = evaluate_mod.get_pickers()
          state.sel = nil
          render.render_list()
          render.update_bar("")
          update_virt()
          clear()
        end
      end
    else
      if #state.items > 0 then
        local first_file = utils.parse_item(state.items[1])
        if first_file and fn.filereadable(first_file) == 1 then
          local all_same = not vim.iter(state.items):any(function(v)
            return (utils.parse_item(v)) ~= first_file
          end)
          if all_same then
            state.close()
            utils.open_file_at_line(first_file)
            return
          end
        end
      end
      state.close()
    end
  end

  keymap.set("i", "<Tab>", confirm, { buffer = st.buf })

  keymap.set("i", "<Esc>", function()
    if state.sel then state.sel = nil; render.render_list() else state.close() end
  end, { buffer = st.buf })
  keymap.set("i", "<CR>", confirm, { buffer = st.buf })

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

  for _, k in ipairs({ "<C-j>", "<Down>" }) do keymap.set("i", k, sel_down, { buffer = st.buf }) end
  for _, k in ipairs({ "<C-k>", "<Up>" }) do keymap.set("i", k, sel_up, { buffer = st.buf }) end

  api.nvim_create_autocmd("TextChangedI", {
    buffer = st.buf,
    callback = function()
      local input = get()
      if state.mode == Mode.PICKER then
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
          evaluate_mod.evaluate(); render.render_list(); render.update_bar(""); update_virt(); clear()
        end
      else
        state.prompts[state.idx] = input
        evaluate_mod.evaluate(); render.render_list(); render.update_bar(input); update_virt()
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
