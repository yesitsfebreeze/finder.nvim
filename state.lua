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
  instant_clear = false,
  list_height = 16,
  file_width_ratio = 0.4,
  section_sep = {'─'},
  pickers = {
    Files = "finder.builtin.files",
    Grep = "finder.builtin.grep",
    Commits = "finder.builtin.commits",
    Changes = "finder.builtin.commit_grep",
    File = "finder.builtin.file",
    Sessions = "finder.builtin.sessions",
    Dirs = "finder.builtin.dirs",
    ["/down"] = "finder.builtin.search_down",
    ["?up"] = "finder.builtin.search_up",
  },
  keys = {
    sel_down = { "<Down>", "<C-j>" },
    sel_up = { "<Up>", "<C-k>" },
    preview_down = "<C-s>",
    preview_up = "<C-w>",
    toggle_case = "<C-1>",
    toggle_word = "<C-2>",
    toggle_regex = "<C-3>",
    toggle_gitfiles = "<C-4>",
    multi_add = "+",
    multi_remove = "-",
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
  result_cache = {},
  preview_scroll = 0,
  frecency = {},
  loading = false,
  loading_timer = nil,
  loading_frame = 0,
}

function M.stop_loading()
  M.loading = false
  if M.loading_timer then
    M.loading_timer:stop()
    M.loading_timer:close()
    M.loading_timer = nil
  end
end

function M.start_loading()
  M.loading = true
  M.loading_frame = 0
  if not M.loading_timer then
    M.loading_timer = vim.uv.new_timer()
    M.loading_timer:start(0, 150, vim.schedule_wrap(function()
      if not M.loading or not M.space then
        M.stop_loading()
        return
      end
      M.loading_frame = (M.loading_frame + 1) % 3
      require("finder.render").render_list()
    end))
  end
end

M.Mode = Mode
M.DataType = DataType
M.defaults = defaults
M.register_type = register_type

return M
