local fn = vim.fn
local api = vim.api
local state = require("finder.state")
local DataType = state.DataType
local display = require("finder.display")

local M = {}
M.accepts = { DataType.None, DataType.FileList }
M.produces = DataType.Commits
M.display = display.commit
M.min_query = 3

local pending = { job = nil, cmd = nil, cache = {} }

local function stop_loading()
  state.loading = false
  if state.loading_timer then
    state.loading_timer:stop()
    state.loading_timer:close()
    state.loading_timer = nil
  end
end

function M.filter(query, items)
  if fn.executable("git") ~= 1 then
    return nil, "git not found"
  end

  if not query or #query < M.min_query then
    stop_loading()
    return {}
  end

  local toggles = state.toggles or {}
  local search_flag = toggles.regex and '-G' or '-S'
  local case_flag = (toggles.regex and not toggles.case) and ' -i' or ''

  local cmd = "git log " .. search_flag .. " " .. fn.shellescape(query)
    .. case_flag
    .. " --format='%h%x09%as%x09%an%x09%s' --max-count=100"

  if items and #items > 0 then
    cmd = cmd .. " -- " .. table.concat(vim.tbl_map(fn.shellescape, items), " ")
  end

  if pending.cache[cmd] then
    local result = pending.cache[cmd]
    pending.cache = {}
    stop_loading()
    return result
  end

  if pending.job then
    pcall(function() pending.job:kill() end)
    pending.job = nil
  end

  pending.cmd = cmd
  pending.cache = {}
  state.loading = true
  state.loading_frame = 0
  if not state.loading_timer then
    state.loading_timer = vim.uv.new_timer()
    state.loading_timer:start(0, 150, vim.schedule_wrap(function()
      if not state.loading or not state.space then
        stop_loading()
        return
      end
      state.loading_frame = (state.loading_frame + 1) % 3
      require("finder.render").render_list()
    end))
  end

  pending.job = vim.system(
    { "sh", "-c", cmd .. " 2>/dev/null" },
    { text = true },
    function(result)
      vim.schedule(function()
        if pending.cmd ~= cmd then return end
        if not state.space then stop_loading(); return end

        local cleaned = {}
        if result.code <= 1 and result.stdout then
          for line in result.stdout:gmatch("[^\n]+") do
            if line ~= "" then table.insert(cleaned, line) end
          end
        end

        pending.cache = { [cmd] = cleaned }
        pending.job = nil

        require("finder.evaluate").evaluate()
        local r = require("finder.render")
        r.render_list()
        r.update_bar(state.prompts[state.idx] or "")
      end)
    end
  )

  return {}, "async"
end

function M.on_open(item)
  local hash = item:match('^([^\t]+)')
  if not hash then return end
  local diff = fn.systemlist('git show ' .. hash)
  if vim.v.shell_error ~= 0 then return end
  vim.cmd('enew')
  local buf = api.nvim_get_current_buf()
  api.nvim_buf_set_lines(buf, 0, -1, false, diff)
  vim.bo[buf].filetype = 'git'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].modifiable = false
end

return M
