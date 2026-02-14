local api = vim.api

local M = {}

local defaults = {
  color    = "#80a0ff",
  inactive = "#75797F",
  text     = "#c6c8d1",
}

function M.apply()
  local function fg(name)
    local ok, hl = pcall(api.nvim_get_hl, 0, { name = name, link = false })
    return ok and hl and hl.fg or nil
  end

  api.nvim_set_hl(0, "FinderColor",     { fg = defaults.color, bold = true })
  api.nvim_set_hl(0, "FinderInactive",  { fg = fg("Comment")  or defaults.inactive })
  api.nvim_set_hl(0, "FinderText",      { fg = fg("Normal")   or defaults.text })
  local color_bg = fg("Function") or defaults.color
  local r, g, b = bit.rshift(color_bg, 16), bit.band(bit.rshift(color_bg, 8), 0xFF), bit.band(color_bg, 0xFF)
  local lum = 0.299 * r + 0.587 * g + 0.114 * b
  api.nvim_set_hl(0, "FinderHighlight", {
    fg   = lum > 128 and 0x000000 or 0xFFFFFF,
    bg   = color_bg,
    bold = true,
  })
end

return M
