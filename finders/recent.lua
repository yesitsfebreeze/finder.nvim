local fn = vim.fn
local state = require("finder.state")
local DataType = state.DataType
local utils = require("finder.utils")

local M = {}
M.accepts = { DataType.None }
M.produces = DataType.FileList
M.initial = true
M.actions = utils.file_open_actions

function M.filter(query, _)
  local cwd = fn.getcwd() .. "/"
  local recent = {}
  for _, file in ipairs(vim.v.oldfiles) do
    local abs = fn.fnamemodify(file, ":p")
    if abs:sub(1, #cwd) == cwd and fn.filereadable(abs) == 1 then
      table.insert(recent, fn.fnamemodify(abs, ":."))
    end
  end

  if not query or query == "" then return recent end
  return utils.filter_items(recent, query)
end

return M
