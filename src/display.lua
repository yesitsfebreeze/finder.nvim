local utils = require("finder.src.utils")

local M = {}

function M.create(spec)
  local sep = spec.separator or ' '
  local col_specs = spec.items

  return function(columns, width)
    local virt = {}
    local used = 0

    for i, col in ipairs(columns) do
      local cs = col_specs[i] or {}

      if i > 1 then
        table.insert(virt, { sep, 'FinderInactive' })
        used = used + #sep
      end

      local col_width = cs.remaining and math.max(1, width - used) or (cs.width or 0)
      local chunks = type(col[1]) == 'table' and col or { col }
      local text_len = 0
      for _, c in ipairs(chunks) do text_len = text_len + #c[1] end

      if text_len > col_width then
        local left = math.max(0, col_width - 1)
        for _, c in ipairs(chunks) do
          if left <= 0 then break end
          if #c[1] <= left then
            table.insert(virt, c)
            left = left - #c[1]
          else
            table.insert(virt, { c[1]:sub(1, left), c[2] })
            left = 0
          end
        end
        if col_width > 0 then table.insert(virt, { '…', chunks[#chunks][2] }) end
        used = used + col_width
      else
        for _, c in ipairs(chunks) do table.insert(virt, c) end
        if not cs.remaining and text_len < col_width then
          table.insert(virt, { string.rep(' ', col_width - text_len), chunks[#chunks][2] })
        end
        used = used + math.max(text_len, col_width)
      end
    end

    return virt
  end
end

local commit_displayer = M.create({
  separator = ' ',
  items = {
    { width = 8 },
    { width = 10 },
    { width = 15 },
    { remaining = true },
  },
})

function M.commit(item, ctx)
  local hash, date, author, subject = item:match('^([^\t]+)\t([^\t]+)\t([^\t]+)\t(.*)$')
  if not hash then return { { item, ctx.is_sel and 'FinderHighlight' or 'FinderText' } } end
  local hl = ctx.is_sel and 'FinderHighlight'
  return commit_displayer({
    { hash, hl or 'FinderHash' },
    { date, hl or 'FinderDate' },
    { author, hl or 'FinderAuthor' },
    utils.highlight_matches(subject, ctx.query, hl or 'FinderText'),
  }, ctx.width)
end

return M
