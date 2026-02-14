local Mode = { PICKER = 1, PROMPT = 2 }

local DataType = {
  None = 0,
  FileList = 1,
  GrepList = 2,
  Commits = 3,
  File = 4,
}

local defaults = {
  sep = " > ",
  list_height = 10,
  pickers = {
    Files = "finder.pickers.files",
    Grep = "finder.pickers.grep",
    Commits = "finder.pickers.commits",
    File = "finder.pickers.file",
  },
}

local M = {
  filters = {},
  prompts = {},
  filter_inputs = {},
  mode = Mode.PICKER,
  idx = 0,
  items = {},
  sel = nil,
}

M.Mode = Mode
M.DataType = DataType
M.defaults = defaults

return M
