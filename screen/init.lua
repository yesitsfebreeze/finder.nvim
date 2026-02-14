local api = vim.api
local bo = vim.bo
local wo = vim.wo

local function snapshot(mode, lhs, bufnr)
  local maps = bufnr and api.nvim_buf_get_keymap(bufnr, mode)
    or api.nvim_get_keymap(mode)
  local resolved = api.nvim_replace_termcodes(lhs, true, true, true)
  for _, map in ipairs(maps) do
    if map.lhs == lhs or map.lhs == resolved then return map end
  end
  return nil
end

local function restore_binding(b)
  pcall(vim.keymap.del, b.mode, b.lhs, b.bufnr and { buffer = b.bufnr } or nil)
  if not b.prior then return end
  local ropts = {
    noremap = b.prior.noremap == 1,
    silent  = b.prior.silent == 1,
    expr    = b.prior.expr == 1,
    nowait  = b.prior.nowait == 1,
    desc    = b.prior.desc or nil,
  }
  local rhs = b.prior.rhs or ""
  if b.prior.callback then
    ropts.callback = b.prior.callback
    rhs = ""
  end
  if b.bufnr then
    pcall(api.nvim_buf_set_keymap, b.bufnr, b.mode, b.prior.lhs, rhs, ropts)
  else
    pcall(api.nvim_set_keymap, b.mode, b.prior.lhs, rhs, ropts)
  end
end

local function create(opts)
  opts = opts or {}
  local orig_win = opts.win or api.nvim_get_current_win()
  local total_height = api.nvim_win_get_height(orig_win)
  local width = opts.width or api.nvim_win_get_width(orig_win)
  local ns = api.nvim_create_namespace("")
  local height = opts.height or 4

  local buf = api.nvim_create_buf(false, true)
  bo[buf].bufhidden, bo[buf].buftype = "wipe", "nofile"
  api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn["repeat"]({""}, height))

  local win = api.nvim_open_win(buf, false, {
    relative = "win", win = orig_win,
    width = width, height = height,
    row = total_height - height, col = 0,
    style = "minimal", focusable = opts.focusable or false,
    zindex = opts.zindex or 10,
  })
  wo[win].winhighlight = opts.winhighlight or "Normal:Normal,NormalFloat:Normal"

  local bindings = {}
  local S = {}

  function S.height() return height end
  function S.win_height() return total_height end
  function S.orig() return orig_win end
  function S.buf() return buf end
  function S.win() return win end

  function S.resize(_, new_height)
    new_height = math.min(new_height, total_height)
    if new_height == height then return end
    height = new_height
    if buf and api.nvim_buf_is_valid(buf) then
      api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn["repeat"]({""}, height))
    end
    if win and api.nvim_win_is_valid(win) then
      api.nvim_win_set_config(win, {
        relative = "win", win = orig_win,
        width = width, height = height,
        row = total_height - height, col = 0,
      })
    end
  end

  function S.set_line(_, lnum, virt)
    if not (buf and api.nvim_buf_is_valid(buf) and win and api.nvim_win_is_valid(win)) then return end
    local target = math.max(0, math.min(lnum, height) - 1)
    for _, mark in ipairs(api.nvim_buf_get_extmarks(buf, ns, {target, 0}, {target, -1}, {})) do
      api.nvim_buf_del_extmark(buf, ns, mark[1])
    end
    api.nvim_buf_set_extmark(buf, ns, target, 0, { virt_text = virt, virt_text_pos = "overlay" })
  end

  function S.clear()
    if buf and api.nvim_buf_is_valid(buf) then
      api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    end
  end

  function S.bind(mode, lhs, rhs, kopts)
    kopts = kopts or {}
    local modes = type(mode) == "table" and mode or { mode }
    local bufnr = kopts.buffer
    for _, m in ipairs(modes) do
      table.insert(bindings, {
        mode = m, lhs = lhs, bufnr = bufnr,
        prior = snapshot(m, lhs, bufnr),
        rhs = rhs, opts = kopts,
      })
    end
    vim.keymap.set(mode, lhs, rhs, kopts)
  end

  function S.unbind(mode, lhs, kopts)
    kopts = kopts or {}
    local bufnr = kopts.buffer
    for i, b in ipairs(bindings) do
      if b.mode == mode and b.lhs == lhs and b.bufnr == bufnr then
        restore_binding(b)
        table.remove(bindings, i)
        return
      end
    end
    pcall(vim.keymap.del, mode, lhs, bufnr and { buffer = bufnr } or nil)
  end

  function S.rebind_all()
    for _, b in ipairs(bindings) do
      b.prior = snapshot(b.mode, b.lhs, b.bufnr)
      vim.keymap.set(b.mode, b.lhs, b.rhs, b.opts)
    end
  end

  function S.close()
    for i = #bindings, 1, -1 do restore_binding(bindings[i]) end
    bindings = {}
    if win and api.nvim_win_is_valid(win) then api.nvim_win_close(win, true) end
    win, buf = nil, nil
  end

  return S
end

return create
