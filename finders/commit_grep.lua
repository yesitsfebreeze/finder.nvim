local fn = vim.fn
local state = require("finder.src.state")
local DataType = state.DataType
local display = require("finder.src.display")
local utils = require("finder.src.utils")

local M = {}
M.accepts = { DataType.None, DataType.FileList }
M.produces = DataType.Commits
M.display = display.commit

local run_async = utils.async_filter(function(query, extra)
  local toggles = state.toggles or {}
  local search_flag = toggles.regex and '-G' or '-S'
  local case_flag = (toggles.regex and not toggles.case) and ' -i' or ''

  local cmd = "git log " .. search_flag .. " " .. fn.shellescape(query)
    .. case_flag
    .. " --format='%h%x09%as%x09%an%x09%s' --max-count=100"

  if extra and #extra > 0 then
    cmd = cmd .. " -- " .. table.concat(vim.tbl_map(fn.shellescape, extra), " ")
  end
  return cmd
end)

function M.filter(query, items)
  if fn.executable("git") ~= 1 then
    return nil, "git not found"
  end
  return run_async(query, items)
end

function M.on_open(item)
  local hash = item:match('^([^\t]+)')
  utils.show_commit(hash)
end

return M
