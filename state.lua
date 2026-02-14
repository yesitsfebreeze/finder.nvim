local Mode = { PICKER = 1, PROMPT = 2, INTERACT = 3 }

local DEBOUNCE_DELAY = 25

local DataType = require("finder.types")

local defaults = {
  sep = " > ",
  instant_clear = false,
  list_height = 7,
  file_width_ratio = 0.4,
  section_sep = {'─'},
  pickers = {
    Files = "finder.finders.files",
    Grep = "finder.finders.grep",
    Commits = "finder.finders.commits",
    Changes = "finder.finders.commit_grep",
    File = "finder.finders.file",
    Sessions = "finder.finders.sessions",
    Dirs = "finder.finders.dirs",
    Diagnostics = "finder.finders.diagnostics",
    ["/down"] = "finder.finders.search_down",
    ["?up"] = "finder.finders.search_up",
  },
  open_mode = { pos = "begin", mode = "normal" },
  keys = {
    sel_down = { "<Down>", "<C-j>" },
    sel_up = { "<Up>", "<C-k>" },
    preview_down = "<C-s>",
    preview_up = "<C-w>",
    toggle_case = "<C-1>",
    toggle_word = "<C-2>",
    toggle_regex = "<C-3>",
    toggle_gitfiles = "<C-4>",
    multi_toggle = "+",
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
    M.loading_timer:start(0, DEBOUNCE_DELAY, vim.schedule_wrap(function()
      if not M.loading or not M.space then
        M.stop_loading()
        return
      end
      M.loading_frame = (M.loading_frame + 1) % 3
      require("finder.render").render_list()
    end))
  end
end

M.debounce = DEBOUNCE_DELAY
M.Mode = Mode
M.DataType = DataType
M.defaults = defaults
M.register_type = DataType.register

return M
