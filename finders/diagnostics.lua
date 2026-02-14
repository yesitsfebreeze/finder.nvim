local fn = vim.fn
local state = require("finder.src.state")
local DataType = state.DataType
local utils = require("finder.src.utils")
local display = require("finder.src.display")

local M = {}
M.accepts = { DataType.None }
M.produces = DataType.GrepList
M.initial = true

local severity_order = {
  [vim.diagnostic.severity.ERROR] = 1,
  [vim.diagnostic.severity.WARN] = 2,
  [vim.diagnostic.severity.INFO] = 3,
  [vim.diagnostic.severity.HINT] = 4,
}

local severity_label = {
  [vim.diagnostic.severity.ERROR] = "E",
  [vim.diagnostic.severity.WARN] = "W",
  [vim.diagnostic.severity.INFO] = "I",
  [vim.diagnostic.severity.HINT] = "H",
}

local sev_hl = {
  E = "DiagnosticError",
  W = "DiagnosticWarn",
  I = "DiagnosticInfo",
  H = "DiagnosticHint",
}

local displayer = display.create({
  separator = " ",
  items = {
    { width = 1 },
    { remaining = true },
  },
})

local sev_cache = {}
local diag_by_file = {}

function M.display(item, ctx)
  local sev_char = sev_cache[item] or "?"
  local sel_hl = ctx.is_sel and "FinderHighlight" or nil
  return displayer({
    { sev_char, sel_hl or sev_hl[sev_char] or "FinderText" },
    utils.highlight_matches(item, ctx.query, sel_hl or "FinderText"),
  }, ctx.width)
end

function M.filter(query, _)
  local diags = vim.diagnostic.get(nil)

  table.sort(diags, function(a, b)
    local sa = severity_order[a.severity] or 99
    local sb = severity_order[b.severity] or 99
    if sa ~= sb then return sa < sb end
    local fa = vim.api.nvim_buf_get_name(a.bufnr)
    local fb = vim.api.nvim_buf_get_name(b.bufnr)
    if fa ~= fb then return fa < fb end
    return a.lnum < b.lnum
  end)

  local cwd = fn.getcwd() .. "/"
  sev_cache = {}
  diag_by_file = {}
  local results = {}
  for _, d in ipairs(diags) do
    local file = vim.api.nvim_buf_get_name(d.bufnr)
    if file:sub(1, #cwd) == cwd then file = file:sub(#cwd + 1) end
    local lnum = d.lnum + 1
    local msg = (d.message or ""):gsub("\n", " ")
    local entry = string.format("%s:%d:%s", file, lnum, msg)
    sev_cache[entry] = severity_label[d.severity] or "?"
    if not diag_by_file[file] then diag_by_file[file] = {} end
    table.insert(diag_by_file[file], { lnum = d.lnum, col = d.col, end_col = d.end_col, severity = d.severity, message = msg })
    table.insert(results, entry)
  end

  if query and query ~= "" then
    results = utils.filter_items(results, query)
  end

  return results
end

function M.decorate_preview(buf, file, start_line, end_line)
  local ns = vim.api.nvim_create_namespace("finder_diag_preview")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local fdiags = diag_by_file[file]
  if not fdiags then return end
  for _, d in ipairs(fdiags) do
    local lnum = d.lnum + 1
    if lnum >= start_line and lnum <= end_line then
      local row = lnum - start_line
      local sev = severity_label[d.severity] or "?"
      local hl = sev_hl[sev] or "DiagnosticHint"
      local end_col = d.end_col or (d.col + 1)
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, d.col, { end_col = end_col, hl_group = hl })
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, 0, { virt_text = { { "● " .. d.message, hl } }, virt_text_pos = "eol" })
    end
  end
end

return M
