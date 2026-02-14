local DataType = require("finder.src.state").DataType
local utils = require("finder.src.utils")
local search = require("finder.finders.search")

local M = {}
M.accepts = { DataType.None }
M.produces = DataType.GrepList
M.actions = utils.grep_query_open_actions

function M.filter(query, _)
  return search.filter_with_direction(query, "up")
end

return M
