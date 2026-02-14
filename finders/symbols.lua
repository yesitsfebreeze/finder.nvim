local fn = vim.fn
local api = vim.api
local state = require("finder.state")
local DataType = state.DataType
local utils = require("finder.utils")
local display = require("finder.display")

local M = {}
M.accepts = { DataType.None, DataType.File, DataType.FileList, DataType.GrepList }
M.produces = DataType.GrepList
M.initial = true
M.actions = utils.grep_open_actions

local kind_names = {
  [1]  = "File",       [2]  = "Module",     [3]  = "Namespace",
  [4]  = "Package",    [5]  = "Class",      [6]  = "Method",
  [7]  = "Property",   [8]  = "Field",      [9]  = "Constructor",
  [10] = "Enum",       [11] = "Interface",  [12] = "Function",
  [13] = "Variable",   [14] = "Constant",   [15] = "String",
  [16] = "Number",     [17] = "Boolean",    [18] = "Array",
  [19] = "Object",     [20] = "Key",        [21] = "Null",
  [22] = "EnumMember", [23] = "Struct",     [24] = "Event",
  [25] = "Operator",   [26] = "TypeParam",
}

local kind_hl = {
  File       = "FinderSymFile",
  Module     = "FinderSymModule",
  Namespace  = "FinderSymNamespace",
  Package    = "FinderSymModule",
  Class      = "FinderSymClass",
  Method     = "FinderSymMethod",
  Property   = "FinderSymField",
  Field      = "FinderSymField",
  Constructor= "FinderSymMethod",
  Enum       = "FinderSymEnum",
  Interface  = "FinderSymInterface",
  Function   = "FinderSymFunction",
  Variable   = "FinderSymVariable",
  Constant   = "FinderSymConstant",
  String     = "FinderSymVariable",
  Number     = "FinderSymVariable",
  Boolean    = "FinderSymVariable",
  Array      = "FinderSymVariable",
  Object     = "FinderSymClass",
  Key        = "FinderSymField",
  Null       = "FinderSymVariable",
  EnumMember = "FinderSymEnum",
  Struct     = "FinderSymStruct",
  Event      = "FinderSymMethod",
  Operator   = "FinderSymFunction",
  TypeParam  = "FinderSymInterface",
}

local kind_icons = {
  File       = "󰈙", Module     = "󰏗", Namespace  = "󰌗",
  Package    = "󰏗", Class      = "󰠱", Method     = "󰊕",
  Property   = "󰜢", Field      = "󰜢", Constructor= "󰒓",
  Enum       = "󰕘", Interface  = "󰕘", Function   = "󰊕",
  Variable   = "󰀫", Constant   = "󰏿", String     = "󰉿",
  Number     = "󰎠", Boolean    = "◩", Array      = "󰅪",
  Object     = "󰅩", Key        = "󰌋", Null       = "󰟢",
  EnumMember = "󰕘", Struct     = "󰙅", Event      = "󰉁",
  Operator   = "󰆕", TypeParam  = "󰊄",
}

local sym_cache = {}  -- item -> { kind_name, icon, depth }

local displayer = display.create({
  separator = " ",
  items = {
    { width = 2 },
    { width = 12 },
    { remaining = true },
  },
})

function M.display(item, ctx)
  local info = sym_cache[item]
  if not info then
    return { { item, ctx.is_sel and "FinderHighlight" or "FinderText" } }
  end
  local sel_hl = ctx.is_sel and "FinderHighlight" or nil
  local indent = info.depth > 0 and string.rep("  ", info.depth) or ""
  return displayer({
    { info.icon, sel_hl or kind_hl[info.kind_name] or "FinderText" },
    { info.kind_name, sel_hl or "FinderInactive" },
    utils.highlight_matches(indent .. item:match("^[^:]+:%d+:(.*)$") or item, ctx.query, sel_hl or "FinderText"),
  }, ctx.width)
end

local function flatten_symbols(symbols, file, results, depth)
  for _, sym in ipairs(symbols) do
    local range = sym.selectionRange or sym.range or (sym.location and sym.location.range)
    if range then
      local lnum = range.start.line + 1
      local kind = kind_names[sym.kind] or "Unknown"
      local name = sym.name or ""
      local entry = string.format("%s:%d:%s", file, lnum, name)
      sym_cache[entry] = { kind_name = kind, icon = kind_icons[kind] or "?", depth = depth }
      table.insert(results, entry)
      if sym.children and #sym.children > 0 then
        flatten_symbols(sym.children, file, results, depth + 1)
      end
    end
  end
end

local function get_symbols_for_buf(bufnr, file, results)
  local clients = vim.lsp.get_clients({ bufnr = bufnr, method = "textDocument/documentSymbol" })
  if #clients == 0 then return false end

  local resp = vim.lsp.buf_request_sync(bufnr, "textDocument/documentSymbol", {
    textDocument = vim.lsp.util.make_text_document_params(bufnr),
  }, 2000)

  if not resp then return false end

  for _, client_resp in pairs(resp) do
    if client_resp.result and #client_resp.result > 0 then
      flatten_symbols(client_resp.result, file, results, 0)
      return true
    end
  end
  return false
end

local function resolve_buffers(items)
  local cwd = fn.getcwd() .. "/"
  local bufs = {}

  if not items or #items == 0 then
    local bufnr = state.origin and state.origin.buf or api.nvim_get_current_buf()
    local name = api.nvim_buf_get_name(bufnr)
    if name ~= "" then
      local rel = name:sub(1, #cwd) == cwd and name:sub(#cwd + 1) or name
      bufs[rel] = bufnr
    end
    return bufs
  end

  local files = utils.extract_files(items)
  for _, file in ipairs(files) do
    local abs = fn.fnamemodify(file, ":p")
    local rel = abs:sub(1, #cwd) == cwd and abs:sub(#cwd + 1) or file
    local bufnr = fn.bufnr(abs)
    if bufnr == -1 then
      bufnr = fn.bufadd(abs)
      fn.bufload(bufnr)
    end
    bufs[rel] = bufnr
  end
  return bufs
end

function M.filter(query, items)
  sym_cache = {}
  local results = {}
  local bufs = resolve_buffers(items)

  local got_any = false
  for file, bufnr in pairs(bufs) do
    if get_symbols_for_buf(bufnr, file, results) then
      got_any = true
    end
  end

  if not got_any then
    return nil, "no LSP symbols available"
  end

  if query and query ~= "" then
    results = utils.filter_items(results, query)
  end

  return results
end

-- set up highlight groups
local function setup_highlights()
  local links = {
    FinderSymFile      = "Directory",
    FinderSymModule    = "Include",
    FinderSymNamespace = "Include",
    FinderSymClass     = "Type",
    FinderSymMethod    = "Function",
    FinderSymField     = "Identifier",
    FinderSymEnum      = "Type",
    FinderSymInterface = "Type",
    FinderSymFunction  = "Function",
    FinderSymVariable  = "Identifier",
    FinderSymConstant  = "Constant",
    FinderSymStruct    = "Structure",
  }
  for group, link in pairs(links) do
    vim.api.nvim_set_hl(0, group, { link = link, default = true })
  end
end

setup_highlights()

return M
