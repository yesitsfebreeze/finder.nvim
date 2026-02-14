local Mode = { PICKER = 1, PROMPT = 2, INTERACT = 3 }

local DataType = {
  None = 0,
  FileList = 1,
  GrepList = 2,
  Commits = 3,
  File = 4,
  Dir = 5,
  DirList = 6,
}

local function register_type(name, id)
  assert(type(name) == "string", "register_type: name must be a string")
  assert(type(id) == "number", "register_type: id must be a number")
  if DataType[name] then
    assert(DataType[name] == id, string.format("register_type: '%s' already registered with id %d", name, DataType[name]))
    return id
  end
  for k, v in pairs(DataType) do
    if v == id then
      error(string.format("register_type: id %d already used by '%s'", id, k))
    end
  end
  DataType[name] = id
  return id
end

local defaults = {
  sep = " > ",
  list_height = 10,
  pickers = {
    Files = "finder.builtin.files",
    Grep = "finder.builtin.grep",
    Commits = "finder.builtin.commits",
    File = "finder.builtin.file",
    Sessions = "finder.builtin.sessions",
    Dirs = "finder.builtin.dirs",
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
  multi_sel = {},
  toggles = { case = false, word = false, regex = false, gitfiles = false },
  in_git = false,
}

M.Mode = Mode
M.DataType = DataType
M.defaults = defaults
M.register_type = register_type

return M
