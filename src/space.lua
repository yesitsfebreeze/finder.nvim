local api = vim.api
local bo = vim.bo
local wo = vim.wo

local function create_space(target_win)
  local orig_win = target_win or api.nvim_get_current_win()
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

return create_space
