local api = vim.api

local M = {}

--- @class finder.SavedBinding
--- @field mode string
--- @field lhs string
--- @field bufnr number|nil
--- @field prior table|nil  -- snapshot of the mapping that existed before we overwrote it

--- All bindings set during the current finder session.
--- @type finder.SavedBinding[]
local bindings = {}

--- Snapshot an existing buffer-local or global mapping so we can restore it later.
---@param mode string
---@param lhs string
---@param bufnr? number
---@return table|nil
local function snapshot(mode, lhs, bufnr)
  local maps = bufnr and api.nvim_buf_get_keymap(bufnr, mode)
    or api.nvim_get_keymap(mode)
  local resolved = api.nvim_replace_termcodes(lhs, true, true, true)
  for _, map in ipairs(maps) do
    if map.lhs == lhs or map.lhs == resolved then
      return map
    end
  end
  return nil
end

--- Mirror of vim.keymap.set that tracks every binding it creates.
--- Saves any pre-existing mapping for the same mode/lhs/buffer so it can be
--- restored later via unbind_all().
---
---@param mode string|string[]
---@param lhs string
---@param rhs string|function
---@param opts? table
function M.bind(mode, lhs, rhs, opts)
  opts = opts or {}
  local modes = type(mode) == "table" and mode or { mode }
  local bufnr = opts.buffer

  for _, m in ipairs(modes) do
    table.insert(bindings, {
      mode = m,
      lhs = lhs,
      bufnr = bufnr,
      prior = snapshot(m, lhs, bufnr),
      rhs = rhs,
      opts = opts,
    })
  end

  vim.keymap.set(mode, lhs, rhs, opts)
end

--- Re-snapshot and re-apply all tracked bindings.
--- Call this (via vim.schedule) after startinsert! so that mappings set by
--- plugins during InsertEnter (e.g. nvim-cmp's <Tab>) are captured as priors
--- and then overwritten by ours.
function M.rebind_all()
  for _, b in ipairs(bindings) do
    b.prior = snapshot(b.mode, b.lhs, b.bufnr)
    vim.keymap.set(b.mode, b.lhs, b.rhs, b.opts)
  end
end

--- Delete a single tracked binding (used for dynamic picker action keys).
--- Only removes the first match.
---@param mode string
---@param lhs string
---@param opts? table  -- { buffer = bufnr }
function M.unbind(mode, lhs, opts)
  opts = opts or {}
  local bufnr = opts.buffer

  pcall(vim.keymap.del, mode, lhs, bufnr and { buffer = bufnr } or nil)

  for i, b in ipairs(bindings) do
    if b.mode == mode and b.lhs == lhs and b.bufnr == bufnr then
      if b.prior then
        local ropts = {
          noremap = b.prior.noremap == 1,
          silent  = b.prior.silent == 1,
          expr    = b.prior.expr == 1,
          nowait  = b.prior.nowait == 1,
          desc    = b.prior.desc or nil,
        }
        local rrhs = b.prior.rhs or ""
        if b.prior.callback then
          ropts.callback = b.prior.callback
          rrhs = ""
        end
        if bufnr then
          pcall(api.nvim_buf_set_keymap, bufnr, mode, b.prior.lhs, rrhs, ropts)
        else
          pcall(api.nvim_set_keymap, mode, b.prior.lhs, rrhs, ropts)
        end
      end
      table.remove(bindings, i)
      return
    end
  end
end

--- Remove every tracked binding and restore all prior mappings.
function M.unbind_all()
  for i = #bindings, 1, -1 do
    local b = bindings[i]
    pcall(vim.keymap.del, b.mode, b.lhs, b.bufnr and { buffer = b.bufnr } or nil)

    if b.prior then
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
  end
  bindings = {}
end

return M
