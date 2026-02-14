local M = {
  None = 0,
  FileList = 1,
  GrepList = 2,
  Commits = 3,
  File = 4,
  Dir = 5,
  DirList = 6,
}

function M.register(name, id)
  assert(type(name) == "string", "register_type: name must be a string")
  assert(type(id) == "number", "register_type: id must be a number")
  if M[name] then
    assert(M[name] == id, string.format("register_type: '%s' already registered with id %d", name, M[name]))
    return id
  end
  for k, v in pairs(M) do
    if type(v) == "number" and v == id then
      error(string.format("register_type: id %d already used by '%s'", id, k))
    end
  end
  M[name] = id
  return id
end

return M
