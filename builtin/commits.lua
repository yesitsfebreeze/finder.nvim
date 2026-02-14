local fn = vim.fn
local api = vim.api
local DataType = require("finder.state").DataType
local utils = require("finder.utils")
local display = require("finder.display")

local M = {}
M.accepts = { DataType.None, DataType.FileList }
M.produces = DataType.Commits
M.display = display.commit

function M.filter(query, items)
  if fn.executable("git") ~= 1 then
    return nil, "git not found"
  end

  local format = "%h%x09%as%x09%an%x09%s"
  local cmd

  if items and #items > 0 then
    local files = table.concat(vim.tbl_map(fn.shellescape, items), " ")
    cmd = string.format("git log --pretty=format:'%s' -- %s 2>/dev/null", format, files)
  else
    cmd = string.format("git log --pretty=format:'%s' 2>/dev/null", format)
  end

  local results = fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then
    return nil, "git log failed"
  end

  if not query or query == "" then return results end

  return utils.filter_items(results, query)
end

function M.on_open(item)
  local hash = item:match('^([^\t]+)')
  if not hash then return end
  local diff = fn.systemlist('git show ' .. hash)
  if vim.v.shell_error ~= 0 then return end
  vim.cmd('enew')
  local buf = api.nvim_get_current_buf()
  api.nvim_buf_set_lines(buf, 0, -1, false, diff)
  vim.bo[buf].filetype = 'git'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].modifiable = false
end

return M
