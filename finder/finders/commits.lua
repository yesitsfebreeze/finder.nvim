local fn = vim.fn
local DataType = require("finder.src.state").DataType
local utils = require("finder.src.utils")
local display = require("finder.src.display")

local M = {}
M.accepts = { DataType.None, DataType.FileList, DataType.GrepList, DataType.Dir, DataType.DirList, DataType.Commits }
M.produces = DataType.Commits
M.display = display.commit
M.initial = true

local run_async = utils.async_filter(function(_, items)
  local format = "%h%x09%as%x09%an%x09%s"

  local cmd = string.format("git log --pretty=format:'%s'", format)

  if items and #items > 0 then
    local files = utils.extract_files(items)
    if #files > 0 then
      local args = table.concat(vim.tbl_map(fn.shellescape, files), " ")
      cmd = cmd .. " -- " .. args
    end
  end

  return cmd
end)

function M.filter(query, items)
  if fn.executable("git") ~= 1 then
    return nil, "git not found"
  end

  local result, err = run_async("", items)
  if err == "async" then return result, err end
  if err then return nil, err end

  if query and query ~= "" then
    return utils.filter_items(result, query)
  end
  return result
end

function M.on_open(item)
  local hash = item:match('^([^\t]+)')
  utils.show_commit(hash)
end

return M
