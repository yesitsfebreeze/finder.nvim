local fn = vim.fn
local cmd = vim.cmd
local DataType = require("finder.state").DataType
local utils = require("finder.utils")

local M = {}
M.accepts = { DataType.None }
M.produces = DataType.Dir

local session_dir = fn.stdpath("data") .. "/sessions"

local function read_cwd(session_file)
  for _, line in ipairs(fn.readfile(session_file, "", 20)) do
    local dir = line:match("^cd (.+)$")
    if dir then return fn.expand(dir) end
  end
end

function M.filter(query, _)
  if fn.isdirectory(session_dir) ~= 1 then return {} end

  local sessions = {}
  for _, file in ipairs(fn.readdir(session_dir)) do
    if file:match("%.vim$") then
      local path = session_dir .. "/" .. file
      local dir = read_cwd(path)
      if dir then table.insert(sessions, dir) end
    end
  end

  if not query or query == "" then return sessions end
  return utils.filter_items(sessions, query)
end

function M.on_open(item)
  if fn.isdirectory(item) ~= 1 then return end
  for _, file in ipairs(fn.readdir(session_dir)) do
    if file:match("%.vim$") then
      local path = session_dir .. "/" .. file
      local dir = read_cwd(path)
      if dir and fn.resolve(dir) == fn.resolve(item) then
        cmd("source " .. fn.fnameescape(path))
        return
      end
    end
  end
end

return M
