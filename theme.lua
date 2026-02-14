local api = vim.api

local M = {}

local defaults = {
  color      = "#80a0ff",
  inactive   = "#75797F",
  text       = "#c6c8d1",
  sep_fg     = "#75797F",
  sep_bg     = nil,
  preview_bg = nil,
}

function M.apply()
  local function hl_attr(name, attr)
    local ok, hl = pcall(api.nvim_get_hl, 0, { name = name, link = false })
    return ok and hl and hl[attr] or nil
  end

  local color = hl_attr("Function", "fg") or defaults.color

  api.nvim_set_hl(0, "FinderColor",     { fg = color })
  api.nvim_set_hl(0, "FinderInactive",  { fg = hl_attr("Comment", "fg")  or defaults.inactive })
  api.nvim_set_hl(0, "FinderText",      { fg = hl_attr("Normal", "fg")   or defaults.text })
  api.nvim_set_hl(0, "FinderSeparator", { fg = color, bg = defaults.sep_bg })
  api.nvim_set_hl(0, "FinderCount",     { fg = color, bold = true })

  local preview_bg = hl_attr("NormalFloat", "bg") or hl_attr("Normal", "bg") or defaults.preview_bg
  api.nvim_set_hl(0, "FinderPreviewBG", { fg = color, bg = preview_bg })

  local search_bg = hl_attr("Search", "bg") or color
  local search_fg = hl_attr("Search", "fg")
  if not search_fg then
    local r, g, b = bit.rshift(search_bg, 16), bit.band(bit.rshift(search_bg, 8), 0xFF), bit.band(search_bg, 0xFF)
    local lum = 0.299 * r + 0.587 * g + 0.114 * b
    search_fg = lum > 128 and 0x000000 or 0xFFFFFF
  end
  api.nvim_set_hl(0, "FinderHighlight", {
    fg   = search_fg,
    bg   = search_bg,
    bold = true,
  })
end

return M
