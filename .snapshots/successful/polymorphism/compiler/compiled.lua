local M = {}

function M.__print(s) io.write(tostring(s)); return nil end

function M.main(v__input)
  return M.__print((M.v_identity)((M.v_compose)(M.v_appendY, M.v_appendX, (M.v_const)("a", "b"))))
end

function M.v_const(v_x, v__y)
  return v_x
end

function M.v_identity(v_x)
  return v_x
end

function M.v_appendX(v_s)
  return (v_s .. "x")
end

function M.v_appendY(v_s)
  return (v_s .. "y")
end

function M.v_compose(v_g, v_f, v_x)
  return (v_g)((v_f)(v_x))
end

local ok, dbg = pcall(require, 'debug')
local should_run = false
if ok and dbg and dbg.getinfo then
  local info = dbg.getinfo(1, 'S')
  should_run = info and info.what == 'main'
else
  should_run = true
end
if should_run then
  local input = (_G and _G.arg and _G.arg[1]) or ""
  if type(M.main) == 'function' then M.main(input) end
end
