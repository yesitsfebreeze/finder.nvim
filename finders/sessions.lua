local fn = vim.fn
local cmd = vim.cmd
local DataType = require("finder.src.state").DataType
local utils = require("finder.src.utils")

local M = {}
M.initial = true
M.accepts = { DataType.None }
M.produces = DataType.Dir

local session_dir = fn.stdpath("data") .. "/sessions"

local function read_cwd(session_file)
  for _, line in ipairs(fn.readfile(session_file, "", 20)) do
    local dir = line:match("^cd (.+)$")
    if dir then return fn.expand(dir) end
  end
end

local function get_session_map()
  if fn.isdirectory(session_dir) ~= 1 then return {} end
  local map = {}
  for _, file in ipairs(fn.readdir(session_dir)) do
    if file:match("%.vim$") then
      local path = session_dir .. "/" .. file
      local dir = read_cwd(path)
      if dir then map[dir] = path end
    end
  end
  return map
end

function M.filter(query, _)
  local session_map = get_session_map()
  local sessions = vim.tbl_keys(session_map)
  table.sort(sessions)

  if not query or query == "" then return sessions end
  return utils.filter_items(sessions, query)
end

function M.on_open(item)
  if fn.isdirectory(item) ~= 1 then return end
  local session_map = get_session_map()
  local resolved = fn.resolve(item)
  for dir, path in pairs(session_map) do
    if fn.resolve(dir) == resolved then
      cmd("source " .. fn.fnameescape(path))
      return
    end
  end
end

return M
